import AVFoundation
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Captures microphone audio with AVAudioEngine and converts it to the
/// 16 kHz mono Float32 stream Qwen3-ASR expects. Also publishes a smoothed
/// input level for the dictation pill's level meter.
final class AudioRecorder {
    static let targetSampleRate: Double = 16_000

    /// Called on the main thread ~30×/s with a 0…1 loudness value.
    var onLevel: ((Float) -> Void)?

    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.targetSampleRate,
        channels: 1, interleaved: false)!

    private let lock = NSLock()
    private var samples: [Float] = []
    private var smoothedLevel: Float = 0
    private var lastLevelEmit: TimeInterval = 0
    private(set) var isRecording = false

    // MARK: - Recording

    /// Debug/testing: `HFLOW_TEST_AUDIO=/path.wav` replaces the microphone with a file,
    /// so the full hotkey → overlay → transcribe → paste path can run in a VM or CI.
    static let testAudioPath = ProcessInfo.processInfo.environment["HFLOW_TEST_AUDIO"]
    private var fakeLevelTimer: Timer?

    func start(deviceUID: String?) throws {
        guard !isRecording else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        smoothedLevel = 0

        if let path = Self.testAudioPath {
            let fileSamples = try Benchmark.loadAudio(URL(fileURLWithPath: path))
            lock.lock(); samples = fileSamples; lock.unlock()
            fakeLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.onLevel?(Float.random(in: 0.2...0.8))
            }
            isRecording = true
            return
        }

        engine = AVAudioEngine()
        let input = engine.inputNode
        if let uid = deviceUID, !uid.isEmpty, let deviceID = Self.deviceID(forUID: uid) {
            Self.setInputDevice(deviceID, on: input)
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "BiscuitFlow.Audio", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops capture and returns everything recorded since `start`.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        if Self.testAudioPath != nil {
            fakeLevelTimer?.invalidate()
            isRecording = false
            lock.lock(); defer { lock.unlock() }
            return samples
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); defer { lock.unlock() }
        let out = samples
        samples.removeAll()
        return out
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return }
        let count = Int(out.frameLength)
        let chunk = UnsafeBufferPointer(start: channel, count: count)

        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()

        // Loudness → 0…1 using a dB scale so quiet speech still moves the bars.
        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = count > 0 ? sqrtf(sum / Float(count)) : 0
        let db = 20 * log10f(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 55) / 40))
        // Fast attack, slower release feels natural.
        let k: Float = normalized > smoothedLevel ? 0.6 : 0.25
        smoothedLevel += (normalized - smoothedLevel) * k

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastLevelEmit > 1.0 / 30.0 {
            lastLevelEmit = now
            let level = smoothedLevel
            DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
        }
    }

    // MARK: - Devices

    static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.id
    }

    private static func setInputDevice(_ deviceID: AudioDeviceID, on input: AVAudioInputNode) {
        guard let unit = input.audioUnit else { return }
        var id = deviceID
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr { NSLog("[BiscuitFlow] Could not select input device \(deviceID): \(status)") }
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let str = value?.takeRetainedValue() else { return nil }
        return str as String
    }
}

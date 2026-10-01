import AVFoundation
import CoreAudio

/// Short synthesized UI cues, so we don't ship any audio assets.
final class SoundPlayer {
    enum Cue { case start, stop, cancel, lock }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var started = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.35
        buffers[.start] = tone([(660, 0.045), (990, 0.07)])
        buffers[.stop] = tone([(880, 0.045), (587, 0.07)])
        buffers[.lock] = tone([(660, 0.04), (880, 0.04), (1175, 0.06)])
        buffers[.cancel] = tone([(440, 0.06), (330, 0.08)])
    }

    func play(_ cue: Cue) {
        guard let buffer = buffers[cue] else { return }
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    /// A soft sine "blip" sequence with short fades to avoid clicks.
    private func tone(_ notes: [(freq: Double, dur: Double)]) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let total = notes.reduce(0) { $0 + Int($1.dur * sr) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buffer.frameLength = AVAudioFrameCount(total)
        let out = buffer.floatChannelData![0]
        var i = 0
        var phase = 0.0
        for note in notes {
            let n = Int(note.dur * sr)
            let fade = min(n / 3, Int(0.008 * sr))
            for j in 0..<n {
                var env = 1.0
                if j < fade { env = Double(j) / Double(fade) }
                if j > n - fade { env = Double(n - j) / Double(fade) }
                phase += 2 * .pi * note.freq / sr
                // Fundamental + a quiet octave gives a rounder, less "beepy" tone.
                out[i] = Float((sin(phase) * 0.8 + sin(phase * 2) * 0.12) * env * 0.6)
                i += 1
            }
        }
        return buffer
    }
}

/// Mutes the default output device while dictating, restoring the previous state afterwards.
enum SystemAudio {
    private static var mutedByUs = false

    static func muteOutput() {
        guard let device = defaultOutputDevice(), getMute(device) == false else { return }
        if setMute(device, true) { mutedByUs = true }
    }

    static func restoreOutput() {
        guard mutedByUs, let device = defaultOutputDevice() else { return }
        _ = setMute(device, false)
        mutedByUs = false
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static func getMute(_ device: AudioDeviceID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &muteAddress),
              AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func setMute(_ device: AudioDeviceID, _ mute: Bool) -> Bool {
        var value: UInt32 = mute ? 1 : 0
        return AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

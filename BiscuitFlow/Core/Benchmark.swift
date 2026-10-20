import AVFoundation
import Foundation
import MLX

/// Headless test mode: `BiscuitFlow --bench a.wav [b.wav …] [--runs N] [--language X]`
/// Loads the model, transcribes the files round-robin, prints timings and memory, exits.
enum Benchmark {
    static func run(arguments: [String], settings: AppSettings) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        var paths: [String] = []
        var i = 0
        while i < arguments.count {
            if arguments[i].hasPrefix("--") { i += 2; continue }
            paths.append(arguments[i]); i += 1
        }
        guard !paths.isEmpty else {
            print("usage: BiscuitFlow --bench <audio file>… [--runs N] [--language X]")
            exit(2)
        }
        let runs = Int(value("--runs") ?? "3") ?? 3
        let language = value("--language")

        Task.detached {
            do {
                let clips = try paths.map { try loadAudio(URL(fileURLWithPath: $0)) }
                let lengths = clips.map { String(format: "%.1fs", Double($0.count) / 16_000) }.joined(separator: ", ")
                print("audio: \(lengths), model: \(Transcriber.displayName)")
                let loadStart = Date()
                let transcriber = Transcriber { state in
                    if case .failed(let msg) = state { print("load failed: \(msg)") }
                }
                await transcriber.load()
                guard await transcriber.isReady else { exit(1) }
                print(String(format: "load+warmup: %.2fs", Date().timeIntervalSince(loadStart)))
                print(memoryLine())

                for i in 1...runs {
                    let samples = clips[(i - 1) % clips.count]
                    let r = try await transcriber.transcribe(samples, language: language, context: nil)
                    print(String(format: "run %d (%.0fs audio): %.3fs (RTFx %.1f) · %@", i, r.audioSeconds,
                                 r.inferenceSeconds, r.audioSeconds / r.inferenceSeconds, memoryLine()))
                    if i == runs {
                        print("text: \(r.text)")
                        let processed = TextProcessor().process(r.text, context: nil)
                        print("processed: \(processed)")
                    }
                }
                exit(0)
            } catch {
                print("error: \(error)")
                exit(1)
            }
        }
    }

    /// Process footprint (what Activity Monitor shows) plus MLX's own accounting.
    static func memoryLine() -> String {
        let mb = { (b: Int) in String(format: "%.0f", Double(b) / 1_048_576) }
        return "footprint \(mb(physFootprint())) MB, mlx active \(mb(MLX.Memory.activeMemory)) cache \(mb(MLX.Memory.cacheMemory)) peak \(mb(MLX.Memory.peakMemory))"
    }

    static func physFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Decodes any AVFoundation-readable file to 16 kHz mono Float32.
    static func loadAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "BiscuitFlow.Bench", code: 1)
        }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16_000 / file.processingFormat.sampleRate + 1024)
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
        var done = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}

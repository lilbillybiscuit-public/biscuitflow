import AVFoundation
import Foundation

/// Headless test mode: `BiscuitFlow --bench file.wav [--runs N] [--language X]`
/// Loads the model, transcribes the file, prints timings, exits.
enum Benchmark {
    static func run(arguments: [String], settings: AppSettings) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
            print("usage: BiscuitFlow --bench <audio file> [--runs N] [--language X]")
            exit(2)
        }
        let runs = Int(value("--runs") ?? "3") ?? 3
        let language = value("--language")

        Task.detached {
            do {
                let samples = try loadAudio(URL(fileURLWithPath: path))
                print("audio: \(String(format: "%.2f", Double(samples.count) / 16_000))s, model: \(Transcriber.displayName)")
                let loadStart = Date()
                let transcriber = Transcriber { state in
                    if case .failed(let msg) = state { print("load failed: \(msg)") }
                }
                await transcriber.load()
                guard await transcriber.isReady else { exit(1) }
                print(String(format: "load+warmup: %.2fs", Date().timeIntervalSince(loadStart)))

                for i in 1...runs {
                    let r = try await transcriber.transcribe(samples, language: language, context: nil)
                    print(String(format: "run %d: %.3fs (RTFx %.1f)", i, r.inferenceSeconds, r.audioSeconds / r.inferenceSeconds))
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

import Foundation
import Qwen3ASR

/// On-device speech recognition with Qwen3-ASR 0.6B (MLX, 5-bit) via soniqo/speech-swift.
/// The weights ship inside the app bundle, so nothing is downloaded at runtime.
/// All model work is serialized on this actor.
actor Transcriber {
    enum State: Equatable {
        case notLoaded
        case loading(progress: Double, message: String)
        case ready
        case failed(String)
    }

    struct Result {
        let text: String
        let audioSeconds: Double
        let inferenceSeconds: Double
    }

    /// Hugging Face id of the bundled weights (used for size/bit-width detection).
    static let modelId = "aufklarer/Qwen3-ASR-0.6B-MLX-5bit"
    static let displayName = "Qwen3-ASR 0.6B · MLX 5-bit"

    /// `BiscuitFlow.app/Contents/Resources/Models/Qwen3-ASR-0.6B-MLX-5bit`
    static var bundledModelURL: URL? {
        Bundle.main.url(forResource: "Qwen3-ASR-0.6B-MLX-5bit", withExtension: nil, subdirectory: "Models")
    }

    private var model: Qwen3ASRModel?

    /// Reports load progress.
    private let onState: @Sendable (State) -> Void

    init(onState: @escaping @Sendable (State) -> Void) {
        self.onState = onState
    }

    var isReady: Bool { model != nil }

    func load() async {
        if model != nil { onState(.ready); return }
        guard let directory = Self.bundledModelURL else {
            onState(.failed("Speech model missing from the app bundle"))
            return
        }
        onState(.loading(progress: 0.1, message: "Loading speech model…"))
        do {
            let model = try await Qwen3ASRModel.fromPretrained(
                modelId: Self.modelId, cacheDir: directory, offlineMode: true)
            onState(.loading(progress: 0.9, message: "Warming up…"))
            // One short silent pass compiles the Metal kernels so the first real
            // dictation is fast.
            _ = model.transcribe(audio: [Float](repeating: 0, count: 16_000), sampleRate: 16_000, language: "English", maxTokens: 4)
            self.model = model
            onState(.ready)
        } catch {
            onState(.failed(error.localizedDescription))
        }
    }

    /// Transcribes 16 kHz mono samples.
    /// - Parameters:
    ///   - language: Qwen3-ASR language name ("English", "Chinese", …) or nil to auto-detect.
    ///   - context: optional biasing text (e.g. custom vocabulary).
    func transcribe(_ samples: [Float], language: String?, context: String?) throws -> Result {
        guard let model else {
            throw NSError(domain: "BiscuitFlow.ASR", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The speech model isn't loaded yet."])
        }
        let start = Date()
        let audioSeconds = Double(samples.count) / 16_000
        // Generous cap: ~6 tokens/sec of speech plus headroom.
        let maxTokens = min(1024, max(64, Int(audioSeconds * 8) + 32))
        let raw = model.transcribe(
            audio: samples, sampleRate: 16_000, language: language,
            maxTokens: maxTokens, context: context)
        return Result(
            text: Self.clean(raw),
            audioSeconds: audioSeconds,
            inferenceSeconds: Date().timeIntervalSince(start))
    }

    /// Strips any leftover control markup the decoder can emit.
    static func clean(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "<asr_text>") { text = String(text[range.upperBound...]) }
        for token in ["<|im_end|>", "<|endoftext|>", "<|im_start|>"] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        if text.hasPrefix("language "), let newline = text.firstIndex(where: { $0 == "\n" }) {
            text = String(text[text.index(after: newline)...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

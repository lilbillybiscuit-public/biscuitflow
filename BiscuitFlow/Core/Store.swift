import Foundation

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var rawText: String
    var appName: String?
    var bundleID: String?
    var audioSeconds: Double
    var inferenceSeconds: Double

    var wordCount: Int { Store.countWords(text) }
}

/// A custom vocabulary word. With `spokenForm` set it's also a replacement rule
/// ("hey flow" → "BiscuitFlow"); without it, it's only used to bias recognition.
struct DictionaryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var word: String
    var spokenForm: String = ""

    var isReplacement: Bool { !spokenForm.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Say the trigger phrase on its own and the expansion gets pasted instead.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

/// JSON-file persistence for history, dictionary and snippets in
/// ~/Library/Application Support/HFlow (retained across the BiscuitFlow rename).
@MainActor
final class Store: ObservableObject {
    @Published var history: [HistoryItem] = [] { didSet { save(history, to: "history.json") } }
    @Published var dictionary: [DictionaryEntry] = [] { didSet { save(dictionary, to: "dictionary.json") } }
    @Published var snippets: [Snippet] = [] { didSet { save(snippets, to: "snippets.json") } }

    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HFlow", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        history = load("history.json") ?? []
        dictionary = load("dictionary.json") ?? []
        snippets = load("snippets.json") ?? [
            Snippet(trigger: "my email", expansion: "you@example.com"),
        ]
    }

    func add(_ item: HistoryItem) {
        history.insert(item, at: 0)
        if history.count > 2000 { history.removeLast(history.count - 2000) }
    }

    /// Text handed to Qwen3-ASR as context to bias recognition toward custom words.
    var biasingContext: String? {
        let words = dictionary.map(\.word).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return "Vocabulary: " + words.joined(separator: ", ")
    }

    // MARK: - Stats

    var totalWords: Int { history.reduce(0) { $0 + $1.wordCount } }

    /// Average speaking pace across all dictations.
    var wordsPerMinute: Int {
        let seconds = history.reduce(0) { $0 + $1.audioSeconds }
        guard seconds > 5 else { return 0 }
        return Int((Double(totalWords) / (seconds / 60)).rounded())
    }

    /// Consecutive days (ending today or yesterday) with at least one dictation.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(history.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    nonisolated static func countWords(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    // MARK: - Persistence

    private func load<T: Decodable>(_ file: String) -> T? {
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to file: String) {
        let url = directory.appendingPathComponent(file)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

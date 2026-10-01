import Foundation

/// Turns raw ASR output into the text we actually paste.
struct TextProcessor {
    var removeFillers = true
    var smartSpacing = true
    var replacements: [DictionaryEntry] = []
    var snippets: [Snippet] = []

    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"(?i)(?<![\p{L}'])(?:u+m+|u+h+m*|e+r+m+|a+h+|h+m+)(?![\p{L}'])[,.…]?\s*"#)

    func process(_ input: String, context: TextInserter.FocusContext?) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if removeFillers { text = Self.stripFillers(text) }
        text = applyReplacements(text)
        if let expanded = expandSnippet(text) { return expanded }
        if smartSpacing, let context { text = Self.fitToCaret(text, before: context.textBeforeCaret) }
        return text
    }

    // MARK: - Steps

    static func stripFillers(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var out = fillerPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        out = out.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        // "Um, so we…" → "So we…": the word after a removed leading filler inherits its capital.
        if let first = out.first, first.isLowercase, text.first?.isUppercase == true {
            out = first.uppercased() + out.dropFirst()
        }
        return out
    }

    func applyReplacements(_ text: String) -> String {
        var out = text
        for entry in replacements where entry.isReplacement {
            let escaped = NSRegularExpression.escapedPattern(for: entry.spokenForm)
            out = out.replacingOccurrences(
                of: #"(?i)(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#,
                with: NSRegularExpression.escapedTemplate(for: entry.word),
                options: .regularExpression)
        }
        return out
    }

    /// If the whole utterance is a snippet trigger, return its expansion.
    func expandSnippet(_ text: String) -> String? {
        let key = Self.normalizeTrigger(text)
        guard !key.isEmpty else { return nil }
        return snippets.first { Self.normalizeTrigger($0.trigger) == key }?.expansion
    }

    static func normalizeTrigger(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Adds a leading space or lowercases the first letter depending on what's
    /// already in the field, so dictating mid-sentence reads naturally.
    static func fitToCaret(_ text: String, before: String?) -> String {
        guard let before, let last = before.last else { return text }
        var out = text
        let sentenceEnders: Set<Character> = [".", "!", "?", "\n", "。", "！", "？"]

        if !last.isWhitespace && !"([{\"'“‘/-".contains(last) && !(out.first?.isPunctuation ?? false) {
            out = " " + out
        }
        // Continuing a sentence: "I think" + "Maybe we should" → "I think maybe we should".
        let trimmedBefore = before.trimmingCharacters(in: .whitespaces)
        if let prev = trimmedBefore.last, !sentenceEnders.contains(prev), prev.isLetter || prev == "," {
            if let idx = out.firstIndex(where: { !$0.isWhitespace }) {
                let word = out[idx...].prefix { $0.isLetter }
                // Keep "I", acronyms and proper nouns that are fully uppercase.
                if word.count > 1, word.dropFirst().allSatisfy({ $0.isLowercase }) {
                    out.replaceSubrange(idx...idx, with: String(out[idx]).lowercased())
                }
            }
        }
        return out
    }
}

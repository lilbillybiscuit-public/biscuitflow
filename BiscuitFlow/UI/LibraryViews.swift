import SwiftUI

/// Shared page chrome: big title, subtitle, content.
struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Theme.display(30))
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    @EnvironmentObject private var store: Store
    @State private var newWord = ""
    @State private var newSpoken = ""

    var body: some View {
        Page(title: "Dictionary",
             subtitle: "Teach BiscuitFlow names, jargon and acronyms. Words here bias the speech model toward the right spelling. Add a \"sounds like\" phrase to always replace it.") {
            Card {
                HStack(spacing: 10) {
                    TextField("Word or phrase (e.g. Kubernetes)", text: $newWord)
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                    Divider().frame(height: 18)
                    TextField("Sounds like (optional)", text: $newSpoken)
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .buttonStyle(AccentButtonStyle())
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(14)
            }

            if store.dictionary.isEmpty {
                Text("No words yet.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            } else {
                Card {
                    ForEach(Array(store.dictionary.enumerated()), id: \.element.id) { index, entry in
                        HStack {
                            Text(entry.word).font(.system(size: 13.5, weight: .medium))
                            if entry.isReplacement {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text("“\(entry.spokenForm)”")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            IconButton(systemName: "trash", help: "Remove") {
                                store.dictionary.removeAll { $0.id == entry.id }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if index < store.dictionary.count - 1 { Divider().padding(.leading, 14) }
                    }
                }
            }
        }
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        store.dictionary.insert(DictionaryEntry(word: word, spokenForm: newSpoken.trimmingCharacters(in: .whitespaces)), at: 0)
        newWord = ""
        newSpoken = ""
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @EnvironmentObject private var store: Store
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        Page(title: "Snippets",
             subtitle: "Say a short cue phrase on its own and BiscuitFlow pastes the full text — links, addresses, sign-offs, prompts.") {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("When I say… (e.g. my calendar link)", text: $trigger)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .medium))
                    Divider()
                    TextEditor(text: $expansion)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60, maxHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if expansion.isEmpty {
                                Text("…paste this instead")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Spacer()
                        Button("Add snippet", action: add)
                            .buttonStyle(AccentButtonStyle())
                            .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
                    }
                }
                .padding(14)
            }

            if !store.snippets.isEmpty {
                Card {
                    ForEach(Array(store.snippets.enumerated()), id: \.element.id) { index, snippet in
                        HStack(alignment: .top, spacing: 14) {
                            Text("“\(snippet.trigger)”")
                                .font(.system(size: 13.5, weight: .medium))
                                .frame(width: 200, alignment: .leading)
                            Text(snippet.expansion)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Spacer()
                            IconButton(systemName: "trash", help: "Remove") {
                                store.snippets.removeAll { $0.id == snippet.id }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if index < store.snippets.count - 1 { Divider().padding(.leading, 14) }
                    }
                }
            }
        }
    }

    private func add() {
        store.snippets.insert(Snippet(trigger: trigger.trimmingCharacters(in: .whitespaces), expansion: expansion), at: 0)
        trigger = ""
        expansion = ""
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)))
    }
}

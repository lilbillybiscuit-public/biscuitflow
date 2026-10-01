import SwiftUI

enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .settings: return "gearshape"
        }
    }
}

struct HubView: View {
    @EnvironmentObject private var permissions: Permissions
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var section: HubSection = .home

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    BrandMark()
                        .frame(width: 22, height: 22)
                    Text("BiscuitFlow")
                        .font(Theme.display(20))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)

                ForEach(HubSection.allCases) { item in
                    SidebarRow(section: item, selected: section == item) { section = item }
                }
                Spacer()
                ModelStatusFooter()
            }
            .padding(.top, 36)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                if !permissions.allGranted || !settings.hasCompletedOnboarding {
                    OnboardingView()
                } else {
                    switch section {
                    case .home: HomeView()
                    case .dictionary: DictionaryView()
                    case .snippets: SnippetsView()
                    case .settings: SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .onAppear {
            HubWindow.openWindowAction = { id in openWindow(id: id) }
            permissions.refresh()
        }
    }
}

private struct SidebarRow: View {
    let section: HubSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.sidebarSelection : (hovering ? Theme.sidebarHover : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ModelStatusFooter: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            if case .loading(let p, let message) = controller.modelState {
                ProgressView(value: p).controlSize(.small)
                Text(message).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(Transcriber.displayName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
    }

    private var title: String {
        switch controller.modelState {
        case .ready: return "On-device model ready"
        case .loading: return "Loading model"
        case .notLoaded: return "Model not loaded"
        case .failed: return "Model failed to load"
        }
    }

    private var color: Color {
        switch controller.modelState {
        case .ready: return .green
        case .loading: return .orange
        case .notLoaded: return .gray
        case .failed: return .red
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(Theme.display(34))
                    (Text("Hold ") + Text(settings.hotkey.displayName).bold()
                     + Text(" and speak in any app. Release to paste."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    StatCard(value: "\(store.totalWords.formatted())", label: "words dictated", icon: "text.word.spacing")
                    StatCard(value: store.wordsPerMinute > 0 ? "\(store.wordsPerMinute)" : "—", label: "words per minute", icon: "speedometer")
                    StatCard(value: "\(store.streakDays)", label: store.streakDays == 1 ? "day streak" : "day streak", icon: "flame")
                }

                HStack {
                    Text("History").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $search).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(width: 220)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
                }

                if filtered.isEmpty {
                    EmptyHistory(keyLabel: settings.hotkey.displayName, searching: !search.isEmpty)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.bottom, 8)
                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                        HistoryRow(item: item)
                                        if index < group.items.count - 1 { Divider().padding(.leading, 92) }
                                    }
                                }
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var filtered: [HistoryItem] {
        guard !search.isEmpty else { return store.history }
        return store.history.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    private var groups: [(day: Date, title: String, items: [HistoryItem])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered.prefix(500)) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if cal.isDateInToday(day) { title = "Today" }
            else if cal.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
            return (day, title, grouped[day]!.sorted { $0.date > $1.date })
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text(value)
                .font(Theme.display(28))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    @EnvironmentObject private var store: Store
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 13.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let app = item.appName {
                    Text("\(app) · \(String(format: "%.1fs", item.audioSeconds)) audio · \(String(format: "%.2fs", item.inferenceSeconds)) to transcribe")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                IconButton(systemName: copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                    TextInserter.copyToClipboard(item.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                IconButton(systemName: "trash", help: "Delete") {
                    store.history.removeAll { $0.id == item.id }
                }
            }
            .opacity(hovering || copied ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Theme.sidebarHover : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct EmptyHistory: View {
    let keyLabel: String
    let searching: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: searching ? "magnifyingglass" : "waveform")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(searching ? "No matches" : "Nothing here yet")
                .font(.system(size: 15, weight: .semibold))
            if !searching {
                Text("Click into any text field, hold \(keyLabel), and start talking.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
    }
}

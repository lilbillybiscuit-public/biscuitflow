import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var permissions: Permissions
    @State private var microphones: [AudioInputDevice] = []
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Page(title: "Settings", subtitle: "Everything runs on this Mac. Your voice never leaves it.") {
            SettingsSection(title: "Dictation") {
                SettingsRow(title: "Dictation shortcut",
                            detail: "Hold to talk, release to paste. Click to record a combo (e.g. ⌥D) or a single modifier key (e.g. fn).") {
                    ShortcutRecorder(hotkey: $settings.hotkey) { recording in
                        controller.setHotkeySuspended(recording)
                    }
                }
                SettingsToggle(title: "Double-tap for hands-free",
                               detail: "Double-tap the key (or press key + Space) to keep listening. Press again to finish.",
                               isOn: $settings.handsFreeDoubleTap)
                SettingsRow(title: "Microphone", detail: nil) {
                    Picker("", selection: $settings.microphoneUID) {
                        Text("System default").tag("")
                        ForEach(microphones) { Text($0.name).tag($0.uid) }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
                SettingsRow(title: "Language", detail: "Auto-detect handles 30+ languages; pinning one is slightly more accurate.") {
                    Picker("", selection: $settings.language) {
                        ForEach(AppSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                if settings.hotkey == .fn {
                    SettingsRow(title: "Globe key conflict",
                                detail: "If pressing fn opens the emoji picker or switches input source, set “Press 🌐 key to” → “Do Nothing”.") {
                        Button("Keyboard Settings…") { permissions.openKeyboardSettings() }
                    }
                }
            }

            SettingsSection(title: "Speech model") {
                SettingsRow(title: Transcriber.displayName,
                            detail: "Bundled with BiscuitFlow and runs on this Mac's GPU. Nothing is sent to the cloud.") {
                    switch controller.modelState {
                    case .ready:
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.green)
                    case .loading:
                        ProgressView().controlSize(.small)
                    case .failed(let message):
                        HStack {
                            Text(message).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2)
                            Button("Retry") { controller.loadModel() }
                        }
                    case .notLoaded:
                        Button("Load") { controller.loadModel() }
                    }
                }
            }

            SettingsSection(title: "Text") {
                SettingsToggle(title: "Remove filler words", detail: "Drops “um”, “uh” and friends.", isOn: $settings.removeFillerWords)
                SettingsToggle(title: "Smart spacing & capitalization",
                               detail: "Matches the text around your cursor when dictating mid-sentence.",
                               isOn: $settings.smartSpacing)
                SettingsToggle(title: "Restore clipboard after pasting", detail: nil, isOn: $settings.restoreClipboard)
            }

            SettingsSection(title: "App") {
                SettingsToggle(title: "Sound effects", detail: nil, isOn: $settings.playSounds)
                SettingsToggle(title: "Mute other audio while dictating", detail: nil, isOn: $settings.muteAudioWhileDictating)
                SettingsToggle(title: "Always show the dictation pill", detail: "Otherwise it only appears while dictating.", isOn: $settings.showFlowBarWhenIdle)
                SettingsToggle(title: "Launch at login", detail: nil, isOn: Binding(
                    get: { launchAtLogin },
                    set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }))
            }

            SettingsSection(title: "Permissions") {
                PermissionRow(title: "Microphone", granted: permissions.microphone == .authorized) {
                    permissions.requestMicrophone()
                }
                PermissionRow(title: "Accessibility", granted: permissions.accessibility) {
                    permissions.requestAccessibility()
                }
            }
        }
        .onAppear {
            microphones = AudioRecorder.inputDevices()
            permissions.refresh()
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Card {
                _VariadicView.Tree(DividedLayout()) { content }
            }
        }
    }
}

/// Puts hairline dividers between a section's rows.
private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last { Divider().padding(.leading, 14) }
            }
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        SettingsRow(title: title, detail: nil) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Grant access", action: action).buttonStyle(AccentButtonStyle())
            }
        }
    }
}

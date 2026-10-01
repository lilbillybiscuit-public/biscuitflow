import SwiftUI

struct MenuBarIcon: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        switch controller.phase {
        case .recording: Image(systemName: "waveform.circle.fill")
        case .transcribing: Image(systemName: "ellipsis.circle")
        case .idle: Image(systemName: "waveform")
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open BiscuitFlow") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "hub")
        }
        Divider()
        Button(controller.phase == .idle ? "Start Hands-free Dictation" : "Stop Dictation") {
            controller.toggleHandsFree()
        }
        if let last = store.history.first {
            Button("Paste Last Transcript: “\(String(last.text.prefix(32)))\(last.text.count > 32 ? "…" : "")”") {
                // Let the menu close and focus return to the previous app first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { controller.pasteLast() }
            }
        }
        Divider()
        Picker("Microphone", selection: $settings.microphoneUID) {
            Text("System Default").tag("")
            ForEach(AudioRecorder.inputDevices()) { Text($0.name).tag($0.uid) }
        }
        Picker("Language", selection: $settings.language) {
            ForEach(AppSettings.languages, id: \.code) { Text($0.name).tag($0.code) }
        }
        Divider()
        Text(statusText)
        Divider()
        Button("Quit BiscuitFlow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch controller.modelState {
        case .ready: return "Model ready · hold \(settings.hotkey.displayName) to dictate"
        case .loading(let p, _): return "Loading model… \(Int(p * 100))%"
        case .notLoaded: return "Model not loaded"
        case .failed: return "Model failed to load"
        }
    }
}

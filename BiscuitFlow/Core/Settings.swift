import Foundation
import SwiftUI

/// User-tweakable preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Hold to dictate. Defaults to ⌥D; recorded in Settings.
    @AppStorage("hotkey") var hotkey: Hotkey = .default { willSet { objectWillChange.send() } }
    @AppStorage("handsFreeDoubleTap") var handsFreeDoubleTap = true { willSet { objectWillChange.send() } }
    @AppStorage("language") var language = "auto" { willSet { objectWillChange.send() } }
    @AppStorage("playSounds") var playSounds = true { willSet { objectWillChange.send() } }
    @AppStorage("muteAudioWhileDictating") var muteAudioWhileDictating = false { willSet { objectWillChange.send() } }
    @AppStorage("removeFillerWords") var removeFillerWords = true { willSet { objectWillChange.send() } }
    @AppStorage("smartSpacing") var smartSpacing = true { willSet { objectWillChange.send() } }
    @AppStorage("restoreClipboard") var restoreClipboard = true { willSet { objectWillChange.send() } }
    @AppStorage("showFlowBarWhenIdle") var showFlowBarWhenIdle = true { willSet { objectWillChange.send() } }
    @AppStorage("microphoneUID") var microphoneUID = "" { willSet { objectWillChange.send() } }
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false { willSet { objectWillChange.send() } }

    /// Languages Qwen3-ASR handles well. "auto" lets the model detect.
    static let languages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("English", "English"), ("Chinese", "Chinese"), ("Cantonese", "Cantonese"),
        ("Japanese", "Japanese"), ("Korean", "Korean"), ("Spanish", "Spanish"),
        ("French", "French"), ("German", "German"), ("Italian", "Italian"),
        ("Portuguese", "Portuguese"), ("Russian", "Russian"), ("Arabic", "Arabic"),
        ("Hindi", "Hindi"), ("Vietnamese", "Vietnamese"), ("Thai", "Thai"),
        ("Indonesian", "Indonesian"), ("Turkish", "Turkish"), ("Dutch", "Dutch"),
        ("Polish", "Polish"), ("Swedish", "Swedish"),
    ]
}

import AppKit
import ApplicationServices
import AVFoundation

/// Microphone + Accessibility permission state and helpers.
@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var microphone: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var accessibility: Bool = AXIsProcessTrusted()

    var allGranted: Bool { microphone == .authorized && accessibility }

    private var pollTimer: Timer?

    func refresh() {
        // Assign only on change: @Published fires on every set, and observers of
        // `accessibility` call back into refresh().
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic != microphone { microphone = mic }
        let ax = AXIsProcessTrusted()
        if ax != accessibility { accessibility = ax }
    }

    func requestMicrophone() {
        if microphone == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in self.refresh() }
            }
        } else {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }

    func requestAccessibility() {
        // Shows the system prompt (once) and adds BiscuitFlow to the list in System Settings.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
        startPolling()
    }

    func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// Accessibility has no change notification; poll while the user is in System Settings.
    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.refresh()
                if self.allGranted { timer.invalidate() }
            }
        }
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

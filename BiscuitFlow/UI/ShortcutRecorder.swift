import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a combo (⌥D, ⌃⇧Space, F5…) or tap a single modifier key (fn, right ⌥…).
/// Esc cancels. The global hotkey is suspended while recording so the current shortcut
/// can be re-entered without starting a dictation.
struct ShortcutRecorder: View {
    @Binding var hotkey: Hotkey
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var hint: String?
    @State private var monitor: Any?
    /// The lone modifier currently held, if no other key has been pressed with it.
    @State private var pendingModifier: Int64?

    var body: some View {
        HStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button(action: toggle) {
                Text(isRecording ? "Type shortcut…" : hotkey.displayName)
                    .font(.system(size: 13, weight: .semibold, design: isRecording ? .default : .rounded))
                    .foregroundStyle(isRecording ? Theme.highlight : .primary)
                    .frame(minWidth: 96)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.sidebarSelection))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isRecording ? Theme.highlight : Theme.hairline, lineWidth: isRecording ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            if hotkey != .default && !isRecording {
                IconButton(systemName: "arrow.counterclockwise", help: "Reset to \(Hotkey.default.displayName)") {
                    hotkey = .default
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hint)
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        hint = "Esc to cancel"
        pendingModifier = nil
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { onRecordingChange(false) }
        isRecording = false
        pendingModifier = nil
    }

    private func handle(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        let flags = Self.cgFlags(event.modifierFlags)

        if event.type == .flagsChanged {
            guard let flag = Hotkey.flag(forModifierKeyCode: keyCode) else { return }
            if flags.contains(flag) {
                pendingModifier = keyCode // went down
            } else if pendingModifier == keyCode {
                // Pressed and released on its own → lone-modifier shortcut.
                if flag == .maskShift {
                    hint = "⇧ alone would fire while typing capitals"
                    pendingModifier = nil
                    return
                }
                commit(Hotkey(keyCode: keyCode, modifiers: flag, isModifierOnly: true))
            }
            return
        }

        // keyDown
        pendingModifier = nil
        if keyCode == Int64(kVK_Escape) && flags.intersection(Hotkey.modifierMask).isEmpty {
            hint = nil
            stop()
            return
        }
        var mods = flags.intersection(Hotkey.modifierMask)
        if Hotkey.keyImpliesFn(keyCode) { mods.remove(.maskSecondaryFn) }
        let hasRealModifier = !mods.intersection([.maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]).isEmpty
        guard hasRealModifier || Hotkey.isFunctionKey(keyCode) else {
            hint = "Add ⌘, ⌥, ⌃ or fn"
            return
        }
        commit(Hotkey(keyCode: keyCode, modifiers: mods, isModifierOnly: false))
    }

    private func commit(_ newValue: Hotkey) {
        hotkey = newValue
        hint = nil
        stop()
    }

    static func cgFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var out: CGEventFlags = []
        if flags.contains(.command) { out.insert(.maskCommand) }
        if flags.contains(.option) { out.insert(.maskAlternate) }
        if flags.contains(.control) { out.insert(.maskControl) }
        if flags.contains(.shift) { out.insert(.maskShift) }
        if flags.contains(.function) { out.insert(.maskSecondaryFn) }
        return out
    }
}

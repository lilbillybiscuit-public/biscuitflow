import AppKit
import CoreGraphics

/// Global keyboard monitor built on a CGEventTap.
///
/// Watches for the configured hotkey — a key combo like ⌥D (keyDown/keyUp, swallowed so
/// it doesn't type "∂") or a lone modifier like fn (flagsChanged) — and turns raw key
/// transitions into high-level dictation intents:
///
/// * hold the key            → push-to-talk (stop on release)
/// * double-tap the key      → hands-free (stop on next press)
/// * key + Space while held  → hands-free
/// * Esc while recording     → cancel
/// * any other key combo     → the user was using a shortcut; cancel silently
///
/// Requires Accessibility permission (an active, non-listen-only tap lets us
/// swallow the Space/Esc presses that belong to dictation).
final class HotkeyMonitor {
    enum Event {
        case pressBegan          // key went down while idle → start recording
        case pressEnded          // key released after a hold → stop & transcribe
        case lockHandsFree       // switch the current recording into hands-free
        case toggleStop          // pressed again while hands-free → stop & transcribe
        case cancel              // Esc or interrupted by another shortcut
        case tapTooShort         // single quick tap that never became a double-tap
    }

    var onEvent: ((Event) -> Void)?
    /// Asked on key-down whether a hands-free session is currently active.
    var isHandsFreeActive: (() -> Bool)?
    /// Asked whether any recording (push-to-talk or hands-free) is in progress.
    var isRecording: (() -> Bool)?

    var hotkey: Hotkey = .default {
        didSet { if hotkey != oldValue { keyIsDown = false } }
    }
    var doubleTapEnabled = true
    /// While true (e.g. the Settings shortcut recorder is open) every event passes through.
    var isSuspended = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false
    private var downAt: TimeInterval = 0
    private var lastTapUpAt: TimeInterval = 0
    private var otherKeyPressedDuringHold = false
    private var pendingShortTap: DispatchWorkItem?

    /// A press shorter than this counts as a "tap" rather than push-to-talk.
    private let tapThreshold: TimeInterval = 0.28
    /// Second tap must start within this window after the first tap ends.
    private let doubleTapWindow: TimeInterval = 0.35

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[BiscuitFlow] Failed to create event tap — Accessibility permission missing?")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[BiscuitFlow] Hotkey tap started")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables slow taps; turn ourselves straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case _ where isSuspended:
            return Unmanaged.passUnretained(event)
        case .flagsChanged:
            handleFlagsChanged(event)
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// `HFLOW_DEBUG=1` logs modifier transitions (useful in VMs with odd keyboards).
    private let debug = ProcessInfo.processInfo.environment["HFLOW_DEBUG"] != nil
    /// Debug/testing: `HFLOW_HOTKEY_KEYCODE=58` listens to a different physical key with the
    /// same modifier flag (e.g. left ⌥ for right ⌥) — VMs often can't send right-side modifiers.
    private let keyCodeOverride = ProcessInfo.processInfo.environment["HFLOW_HOTKEY_KEYCODE"].flatMap(Int64.init)

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if debug { NSLog("[BiscuitFlow] flagsChanged keyCode=%lld flags=0x%llx", keyCode, event.flags.rawValue) }
        // Combos are driven by keyDown/keyUp; modifier changes mid-hold don't matter.
        guard hotkey.isModifierOnly else { return }
        guard keyCode == keyCodeOverride ?? hotkey.keyCode else {
            // Another modifier changed while ours is held (e.g. fn+shift): treat as a shortcut.
            if keyIsDown, !(isHandsFreeActive?() ?? false) { otherKeyPressedDuringHold = true }
            return
        }
        let down = event.flags.contains(hotkey.modifiers)
        guard down != keyIsDown else { return }
        if down { pressDown() } else { pressUp() }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if !hotkey.isModifierOnly {
            if keyIsDown, keyCode == hotkey.keyCode {
                return nil // auto-repeat while held
            }
            if hotkey.matches(keyCode: keyCode, flags: event.flags) {
                pressDown()
                return nil
            }
        }

        let recording = isRecording?() ?? false
        if recording, keyCode == 53 { // Esc
            emit(.cancel)
            return nil
        }
        if keyIsDown, recording, keyCode == 49 { // Space while holding the key
            if isHandsFreeActive?() != true { emit(.lockHandsFree) }
            return nil
        }
        if keyIsDown, recording, isHandsFreeActive?() != true {
            // fn+arrow, ⌥+letter, etc. The user is using a shortcut, not dictating.
            otherKeyPressedDuringHold = true
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !hotkey.isModifierOnly, keyIsDown,
              event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keyCode else {
            return Unmanaged.passUnretained(event)
        }
        pressUp()
        return nil
    }

    // MARK: - Press state machine (shared by combos and lone modifiers)

    private func pressDown() {
        keyIsDown = true
        let now = ProcessInfo.processInfo.systemUptime
        downAt = now
        otherKeyPressedDuringHold = false

        if isHandsFreeActive?() == true {
            emit(.toggleStop)
            return
        }
        if doubleTapEnabled, let pending = pendingShortTap, now - lastTapUpAt <= doubleTapWindow {
            // Second tap of a double-tap: keep the recording running, hands-free.
            pending.cancel()
            pendingShortTap = nil
            emit(.lockHandsFree)
            return
        }
        if isRecording?() == true { return }
        emit(.pressBegan)
    }

    private func pressUp() {
        keyIsDown = false
        let now = ProcessInfo.processInfo.systemUptime
        let held = now - downAt
        guard isRecording?() == true, isHandsFreeActive?() != true else { return }

        if otherKeyPressedDuringHold {
            emit(.cancel)
            return
        }
        if held < tapThreshold {
            lastTapUpAt = now
            if doubleTapEnabled {
                // Wait briefly to see whether this becomes a double-tap.
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingShortTap = nil
                    self.emit(.tapTooShort)
                }
                pendingShortTap = work
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
            } else {
                emit(.tapTooShort)
            }
        } else {
            emit(.pressEnded)
        }
    }

    /// The tap's run-loop source lives on the main run loop, so we're already on the
    /// main thread here. Deliver synchronously so `isRecording`/`isHandsFreeActive`
    /// reflect the new state before the next key event is processed. Receivers must
    /// return quickly (the system disables taps that block).
    private func emit(_ event: Event) {
        onEvent?(event)
    }
}

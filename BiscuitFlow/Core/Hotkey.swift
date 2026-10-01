import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// The dictation shortcut: either a key combo (⌥D, ⌃⇧Space, F5…) or a lone modifier key
/// held by itself (fn, right ⌥…). Persisted as a compact string in UserDefaults.
struct Hotkey: Equatable, RawRepresentable {
    /// Virtual key code (kVK_*). For modifier-only hotkeys, the modifier's own key code.
    var keyCode: Int64
    /// Required modifier flags (subset of `Hotkey.modifierMask`). For modifier-only hotkeys,
    /// the flag that key sets.
    var modifiers: CGEventFlags
    var isModifierOnly: Bool

    static let optionD = Hotkey(keyCode: Int64(kVK_ANSI_D), modifiers: .maskAlternate, isModifierOnly: false)
    static let fn = Hotkey(keyCode: Int64(kVK_Function), modifiers: .maskSecondaryFn, isModifierOnly: true)
    static let `default` = optionD

    static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]

    init(keyCode: Int64, modifiers: CGEventFlags, isModifierOnly: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.modifierMask)
        self.isModifierOnly = isModifierOnly
    }

    // MARK: Persistence ("combo:2:524288" / "mod:63:8388608")

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 3, let code = Int64(parts[1]), let mods = UInt64(parts[2]) else { return nil }
        switch parts[0] {
        case "combo": self.init(keyCode: code, modifiers: CGEventFlags(rawValue: mods), isModifierOnly: false)
        case "mod": self.init(keyCode: code, modifiers: CGEventFlags(rawValue: mods), isModifierOnly: true)
        default: return nil
        }
    }

    var rawValue: String {
        "\(isModifierOnly ? "mod" : "combo"):\(keyCode):\(modifiers.rawValue)"
    }

    // MARK: Matching

    /// Keys for which macOS sets the fn flag on its own (arrows, F-keys, Home/End…).
    static func keyImpliesFn(_ keyCode: Int64) -> Bool {
        functionKeyNames[keyCode] != nil || navigationKeyNames[keyCode] != nil
    }

    /// Whether a keyDown/keyUp with these flags is this (combo) hotkey.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard !isModifierOnly, keyCode == self.keyCode else { return false }
        var pressed = flags.intersection(Self.modifierMask)
        if !modifiers.contains(.maskSecondaryFn) && Self.keyImpliesFn(keyCode) {
            pressed.remove(.maskSecondaryFn)
        }
        return pressed == modifiers
    }

    /// The flag a lone modifier key sets, or nil if `keyCode` isn't a modifier.
    static func flag(forModifierKeyCode keyCode: Int64) -> CGEventFlags? {
        switch Int(keyCode) {
        case kVK_Function: return .maskSecondaryFn
        case kVK_Option, kVK_RightOption: return .maskAlternate
        case kVK_Command, kVK_RightCommand: return .maskCommand
        case kVK_Control, kVK_RightControl: return .maskControl
        case kVK_Shift, kVK_RightShift: return .maskShift
        default: return nil
        }
    }

    // MARK: Display

    /// "⌥D", "⌃⇧Space", "fn", "right ⌥".
    var displayName: String {
        if isModifierOnly { return Self.modifierKeyNames[keyCode] ?? "key \(keyCode)" }
        var s = ""
        if modifiers.contains(.maskSecondaryFn) { s += "fn " }
        if modifiers.contains(.maskControl) { s += "⌃" }
        if modifiers.contains(.maskAlternate) { s += "⌥" }
        if modifiers.contains(.maskShift) { s += "⇧" }
        if modifiers.contains(.maskCommand) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: Int64) -> String {
        if let name = specialKeyNames[keyCode] ?? functionKeyNames[keyCode] ?? navigationKeyNames[keyCode] {
            return name
        }
        if let ch = KeyboardLayout.character(for: CGKeyCode(keyCode)), !ch.isEmpty {
            return ch.uppercased()
        }
        return "key \(keyCode)"
    }

    private static let modifierKeyNames: [Int64: String] = [
        Int64(kVK_Function): "fn",
        Int64(kVK_Option): "left ⌥", Int64(kVK_RightOption): "right ⌥",
        Int64(kVK_Command): "left ⌘", Int64(kVK_RightCommand): "right ⌘",
        Int64(kVK_Control): "left ⌃", Int64(kVK_RightControl): "right ⌃",
        Int64(kVK_Shift): "left ⇧", Int64(kVK_RightShift): "right ⇧",
    ]

    private static let specialKeyNames: [Int64: String] = [
        Int64(kVK_Space): "Space", Int64(kVK_Return): "↩", Int64(kVK_Tab): "⇥",
        Int64(kVK_Delete): "⌫", Int64(kVK_Escape): "⎋", Int64(kVK_ANSI_KeypadEnter): "⌤",
    ]

    private static let navigationKeyNames: [Int64: String] = [
        Int64(kVK_LeftArrow): "←", Int64(kVK_RightArrow): "→", Int64(kVK_UpArrow): "↑", Int64(kVK_DownArrow): "↓",
        Int64(kVK_Home): "↖", Int64(kVK_End): "↘", Int64(kVK_PageUp): "⇞", Int64(kVK_PageDown): "⇟",
        Int64(kVK_ForwardDelete): "⌦", Int64(kVK_Help): "Help",
    ]

    private static let functionKeyNames: [Int64: String] = {
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return Dictionary(uniqueKeysWithValues: codes.enumerated().map { (Int64($1), "F\($0 + 1)") })
    }()

    static func isFunctionKey(_ keyCode: Int64) -> Bool { functionKeyNames[keyCode] != nil }
}

/// Translates between physical key codes and characters using the current keyboard layout.
enum KeyboardLayout {
    static func character(for keyCode: CGKeyCode) -> String? {
        withLayout { layout in
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        } ?? nil
    }

    /// The physical key that types `character` in the current layout, if any.
    static func keyCode(for character: String) -> CGKeyCode? {
        for code in 0..<CGKeyCode(128) where self.character(for: code) == character {
            return code
        }
        return nil
    }

    private static func withLayout<T>(_ body: (UnsafePointer<UCKeyboardLayout>) -> T) -> T? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw in
            raw.baseAddress.map { body($0.assumingMemoryBound(to: UCKeyboardLayout.self)) }
        }
    }
}

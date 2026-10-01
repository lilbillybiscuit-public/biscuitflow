import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import BiscuitFlow

final class HotkeyTests: XCTestCase {
    func testDefaultIsOptionD() {
        XCTAssertEqual(Hotkey.default, .optionD)
        XCTAssertEqual(Hotkey.optionD.keyCode, Int64(kVK_ANSI_D))
        XCTAssertFalse(Hotkey.optionD.isModifierOnly)
    }

    func testRawValueRoundTrip() {
        for hk in [Hotkey.optionD, .fn,
                   Hotkey(keyCode: Int64(kVK_Space), modifiers: [.maskControl, .maskShift], isModifierOnly: false),
                   Hotkey(keyCode: Int64(kVK_RightOption), modifiers: .maskAlternate, isModifierOnly: true)] {
            XCTAssertEqual(Hotkey(rawValue: hk.rawValue), hk)
        }
        XCTAssertNil(Hotkey(rawValue: "garbage"))
    }

    func testComboMatchingIsExact() {
        let d = Int64(kVK_ANSI_D)
        XCTAssertTrue(Hotkey.optionD.matches(keyCode: d, flags: .maskAlternate))
        // Non-modifier flags (caps lock, device bits) are ignored.
        XCTAssertTrue(Hotkey.optionD.matches(keyCode: d, flags: [.maskAlternate, .maskAlphaShift, CGEventFlags(rawValue: 0x20)]))
        XCTAssertFalse(Hotkey.optionD.matches(keyCode: d, flags: []))
        XCTAssertFalse(Hotkey.optionD.matches(keyCode: d, flags: [.maskAlternate, .maskShift]))
        XCTAssertFalse(Hotkey.optionD.matches(keyCode: d, flags: [.maskAlternate, .maskCommand]))
        XCTAssertFalse(Hotkey.optionD.matches(keyCode: Int64(kVK_ANSI_F), flags: .maskAlternate))
        XCTAssertFalse(Hotkey.fn.matches(keyCode: Int64(kVK_Function), flags: .maskSecondaryFn)) // modifier-only never "matches" a keyDown
    }

    func testImplicitFnIgnoredForArrowsAndFKeys() {
        let f5 = Hotkey(keyCode: Int64(kVK_F5), modifiers: [], isModifierOnly: false)
        XCTAssertTrue(f5.matches(keyCode: Int64(kVK_F5), flags: .maskSecondaryFn))
        let optLeft = Hotkey(keyCode: Int64(kVK_LeftArrow), modifiers: .maskAlternate, isModifierOnly: false)
        XCTAssertTrue(optLeft.matches(keyCode: Int64(kVK_LeftArrow), flags: [.maskAlternate, .maskSecondaryFn]))
    }

    func testDisplayNames() {
        XCTAssertEqual(Hotkey.fn.displayName, "fn")
        XCTAssertEqual(Hotkey(keyCode: Int64(kVK_RightOption), modifiers: .maskAlternate, isModifierOnly: true).displayName, "right ⌥")
        XCTAssertEqual(Hotkey(keyCode: Int64(kVK_Space), modifiers: [.maskShift, .maskControl], isModifierOnly: false).displayName, "⌃⇧Space")
        XCTAssertEqual(Hotkey(keyCode: Int64(kVK_F5), modifiers: [], isModifierOnly: false).displayName, "F5")
        // Letter comes from the active layout; on US/most Latin layouts it's D.
        XCTAssertTrue(Hotkey.optionD.displayName.hasPrefix("⌥"))
    }
}

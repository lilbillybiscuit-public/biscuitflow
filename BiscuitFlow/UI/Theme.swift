import AppKit
import SwiftUI

/// BiscuitFlow's look: warm toasted neutrals, honey-amber accent, rounded type.
enum Theme {
    // Surfaces
    static let canvas = dynamic(light: 0xFBF7F1, dark: 0x1C1A17)
    static let sidebar = dynamic(light: 0xF4EDE3, dark: 0x171512)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x26231F)
    static let hairline = dynamic(light: 0xE9E0D2, dark: 0x3A352E)
    static let sidebarSelection = dynamic(light: 0xEDE2D0, dark: 0x352F27)
    static let sidebarHover = dynamic(light: 0xF2E9DB, dark: 0x2B2722)

    /// Primary button fill.
    static let accent = dynamic(light: 0xD9822B, dark: 0xF0A34C)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1C1A17)
    /// Icons, selection marks, progress.
    static let highlight = dynamic(light: 0xC0701F, dark: 0xF4B867)

    // Dictation pill (always dark, so it reads on any wallpaper)
    static let pillInk = Color(hex: 0x1E1B17)
    static let pillStroke = Color.white.opacity(0.14)
    static let honey = Color(hex: 0xF4B867)
    static let crumb = Color(hex: 0xFFE9C7)
    static let record = Color(hex: 0xF0644A)
    static let error = Color(hex: 0xF0644A)

    /// Rounded display face for headings and big numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// The BiscuitFlow mark: a round "biscuit" with three rising bars cut out of it.
struct BrandMark: View {
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(color)
                HStack(alignment: .bottom, spacing: s * 0.08) {
                    ForEach([0.26, 0.42, 0.58], id: \.self) { h in
                        RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                            .frame(width: s * 0.12, height: s * h)
                    }
                }
                .offset(y: s * 0.03)
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

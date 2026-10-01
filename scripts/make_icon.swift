// Renders the BiscuitFlow app icon into the asset catalog: swift scripts/make_icon.swift
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "BiscuitFlow/Resources/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a).cgColor
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let space = CGColorSpaceCreateDeviceRGB()

    // macOS icon grid: 824/1024 body.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tile = CGPath(roundedRect: body, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: rgb(0x000000, 0.3))
    ctx.addPath(tile); ctx.setFillColor(rgb(0xD9822B)); ctx.fillPath()
    ctx.restoreGState()

    // Toasted amber tile: honey at the top, deeper bake at the bottom.
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [rgb(0xF6C16E), rgb(0xE08A33), rgb(0xB8621C)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // The biscuit: a cream disc with a subtle rim.
    let r = body.width * 0.30
    let c = CGPoint(x: s / 2, y: s / 2)
    let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.025, color: rgb(0x5A2E0A, 0.35))
    ctx.setFillColor(rgb(0xFFF1DA)); ctx.fillEllipse(in: disc)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setStrokeColor(rgb(0xF2D3A3)); ctx.setLineWidth(max(1, s * 0.012))
    ctx.strokeEllipse(in: disc.insetBy(dx: s * 0.02, dy: s * 0.02))

    // Three rising bars "baked" into the biscuit.
    let heights: [CGFloat] = [0.26, 0.42, 0.58].map { $0 * 2 * r }
    let barW = 2 * r * 0.13
    let gap = 2 * r * 0.09
    var x = c.x - (3 * barW + 2 * gap) / 2
    let baseY = c.y - 2 * r * 0.29
    for h in heights {
        let bar = CGPath(roundedRect: CGRect(x: x, y: baseY, width: barW, height: h),
                         cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
        ctx.addPath(bar); ctx.setFillColor(rgb(0xC46A1F)); ctx.fillPath()
        x += barW + gap
    }
    ctx.restoreGState()

    ctx.addPath(tile)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18)); ctx.setLineWidth(max(1, s / 512)); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! render(size * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted]).write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(out.path)")

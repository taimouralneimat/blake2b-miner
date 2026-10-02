// Draws the app icon into an .iconset folder. Usage: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded square background with a deep orange-to-amber gradient.
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.62, blue: 0.11, alpha: 1),
                        NSColor(calibratedRed: 0.86, green: 0.32, blue: 0.05, alpha: 1)])!.draw(in: bg, angle: -90)

    // An isometric cube (a block) in white.
    let c = CGPoint(x: s / 2, y: s / 2)
    let r = s * 0.24
    let top = CGPoint(x: c.x, y: c.y + r), bottom = CGPoint(x: c.x, y: c.y - r)
    let ul = CGPoint(x: c.x - r * 0.866, y: c.y + r / 2), ur = CGPoint(x: c.x + r * 0.866, y: c.y + r / 2)
    let ll = CGPoint(x: c.x - r * 0.866, y: c.y - r / 2), lr = CGPoint(x: c.x + r * 0.866, y: c.y - r / 2)
    func face(_ pts: [CGPoint], _ alpha: CGFloat) {
        ctx.beginPath()
        ctx.move(to: pts[0])
        pts.dropFirst().forEach { ctx.addLine(to: $0) }
        ctx.closePath()
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
    }
    face([top, ur, c, ul], 1.0)
    face([ul, c, bottom, ll], 0.82)
    face([c, ur, lr, bottom], 0.64)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

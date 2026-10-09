// Renders the app icon from the logo (docs/images/logo.svg, made by gen_logo.py)
// into an .iconset folder, at every size macOS uses.
// Usage: swift make-icon.swift <logo.svg> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <logo.svg> <out.iconset>\n".utf8))
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The logo at `px` × `px` pixels, with its transparent corners.
func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    logo.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

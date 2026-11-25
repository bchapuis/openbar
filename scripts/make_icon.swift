// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make_icon.swift   (run from the project root)

import AppKit

let canvas: CGFloat = 1024

func draw() -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // macOS icon grid: an 824-point rounded square centred on a 1024 canvas.
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

    // Soft shadow under the plate.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Green gradient, the colour the app uses for "connected".
    let top = NSColor(srgbRed: 0.33, green: 0.86, blue: 0.52, alpha: 1)
    let bottom = NSColor(srgbRed: 0.04, green: 0.55, blue: 0.42, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: shape, angle: 90)

    // A light sheen on the upper half.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.18), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // A white shield with a green lock (the symbol's two layers).
    let lock = NSColor(srgbRed: 0.08, green: 0.60, blue: 0.44, alpha: 1)
    let configuration = NSImage.SymbolConfiguration(pointSize: 500, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [lock, .white]))
    let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(configuration)!
    let size = symbol.size
    let origin = NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 6)
    NSGraphicsContext.saveGraphicsState()
    let symbolShadow = NSShadow()
    symbolShadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    symbolShadow.shadowOffset = NSSize(width: 0, height: -8)
    symbolShadow.shadowBlurRadius = 16
    symbolShadow.set()
    symbol.draw(in: NSRect(origin: origin, size: size))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func resized(_ source: NSBitmapImageRep, to pixels: Int) -> Data {
    let target = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return target.representation(using: .png, properties: [:])!
}

let master = draw()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try resized(master, to: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try resized(master, to: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
if CommandLine.arguments.count > 1 {
    try resized(master, to: 512).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")

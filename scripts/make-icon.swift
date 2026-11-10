// Draws the Overview app icon and writes Resources/AppIcon.icns.
// Run from the project root: swift scripts/make-icon.swift
//
// Vector redraw of Resources/icon-source.png (264 x 284 px). Geometry is in
// source pixels, measured from that image: circle outer radius 94.5, stroke
// width 6.3, five 45° stripes 19.25 px apart with half-lengths 31, 50, 68.5.
// Color #506D55 is the darkest pixel in the source.
import AppKit

let green = NSColor(srgbRed: 0x50 / 255, green: 0x6D / 255, blue: 0x55 / 255, alpha: 1)
let stroke = 6.3
let circleRadius = 94.5 - stroke / 2
let stripes: [(offset: Double, halfLength: Double)] = [
    (-38.5, 31), (-19.25, 50), (0, 68.5), (19.25, 50), (38.5, 31),
]

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = Double(size) / 1024

    // macOS icon grid: 824 pt rounded square centered on a 1024 pt canvas.
    let plate = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: plate, xRadius: 185 * unit, yRadius: 185 * unit).fill()

    let scale = 313 / 94.5 * unit
    let center = NSPoint(x: 512 * unit, y: 512 * unit)
    green.setStroke()

    let circle = NSBezierPath(ovalIn: NSRect(x: center.x - circleRadius * scale, y: center.y - circleRadius * scale,
                                             width: 2 * circleRadius * scale, height: 2 * circleRadius * scale))
    circle.lineWidth = stroke * scale
    circle.stroke()

    // Stripes run lower-left to upper-right; offsets are perpendicular, toward lower-right.
    let r = 1 / 2.0.squareRoot()
    for stripe in stripes {
        let ox = stripe.offset * r, oy = -stripe.offset * r
        let dx = stripe.halfLength * r, dy = stripe.halfLength * r
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + (ox - dx) * scale, y: center.y + (oy - dy) * scale))
        path.line(to: NSPoint(x: center.x + (ox + dx) * scale, y: center.y + (oy + dy) * scale))
        path.lineWidth = stroke * scale
        path.lineCapStyle = .butt
        path.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(size: points * factor).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")

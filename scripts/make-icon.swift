// Draws the Pulse app icon and writes Icon.icns. Run: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // Squircle on Apple's icon grid: 824pt body centred in a 1024pt canvas.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: body, cornerWidth: 186 * s, cornerHeight: 186 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.05, green: 0.09, blue: 0.20, alpha: 1).cgColor,
        NSColor(srgbRed: 0.09, green: 0.20, blue: 0.38, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])

    // Faint baseline grid.
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.07).cgColor)
    ctx.setLineWidth(4 * s)
    for y in stride(from: 330.0, through: 730.0, by: 100.0) {
        ctx.move(to: CGPoint(x: 200 * s, y: y * s)); ctx.addLine(to: CGPoint(x: 824 * s, y: y * s))
    }
    ctx.strokePath()

    // Three rising bars, green → amber → red, like load levels.
    let bars: [(x: CGFloat, h: CGFloat, top: NSColor, bottom: NSColor)] = [
        (232, 220, NSColor(srgbRed: 0.40, green: 0.92, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.13, green: 0.70, blue: 0.45, alpha: 1)),
        (437, 360, NSColor(srgbRed: 1.00, green: 0.82, blue: 0.35, alpha: 1), NSColor(srgbRed: 0.96, green: 0.58, blue: 0.16, alpha: 1)),
        (642, 500, NSColor(srgbRed: 1.00, green: 0.47, blue: 0.42, alpha: 1), NSColor(srgbRed: 0.88, green: 0.22, blue: 0.27, alpha: 1)),
    ]
    let barWidth: CGFloat = 150, baseY: CGFloat = 230
    for bar in bars {
        let rect = CGRect(x: bar.x * s, y: baseY * s, width: barWidth * s, height: bar.h * s)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34 * s, cornerHeight: 34 * s, transform: nil))
        ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [bar.bottom.cgColor, bar.top.cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    // Soft top highlight.
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor.white.withAlphaComponent(0.12).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/Icon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: px).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Icon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Icon.icns" : "iconutil failed")

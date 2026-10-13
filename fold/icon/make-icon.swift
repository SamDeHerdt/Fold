// Draws Fold's app icon and writes fold/icon/Fold.icns.
//   swift fold/icon/make-icon.swift <output-dir>
import AppKit

func drawIcon(size s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let u = s / 1024

        // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
        let plate = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
        let platePath = CGPath(roundedRect: plate, cornerWidth: 186 * u, cornerHeight: 186 * u, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(platePath)
        ctx.setFillColor(NSColor(red: 0.2, green: 0.16, blue: 0.5, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(platePath)
        ctx.clip()
        let colors = [
            NSColor(red: 0.16, green: 0.62, blue: 0.72, alpha: 1).cgColor,
            NSColor(red: 0.36, green: 0.29, blue: 0.86, alpha: 1).cgColor,
            NSColor(red: 0.76, green: 0.28, blue: 0.62, alpha: 1).cgColor,
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.minY), end: CGPoint(x: plate.maxX, y: plate.maxY), options: [])
        // Soft top light.
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(glow, start: CGPoint(x: 512 * u, y: plate.maxY), end: CGPoint(x: 512 * u, y: 512 * u), options: [])
        ctx.restoreGState()

        // The pour: a drop at the top, a neck, and the bar it melts into.
        let barH = 190 * u, barW = 600 * u
        let bar = CGRect(x: (1024 * u - barW) / 2, y: 330 * u, width: barW, height: barH)
        let dropR = 50 * u
        let drop = CGPoint(x: 512 * u, y: 752 * u)
        let goo = CGMutablePath()
        goo.addRoundedRect(in: bar, cornerWidth: barH / 2, cornerHeight: barH / 2)
        goo.addEllipse(in: CGRect(x: drop.x - dropR, y: drop.y - dropR, width: dropR * 2, height: dropR * 2))
        let neck = CGMutablePath()
        let top = drop.y - dropR * 0.5, bottom = bar.maxY - 4 * u
        neck.move(to: CGPoint(x: drop.x - dropR * 0.82, y: top))
        neck.addQuadCurve(to: CGPoint(x: drop.x - 92 * u, y: bottom), control: CGPoint(x: drop.x - 16 * u, y: bottom + 34 * u))
        neck.addLine(to: CGPoint(x: drop.x + 92 * u, y: bottom))
        neck.addQuadCurve(to: CGPoint(x: drop.x + dropR * 0.82, y: top), control: CGPoint(x: drop.x + 16 * u, y: bottom + 34 * u))
        neck.closeSubpath()
        goo.addPath(neck)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * u), blur: 22 * u, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(goo)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
        ctx.fillPath(using: .winding)
        ctx.restoreGState()

        // Three icons in the bar.
        let dotR = 34 * u
        ctx.setFillColor(NSColor(red: 0.3, green: 0.24, blue: 0.7, alpha: 1).cgColor)
        for offset in [-150, 0, 150] as [CGFloat] {
            ctx.fillEllipse(in: CGRect(x: 512 * u + offset * u - dotR, y: bar.midY - dotR, width: dotR * 2, height: dotR * 2))
        }
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = out.appendingPathComponent("Fold.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! png(drawIcon(size: CGFloat(pixels)), pixels: pixels).write(to: iconset.appendingPathComponent(name))
}
try! png(drawIcon(size: 1024), pixels: 1024).write(to: out.appendingPathComponent("Fold-preview.png"))
print("wrote \(iconset.path)")

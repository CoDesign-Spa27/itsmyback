import AppKit
import CoreGraphics
import Foundation

// Finder shows this image at its native size in the icon-view window.
// Keep these dimensions in sync with the icon-view area in create-dmg.sh.
let width = 1664
let height = 788
let scale = 2
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/dmg-background.png")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red / 255, green / 255, blue / 255, alpha])!
}

func point(_ x: CGFloat, _ yFromTop: CGFloat) -> CGPoint {
    CGPoint(x: x, y: CGFloat(height) - yFromTop)
}

func drawText(_ value: String, size: CGFloat, weight: NSFont.Weight, ink: NSColor, centerY: CGFloat, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: ink,
        .kern: tracking
    ]
    let text = NSAttributedString(string: value, attributes: attributes)
    let measured = text.size()
    text.draw(at: NSPoint(x: (CGFloat(width) - measured.width) / 2, y: CGFloat(height) - centerY - measured.height / 2))
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width * scale,
    pixelsHigh: height * scale,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create the installer background")
}
bitmap.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let bounds = CGRect(x: 0, y: 0, width: width, height: height)
let space = CGColorSpaceCreateDeviceRGB()
let background = CGGradient(colorsSpace: space, colors: [color(18, 20, 25), color(38, 42, 51)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(background, start: point(0, 0), end: point(0, CGFloat(height)), options: [])

// Subtle blue-grey light keeps the dark surface from feeling flat.
let glow = CGGradient(colorsSpace: space, colors: [color(124, 145, 255, 0.16), color(124, 145, 255, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: point(832, 340), startRadius: 0, endCenter: point(832, 340), endRadius: 700, options: [])
let lowerGlow = CGGradient(colorsSpace: space, colors: [color(255, 255, 255, 0.04), color(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(lowerGlow, startCenter: point(832, 730), startRadius: 0, endCenter: point(832, 730), endRadius: 620, options: [])

let panel = CGRect(x: 116, y: 104, width: 1432, height: 576)
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0, 0, 0, 0.28))
context.setFillColor(color(255, 255, 255, 0.035))
context.addPath(CGPath(roundedRect: panel, cornerWidth: 34, cornerHeight: 34, transform: nil))
context.fillPath()
context.setShadow(offset: .zero, blur: 0)
context.setStrokeColor(color(255, 255, 255, 0.12))
context.setLineWidth(1)
context.addPath(CGPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 33.5, cornerHeight: 33.5, transform: nil))
context.strokePath()

drawText("Install ItsMyBack", size: 30, weight: .semibold, ink: NSColor(calibratedWhite: 1, alpha: 0.94), centerY: 190)
drawText("Move the app to Applications to finish setup", size: 15, weight: .regular, ink: NSColor(calibratedWhite: 1, alpha: 0.52), centerY: 228)

// The Finder icons sit at x=460 and x=1204, y=410. Leave those areas empty.
let arrowY: CGFloat = 410
let arrow = CGMutablePath()
arrow.move(to: point(680, arrowY))
arrow.addLine(to: point(984, arrowY))
context.addPath(arrow)
context.setStrokeColor(color(142, 157, 255, 0.18))
context.setLineWidth(22)
context.setLineCap(.round)
context.strokePath()

let arrowCore = CGMutablePath()
arrowCore.move(to: point(684, arrowY))
arrowCore.addLine(to: point(980, arrowY))
context.addPath(arrowCore)
context.setStrokeColor(color(235, 239, 255, 0.78))
context.setLineWidth(4)
context.setLineCap(.round)
context.strokePath()

let head = CGMutablePath()
head.move(to: point(950, arrowY - 19))
head.addLine(to: point(980, arrowY))
head.addLine(to: point(950, arrowY + 19))
context.addPath(head)
context.setStrokeColor(color(235, 239, 255, 0.78))
context.setLineWidth(4)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

drawText("DRAG TO INSTALL", size: 11, weight: .semibold, ink: NSColor(calibratedWhite: 1, alpha: 0.42), centerY: 604, tracking: 2.8)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the installer background")
}
try png.write(to: output)
print("Generated \(output.path) (\(width) × \(height))")

import AppKit
import Foundation

// A vector-drawn icon: an upright seated figure on a quiet teal surface.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = CGRect(x: 60, y: 60, width: 904, height: 904)
        let path = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
        NSColor(calibratedRed: 0.04, green: 0.34, blue: 0.34, alpha: 1).setFill()
        path.fill()
        NSColor(calibratedRed: 0.80, green: 0.96, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 467, y: 670, width: 128, height: 128)).fill()
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 521, y: 610))
        body.line(to: NSPoint(x: 521, y: 437))
        body.line(to: NSPoint(x: 679, y: 437))
        body.line(to: NSPoint(x: 679, y: 270))
        body.lineWidth = 82
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        NSColor(calibratedRed: 0.80, green: 0.96, blue: 0.88, alpha: 1).setStroke()
        body.stroke()
        let chair = NSBezierPath()
        chair.move(to: NSPoint(x: 360, y: 595))
        chair.line(to: NSPoint(x: 360, y: 351))
        chair.line(to: NSPoint(x: 533, y: 351))
        chair.move(to: NSPoint(x: 386, y: 351))
        chair.line(to: NSPoint(x: 386, y: 249))
        chair.lineWidth = 38
        chair.lineCapStyle = .round
        chair.lineJoinStyle = .round
        NSColor(calibratedRed: 0.35, green: 0.69, blue: 0.65, alpha: 1).setStroke()
        chair.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}

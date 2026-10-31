// Run with: swift Tools/generate-icon.swift
// Original vector sunrise mark, rendered to the App Store's required opaque PNG.
import AppKit
let size = CGSize(width: 1024, height: 1024)
// A 3-channel NSBitmapImageRep isn't a supported drawing target (it renders solid black).
// Draw into an opaque 32-bit CGContext instead; the alpha byte is skipped, so the PNG stays opaque.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSGradient(colors: [NSColor(red: 0.065, green: 0.075, blue: 0.095, alpha: 1),
                    NSColor(red: 0.20, green: 0.15, blue: 0.12, alpha: 1)])!.draw(in: NSRect(origin: .zero, size: size), angle: 45)
let amber = NSColor(red: 1, green: 0.72, blue: 0.43, alpha: 1)
amber.setFill()
let sun = NSBezierPath()
sun.move(to: CGPoint(x: 310, y: 438))
sun.appendArc(withCenter: CGPoint(x: 512, y: 438), radius: 202, startAngle: 0, endAngle: 180)
sun.close()
sun.fill()
amber.setStroke()
func stroke(_ start: CGPoint, _ end: CGPoint, width: CGFloat) {
    let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round
    p.move(to: start); p.line(to: end); p.stroke()
}
stroke(CGPoint(x: 220, y: 400), CGPoint(x: 804, y: 400), width: 16)
for degrees in [0.0, 45, 90, 135, 180] {
    let angle = degrees * .pi / 180
    stroke(CGPoint(x: 512 + cos(angle) * 260, y: 438 + sin(angle) * 260),
           CGPoint(x: 512 + cos(angle) * 308, y: 438 + sin(angle) * 308), width: 16)
}
NSColor(red: 1, green: 0.72, blue: 0.43, alpha: 0.35).setStroke()
stroke(CGPoint(x: 355, y: 340), CGPoint(x: 669, y: 340), width: 8)
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Daybreak/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))

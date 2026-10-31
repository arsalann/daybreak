// Run with: swift Tools/generate-icon.swift
// Sunrise mark in the Daybook style (same palette, sun and ray geometry), rendered to the
// App Store's required opaque 1024 px PNG. Geometry is in a 100-unit space, like Daybook's SVGs.
import AppKit
import CoreGraphics

// An opaque 32-bit context (alpha byte skipped). A 3-channel NSBitmapImageRep can't be drawn into.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// SVG coordinates: origin top-left, y down, 100 units across.
context.translateBy(x: 0, y: 1024)
context.scaleBy(x: 10.24, y: -10.24)

let background = CGColor(srgbRed: 0x17 / 255, green: 0x17 / 255, blue: 0x16 / 255, alpha: 1)
let gold = CGColor(srgbRed: 0xd7 / 255, green: 0xb1 / 255, blue: 0x7a / 255, alpha: 1)
context.setFillColor(background)
context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

let center = CGPoint(x: 50, y: 59)
let radius: CGFloat = 15
let horizonY = center.y + 5.5

// Half sun, sitting just above the horizon.
context.setFillColor(gold)
context.move(to: CGPoint(x: center.x - radius, y: center.y))
context.addArc(center: center, radius: radius, startAngle: .pi, endAngle: 0, clockwise: false)
context.closePath()
context.fillPath()

context.setStrokeColor(gold)
context.setLineWidth(2.8)
context.setLineCap(.round)
// Daybook's rays (18.5 to 24.5 units from the center), upper half only.
for degrees in [180.0, 225, 270, 315, 0] {
    let angle = degrees * .pi / 180
    context.move(to: CGPoint(x: center.x + cos(angle) * 18.5, y: center.y + sin(angle) * 18.5))
    context.addLine(to: CGPoint(x: center.x + cos(angle) * 24.5, y: center.y + sin(angle) * 24.5))
}
// Horizon.
context.move(to: CGPoint(x: center.x - 24.5, y: horizonY))
context.addLine(to: CGPoint(x: center.x + 24.5, y: horizonY))
context.strokePath()

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Daybreak/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))

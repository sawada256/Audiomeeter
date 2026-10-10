import AppKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 220, yRadius: 220).fill()
let heights: [CGFloat] = [160, 300, 470, 640, 470, 300, 160]
for (index, height) in heights.enumerated() {
    NSColor(calibratedRed: 0.95, green: 0.24 + Double(index) * 0.03, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 192 + index * 94, y: Int((1024 - height) / 2), width: 64, height: Int(height)), xRadius: 32, yRadius: 32).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Assets/AppIcon.png"))

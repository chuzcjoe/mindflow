import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.33, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.94, alpha: 1).setFill()
for (index, height) in [150.0, 290, 470, 350, 200].enumerated() {
    let rect = NSRect(x: 256 + Double(index) * 108, y: (1024 - height) / 2, width: 70, height: height)
    NSBezierPath(roundedRect: rect, xRadius: 35, yRadius: 35).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: output)

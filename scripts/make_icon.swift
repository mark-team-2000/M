#!/usr/bin/env swift
// Generates AppIcon.icns for M — same artwork as the runtime icon:
// rounded red gradient square with a heavy white "M".
// Usage: swift scripts/make_icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func render(_ side: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = side * 0.039
    let shape = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2), xRadius: side * 0.226, yRadius: side * 0.226)
    NSGradient(starting: NSColor(calibratedRed: 0.82, green: 0.13, blue: 0.19, alpha: 1), ending: NSColor(calibratedRed: 0.25, green: 0.025, blue: 0.07, alpha: 1))?.draw(in: shape, angle: -65)
    let text = "M" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: side * 0.64, weight: .heavy), .foregroundColor: NSColor.white]
    let size = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2 + side * 0.02), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MIconset-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: work) }
func png(_ side: Int, _ name: String) throws {
    let data = render(CGFloat(side)).representation(using: .png, properties: [:])!
    try data.write(to: work.appendingPathComponent(name))
}
try png(16, "icon_16x16.png"); try png(32, "icon_16x16@2x.png")
try png(32, "icon_32x32.png"); try png(64, "icon_32x32@2x.png")
try png(128, "icon_128x128.png"); try png(256, "icon_128x128@2x.png")
try png(256, "icon_256x256.png"); try png(512, "icon_256x256@2x.png")
try png(512, "icon_512x512.png"); try png(1024, "icon_512x512@2x.png")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", output, work.path]
task.standardError = FileHandle.standardError
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil fallito (\(task.terminationStatus))\n".utf8))
    exit(1)
}
print("Icona generata: \(output)")

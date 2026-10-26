import AppKit

// A vector-drawn icon; regenerate with swift Scripts/GenerateIcon.swift.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let factor = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: factor)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.34, blue: 0.36, alpha: 1), ending: NSColor(srgbRed: 0.04, green: 0.19, blue: 0.22, alpha: 1))!.draw(in: background, angle: -90)
    let heart = NSBezierPath()
    heart.move(to: NSPoint(x: 512, y: 280))
    heart.curve(to: NSPoint(x: 266, y: 625), controlPoint1: NSPoint(x: 452, y: 337), controlPoint2: NSPoint(x: 245, y: 480))
    heart.curve(to: NSPoint(x: 512, y: 676), controlPoint1: NSPoint(x: 286, y: 785), controlPoint2: NSPoint(x: 444, y: 795))
    heart.curve(to: NSPoint(x: 758, y: 625), controlPoint1: NSPoint(x: 580, y: 795), controlPoint2: NSPoint(x: 738, y: 785))
    heart.curve(to: NSPoint(x: 512, y: 280), controlPoint1: NSPoint(x: 779, y: 480), controlPoint2: NSPoint(x: 572, y: 337))
    heart.close()
    NSColor(srgbRed: 0.96, green: 0.53, blue: 0.57, alpha: 1).setFill()
    heart.fill()
    let pulse = NSBezierPath()
    pulse.move(to: NSPoint(x: 195, y: 520))
    for point in [(373, 520), (431, 604), (500, 418), (566, 559), (608, 520), (829, 520)] {
        pulse.line(to: NSPoint(x: point.0, y: point.1))
    }
    pulse.lineWidth = 27
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor.white.setStroke()
    pulse.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}

func lengthBytes(_ length: Int) -> Data {
    var value = UInt32(length).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var chunks = Data()
for (type, filename) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
                         ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
                         ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
                         ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
                         ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
                         ("ic14", "icon_256x256@2x.png")] {
    let png = try Data(contentsOf: folder.appendingPathComponent(filename))
    chunks.append(Data(type.utf8))
    chunks.append(lengthBytes(png.count + 8))
    chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(lengthBytes(chunks.count + 8))
icns.append(chunks)
try icns.write(to: root.appendingPathComponent("Resources/AppIcon.icns"))

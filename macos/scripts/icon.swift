import AppKit

let target = CommandLine.arguments[1]
var family = Data()
func uint32(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
}
for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let bounds = CGRect(x: 80, y: 80, width: 864, height: 864)
    NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210).fill()
    NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.66, alpha: 1).setStroke()
    let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 14, dy: 14), xRadius: 200, yRadius: 200)
    border.lineWidth = 14
    border.stroke()
    let shirt = NSBezierPath()
    shirt.move(to: CGPoint(x: 360, y: 735))
    for p in [CGPoint(x: 220, y: 640), CGPoint(x: 290, y: 520), CGPoint(x: 355, y: 550),
              CGPoint(x: 355, y: 300), CGPoint(x: 670, y: 300), CGPoint(x: 670, y: 550),
              CGPoint(x: 735, y: 520), CGPoint(x: 805, y: 640), CGPoint(x: 665, y: 735), CGPoint(x: 595, y: 735)] {
        shirt.line(to: p)
    }
    shirt.curve(to: CGPoint(x: 430, y: 735), controlPoint1: CGPoint(x: 585, y: 640), controlPoint2: CGPoint(x: 440, y: 640))
    shirt.close()
    NSColor(calibratedRed: 0.57, green: 0.97, blue: 0.77, alpha: 1).setFill()
    shirt.fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
    family.append(type.data(using: .ascii)!)
    family.append(uint32(png.count + 8))
    family.append(png)
}
var output = "icns".data(using: .ascii)!
output.append(uint32(family.count + 8))
output.append(family)
try output.write(to: URL(fileURLWithPath: target))

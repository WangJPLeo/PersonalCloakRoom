import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// iOS supplies the rounded icon mask; its source image must have no transparency.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Invalid app icon") }
let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
context.setFillColor(CGColor(red: 0.08, green: 0.14, blue: 0.15, alpha: 1))
context.fill(bounds)
context.draw(image, in: bounds)
guard let opaque = context.makeImage() else { fatalError("Cannot flatten app icon") }
let bytes = NSMutableData()
guard let output = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot encode app icon") }
CGImageDestinationAddImage(output, opaque, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Cannot encode app icon") }
try (bytes as Data).write(to: url, options: .atomic)

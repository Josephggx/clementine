import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments[1]
let version = CommandLine.arguments[2]
let width: CGFloat = 720, height: CGFloat = 540, scale: CGFloat = 2
let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.scaleBy(x: scale, y: scale)
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let orange = color(1, 0.43, 0.16)
let white = color(0.97, 0.96, 0.94)
let muted = color(0.65, 0.64, 0.61)
func rounded(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
  let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  fill.setFill(); path.fill()
  if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
}
func text(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat,
  size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = white,
  alignment: NSTextAlignment = .left) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = alignment
  let font = NSFont.systemFont(ofSize: size, weight: weight)
  (string as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size * 2.8),
    withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

color(0.14, 0.14, 0.13).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
  color(0.60, 0.29, 0.13, 0.28).cgColor, color(0.14, 0.14, 0.13, 0).cgColor
] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 670, y: 35), startRadius: 0,
  endCenter: CGPoint(x: 670, y: 35), endRadius: 420, options: [])

text("Clémentine", x: 42, y: 29, width: 220, size: 17, weight: .semibold)
rounded(CGRect(x: 574, y: 27, width: 104, height: 27), radius: 13,
  fill: color(1, 1, 1, 0.04), stroke: color(1, 1, 1, 0.09))
text("VERSION \(version)", x: 580, y: 34, width: 92, size: 9, weight: .semibold,
  color: muted, alignment: .center)
text("Installez Clémentine.", x: 42, y: 83, width: 640, size: 34, weight: .bold)
text("Glissez l’app dans Applications.", x: 43, y: 129, width: 630,
  size: 15, color: muted)

// The icons remain real Finder items, above these subtle landing surfaces.
for x: CGFloat in [100, 440] {
  rounded(CGRect(x: x, y: 179, width: 180, height: 166), radius: 25,
    fill: color(0.91, 0.90, 0.88), stroke: color(1, 1, 1, 0.30))
}
rounded(CGRect(x: 330, y: 225, width: 60, height: 40), radius: 20,
  fill: color(1, 0.43, 0.16, 0.11), stroke: color(1, 0.43, 0.16, 0.16))
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 346, y: 245)); arrow.line(to: CGPoint(x: 374, y: 245))
arrow.move(to: CGPoint(x: 365, y: 236)); arrow.line(to: CGPoint(x: 374, y: 245))
arrow.line(to: CGPoint(x: 365, y: 254))
arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
orange.setStroke(); arrow.stroke()

let divider = NSBezierPath()
divider.move(to: CGPoint(x: 42, y: 377)); divider.line(to: CGPoint(x: 678, y: 377))
color(1, 1, 1, 0.09).setStroke(); divider.lineWidth = 1; divider.stroke()
for (index, x, title, caption) in [
  ("1", CGFloat(42), "Glissez pour installer", "Attendez la fin de la copie."),
  ("2", CGFloat(370), "Ouvrez depuis Applications", "Clémentine est prête à vous suivre.")
] {
  rounded(CGRect(x: x, y: 399, width: 25, height: 25), radius: 12.5,
    fill: color(1, 0.43, 0.16, 0.14))
  text(index, x: x, y: 403, width: 25, size: 12, weight: .semibold,
    color: orange, alignment: .center)
  text(title, x: x + 35, y: 397, width: 280, size: 13, weight: .semibold)
  text(caption, x: x + 35, y: 418, width: 280, size: 11, color: muted)
}
text("macOS 14 ou ultérieur  ·  Apple Silicon", x: 42, y: 456, width: 636,
  size: 10, color: color(0.45, 0.45, 0.42), alignment: .center)
NSGraphicsContext.restoreGraphicsState()

// Finder uses the TIFF's logical point size, keeping Retina text crisp.
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
  UTType.tiff.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 144,
  kCGImagePropertyDPIHeight: 144] as CFDictionary)
precondition(CGImageDestinationFinalize(destination))

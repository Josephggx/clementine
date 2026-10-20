import AppKit
import ImageIO
import UniformTypeIdentifiers

// The app icon is the sidebar flower at app-icon scale, on a warm charcoal tile.
let output = CommandLine.arguments[1]
let light = CommandLine.arguments.contains("--light")
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
  bytesPerRow: 0, space: space,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(red: r, green: g, blue: b, alpha: a)
}

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: tileRect, cornerWidth: 190, cornerHeight: 190, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0, 0, 0, 0.25))
context.addPath(tile); context.setFillColor(light ? color(0.98, 0.98, 0.97) : color(0.14, 0.14, 0.13)); context.fillPath()
context.restoreGState()
context.saveGState(); context.addPath(tile); context.clip()
let tileGradient = CGGradient(colorsSpace: space,
  colors: (light ? [color(1, 1, 1), color(0.94, 0.94, 0.93)] :
    [color(0.22, 0.215, 0.20), color(0.105, 0.105, 0.095)]) as CFArray,
  locations: [0, 1])!
context.drawLinearGradient(tileGradient, start: CGPoint(x: 320, y: 900),
  end: CGPoint(x: 760, y: 110),
  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.restoreGState()

let center = CGPoint(x: 512, y: 512)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -4), blur: 24,
  color: color(1, 0.28, 0.02, 0.30))
for index in 0..<8 {
  context.saveGState()
  context.translateBy(x: center.x, y: center.y)
  context.rotate(by: CGFloat(index) * .pi / 4)
  let petal = CGMutablePath()
  petal.move(to: CGPoint(x: 0, y: 18))
  petal.addCurve(to: CGPoint(x: -95, y: 160),
    control1: CGPoint(x: -25, y: 55), control2: CGPoint(x: -95, y: 86))
  petal.addCurve(to: CGPoint(x: 0, y: 332),
    control1: CGPoint(x: -95, y: 270), control2: CGPoint(x: -52, y: 332))
  petal.addCurve(to: CGPoint(x: 95, y: 160),
    control1: CGPoint(x: 52, y: 332), control2: CGPoint(x: 95, y: 270))
  petal.addCurve(to: CGPoint(x: 0, y: 18),
    control1: CGPoint(x: 95, y: 86), control2: CGPoint(x: 25, y: 55))
  petal.closeSubpath()
  context.addPath(petal); context.setFillColor(color(0.98, 0.37, 0.08)); context.fillPath()
  context.saveGState(); context.addPath(petal); context.clip()
  let petalGradient = CGGradient(colorsSpace: space,
    colors: [color(1, 0.66, 0.22), color(0.96, 0.28, 0.045)] as CFArray,
    locations: [0, 1])!
  context.drawLinearGradient(petalGradient, start: CGPoint(x: -40, y: 320),
    end: CGPoint(x: 65, y: 15), options: [])
  context.restoreGState()
  context.addPath(petal); context.setStrokeColor(color(1, 0.78, 0.39, 0.38))
  context.setLineWidth(4); context.strokePath()
  context.restoreGState()
}
context.restoreGState()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14,
  color: color(0.4, 0.08, 0, 0.28))
context.setFillColor(color(0.98, 0.36, 0.06))
context.fillEllipse(in: CGRect(x: 407, y: 407, width: 210, height: 210))
context.restoreGState()
let coreGradient = CGGradient(colorsSpace: space,
  colors: [color(1, 0.72, 0.27), color(0.96, 0.29, 0.04)] as CFArray,
  locations: [0, 1])!
context.saveGState(); context.addEllipse(in: CGRect(x: 414, y: 414, width: 196, height: 196)); context.clip()
context.drawLinearGradient(coreGradient, start: CGPoint(x: 455, y: 610),
  end: CGPoint(x: 570, y: 410), options: [])
context.restoreGState()
context.setStrokeColor(color(1, 0.85, 0.52, 0.48)); context.setLineWidth(5)
context.strokeEllipse(in: CGRect(x: 414, y: 414, width: 196, height: 196))

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)

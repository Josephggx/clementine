import AppKit

// All dimensions are points. The empty centre and the four-point gutters are not drop targets.
enum WheelGeometry {
  static let inner = 48.64
  // Keep the transparent hub just inside the petal stroke so the desktop
  // visible through it never appears to overlap the petals.
  static let hubHole = inner - 0.75
  static let outer = 119.52
  static let backdrop = 125.92
  static let gap = 4.0
  static let side = 272.0
  static func flowerProgress(_ progress: CGFloat, index: Int, count: Int) -> CGFloat {
    guard count > 0 else { return 1 }
    // A very short clockwise cascade keeps the opening organic while every
    // petal still feels attached to the same gesture.
    let delay = min(0.12, CGFloat(index) * 0.012)
    let t = min(1, max(0, (progress - delay) / (1 - delay)))
    return 1 - pow(1 - t, 3)
  }
  static func flowerTransform(progress: CGFloat, index: Int, count: Int, center: CGPoint) -> CGAffineTransform {
    let p = flowerProgress(progress, index: index, count: count)
    let a = angle(index, count: count)
    let scale = 0.74 + 0.26 * p
    let inward = 25 * (1 - p)
    let pivot = point(84.5312, a, center: center)
    return CGAffineTransform(translationX: -inward * cos(a), y: -inward * sin(a))
      .translatedBy(x: pivot.x, y: pivot.y)
      .scaledBy(x: scale, y: scale)
      .translatedBy(x: -pivot.x, y: -pivot.y)
  }
  static func backdropPath(center: CGPoint) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x-backdrop, y: center.y-backdrop,
                            width: backdrop*2, height: backdrop*2), transform: nil)
  }
  static func backdropRingPath(center: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: center.x-backdrop, y: center.y-backdrop,
                              width: backdrop*2, height: backdrop*2))
    let hole = hubHole
    path.addEllipse(in: CGRect(x: center.x-hole, y: center.y-hole,
                              width: hole*2, height: hole*2))
    return path
  }
  static func openingTransform(scale: CGFloat, pointer: CGPoint, bounds: CGRect, anchor: CGPoint) -> CATransform3D {
    let pivot = CGPoint(x: bounds.width * anchor.x, y: bounds.height * anchor.y)
    var transform = CATransform3DIdentity
    transform.m11 = scale
    transform.m22 = scale
    transform.m41 = (1 - scale) * (pointer.x - pivot.x)
    transform.m42 = (1 - scale) * (pointer.y - pivot.y)
    return transform
  }
  static func origin(around point: NSPoint, in area: NSRect) -> NSPoint {
    NSPoint(x: min(max(point.x - side / 2, area.minX), max(area.minX, area.maxX - side)),
            y: min(max(point.y - side / 2, area.minY), max(area.minY, area.maxY - side)))
  }
  static func operation(allowed: NSDragOperation) -> NSDragOperation {
    // Consuming a file for conversion must never ask the source to move or delete it.
    for operation: NSDragOperation in [.copy, .generic, .link, .private] {
      if allowed.contains(operation) { return operation }
    }
    return []
  }
  static func angle(_ index: Int, count: Int) -> Double {
    (count == 3 ? Double.pi : Double.pi / 2) - 2 * Double.pi * Double(index) / Double(count)
  }
  static func point(_ radius: Double, _ angle: Double, center: NSPoint) -> NSPoint {
    NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
  }
  static func petal(_ index: Int, count: Int, center: NSPoint) -> CGPath {
    let mid = angle(index, count: count), half = Double.pi / Double(count)
    let low = mid - half, high = mid + half
    func inset(_ radius: Double) -> Double { asin(min(0.95, gap / (2 * radius))) }
    let a = low + inset(outer), b = high - inset(outer)
    let c = low + inset(inner), d = high - inset(inner)
    let turn = min(0.15, (b - a) * 0.24), innerTurn = min(0.18, (d - c) * 0.18)
    let shoulder = outer - 20.16
    let control = inner / cos(innerTurn), tip = control + inner * tan(innerTurn)
    func p(_ radius: Double, _ angle: Double) -> CGPoint { point(radius, angle, center: center) }
    let path = CGMutablePath()
    path.move(to: p(tip, low + inset(tip)))
    path.addLine(to: p(shoulder, low + inset(shoulder)))
    path.addQuadCurve(to: p(outer, a + turn), control: p(outer, a))
    path.addArc(center: center, radius: outer, startAngle: a + turn, endAngle: b - turn, clockwise: false)
    path.addQuadCurve(to: p(shoulder, high - inset(shoulder)), control: p(outer, b))
    path.addLine(to: p(tip, high - inset(tip)))
    path.addQuadCurve(to: p(inner, d - innerTurn), control: p(control, high - inset(control)))
    path.addArc(center: center, radius: inner, startAngle: d - innerTurn, endAngle: c + innerTurn, clockwise: true)
    path.addQuadCurve(to: p(tip, low + inset(tip)), control: p(control, low + inset(control)))
    path.closeSubpath()
    return path
  }
  static func hit(_ point: NSPoint, count: Int, center: NSPoint) -> Int? {
    guard count > 0 else { return nil }
    let radius = hypot(point.x - center.x, point.y - center.y)
    guard radius >= inner, radius <= outer else { return nil }
    return (0..<count).first { petal($0, count: count, center: center).contains(point) }
  }
}

struct WheelGesture {
  private(set) var mode: String?
  private var previous: NSEvent.ModifierFlags = []
  private var wasDragging = false
  mutating func update(dragging: Bool, flags: NSEvent.ModifierFlags, cancelled: Bool = false,
                       resolve: (NSEvent.ModifierFlags) -> String?) -> String? {
    let current = flags.intersection([.shift, .command, .control, .option, .function])
    if !dragging || cancelled { mode = nil }
    else if !wasDragging || !current.subtracting(previous).isEmpty {
      if let next = resolve(current) { mode = next }
    }
    previous = current
    wasDragging = dragging && !cancelled
    return mode
  }
}


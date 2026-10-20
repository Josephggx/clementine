import AppKit
import SwiftUI
import CoreText

/// A single shared selection drives glass and foreground without replacing the drag window.
final class WheelAppearance: ObservableObject {
  @Published var count: Int
  @Published var selected: Int?
  @Published var hoverLevels: [CGFloat]
  @Published var hasIcons: Bool
  @Published var opening: CGFloat
  init(items: [WheelItem], opened: Bool = true) {
    count = items.count
    hoverLevels = Array(repeating:0,count:items.count)
    hasIcons = items.contains { !$0.icon.isEmpty }
    opening = opened ? 1 : 0
  }
  var centerHeight: CGFloat { hasIcons && selected != nil ? 36 : 32 }
}

/// Thin, round-ended line drawings on a consistent 24-point grid.
/// Foreground colours come from the active petal; no cached SF Symbol is mutated.
enum WheelGlyph {
  static func key(_ tool: String, family: Family) -> String {
    if tool == "split" { return family == .pdf ? "wheel:splitPDF" : "wheel:splitVideo" }
    if tool == "archive" { return "doc.zipper" }
    if tool == "redact" { return "eye.slash" }
    return "wheel:" + tool
  }
  static func draw(_ key: String, in rect: CGRect, color: NSColor, context c: CGContext) {
    c.saveGState(); defer { c.restoreGState() }
    c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: rect.width / 24, y: -rect.height / 24)
    c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor)
    c.setLineWidth(1.75); c.setLineCap(.round); c.setLineJoin(.round)
    func line(_ points: [CGFloat]) {
      guard points.count >= 4 else { return };c.beginPath();c.move(to:CGPoint(x:points[0],y:points[1]))
      for i in stride(from:2,to:points.count,by:2) { c.addLine(to:CGPoint(x:points[i],y:points[i+1])) };c.strokePath()
    }
    func polygon(_ points:[CGFloat]) {c.beginPath();c.move(to:CGPoint(x:points[0],y:points[1]));for i in stride(from:2,to:points.count,by:2){c.addLine(to:CGPoint(x:points[i],y:points[i+1]))};c.closePath();c.strokePath()}
    func circle(_ x:CGFloat,_ y:CGFloat,_ r:CGFloat) { c.strokeEllipse(in:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)) }
    func box(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ r:CGFloat=2) {c.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:r,cornerHeight:r,transform:nil));c.strokePath()}
    func curve(_ start:CGPoint,_ c1:CGPoint,_ c2:CGPoint,_ end:CGPoint){c.beginPath();c.move(to:start);c.addCurve(to:end,control1:c1,control2:c2);c.strokePath()}
    switch key.replacingOccurrences(of:"wheel:",with:"") {
    case "compress": line([3,3,9,9]);line([4,9,9,9,9,4]);line([21,21,15,15]);line([20,15,15,15,15,20])
    case "strip", "metadata":
      line([9,5,11,3,18,3,21,6,21,13,12,22,3,13,5,11]);line([3,3,21,21]);circle(16.5,7.5,1)
    case "adjust":
      for p:[CGFloat] in [[4,6,13,6],[17,6,20,6],[4,12,7,12],[11,12,20,12],[4,18,15,18],[19,18,20,18]] {line(p)}
      circle(15,6,2);circle(9,12,2);circle(17,18,2)
    case "annotate":
      line([14,4,20,10]);line([4,20,9,19,21,7]);curve(CGPoint(x:21,y:7),CGPoint(x:25,y:3),CGPoint(x:19,y:-1),CGPoint(x:17,y:3));line([17,3,5,15,4,20]);line([12,21,21,21])
    case "frame":
      box(3,4,18,16);line([7,16,10.5,12,13.3,15,15,13,18,16]);circle(8,8,0.25)
      line([1.5,7,1.5,3.5,3.5,1.5,7,1.5]);line([17,1.5,20.5,1.5,22.5,3.5,22.5,7]);line([22.5,17,22.5,20.5,20.5,22.5,17,22.5]);line([7,22.5,3.5,22.5,1.5,20.5,1.5,17])
    case "crop": line([7,3,7,17,21,17]);line([3,7,17,7,17,21])
    case "airdrop":
      circle(12,7,1);c.addArc(center:CGPoint(x:12,y:6.5),radius:5,startAngle:.pi*0.25,endAngle:.pi*0.75,clockwise:true);c.strokePath()
      c.addArc(center:CGPoint(x:12,y:6.5),radius:8.5,startAngle:.pi*0.25,endAngle:.pi*0.75,clockwise:true);c.strokePath();polygon([12,12,17,20,7,20])
    case "float": polygon([8,3,16,3,15,9,19,13,19,15,5,15,5,13,9,9]);line([12,15,12,22])
    case "copy": box(8,8,12,13);line([15,8,15,5]);curve(CGPoint(x:15,y:5),CGPoint(x:15,y:3),CGPoint(x:14,y:3),CGPoint(x:13,y:3));line([13,3,5,3]);curve(CGPoint(x:5,y:3),CGPoint(x:3,y:3),CGPoint(x:3,y:4),CGPoint(x:3,y:5));line([3,5,3,15]);curve(CGPoint(x:3,y:15),CGPoint(x:3,y:17),CGPoint(x:4,y:17),CGPoint(x:5,y:17));line([5,17,8,17])
    case "moveto":
      line([3,8,3,5,5,3,10,3,12,6,19,6,21,8,21,19,19,21,5,21,3,19,3,16]);line([1,12,14,12]);line([10,8,14,12,10,16])
    case "path": polygon([14,2,5,2,3,4,3,20,5,22,19,22,21,20,21,9]);line([14,2,14,9,21,9]);line([7,13,17,13]);line([7,17,14,17])
    case "terminal": box(2,4,20,16,3);line([6,9,9,12,6,15]);line([12,15,17,15])
    case "mute": polygon([11,5,6,9,3,9,3,15,6,15,11,19]);line([16,9,22,15]);line([22,9,16,15])
    case "trim": circle(6,6,3);circle(6,18,3);line([8.2,8.2,19.5,19.5]);line([8.2,15.8,19.5,4.5])
    case "speed":
      c.addArc(center:CGPoint(x:12,y:13),radius:10,startAngle:.pi*0.205,endAngle:.pi*0.795,clockwise:true);c.strokePath();line([4,19,20,19]);line([12,5,12,7]);line([5,9,6.5,10]);line([19,9,13.5,14.5]);circle(12,16,2)
    case "snapshot": box(2,6,20,15);line([8,6,10,3,14,3,16,6]);circle(12,13.5,4);circle(18.5,9,0.2)
    case "splitVideo": box(2,4,20,16,1.5);line([6,4,6,20]);line([18,4,18,20]);for y:CGFloat in [9,15]{line([2,y,6,y]);line([18,y,22,y])};c.setLineDash(phase:0,lengths:[2,3]);line([12,2,12,22])
    case "splitPDF": box(3,4,7,16,1.5);box(14,4,7,16,1.5);for y:CGFloat in [8,11]{line([6,y,7,y]);line([17,y,18,y])}
    case "normalize": for (x,a,b):(CGFloat,CGFloat,CGFloat) in [(4,10,14),(8,6,18),(12,3,21),(16,6,18),(20,10,14)]{line([x,a,x,b])}
    case "visualize": box(2.5,4,19,16);line([5.5,12,7.5,12,8.75,8,10.85,16,13.15,7,15.05,14,16.3,10,17.5,12,18.5,12])
    case "channels": box(3,3,7,18,1.5);box(14,3,7,18,1.5);circle(6.5,14.5,2);circle(17.5,14.5,2);circle(6.5,7,0.25);circle(17.5,7,0.25)
    case "bleep": line([3,12,5,12,6.5,7,8.9,17,11.2,5,13.8,19,15.9,9,17.2,15,21,15]);line([16.5,5.5,21.5,5.5])
    case "organize", "collage": for x:CGFloat in [3,14]{for y:CGFloat in [3,14]{box(x,y,7,7,1.25)}}
    case "extract": box(3,3,18,5,1);line([5,8,5,20,6,21,18,21,19,20,19,8]);line([12,18,12,11]);line([9,14,12,11,15,14])
    case "mergepdf", "join": box(3,3,13,16,1.5);line([8,21,20,21,21,20,21,7]);line([7,11,12,11]);line([9.5,8.5,9.5,13.5])
    case "finovox":
      // Both rings stop at the fold. Its interior remains transparent.
      c.setLineWidth(1.9)
      for radius: CGFloat in [9, 5.3] {
        c.beginPath()
        c.addArc(center: CGPoint(x:12,y:12), radius:radius,
          startAngle:0, endAngle: -.pi / 2, clockwise:false)
        c.strokePath()
      }
      c.beginPath(); c.move(to:CGPoint(x:12,y:3))
      c.addLine(to:CGPoint(x:12,y:9.45))
      c.addCurve(to:CGPoint(x:14.55,y:12),control1:CGPoint(x:12,y:10.85),control2:CGPoint(x:13.15,y:12))
      c.addLine(to:CGPoint(x:21,y:12))
      c.closePath(); c.strokePath()
    default:
      c.restoreGState();c.saveGState()
      if let image=NSImage(systemSymbolName:key,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:18,weight:.regular)) {
        let scale=min(rect.width/image.size.width,rect.height/image.size.height),size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
        let target=CGRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height)
        c.saveGState();c.beginTransparencyLayer(auxiliaryInfo:nil);image.draw(in:target);c.setBlendMode(.sourceIn);c.setFillColor(color.cgColor);c.fill(target);c.endTransparencyLayer();c.restoreGState()
      }
    }
  }
  static func text(_ text: String, centeredAt point: CGPoint, font: NSFont, color: NSColor, tracking: CGFloat) {
    let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:color,.kern:tracking]))
    guard let c=NSGraphicsContext.current?.cgContext else{return}
    c.saveGState();c.textMatrix = .identity
    c.textPosition=CGPoint(x:point.x-CGFloat(CTLineGetTypographicBounds(line,nil,nil,nil))/2,y:point.y-font.capHeight/2)
    CTLineDraw(line,c);c.restoreGState()
  }
}

final class WheelHoverFeedback {
  static let shared = WheelHoverFeedback()
  private var voices: [NSSound] = []
  private var next = 0
  private var last = -Double.infinity
  private(set) var playCount = 0
  private init() {
    if let url=Bundle.main.url(forResource:"WheelHover",withExtension:"wav") {
      voices=(0..<3).compactMap { _ in NSSound(contentsOf:url,byReference:false) }
      voices.forEach { $0.volume=0.24 }
    }
  }
  func perform(sound: Bool, haptic: Bool) {
    if haptic {
      // AppKit does not expose intensity. Generic is its firmest short detent.
      NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    if sound { play() }
  }
  func play(at time: Double = ProcessInfo.processInfo.systemUptime) {
    guard time-last >= 0.025, !voices.isEmpty else{return}
    last=time;let voice=voices[next];next=(next+1)%voices.count
    voice.stop();voice.currentTime=0
    if voice.play() {playCount += 1}
  }
}

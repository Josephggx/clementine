import AppKit
import SwiftUI

/// The Clémentine mark echoes the open conversion wheel: eight soft petals around a warm core.
private struct ClementinePetal: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addCurve(
      to: CGPoint(x: rect.minX, y: rect.height * 0.43),
      control1: CGPoint(x: rect.midX - rect.width * 0.20, y: rect.height * 0.88),
      control2: CGPoint(x: rect.minX, y: rect.height * 0.68))
    path.addCurve(
      to: CGPoint(x: rect.midX, y: rect.minY),
      control1: CGPoint(x: rect.minX, y: rect.height * 0.14),
      control2: CGPoint(x: rect.midX - rect.width * 0.26, y: rect.minY))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.height * 0.43),
      control1: CGPoint(x: rect.midX + rect.width * 0.26, y: rect.minY),
      control2: CGPoint(x: rect.maxX, y: rect.height * 0.14))
    path.addCurve(
      to: CGPoint(x: rect.midX, y: rect.maxY),
      control1: CGPoint(x: rect.maxX, y: rect.height * 0.68),
      control2: CGPoint(x: rect.midX + rect.width * 0.20, y: rect.height * 0.88))
    path.closeSubpath()
    return path
  }
}

struct ClementineMark: View {
  var size: CGFloat = 30

  var body: some View {
    ZStack {
      ForEach(0..<8, id: \.self) { index in
        ClementinePetal()
          .fill(
            LinearGradient(
              colors: [Color(red: 1, green: 0.61, blue: 0.24), citrus],
              startPoint: .top, endPoint: .bottom))
          .frame(width: size * 0.35, height: size * 0.47)
          .offset(y: -size * 0.245)
          .rotationEffect(.degrees(Double(index) * 45))
      }
      Circle()
        .fill(LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.30), citrus],
          startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: size * 0.36, height: size * 0.36)
        .overlay(Circle().stroke(.white.opacity(0.38), lineWidth: max(0.6, size * 0.025)))
    }
    .frame(width: size, height: size)
    .shadow(color: citrus.opacity(0.20), radius: size * 0.08, y: size * 0.03)
    .accessibilityLabel("Clémentine")
  }
}

enum ClementineMarkImage {
  static func statusItem() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.translateBy(x: rect.midX, y: rect.midY)
      context.setFillColor(NSColor.labelColor.cgColor)
      for index in 0..<8 {
        context.saveGState()
        context.rotate(by: CGFloat(index) * .pi / 4)
        context.fillEllipse(in: CGRect(x: -2.4, y: 2.0, width: 4.8, height: 6.6))
        context.restoreGState()
      }
      context.fillEllipse(in: CGRect(x: -2.45, y: -2.45, width: 4.9, height: 4.9))
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Clémentine"
    return image
  }
}

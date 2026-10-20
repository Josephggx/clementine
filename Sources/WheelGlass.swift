import AppKit

import SwiftUI

@available(macOS 26.0, *)
struct WheelPetal: Shape {
  let index: Int
  let count: Int
  func path(in rect: CGRect) -> Path {
    let path = WheelGeometry.petal(index, count: count, center: CGPoint(x: rect.midX, y: rect.midY))
    var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height)
    return Path(path.copy(using: &flip) ?? path)
  }
}

@available(macOS 26.0, *)
private struct WheelBackdropRing: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    path.addEllipse(in: CGRect(x: center.x-WheelGeometry.backdrop,
      y: center.y-WheelGeometry.backdrop, width: WheelGeometry.backdrop*2,
      height: WheelGeometry.backdrop*2))
    let hole = WheelGeometry.hubHole
    path.addEllipse(in: CGRect(x: center.x-hole, y: center.y-hole,
      width: hole*2, height: hole*2))
    return path
  }
}

@available(macOS 26.0, *)
struct WheelGlass: View {
  @ObservedObject var appearance: WheelAppearance
  var body: some View {
    // Same neutral, translucent glass used by Tangerine: the desktop remains
    // visible and determines the final tone instead of a painted gray disc.
    let disc = Color(red: 192/255, green: 201/255, blue: 205/255)
    ZStack {
      Circle()
        .fill(disc.opacity(0.25))
        .glassEffect(.regular.tint(disc.opacity(0.16)), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.33), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .frame(width: WheelGeometry.backdrop * 2, height: WheelGeometry.backdrop * 2)
        .scaleEffect(0.82 + 0.18 * appearance.opening)
        .opacity(appearance.opening)
      ForEach(0..<appearance.count,id:\.self) {index in
        let level=index < appearance.hoverLevels.count ? appearance.hoverLevels[index] : 0
        let petal=WheelPetal(index:index,count:appearance.count)
        petal.fill(.clear)
          .glassEffect(.regular.tint(Color(red:1,green:82/255,blue:0).opacity(0.55)),in:petal)
          .opacity(level * max(0,(appearance.opening-0.55)/0.45))
      }
    }
    .frame(width:WheelGeometry.side,height:WheelGeometry.side)
    .mask {
      WheelBackdropRing().fill(.white, style: FillStyle(eoFill: true))
    }
    .allowsHitTesting(false)
  }
}

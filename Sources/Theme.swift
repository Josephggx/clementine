import AppKit
import SwiftUI

enum ClementineAppearance: String, CaseIterable {
  case system, light, dark

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  var nsAppearance: NSAppearance? {
    switch self {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }
}

extension NSColor {
  private static func clementineDynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
  }

  static let clementineCanvas = clementineDynamic(
    light: NSColor(calibratedWhite: 0.985, alpha: 1),
    dark: NSColor(calibratedRed: 0.155, green: 0.150, blue: 0.142, alpha: 1))

  // The content of each page shares the inset background used by Settings.
  // Header and sidebar keep the surrounding canvas/material.
  static let clementinePageBackground = clementineDynamic(
    light: NSColor(calibratedWhite: 0.95, alpha: 1),
    dark: NSColor.controlBackgroundColor)

  static let clementineSurface = clementineDynamic(
    light: .white,
    dark: NSColor(calibratedRed: 0.215, green: 0.207, blue: 0.195, alpha: 1))

  static let clementineGroupedSurface = clementineDynamic(
    light: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.925, alpha: 1),
    dark: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.14, alpha: 1))

  static let clementineRaisedSurface = clementineDynamic(
    light: NSColor(calibratedWhite: 0.985, alpha: 1),
    dark: NSColor(calibratedRed: 0.255, green: 0.245, blue: 0.230, alpha: 1))

  static let clementineBorder = clementineDynamic(
    light: NSColor.black.withAlphaComponent(0.075),
    dark: NSColor.white.withAlphaComponent(0.105))
}

extension Color {
  static let clementineCanvas = Color(nsColor: .clementineCanvas)
  static let clementinePageBackground = Color(nsColor: .clementinePageBackground)
  static let clementineSurface = Color(nsColor: .clementineSurface)
  static let clementineGroupedSurface = Color(nsColor: .clementineGroupedSurface)
  static let clementineRaisedSurface = Color(nsColor: .clementineRaisedSurface)
  static let clementineBorder = Color(nsColor: .clementineBorder)
}

/// Keeps navigation controls visually stable while the pointer is held down.
/// Their appearance is driven explicitly by hover and selection state.
struct StableInteractionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}


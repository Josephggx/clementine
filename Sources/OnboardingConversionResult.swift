import Foundation

enum OnboardingConversionResult {
  static func url(source: URL, item: WheelItem?) -> URL {
    guard let action = item?.action, action.hasPrefix("convert:") else { return source }
    let format = String(action.dropFirst("convert:".count))
    guard !format.isEmpty else { return source }
    return source.deletingPathExtension().appendingPathExtension(format)
  }
}

import Foundation

/// Coalesces brief drag exits/re-entries without suppressing a different button.
/// The gate belongs to a wheel, never to the files in its selection.
struct WheelFeedbackGate {
  private var lastAction: String?
  private var exitedAt: TimeInterval?
  static let minimumExitDuration: TimeInterval = 0.12

  mutating func selectionChanged(to action: String?, at time: TimeInterval) -> Bool {
    guard let action else {
      if exitedAt == nil { exitedAt = time }
      return false
    }
    let returnedAfterExit = exitedAt.map { time - $0 >= Self.minimumExitDuration } ?? false
    let emit = action != lastAction || returnedAfterExit
    lastAction = action
    exitedAt = nil
    return emit
  }
}

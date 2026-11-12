import Foundation

/// An install callback is available only after Sparkle has prepared the update.
/// Consume it before invocation: repeated clicks must never restart twice.
struct UpdatePreparation {
  enum Phase: Equatable {
    case idle, downloading, preparing, ready, waitingForWork, installing, needsInteraction, failed
  }
  private(set) var phase: Phase = .idle
  private var install: (() -> Void)?

  var isPreparing: Bool { phase == .downloading || phase == .preparing }
  var canInstall: Bool { phase == .ready }

  mutating func downloading() { install = nil; phase = .downloading }
  mutating func extracting() { install = nil; phase = .preparing }
  mutating func ready(_ install: @escaping () -> Void) { self.install = install; phase = .ready }
  mutating func needsInteraction() { install = nil; phase = .needsInteraction }
  mutating func fail() { install = nil; phase = .failed }
  mutating func reset() { install = nil; phase = .idle }

  /// Returns the continuation instead of invoking it inside a mutating access.
  /// Sparkle can synchronously call back into the owner when installation starts.
  mutating func requestInstallation(isBusy: Bool) -> (() -> Void)? {
    guard phase == .ready, install != nil else { return nil }
    if isBusy { phase = .waitingForWork; return nil }
    return consume()
  }
  mutating func continueInstallation(isBusy: Bool) -> (() -> Void)? {
    guard phase == .waitingForWork, !isBusy else { return nil }
    return consume()
  }
  private mutating func consume() -> (() -> Void)? {
    let action = install
    install = nil
    phase = .installing
    return action
  }
}

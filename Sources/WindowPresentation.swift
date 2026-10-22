import AppKit

/// Floating UI belongs to the user's current activity, not the Atelier's app set.
/// `canJoinAllApplications` is distinct from `canJoinAllSpaces`: Stage Manager
/// otherwise treats an overlay as part of its owning app's group of windows.
enum FloatingWindowPresentation {
  static let wheel: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .transient, .ignoresCycle
  ]
  // A Float is a persistent file shelf, not a transient drag/menu overlay.
  static let float: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle
  ]
  static let tool: NSWindow.CollectionBehavior = [
    .moveToActiveSpace, .canJoinAllApplications, .fullScreenAuxiliary, .transient, .ignoresCycle
  ]
}

/// AppKit can deliver a reopen after the drag panel has already been dismissed.
/// Do not use the existence of an NSPanel as the lifetime of a file gesture.
struct WorkspaceReopenPolicy {
  static let settlingInterval: TimeInterval = 0.75
  private var suppressedUntil:TimeInterval = -.infinity
  static func shouldPresentWorkspace(isVisible:Bool,isMiniaturized:Bool) -> Bool {
    !isVisible || isMiniaturized
  }
  mutating func overlayDismissed(at time:TimeInterval) {
    suppressedUntil=max(suppressedUntil,time+Self.settlingInterval)
  }
  func allowsReopen(phase:WheelDragSession.Phase, hasOverlay:Bool, at time:TimeInterval) -> Bool {
    !hasOverlay && phase != .dragging && phase != .ending && phase != .blocked && time >= suppressedUntil
  }
}

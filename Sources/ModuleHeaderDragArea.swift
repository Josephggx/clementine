import AppKit
import SwiftUI

/// Only live module headers move their panel; embedded catalogue previews stay inert.
struct ModuleHeaderDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> ModuleHeaderDragView { ModuleHeaderDragView() }
  func updateNSView(_ nsView: ModuleHeaderDragView, context: Context) {}
}

final class ModuleHeaderDragView: NSView {
  override var mouseDownCanMoveWindow: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Leave the close button (12 pt inset + 26 pt diameter) and its surrounding
    // padding to SwiftUI, including its hover feedback and accessibility action.
    guard let parent = superview else { return nil }
    let local = convert(point, from: parent)
    guard bounds.contains(local), local.x >= 44 else { return nil }
    return self
  }

  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}

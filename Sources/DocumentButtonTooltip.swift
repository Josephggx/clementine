import AppKit
import SwiftUI

extension View {
  func documentTooltip(_ text: String, hovered: Bool) -> some View {
    background(DocumentTooltipAnchor(text: trString(text), hovered: hovered).allowsHitTesting(false))
  }
}

/// A separate popover keeps labels above the icons, outside the document scroll view's clip.
private struct DocumentTooltipAnchor: NSViewRepresentable {
  let text: String
  let hovered: Bool

  final class Coordinator {
    let popover = NSPopover()
    init() {
      popover.behavior = .applicationDefined
      popover.animates = false
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    let popover = context.coordinator.popover
    guard hovered, view.window != nil else { popover.close(); return }
    guard !popover.isShown else { return }
    let width = min(280, max(40, ceil((text as NSString).size(
      withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width)))
    let label = Text(verbatim: text).font(.system(size: 11))
      .multilineTextAlignment(.center)
      .frame(width: width).fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 10).padding(.vertical, 7)
    let controller = NSHostingController(rootView: label)
    popover.contentViewController = controller
    popover.contentSize = controller.view.fittingSize
    popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
  }
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.popover.close()
  }
}

import AppKit
import SwiftUI

/// Scoped to the onboarding's own key window. The native wheel and buttons may
/// own first responder without swallowing slide navigation.
struct OnboardingArrowKeys: NSViewRepresentable {
  let move: (Int) -> Void
  func makeNSView(context: Context) -> KeyHost { KeyHost(move: move) }
  func updateNSView(_ view: KeyHost, context: Context) { view.move = move }
  static func dismantleNSView(_ view: KeyHost, coordinator: ()) { view.stop() }

  final class KeyHost: NSView {
    var move: (Int) -> Void
    private var monitor: Any?
    init(move: @escaping (Int) -> Void) { self.move = move; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stop()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let window = self.window, window.isKeyWindow,
          event.window === window,
          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
          event.keyCode == 123 || event.keyCode == 124 else { return event }
        if !event.isARepeat { self.move(event.keyCode == 123 ? -1 : 1) }
        return nil
      }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    deinit { stop() }
  }
}

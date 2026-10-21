import AppKit
import SwiftUI

@main struct WindowPresentationCheck {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    if Bundle.main.object(forInfoDictionaryKey:"WindowPresentationUI") as? Bool == true {
      let delegate=SpaceFocusFixture();NSApp.delegate=delegate
      withExtendedLifetime(delegate) {NSApp.run()}
      return
    }
    precondition(!WorkspaceReopenPolicy.shouldPresentWorkspace(isVisible:true,isMiniaturized:false),"An existing window must not be ordered across Desktops by a generic reopen")
    precondition(WorkspaceReopenPolicy.shouldPresentWorkspace(isVisible:false,isMiniaturized:false))
    precondition(WorkspaceReopenPolicy.shouldPresentWorkspace(isVisible:true,isMiniaturized:true))
    var policy=WorkspaceReopenPolicy()
    precondition(policy.allowsReopen(phase:.idle,hasOverlay:false,at:0))
    precondition(policy.allowsReopen(phase:.pressed,hasOverlay:false,at:0),"An ordinary Dock click remains available")
    for phase:WheelDragSession.Phase in [.dragging,.ending,.blocked] {
      precondition(!policy.allowsReopen(phase:phase,hasOverlay:false,at:0),"A native gesture blocks reopen even without a panel")
    }
    for phase:WheelDragSession.Phase in [.idle,.pressed,.dragging,.ending,.blocked] {
      precondition(!policy.allowsReopen(phase:phase,hasOverlay:true,at:0))
    }
    policy.overlayDismissed(at:10)
    precondition(!policy.allowsReopen(phase:.idle,hasOverlay:false,at:10.01))
    precondition(!policy.allowsReopen(phase:.idle,hasOverlay:false,at:10.74))
    precondition(policy.allowsReopen(phase:.idle,hasOverlay:false,at:10.75))
    policy.overlayDismissed(at:10.5)
    precondition(!policy.allowsReopen(phase:.idle,hasOverlay:false,at:11.0))
    precondition(policy.allowsReopen(phase:.idle,hasOverlay:false,at:11.25))
    let behavior=FloatingWindowPresentation.wheel
    precondition(behavior.contains([.canJoinAllSpaces,.canJoinAllApplications,.transient,.ignoresCycle,.fullScreenAuxiliary]))
    precondition(!behavior.contains(.primary) && !behavior.contains(.auxiliary) && !behavior.contains(.moveToActiveSpace))
    let file=FileManager.default.temporaryDirectory.appendingPathComponent("clementine-window-focus.txt")
    try "Focus fixture".write(to:file,atomically:true,encoding:.utf8)
    defer {try? FileManager.default.removeItem(at:file)}
    let state=AppState();state.sound=false;state.haptics=false
    let controller=WheelController(state:state)
    controller.show([file],mode:"formats")
    let panel=controller.panel!
    precondition(panel.styleMask.contains(.nonactivatingPanel) && !panel.canBecomeMain)
    precondition(panel.collectionBehavior == behavior && panel.becomesKeyOnlyIfNeeded)
    precondition(!controller.allowsWorkspaceReopen)
    controller.close()
    precondition(!controller.allowsWorkspaceReopen,"The delayed reopen must remain blocked after teardown")
    // Repeat cycles and mode changes must not reset the guard early.
    for mode in ["formats","tools","actions"] {
      controller.show([file],mode:mode)
      precondition(!controller.allowsWorkspaceReopen)
      controller.close()
      precondition(!controller.allowsWorkspaceReopen)
    }
    print("PASS: file-gesture phases, delayed reopen after teardown, repeated wheels, normal Dock clicks and independent nonactivating panel flags")
  }
}

/// Isolated real-drag fixture: keep this window on another Desktop, then drag
/// only its demo file in Finder. It never opens user documents or requests TCC.
final class SpaceFocusFixture:NSObject,NSApplicationDelegate,NSWindowDelegate {
  let state=AppState()
  var wheel:WheelController!
  var window:NSWindow!
  let label=NSTextField(wrappingLabelWithString:"Passez sur un autre bureau, puis glissez Focus demo.txt dans le Finder.")
  var before:[String:Any]?
  var checking=false
  var root:URL {URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"FocusTestRoot") as! String)}
  var file:URL {root.appendingPathComponent("Focus demo.txt")}
  func applicationDidFinishLaunching(_ notification:Notification) {
    try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    try! "Clémentine focus test".write(to:file,atomically:true,encoding:.utf8)
    state.sound=false;state.haptics=false
    NSApp.setActivationPolicy(.regular)
    window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:240),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.title="Vérification bureaux — Atelier";window.isReleasedWhenClosed=false;window.delegate=self
    window.collectionBehavior=[.fullScreenPrimary]
    label.frame=NSRect(x:24,y:70,width:532,height:120)
    let content=NSView(frame:NSRect(x:0,y:0,width:580,height:240));content.addSubview(label)
    window.contentView=content
    wheel=WheelController(state:state)
    wheel.acceptsDragFiles={ [weak self] urls in urls == self.map {[$0.file]} }
    wheel.trace={ [weak self] message in self?.trace(message) }
    wheel.start()
    window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
  }
  func trace(_ message:String) {
    if message.contains("phase=dragging") && before == nil {
      before=["workspaceOnCurrentDesktop":window.isOnActiveSpace,
        "foreground":NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"]
      // Arm the production modifier path during the real native Finder drag;
      // the remote driver cannot hold a modifier while using its drag API.
      DispatchQueue.main.async { [weak self] in self?.wheel.modifierChanged(flags:.shift,keyCode:56) }
    }
    if message.hasPrefix("show mode=") && !checking {
      checking=true
      DispatchQueue.main.async { [weak self] in self?.check() }
    }
  }
  func check() {
    guard let before,let panel=wheel.panel else {return}
    let blocked = !wheel.handleWorkspaceReopen(workspace:window) {self.window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    let after:[String:Any]=["workspaceOnCurrentDesktop":window.isOnActiveSpace,
      "foreground":NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown",
      "appActive":NSApp.isActive,"wheelOnCurrentDesktop":panel.isOnActiveSpace,
      "wheelCanBecomeKey":panel.canBecomeKey,"reopenBlocked":blocked]
    let passed=before["workspaceOnCurrentDesktop"] as? Bool == false && !window.isOnActiveSpace && !NSApp.isActive
      && before["foreground"] as? String == after["foreground"] as? String
      && panel.isOnActiveSpace && !panel.canBecomeKey && blocked
    let result:[String:Any]=["before":before,"after":after,"passed":passed,"actualFinderDrag":true]
    try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
      .write(to:root.appendingPathComponent("space-result.json"))
    label.stringValue=passed ? "PASS — le bureau et le Finder sont restés actifs." : "Vérifier space-result.json"
  }
  func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
    wheel.handleWorkspaceReopen(workspace:window) {self.window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
  }
  func windowWillClose(_ notification:Notification) {wheel.stop();NSApp.terminate(nil)}
}

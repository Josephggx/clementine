import AppKit
import QuickLookUI

private final class WorkspacePreviewWindow:NSWindow {
  override var canBecomeKey:Bool {true}
  override var canBecomeMain:Bool {true}
  override func cancelOperation(_ sender:Any?) {close()}
}

/// Native Quick Look renders full documents (including scroll and media controls).
/// This panel is independent of the workspace, so it can resize and move freely.
final class WorkspacePreviewController:NSObject,NSWindowDelegate {
  static let shared=WorkspacePreviewController()
  private var panel:WorkspacePreviewWindow?
  private var preview:QLPreviewView?
  private var outsideMonitor:Any?
  private var fileTimer:Timer?
  private var fullScreenTransition=false
  static func canPreview(_ url:URL)->Bool {
    !Family.isFolder(url) && [.pdf,.image,.video,.audio].contains(Family.of(url))
  }

  func show(_ url:URL,appearance:String) {
    guard Self.canPreview(url),FileManager.default.fileExists(atPath:url.path) else {return}
    panel?.close()
    let screen=NSScreen.screens.first {$0.frame.contains(NSEvent.mouseLocation)} ?? NSScreen.main
    let area=screen?.visibleFrame ?? CGRect(x:0,y:0,width:1200,height:850)
    let size=CGSize(width:min(960,area.width-60),height:min(760,area.height-60))
    let panel=WorkspacePreviewWindow(contentRect:CGRect(x:area.midX-size.width/2,
      y:area.midY-size.height/2,width:size.width,height:size.height),
      styleMask:[.titled,.closable,.resizable,.fullSizeContentView,.miniaturizable],
      backing:.buffered,defer:false)
    self.panel=panel
    panel.title=url.lastPathComponent;panel.titlebarAppearsTransparent=true
    panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true
    panel.minSize=CGSize(width:400,height:300)
    panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false
    panel.level = .normal
    panel.collectionBehavior=[.moveToActiveSpace,.canJoinAllApplications,.fullScreenPrimary]
    panel.standardWindowButton(.zoomButton)?.target=panel
    panel.standardWindowButton(.zoomButton)?.action=#selector(NSWindow.toggleFullScreen(_:))
    panel.appearance=NSAppearance(named:appearance == "light" ? .aqua : .darkAqua)
    let glass=NSVisualEffectView()
    glass.material = .hudWindow;glass.blendingMode = .behindWindow;glass.state = .active
    glass.wantsLayer=true;glass.layer?.cornerRadius=16;glass.layer?.masksToBounds=true
    glass.layer?.borderWidth=0.5;glass.layer?.borderColor=NSColor.white.withAlphaComponent(0.18).cgColor
    panel.contentView=glass
    let preview=QLPreviewView(frame:.zero,style:.normal)!
    self.preview=preview
    preview.translatesAutoresizingMaskIntoConstraints=false
    preview.autostarts=false
    preview.previewItem=url as NSURL
    glass.addSubview(preview)
    NSLayoutConstraint.activate([
      preview.leadingAnchor.constraint(equalTo:glass.leadingAnchor,constant:12),
      preview.trailingAnchor.constraint(equalTo:glass.trailingAnchor,constant:-12),
      preview.topAnchor.constraint(equalTo:glass.topAnchor,constant:40),
      preview.bottomAnchor.constraint(equalTo:glass.bottomAnchor,constant:-12)])
    panel.delegate=self
    panel.makeKeyAndOrderFront(nil)
    outsideMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self,weak panel] event in
      if self?.fullScreenTransition != true,let eventWindow=event.window,
        eventWindow !== panel,eventWindow.parent !== panel {self?.panel?.close()}
      return event
    }
    let timer=Timer(timeInterval:0.8,repeats:true) { [weak self] _ in
      if !FileManager.default.fileExists(atPath:url.path) || TrackedFiles.isInTrash(url) {self?.panel?.close()}
    }
    fileTimer=timer;RunLoop.main.add(timer,forMode:.common)
  }

  func windowWillEnterFullScreen(_ notification:Notification) {fullScreenTransition=true}
  func windowDidEnterFullScreen(_ notification:Notification) {fullScreenTransition=false}
  func windowWillExitFullScreen(_ notification:Notification) {fullScreenTransition=true}
  func windowDidExitFullScreen(_ notification:Notification) {fullScreenTransition=false}
  func windowDidFailToEnterFullScreen(_ window:NSWindow) {fullScreenTransition=false}
  func windowDidFailToExitFullScreen(_ window:NSWindow) {fullScreenTransition=false}
  func windowDidResignKey(_ notification:Notification) {
    if !fullScreenTransition {panel?.close()}
  }
  func windowWillClose(_ notification:Notification) {
    if let outsideMonitor {NSEvent.removeMonitor(outsideMonitor)}
    outsideMonitor=nil;fileTimer?.invalidate();fileTimer=nil;fullScreenTransition=false
    preview?.close();preview=nil
    panel?.delegate=nil;panel=nil
  }
}

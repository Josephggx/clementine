import AppKit
import PDFKit

final class PreviewLifecycleFixture:NSObject,NSApplicationDelegate {
  let root=URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"PreviewTestRoot") as! String)
  var checks:[String]=[]
  func require(_ value:@autoclosure()->Bool,_ message:String) {
    let passed=value()
    FileHandle.standardError.write(Data(((passed ? "PASS: " : "FAIL: ")+message+"\n").utf8))
    precondition(passed,message);checks.append(message)
  }
  func pump(_ seconds:TimeInterval=0.15) {
    let end=Date().addingTimeInterval(seconds)
    while Date()<end {
      while let event=NSApp.nextEvent(matching:.any,until:Date(),inMode:.default,dequeue:true) {NSApp.sendEvent(event)}
      RunLoop.current.run(until:Date().addingTimeInterval(0.005))
    }
  }
  func show(_ url:URL)->NSWindow {
    NSApp.activate(ignoringOtherApps:true);pump(0.1)
    WorkspacePreviewController.shared.show(url,appearance:"dark")
    pump()
    let window=NSApp.windows.first {$0.title == url.lastPathComponent && $0.isVisible}!
    require(window.contentView?.subviews.contains {$0 is QLPreviewView} == true,"Real Quick Look view attached for \(url.pathExtension)")
    return window
  }
  func applicationDidFinishLaunching(_ notification:Notification) {
    NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)
    DispatchQueue.main.async {self.run()}
  }
  func run() {
    let image=NSImage(size:CGSize(width:420,height:600))
    image.lockFocus();NSColor.orange.setFill();NSRect(x:0,y:0,width:420,height:600).fill();image.unlockFocus()
    let png=root.appendingPathComponent("Image.png")
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try! bitmap.representation(using:.png,properties:[:])!.write(to:png)
    let pdf=root.appendingPathComponent("Document.pdf")
    let document=PDFDocument();document.insert(PDFPage(image:image)!,at:0);document.insert(PDFPage(image:image)!,at:1)
    require(document.write(to:pdf),"PDF fixture created")
    let inputs=[pdf,png,root.appendingPathComponent("Video.mp4"),root.appendingPathComponent("Audio.wav")]
    for url in inputs {
      require(WorkspacePreviewController.canPreview(url),"Preview supports \(url.pathExtension)")
      let closeButton=show(url)
      closeButton.standardWindowButton(.closeButton)!.performClick(nil);pump()
      require(!closeButton.isVisible,"Red close button dismisses \(url.pathExtension) without double deactivation")
      let escape=show(url);escape.cancelOperation(nil);pump()
      require(!escape.isVisible,"Escape dismisses \(url.pathExtension)")
      let outside=show(url)
      let other=NSWindow(contentRect:CGRect(x:30,y:30,width:200,height:140),styleMask:[.titled],backing:.buffered,defer:false)
      other.isReleasedWhenClosed=false;other.orderFront(nil)
      let event=NSEvent.mouseEvent(with:.leftMouseDown,location:CGPoint(x:60,y:60),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:other.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
      NSApp.sendEvent(event);pump()
      require(!outside.isVisible,"Outside click dismisses \(url.pathExtension) without crashing the event monitor")
      other.close()
    }
    let first=show(pdf),second=show(png)
    require(!first.isVisible && second.isVisible,"Replacing an open preview closes only the old window")
    WorkspacePreviewController.shared.windowWillClose(Notification(name:NSWindow.willCloseNotification,object:first))
    require(second.isVisible,"Late notification from an old window leaves the current preview intact")
    WorkspacePreviewController.shared.windowDidResignKey(Notification(name:NSWindow.didResignKeyNotification,object:first))
    require(second.isVisible,"Late focus loss from an old preview leaves the current preview intact")
    second.close();pump()
    for _ in 0..<16 {
      WorkspacePreviewController.shared.show(pdf,appearance:"light")
      let window=NSApp.windows.first {$0.title == pdf.lastPathComponent && $0.isVisible}!
      window.close();pump(0.025)
      require(!window.isVisible,"Immediate close during asynchronous Quick Look load is safe")
    }
    let missing=show(png);try! FileManager.default.removeItem(at:png)
    DispatchQueue.main.asyncAfter(deadline:.now()+1.2) {
      self.require(!missing.isVisible,"Removing the file closes its preview once")
      try! JSONSerialization.data(withJSONObject:["passed":self.checks.count,"checks":self.checks],options:[.prettyPrinted]).write(to:self.root.appendingPathComponent("results.json"))
      print("PASS: \(self.checks.count) preview lifecycle checks; PDF/image/video/audio, close button, Escape, outside click, replacement, immediate close and deleted file")
      NSApp.terminate(nil)
    }
  }
}
import QuickLookUI
@main struct PreviewLifecycleCheck {
  static func main() {
    let app=NSApplication.shared,delegate=PreviewLifecycleFixture();app.delegate=delegate
    withExtendedLifetime(delegate) {app.run()}
  }
}

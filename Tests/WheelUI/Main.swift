import AppKit
import Foundation
import ImageIO

final class WheelFixtureSource: NSView, NSDraggingSource {
  let file: URL
  var onStart: ((NSDraggingSession) -> Void)?
  init(file: URL, frame: NSRect) {
    self.file = file; super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Fichier de test à glisser")
  }
  required init?(coder: NSCoder) { fatalError() }
  override func mouseDown(with event: NSEvent) {}
  override func mouseDragged(with event: NSEvent) { start(event) }
  private func start(_ event: NSEvent) {
    let item = NSDraggingItem(pasteboardWriter: file as NSURL)
    item.setDraggingFrame(NSRect(x: 58, y: 60, width: 64, height: 64), contents: NSWorkspace.shared.icon(forFile: file.path))
    beginDraggingSession(with: [item], event: event, source: self)
  }
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .generic, .link, .private] }
  func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onStart?(session) }
  override func draw(_ dirtyRect: NSRect) {
    NSWorkspace.shared.icon(forFile: file.path).draw(in: NSRect(x: 58, y: 60, width: 64, height: 64))
    ("Fichier de test.png" as NSString).draw(at: NSPoint(x: 30, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
  }
}

final class WheelUIFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let state = AppState()
  var wheel: WheelController!
  var window: NSWindow!
  let status = NSTextField(wrappingLabelWithString: "Prêt — glisser le fichier puis taper une touche")
  var root: URL!
  var file: URL!
  var rows: [String] = []
  var checks = 0
  var failures = 0
  var armFnDrop = false
  var embedded: WheelSurface?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    state.appearance = "dark"; state.applyAppearance()
    root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestRoot") as! String)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    file = root.appendingPathComponent("Fichier de test.png")
    let context = CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.95, green: 0.35, blue: 0.12, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
    let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil); CGImageDestinationFinalize(destination)
    state.sound = false; state.reveal = false
    state.options.outputFolder = root.appendingPathComponent("results").path
    try! FileManager.default.createDirectory(atPath: state.options.outputFolder, withIntermediateDirectories: true)
    state.conversionModifier = "fn"; state.toolModifier = "command"; state.actionModifier = "control"
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 420), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Clémentine — Vérification du drag"
    window.delegate = self; window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))
    let instructions = NSTextField(wrappingLabelWithString: "Glisser le fichier, taper Fn / Commande / Contrôle, relâcher la touche puis déposer. Échap annule.")
    instructions.frame = NSRect(x: 30, y: 330, width: 660, height: 60); content.addSubview(instructions)
    let source = WheelFixtureSource(file: file, frame: NSRect(x: 40, y: 120, width: 180, height: 150))
    source.onStart = { [weak self] session in
      let pb = session.draggingPasteboard
      self?.record("native start flags=\(NSEvent.modifierFlags.rawValue) buttons=\(NSEvent.pressedMouseButtons) cg=\(CGEventSource.buttonState(.combinedSessionState, button: .left))")
      self?.record("native pb=\(pb.name.rawValue) generation=\(pb.changeCount) global=\(NSPasteboard(name: .drag).changeCount)")
      if let self, self.armFnDrop {
        self.armFnDrop = false
        self.wheel.modifierChanged(flags: .function, keyCode: 63)
        self.wheel.panel?.orderOut(nil)
        self.record("Fn state replayed during a real native drag; target JPG")
      }
    }
    content.addSubview(source)
    status.frame = NSRect(x: 250, y: 120, width: 430, height: 180); content.addSubview(status)
    let run = NSButton(title: "Vérifier les régressions", target: self, action: #selector(runChecks))
    run.frame = NSRect(x: 30, y: 35, width: 220, height: 34); content.addSubview(run)
    let clear = NSButton(title: "Réinitialiser", target: self, action: #selector(reset))
    clear.frame = NSRect(x: 270, y: 35, width: 180, height: 34); content.addSubview(clear)
    let target = NSTextField(labelWithString: "JPG")
    target.alignment = .center; target.font = .boldSystemFont(ofSize: 16)
    target.frame = NSRect(x: 440, y: 280, width: 72, height: 40); content.addSubview(target)
    let arm = NSButton(title: "Armer un dépôt Fn", target: self, action: #selector(armDrop))
    arm.frame = NSRect(x: 30, y: 75, width: 220, height: 34); content.addSubview(arm)
    let preview = NSButton(title:"Aperçu glass et clic",target:self,action:#selector(previewWheel))
    preview.frame=NSRect(x:270,y:75,width:220,height:34);content.addSubview(preview)
    let quit = NSButton(title: "Quitter le test", target: self, action: #selector(quitTest))
    quit.frame = NSRect(x: 470, y: 35, width: 180, height: 34); content.addSubview(quit)
    window.contentView = content
    let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quitter le test", action: #selector(quitTest), keyEquivalent: "q").target = self
    item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
    reset()
    window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  func record(_ text: String) {
    rows.append(text)
    status.stringValue = rows.suffix(7).joined(separator: "\n")
    try? rows.joined(separator: "\n").write(to: root.appendingPathComponent("events.txt"), atomically: true, encoding: .utf8)
  }
  @objc func previewWheel() {
    embedded?.removeFromSuperview()
    let items=Tool.available([file]).map { WheelItem(title:$0.wheelTitle,icon:WheelGlyph.key($0.id,family:.image),action:$0.id) }
    let target=WheelSurface(frame:NSRect(x:340,y:80,width:272,height:272),files:[file],items:items,preview:true)
    target.wheel.onSelectionChange={ [weak self] slot in
      if slot != nil { WheelHoverFeedback.shared.play(); self?.record("Hover sound starts: \(WheelHoverFeedback.shared.playCount)") }
    }
    window.contentView?.addSubview(target);embedded=target
    target.wheel.hover(at:WheelGeometry.point(84.5312,WheelGeometry.angle(0,count:items.count),center:target.wheel.center))
    record("Preview glass with hover feedback")
  }
  @objc func armDrop() {
    embedded?.removeFromSuperview()
    let items = Compatibility.targets([file]).map { WheelItem(title: Compatibility.label($0), icon: "", action: "convert:" + $0) }
    let target = WheelSurface(frame: NSRect(x: 340, y: 80, width: 272, height: 272), files: [file], items: items, preview: false)
    target.wheel.onRefresh = { [weak self] in self?.wheel.surface?.wheel.onRefresh?() }
    target.wheel.onValidate = { [weak self] info in self?.wheel.surface?.wheel.onValidate?(info) ?? false }
    target.wheel.onChoose = { [weak self] item, files, generation in self?.wheel.surface?.wheel.onChoose?(item, files, generation) ?? false }
    target.wheel.onEnd = { [weak self] in self?.wheel.surface?.wheel.onEnd?() }
    window.contentView?.addSubview(target); embedded = target
    armFnDrop = true; record("Ready for native Fn-state drop onto JPG")
  }
  @objc func reset() {
    wheel?.progressPanels.forEach { $0.close() }
    wheel?.stop()
    wheel = WheelController(state: state)
    wheel.trace = { [weak self] text in self?.record(text) }
    wheel.acceptsDragFiles = { [weak self] files in files == [self?.file].compactMap { $0 } }
    wheel.start()
    record("Ready")
  }
  func require(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    guard condition() else { failures += 1;record("FAIL \(name)"); return }
    record("OK \(name)")
  }
  func setPasteboard() { let pb = NSPasteboard(name: .drag); pb.clearContents(); pb.writeObjects([file as NSURL]) }
  @objc func runChecks() {
    checks=0;failures=0
    wheel.stop()
    wheel = WheelController(state: state)
    let test = wheel!
    test.trace = { [weak self] text in self?.record(text) }
    state.conversionModifier = "shift"
    test.refresh(down: false, flags: [])
    setPasteboard()
    test.refresh(down: true, flags: .shift)
    require(test.panel != nil, "Open on held Shift at drag start")
    guard let opened=test.panel else { record("FAIL no panel");return }
    let number = opened.windowNumber
    let destination = test.surface!.wheel
    let frame = test.panel!.frame
    for flags: NSEvent.ModifierFlags in [[], .command, [], .control, [], .shift, [], .command] {
      test.refresh(down: true, flags: flags)
      require(test.panel?.windowNumber == number, "Keep one NSPanel through all modifier changes")
      require(test.surface?.wheel === destination, "Keep one native destination")
      require(test.panel?.frame == frame, "Never move the anchor while switching")
      require(test.surface?.subviews.allSatisfy { $0.frame == test.surface!.bounds } == true, "Glass and hit area alignment")
    }
    var transitions:[Int?]=[]
    destination.onSelectionChange={ transitions.append($0) }
    let point=WheelGeometry.point(84.5312,WheelGeometry.angle(0,count:destination.items.count),center:destination.center)
    destination.hover(at:point);destination.hover(at:point)
    require(transitions.count == 1,"Stationary hover emits exactly one click")
    require(destination.visualState.selected == 0,"Glass and foreground share selection")
    destination.hover(at:destination.center)
    require(transitions.count == 2 && transitions.last! == nil,"Centre clears glass selection")
    destination.hover(at:point)
    require(transitions.count == 3,"Reentering petal emits a new click")
    let ring = WheelGeometry.backdropRingPath(center: destination.center)
    require(!ring.contains(destination.center, using: .evenOdd), "Glass backdrop leaves the centre transparent")
    require(ring.contains(point, using: .evenOdd), "Glass backdrop remains behind the petals")
    let callback = destination.onChoose!
    let item = destination.items.first!
    let generation = NSPasteboard(name: .drag).changeCount
    require(callback(item, [file], generation), "Commit once")
    require(!callback(item, [file], generation), "Reject duplicate native callback")
    test.refresh(down: false, flags: [])
    setPasteboard()
    test.refresh(down: true, flags: .shift)
    test.refresh(down: false, flags: [])
    setPasteboard()
    test.refresh(down: true, flags: .control)
    let next = test.panel!.windowNumber
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self, test] in
      require(test.panel?.windowNumber == next, "Old deferred cleanup cannot close a new gesture")
      test.refresh(down: false, flags: [])
      state.conversionModifier = "fn"
      setPasteboard()
      test.refresh(down: true, flags: [])
      test.modifierChanged(flags: .function, keyCode: 123)
      require(test.panel == nil, "An arrow key cannot open the Fn wheel")
      test.modifierChanged(flags: .function, keyCode: 63)
      require(test.shownMode == "formats", "Fn opens formats")
      let fnWindow = test.panel!.windowNumber
      test.modifierChanged(flags: [], keyCode: 63)
      require(test.panel?.windowNumber == fnWindow, "Releasing Fn keeps the same wheel")
      test.refresh(down: false, flags: [])
      state.conversionModifier = "option"
      setPasteboard()
      test.refresh(down: true, flags: .option)
      require(test.shownMode == "formats", "Option opens formats")
      let optionWindow = test.panel!.windowNumber
      let optionFrame = test.panel!.frame
      test.modifierChanged(flags: [], keyCode: 58)
      require(test.panel?.windowNumber == optionWindow, "Releasing Option retains wheel")
      test.modifierChanged(flags: .control, keyCode: 59)
      require(test.shownMode == "actions", "Control switches Option wheel to actions")
      require(test.panel?.windowNumber == optionWindow && test.panel?.frame == optionFrame, "Option to actions retains geometry")
      require(test.surface!.wheel.items.contains(where: { $0.action == "action:finovox" }), "Supported image offers Finovox")
      require(test.surface!.wheel.items.count == 9, "Nine action petals including Duplicate and Atelier")
      require(test.matches("option", .option) && !test.matches("option", [.option, .shift]), "Option only matches unambiguous key")
      test.refresh(down: false, flags: [])
      record("RESULT \(checks) checks, \(failures) failures")
      let data: [String: Any] = ["passed": checks-failures, "failures":failures, "windowRetainedAcrossModes": true, "destinationRetainedAcrossModes": true, "duplicateDropRejected": true, "oldCleanupIgnored": true]
      try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("native-validation.json"))
      reset()
    }
  }
  @objc func quitTest() { wheel.stop(); NSApp.terminate(nil) }
  func windowWillClose(_ notification: Notification) { quitTest() }
}
@main struct WheelUIRegression {
  static func main() {
    let app = NSApplication.shared
    let delegate = WheelUIFixture(); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

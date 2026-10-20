import AppKit
import SwiftUI

extension OnboardingCheck {
  func checkPreviewPointerIsolation() {
    let items = ["PNG", "WEBP", "PDF"].map { WheelItem(title:$0,icon:"",action:$0) }
    let frame = NSRect(x:0,y:0,width:WheelGeometry.side,height:WheelGeometry.side)
    let preview = WheelView(frame:frame,urls:[],items:items,preview:true)
    let panel = NSWindow(contentRect:frame,styleMask:.borderless,backing:.buffered,defer:false)
    panel.isReleasedWhenClosed = false
    panel.contentView = preview
    let target = WheelGeometry.point(84.5,WheelGeometry.angle(0,count:items.count),center:preview.center)
    preview.updateTrackingAreas()
    precondition(!preview.trackingAreas.isEmpty)
    preview.allowsPointerInteraction = false
    precondition(preview.trackingAreas.isEmpty)
    precondition(preview.hitTest(target) == nil && !preview.acceptsFirstResponder)
    preview.setPreviewSelection(2)
    var choices = 0
    preview.onChoose = { _,_,_ in choices += 1; return false }
    for _ in 0..<30 {
      preview.hover(at:target)
      for type in [NSEvent.EventType.mouseMoved,.mouseEntered,.mouseExited,.leftMouseDown,.leftMouseUp] {
        let event: NSEvent
        if type == .mouseEntered || type == .mouseExited {
          event = NSEvent.enterExitEvent(with:type,location:target,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
        } else {
          event = NSEvent.mouseEvent(with:type,location:target,modifierFlags:[],timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
        }
        switch type {
        case .mouseMoved: preview.mouseMoved(with:event)
        case .mouseEntered: preview.mouseEntered(with:event)
        case .mouseExited: preview.mouseExited(with:event)
        case .leftMouseDown: preview.mouseDown(with:event)
        default: preview.mouseUp(with:event)
        }
      }
      precondition(preview.selected == 2, "Real pointer must not override the animated selection")
    }
    precondition(choices == 0)
    preview.setPreviewSelection(1)
    precondition(preview.selected == 1, "Animation must remain in control")
    preview.allowsPointerInteraction = true
    preview.hover(at:target)
    precondition(preview.selected == 0 && !preview.trackingAreas.isEmpty)
    let live = WheelView(frame:frame,urls:[],items:items,preview:false)
    live.allowsPointerInteraction = false
    live.hover(at:target)
    precondition(live.selected == 0, "The actual drag wheel must remain interactive")
    print("PASS: 150 native pointer events ignored by animated preview; animation, interactive catalogue and live wheel preserved")
  }
}

final class OnboardingCheck: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  let state = AppState()
  var wheel: WheelController?
  var module: ModuleWindowController?
  let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestRoot") as! String)
  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--preview-pointer") {
      checkPreviewPointerIsolation()
      NSApp.terminate(nil)
      return
    }
    NSApp.setActivationPolicy(CommandLine.arguments.contains("--panels") ? .accessory : .regular)
    state.appearance = "dark"; state.applyAppearance()
    window = NSWindow(contentRect: NSRect(x:0,y:0,width:1136,height:790),
      styleMask:[.titled,.closable], backing:.buffered, defer:false)
    window.title = "Vérification onboarding"
    window.contentView = NSHostingView(rootView: OnboardingView(state:state))
    window.center()
    if !CommandLine.arguments.contains("--panels") {
      window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    if CommandLine.arguments.contains("--panels") {
      checkPanelActivation()
      return
    }
    let examples = OnboardingToolExample.all
    let expected = Set(Compatibility.conversions.keys.flatMap {
      Tool.catalogue(for: URL(fileURLWithPath:"/sample."+$0)).map(\.id)
    })
    precondition(Set(examples.map { $0.tool.id }) == expected)
    precondition(!examples.contains { $0.tool.id == "qr" })
    precondition(examples.contains { $0.tool.id == "archive" && $0.icon == "doc.zipper" })
    precondition(Set(examples.map(\.id)).count == examples.count)
    precondition(examples.prefix(6).allSatisfy { $0.family == .pdf })
    for name in ["Image.jpg", "Document.pdf", "Tableau.xlsx", "Document.docx", "Vidéo.mp4", "Audio.mp3"] {
      let source = URL(fileURLWithPath: "/" + name)
      for format in Compatibility.targets([source]) {
        let item = WheelItem(title: Compatibility.label(format), icon: "", action: "convert:" + format)
        let output = OnboardingConversionResult.url(source: source, item: item)
        precondition(output.pathExtension == format)
        precondition(output.deletingPathExtension() == source.deletingPathExtension())
      }
      precondition(OnboardingConversionResult.url(source: source, item: nil) == source)
    }
    print("Animation: extension du résultat conforme à chaque destination proposée")
    if CommandLine.arguments.contains("--startup") {
      let defaults = UserDefaults.standard
      let key = "launchAtLogin"
      let saved = defaults.object(forKey: key)
      defer {
        if let saved { defaults.set(saved, forKey: key) }
        else { defaults.removeObject(forKey: key) }
      }
      defaults.removeObject(forKey: key)
      precondition(AppState().login, "Fresh installations must default to launch at login")
      defaults.set(false, forKey: key)
      precondition(!AppState().login, "An explicit opt-out must survive relaunch")
      let resources = root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
      for name in ["AppIcon", "AppIconLight"] {
        let image = NSImage(contentsOf: resources.appendingPathComponent(name+".icns"))!
        for size in [16, 32, 48, 64, 128, 256] {
          let rect = NSRect(x: 0, y: 0, width: size, height: size)
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
          NSGraphicsContext.saveGraphicsState()
          NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
          image.draw(in: rect)
          NSGraphicsContext.restoreGraphicsState()
          let center = bitmap.colorAt(x: size/2, y: size/2)!.usingColorSpace(.deviceRGB)!
          precondition(center.redComponent > 0.85 && center.greenComponent > 0.2
            && center.greenComponent < 0.85 && center.blueComponent < 0.4,
            "Icon center must render orange at every system size")
        }
      }
      print("PASS: démarrage activé par défaut, choix conservé, icônes clair/sombre décodées à six tailles système")
      NSApp.terminate(nil)
      return
    }
    if CommandLine.arguments.contains("--permissions") {
      let center = PermissionCenter.shared
      let onboardingOwner = UUID(), pageOwner = UUID()
      center.startMonitoring(owner: onboardingOwner)
      center.startMonitoring(owner: pageOwner)
      center.stopMonitoring(owner: onboardingOwner)
      precondition(center.monitoring, "Leaving onboarding must not stop the permissions page")
      center.suspendMonitoring()
      precondition(!center.monitoring)
      center.resumeMonitoring()
      precondition(center.monitoring, "Reopening the window must resume its permission checks")
      center.stopMonitoring(owner: pageOwner)
      precondition(!center.monitoring)
      print("PASS: suivi indépendant des écrans, suspension et reprise")
      NSApp.terminate(nil)
      return
    }
    if CommandLine.arguments.contains("--automation") {
      let suite = "io.joseph.clementine.permission-tests." + UUID().uuidString
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let apps: [(ClementinePermission, String)] = [(.pages, "com.apple.Pages"),
        (.numbers, "com.apple.Numbers"), (.keynote, "com.apple.Keynote")]
      for (permission, _) in apps { defaults.set("granted", forKey: "permissionStatus." + permission.id) }
      var recoveries: [ClementinePermission] = []
      let center = PermissionCenter(defaults: defaults, recovery: { recoveries.append($0) })
      for (permission, bundleID) in apps {
        // A prior grant survives both relaunch and a busy/stopped app.
        let key = "permissionStatus." + permission.id
        if center.status(permission) != .unavailable { precondition(center.status(permission) == .granted) }
        for transient: OSStatus in [-1712, -600, -1] {
          center.recordPassiveAutomationResult(transient, for: permission)
          precondition(defaults.string(forKey: key) == "granted")
        }
        let report: (String, OSStatus) -> Void = { center.recordWorkflowResult(bundleID: $0, result: $1) }
        do {
          _ = try NativeOfficeScript.run("error \"Simulated refusal\" number -1743",
            bundleID: bundleID, operation: "Test", report: report)
          preconditionFailure("Permission refusal must fail the operation")
        } catch {
          precondition(defaults.string(forKey: key) == "denied")
          precondition(recoveries.last == permission)
        }
        let result = try! NativeOfficeScript.run("return \"ok\"", bundleID: bundleID,
          operation: "Test", report: report)
        precondition(result.stringValue == "ok")
        precondition(defaults.string(forKey: key) == "granted")
        // A document/script error must not revoke an existing grant.
        do {
          _ = try NativeOfficeScript.run("error \"Missing document\" number -1728",
            bundleID: bundleID, operation: "Test", report: report)
          preconditionFailure("Non-permission error must propagate")
        } catch { precondition(defaults.string(forKey: key) == "granted") }
      }
      precondition(recoveries.count == 3)
      var bridged: NativeOfficePermissionResult?
      let observer = NotificationCenter.default.addObserver(forName: NativeOfficeScript.permissionResult,
        object: nil, queue: nil) { bridged = $0.object as? NativeOfficePermissionResult }
      _ = try! NativeOfficeScript.run("return \"ok\"", bundleID: "io.example.App", operation: "Test")
      precondition(bridged?.bundleID == "io.example.App" && bridged?.result == noErr)
      NotificationCenter.default.removeObserver(observer)
      let reloaded = PermissionCenter(defaults: defaults)
      for (permission, bundleID) in apps {
        precondition(ClementinePermission.automation(bundleID: bundleID) == permission)
        precondition(ClementinePermission.automation(bundleID: bundleID.replacingOccurrences(of: "com.apple.", with: "com.apple.iWork.")) == permission)
        if reloaded.status(permission) != .unavailable { precondition(reloaded.status(permission) == .granted) }
      }
      print("PASS: Pages/Numbers/Keynote — grants persist, transient failures preserve status, actual workflow refusals request the right app, successes restore status")
      NSApp.terminate(nil)
      return
    }
    print("Catalogue: \(expected.count) outils réels, \(examples.count) exemples, aucune fonction inventée")
    try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    if CommandLine.arguments.contains("--tools") {
      window.contentView = NSHostingView(rootView:
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
          ForEach(examples) { example in
            VStack(alignment: .leading, spacing: 10) {
              Text(example.tool.name).font(.system(size: 12, weight: .semibold))
              OnboardingToolIllustration(example: example).frame(height: 58)
            }.padding(12).frame(height: 102).background(Color.clementineRaisedSurface,
              in: RoundedRectangle(cornerRadius: 10))
          }
        }.padding(20).frame(width: 1136, height: 790).background(Color.clementineCanvas))
      DispatchQueue.main.asyncAfter(deadline:.now()+1) { [self] in
        saveScreenshot("tools-gallery")
        NSApp.terminate(nil)
      }
      return
    }
    if CommandLine.arguments.contains("--keyboard") {
      DispatchQueue.main.asyncAfter(deadline:.now()+1) { [self] in
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeated: Bool = false) {
          let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: repeated, keyCode: code)!
          NSApp.sendEvent(event)
        }
        key(123); precondition(state.onboardingPage == 0)
        key(124); precondition(state.onboardingPage == 1)
        key(124, flags: .command); precondition(state.onboardingPage == 1)
        key(124, repeated: true); precondition(state.onboardingPage == 1)
        key(124); precondition(state.onboardingPage == 2)
        key(123); precondition(state.onboardingPage == 1)
        state.onboardingPage = 4
        key(124); precondition(state.onboardingPage == 4)
        key(123); precondition(state.onboardingPage == 3)
        print("PASS: flèches gauche/droite, limites, touches modifiées et répétitions")
        NSApp.terminate(nil)
      }
      return
    }
    capture(page:0, light:false)
  }
  func saveScreenshot(_ name: String) {
    let task = Process(); task.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
    task.arguments = ["-x","-l",String(window.windowNumber),root.appendingPathComponent(name+".png").path]
    try! task.run(); task.waitUntilExit()
    precondition(task.terminationStatus == 0)
  }
  func checkPanelActivation() {
    let file = Bundle.main.url(forResource:"clementine-demo",withExtension:"jpg",subdirectory:"Demo")!
    window.orderOut(nil)
    NSApp.deactivate()
    DispatchQueue.main.asyncAfter(deadline:.now()+1) { [self] in
      precondition(!NSApp.isActive)
      wheel = WheelController(state:state)
      wheel!.show([file], mode:"tools")
      DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [self] in
        precondition(!NSApp.isActive, "Wheel must not activate the app")
        precondition(!window.isVisible, "Wheel must not restore the main window")
        precondition(wheel!.panel!.styleMask.contains(.nonactivatingPanel))
        wheel!.close()
        module = ModuleWindowController(tool:"compress",files:[file],defaults:Options(),reveal:false)
        module!.show()
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [self] in
          precondition(!NSApp.isActive, "Module must not activate the app")
          precondition(!window.isVisible, "Module must not restore the main window")
          precondition(module!.window.styleMask.contains(.nonactivatingPanel))
          precondition(!module!.window.canBecomeMain)
          module!.window.close()
          print("PASS: roue et module restent non activants; fenêtre principale inchangée")
          NSApp.terminate(nil)
        }
      }
    }
  }
  func capture(page:Int, light:Bool) {
    state.onboardingPage = page
    state.appearance = light ? "light" : "dark"; state.applyAppearance()
    DispatchQueue.main.asyncAfter(deadline:.now()+3.9) { [self] in
      let file = root.appendingPathComponent("slide-\(page+1)-\(light ? "light" : "dark").png")
      let task = Process(); task.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
      task.arguments = ["-x","-l",String(window.windowNumber),file.path]
      try? task.run(); task.waitUntilExit()
      print("Capture \(file.lastPathComponent): \(task.terminationStatus)")
      if page < 4 { capture(page:page+1,light:light) }
      else if !light { capture(page:0,light:true) }
      else {
        iconCheck()
        NSApp.terminate(nil)
      }
    }
  }
  func iconCheck() {
    let image = NSImage(size:NSSize(width:240,height:240))
    image.lockFocus()
    WheelGlyph.draw("wheel:finovox",in:NSRect(x:0,y:0,width:240,height:240),color:.orange,context:NSGraphicsContext.current!.cgContext)
    image.unlockFocus()
    let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
    // The upper-right folded quadrant must be empty, with only its outline.
    let color = rep.colorAt(x:rep.pixelsWide * 15 / 24,y:rep.pixelsHigh * 8 / 24)!
    precondition(color.alphaComponent < 0.1, "Finovox fold must stay hollow")
    try! rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("finovox.png"))
    print("Finovox: intérieur transparent OK")
  }
}
@main struct Main {
  static func main() { let app=NSApplication.shared;let delegate=OnboardingCheck();app.delegate=delegate;app.run() }
}

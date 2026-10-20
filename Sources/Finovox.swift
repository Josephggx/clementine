import AppKit
import ApplicationServices
import SwiftUI

// Uses the same blue import button and native file picker as a manual SaaS upload.
// Never reads credentials, browser storage, or private API endpoints.
final class FinovoxUploader {
  static let shared = FinovoxUploader()
  static let extensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "tif", "tiff", "zip"]
  static func accepts(_ urls: [URL]) -> Bool {
    !urls.isEmpty && urls.allSatisfy {
      $0.isFileURL && extensions.contains($0.pathExtension.lowercased())
        && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
  }
  private var busy = false
  private var cancelled = false
  private var timer: Timer?
  private var panel: NSPanel?
  private var progressIndicator: NSView?
  private var label: NSTextField?
  private var queue: [URL] = []
  private var completed = 0
  private var chrome: NSRunningApplication?
  private var organization: String?
  private var baseline = 0
  private var stage = ""
  private var stageStarted = Date()
  private var deadline = Date()
  private var handedOff = false
  private var runID = UUID()
  private var lastChromeActivation = Date.distantPast
  private var preferredChromeWindow: AXUIElement?
  private var requestedChromeTab = false
  private var pendingAccessibilityURLs: [URL] = []
  private var accessibilityTimer: Timer?
  private var accessibilityDeadline = Date()

  func start(_ urls: [URL]) {
    guard !busy else { panel?.orderFront(nil); return }
    guard pendingAccessibilityURLs.isEmpty else { return }
    guard Self.accepts(urls) else {
      alert("Format non pris en charge", "Finovox accepte PDF, PNG, JPG, TIFF et ZIP. Sélectionnez uniquement des fichiers dans ces formats.")
      return
    }
    guard AXIsProcessTrusted() else {pendingAccessibilityURLs=urls;showAccessibilityRepair();return}
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
      alert("Chrome requis", "L’import utilise votre session Finovox connectée dans Google Chrome.")
      return
    }
    queue = urls.reduce(into: [URL]()) { result, url in
      if !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { result.append(url) }
    }
    completed = 0; organization = nil; cancelled = false; handedOff = false
    runID = UUID()
    let currentRun = runID
    preferredChromeWindow = nil; requestedChromeTab = false
    lastChromeActivation = .distantPast
    busy = true
    showProgress()
    chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first
    if let chrome, focusAuthenticatedFinovoxTab(chrome) {
      begin("ready", seconds: 45)
    } else if let chrome, focusExistingFinovoxTab(chrome) {
      begin("ready", seconds: 45)
    } else if let chrome, prepareFinovoxTabInPreferredProfile(chrome) {
      begin("new-tab", seconds: 15)
    } else {
      begin("opening", seconds: 60)
      let config = NSWorkspace.OpenConfiguration(); config.activates = true
      NSWorkspace.shared.open([URL(string: "https://app.finovox.com/")!], withApplicationAt: appURL, configuration: config) { [weak self] app, error in
        DispatchQueue.main.async {
          guard let self, self.busy, self.runID == currentRun else { return }
          guard let app, error == nil else { self.fail("Impossible d’ouvrir Chrome."); return }
          self.chrome = app; self.begin("ready", seconds: 60)
        }
      }
    }
    timer?.invalidate()
    let nextTimer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
      guard let self, self.runID == currentRun else { return }
      self.tick()
    }
    RunLoop.main.add(nextTimer, forMode: .common)
    timer = nextTimer
  }
  private func begin(_ next: String, seconds: Double) {
    stage = next; stageStarted = Date(); deadline = Date().addingTimeInterval(seconds)
  }
  private func showProgress() {
    closePanel()
    let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 145), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    p.title = "Finovox"; p.isReleasedWhenClosed = false; p.level = .floating
    let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 420, height: 145))
    effect.material = .hudWindow; effect.blendingMode = .behindWindow; effect.state = .active
    let text = NSTextField(wrappingLabelWithString: "Ouverture de Finovox…")
    text.frame = NSRect(x: 20, y: 60, width: 380, height: 65); effect.addSubview(text); label = text
    let indicator = NSHostingView(rootView:
      ProgressView().progressViewStyle(.linear).tint(citrus).frame(width: 380))
    indicator.frame = NSRect(x: 20, y: 43, width: 380, height: 8)
    effect.addSubview(indicator)
    progressIndicator = indicator
    let cancel = NSButton(title: "Arrêter", target: self, action: #selector(cancelUpload))
    cancel.frame = NSRect(x: 300, y: 12, width: 100, height: 30); effect.addSubview(cancel)
    p.contentView = effect; p.center(); p.orderFrontRegardless(); panel = p
  }
  @objc private func cancelUpload() {
    cancelled = true
    finish(handedOff ? "Arrêté. Le fichier déjà transmis peut continuer à être traité dans Finovox." : "Import arrêté.")
  }
  private func tick() {
    guard busy, !cancelled, let chrome, let file = queue.first else { return }
    if Date() > deadline {
      if handedOff {
        fail("Le fichier a été remis à Finovox, mais son apparition n’a pas pu être confirmée. Vérifiez le SaaS avant de réessayer pour éviter un doublon.")
      } else if stage == "ready" || stage == "opening" || stage == "new-tab" {
        fail("Clémentine n’a pas retrouvé de session Finovox connectée dans Chrome. Ouvrez app.finovox.com dans le bon profil Chrome puis relancez l’action. Aucun fichier n’a été envoyé.")
      } else {
        fail("Le sélecteur de fichiers de Chrome n’a pas répondu. Fermez tout sélecteur déjà ouvert puis relancez l’action. Aucun fichier n’a été envoyé.")
      }
      return
    }
    let root = AXUIElementCreateApplication(chrome.processIdentifier)
    if stage == "new-tab" {
      guard let window = preferredChromeWindow else {
        fail("La fenêtre du profil Chrome Finovox n’est plus disponible. Aucun fichier n’a été envoyé.")
        return
      }
      focus(chrome, window: window)
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else { return }
      if !requestedChromeTab {
        guard Date().timeIntervalSince(stageStarted) > 0.55 else { return }
        requestedChromeTab = true
        key(17, flags: .maskCommand) // New tab in the verified Chrome profile window.
        return
      }
      guard Date().timeIntervalSince(stageStarted) > 1.05 else { return }
      let root = AXUIElementCreateApplication(chrome.processIdentifier)
      guard let focused = element(root, kAXFocusedUIElementAttribute),
        [kAXTextFieldRole, "AXComboBox"].contains(role(focused)) else { return }
      guard AXUIElementSetAttributeValue(
        focused, kAXValueAttribute as CFString, "https://app.finovox.com/" as CFString) == .success
      else { return }
      key(36)
      preferredChromeWindow = nil
      begin("opening", seconds: 30)
    } else if stage == "opening" {
      guard let context = authenticatedFinovoxContext(chrome) ?? finovoxContext(chrome) else { return }
      focus(chrome, window: context.window)
      begin("ready", seconds: 45)
    } else if stage == "ready" {
      label?.stringValue = "Connexion à Finovox…\n\(completed + 1) / \(completed + queue.count) · \(file.lastPathComponent)"
      guard let context = finovoxContext(chrome) else {
        _ = focusExistingFinovoxTab(chrome)
        return
      }
      focus(chrome, window: context.window)
      let web = context.web
      let nodes = descendants(web)
      guard let button = importButton(nodes) else { return }
      let org = nodes.first(where: { normalizedName($0).contains("changer d’organisation") })
        .map { string($0, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
      guard !org.isEmpty else { fail("L’organisation Finovox n’a pas pu être identifiée. Aucun fichier n’a été envoyé."); return }
      if let organization, organization != org { fail("L’organisation active a changé. Import arrêté pour éviter un envoi dans le mauvais espace."); return }
      organization = org
      baseline = fileCount(nodes, file: file)
      // Chrome must own the foreground before Clémentine presses a control in
      // its accessibility tree. Reassert activation because a nonactivating
      // wheel panel can otherwise leave Finder in front after the drop.
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
        label?.stringValue = "Activation de Chrome…\n\(file.lastPathComponent)"
        focus(chrome, window: context.window)
        return
      }
      begin("picker", seconds: 12)
      // One verified native click. AXPress followed by a speculative click can
      // open the importer twice when Chrome exposes its file sheet late.
      guard clickCenter(button) else { fail("Le bouton bleu d’import ne répond pas."); return }
    } else if stage == "picker" {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
        _ = focusExistingFinovoxTab(chrome); return
      }
      guard let picker = openPanel(root) else { return }
      guard !descendants(picker).contains(where: { role($0) == kAXTextFieldRole && name($0).contains("mot de passe") }) else { fail("Sélecteur inattendu."); return }
      key(5, flags: [.maskCommand, .maskShift]) // Go to Folder, only inside the verified Open panel.
      begin("path", seconds: 10)
    } else if stage == "path" {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
        _ = chrome.activate(options: []); return
      }
      // Go to Folder's editable path field is focused by macOS.
      guard let focused = element(root, kAXFocusedUIElementAttribute),
        [kAXTextFieldRole, "AXComboBox"].contains(role(focused)),
        (string(focused, kAXIdentifierAttribute) == "PathTextField"
          || normalizedName(focused).contains("dossier")) else { return }
      guard AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, file.path as CFString) == .success else { fail("Impossible de renseigner le chemin du fichier."); return }
      key(36)
      begin("select", seconds: 10)
    } else if stage == "select" {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
        _ = chrome.activate(options: []); return
      }
      guard let picker = openPanel(root) else { return }
      let nodes = descendants(picker)
      // Do not confirm until macOS has resolved and selected the exact requested filename.
      guard nodes.contains(where: { role($0) == kAXRowRole && (attr($0, kAXSelectedAttribute) as? Bool) == true && descendants($0).contains(where: { name($0) == file.lastPathComponent || string($0, kAXValueAttribute) == file.lastPathComponent }) }),
        let open = nodes.first(where: { string($0, kAXIdentifierAttribute) == "OKButton" }),
        (attr(open, kAXEnabledAttribute) as? Bool) == true else { return }
      guard press(open) else { fail("Le sélecteur n’a pas accepté le fichier."); return }
      handedOff = true
      label?.stringValue = "Envoi dans \(organization ?? "Finovox")…\n\(file.lastPathComponent)"
      begin("verify", seconds: 90)
    } else if stage == "verify" {
      guard let web = finovoxContext(chrome)?.web else { return }
      let nodes = descendants(web)
      guard fileCount(nodes, file: file) > baseline else { return }
      completed += 1; queue.removeFirst(); handedOff = false
      if queue.isEmpty { finish("\(completed) document\(completed > 1 ? "s" : "") importé\(completed > 1 ? "s" : "") dans \(organization ?? "Finovox").", success: true) }
      else { begin("ready", seconds: 20) }
    }
  }
  private func focus(_ chrome: NSRunningApplication, window: AXUIElement) {
    guard Date().timeIntervalSince(lastChromeActivation) >= 0.7 else { return }
    lastChromeActivation = Date()
    // Activating through NSWorkspace may raise another Chrome profile/window.
    // Activate the process, then explicitly raise the window that owns Finovox.
    _ = chrome.activate(options: [])
    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  }
  private func finish(_ message: String, success: Bool = false) {
    timer?.invalidate(); timer = nil; busy = false
    runID = UUID()
    preferredChromeWindow = nil; requestedChromeTab = false
    progressIndicator?.removeFromSuperview(); progressIndicator = nil
    if success { closePanel(); return }
    label?.stringValue = message
    if let button = panel?.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
      button.title = "Fermer"; button.action = #selector(closePanel)
    }
  }
  @objc private func closePanel() {
    panel?.close(); panel = nil; label = nil; progressIndicator = nil
  }
  private func fail(_ message: String) { finish(message) }
  private func alert(_ title: String, _ message: String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; NSApp.activate(ignoringOtherApps: true); a.runModal() }
  private func showAccessibilityRepair() {
    let a = NSAlert()
    a.messageText = "Clémentine n’a pas accès à Chrome"
    a.informativeText = "macOS conserve parfois l’autorisation de l’ancienne version après une mise à jour, même si l’interrupteur Clémentine reste bleu. Réparer retire uniquement cette autorisation obsolète, puis affiche la demande correcte. L’import reprendra automatiquement dès que l’accès sera activé. Aucun mot de passe ni contenu de navigation n’est lu."
    a.addButton(withTitle:"Réparer l’autorisation")
    a.addButton(withTitle:"Ouvrir les réglages")
    a.addButton(withTitle:"Annuler")
    NSApp.activate(ignoringOtherApps:true)
    switch a.runModal() {
    case .alertFirstButtonReturn: repairAccessibilityPermission()
    case .alertSecondButtonReturn: openAccessibilitySettings();watchForAccessibilityPermission()
    default: pendingAccessibilityURLs=[]
    }
  }
  private func repairAccessibilityPermission() {
    let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/bin/tccutil")
    task.arguments=["reset","Accessibility",Bundle.main.bundleIdentifier ?? "io.joseph.clementine.desktop"]
    do {
      try task.run();task.waitUntilExit()
      guard task.terminationStatus == 0 else {openAccessibilitySettings();watchForAccessibilityPermission();return}
      let key=kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      _=AXIsProcessTrustedWithOptions([key:true] as CFDictionary)
      DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {self.openAccessibilitySettings();self.watchForAccessibilityPermission()}
    } catch {openAccessibilitySettings();watchForAccessibilityPermission()}
  }
  private func watchForAccessibilityPermission() {
    accessibilityTimer?.invalidate();accessibilityDeadline=Date().addingTimeInterval(120)
    accessibilityTimer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) {[weak self] timer in
      guard let self else {timer.invalidate();return}
      if AXIsProcessTrusted() {
        timer.invalidate();self.accessibilityTimer=nil
        let urls=self.pendingAccessibilityURLs;self.pendingAccessibilityURLs=[]
        if !urls.isEmpty {self.start(urls)}
      } else if Date()>self.accessibilityDeadline {
        timer.invalidate();self.accessibilityTimer=nil;self.pendingAccessibilityURLs=[]
      }
    }
  }
  private func openAccessibilitySettings() {
    guard let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {return}
    NSWorkspace.shared.open(url)
  }
  private func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? { var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success else { return nil }; return v }
  private func element(_ e: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attr(e, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }; return (value as! AXUIElement)
  }
  private func string(_ e: AXUIElement, _ key: String) -> String { (attr(e, key) as? String) ?? "" }
  private func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) }
  private func name(_ e: AXUIElement) -> String { let title = string(e, kAXTitleAttribute); return title.isEmpty ? string(e, kAXDescriptionAttribute) : title }
  private func descendants(_ e: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []; var stack = [e]
    var visited = Set<AXNodeKey>()
    while let current = stack.popLast(), result.count < 6000 {
      guard visited.insert(AXNodeKey(element: current)).inserted else { continue }
      result.append(current)
      stack.append(contentsOf: ((attr(current, kAXChildrenAttribute) as? [AXUIElement]) ?? []).reversed())
      if [kAXWindowRole, "AXSheet", "AXDialog"].contains(role(current)) {
        stack.append(contentsOf: ((attr(current, kAXContentsAttribute) as? [AXUIElement]) ?? []).reversed())
      }
    }
    return result
  }
  private func windows(_ root: AXUIElement) -> [AXUIElement] {
    (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
  }
  private func finovoxContext(_ app: NSRunningApplication) -> (window: AXUIElement, web: AXUIElement)? {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let candidates = ([element(root, kAXFocusedWindowAttribute)].compactMap { $0 } + windows(root))
    for window in candidates {
      if let web = descendants(window).first(where: { role($0) == "AXWebArea" && isFinovox($0) }) {
        return (window, web)
      }
    }
    return nil
  }
  private func authenticatedFinovoxContext(_ app: NSRunningApplication) -> (window: AXUIElement, web: AXUIElement)? {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let candidates = ([element(root, kAXFocusedWindowAttribute)].compactMap { $0 } + windows(root))
    for window in candidates {
      for web in descendants(window) where role(web) == "AXWebArea" && isFinovox(web) {
        if importButton(descendants(web)) != nil { return (window, web) }
      }
    }
    return nil
  }
  private func focusAuthenticatedFinovoxTab(_ app: NSRunningApplication) -> Bool {
    guard let context = authenticatedFinovoxContext(app) else { return false }
    focus(app, window: context.window)
    return true
  }
  private func prepareFinovoxTabInPreferredProfile(_ app: NSRunningApplication) -> Bool {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    // Chrome appends the profile name to each native window title. Prefer a
    // profile explicitly named for Finovox before falling back to Chrome's
    // default profile, which may be a personal and unauthenticated session.
    guard let window = windows(root).first(where: {
      string($0, kAXTitleAttribute).folding(
        options: [.diacriticInsensitive, .caseInsensitive], locale: .current
      ).contains("finovox")
    }) else { return false }
    preferredChromeWindow = window
    requestedChromeTab = false
    focus(app, window: window)
    return true
  }
  private func focusExistingFinovoxTab(_ app: NSRunningApplication) -> Bool {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    if let context = finovoxContext(app) {
      focus(app, window: context.window)
      return true
    }
    // Search per window so the exact Chrome window can be raised after its
    // Finovox tab is selected. This also works with several Chrome profiles.
    for window in windows(root) {
      if let tab = descendants(window).first(where: {
        [kAXRadioButtonRole, "AXTab"].contains(role($0))
          && normalizedName($0).contains("finovox")
      }), press(tab) {
        focus(app, window: window)
        return true
      }
    }
    return false
  }
  private func isFinovox(_ web: AXUIElement) -> Bool {
    let raw = string(web, "AXURL").trimmingCharacters(in: .whitespacesAndNewlines)
    let value = attr(web, "AXURL")
    let url = (value as? URL) ?? (value as? NSURL).map { $0 as URL }
      ?? URL(string: raw.contains("://") ? raw : "https://" + raw)
    return url?.scheme == "https" && url?.host == "app.finovox.com"
  }
  private func normalizedName(_ element: AXUIElement) -> String {
    name(element).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }
  private func importButton(_ nodes: [AXUIElement]) -> AXUIElement? {
    nodes.first {
      role($0) == kAXButtonRole && normalizedName($0).contains("importer des documents")
    }
  }
  private func openPanel(_ root: AXUIElement) -> AXUIElement? {
    // Native dialogs may not be in the browser's window list. Follow the
    // focused field's ancestors first, before traversing a large web document.
    var ancestor = element(root, kAXFocusedUIElementAttribute)
    for _ in 0..<16 {
      guard let current = ancestor else { break }
      if string(current, kAXIdentifierAttribute) == "open-panel" { return current }
      if ["AXSheet", "AXDialog", kAXWindowRole].contains(role(current)),
        descendants(current).contains(where: { string($0, kAXIdentifierAttribute) == "OKButton" }) { return current }
      ancestor = element(current, kAXParentAttribute)
    }
    let candidates = ([element(root, kAXFocusedWindowAttribute)].compactMap { $0 } + windows(root)).flatMap(descendants)
    if let exact = candidates.first(where: { string($0, kAXIdentifierAttribute) == "open-panel" }) { return exact }
    return candidates.first(where: {
      ["AXSheet", "AXDialog", kAXWindowRole].contains(role($0))
        && descendants($0).contains(where: { string($0, kAXIdentifierAttribute) == "OKButton" })
    })
  }
  private func clickCenter(_ element: AXUIElement) -> Bool {
    guard let positionValue = attr(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
      let sizeValue = attr(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return false }
    var position = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return false }
    let original = NSEvent.mouseLocation
    let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    let source = CGEventSource(stateID: .privateState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    // CGEvent uses the global top-left coordinate space; restore the pointer.
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(original) }) {
      let restored = CGPoint(x: original.x, y: screen.frame.maxY - original.y)
      CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: restored, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    return true
  }
  private func fileCount(_ nodes: [AXUIElement], file: URL) -> Int {
    // Count exact filename labels too: Finovox can render its document list
    // without AXRow elements. The pre-import baseline prevents old files from
    // being mistaken for this upload's confirmation.
    nodes.filter { name($0).trimmingCharacters(in: .whitespacesAndNewlines) == file.lastPathComponent
      || string($0, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines) == file.lastPathComponent }.count
  }
  private func press(_ e: AXUIElement) -> Bool { AXUIElementPerformAction(e, kAXPressAction as CFString) == .success }
  private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .privateState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags; up?.flags = flags
    down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
  }
}

private struct AXNodeKey: Hashable {
  let element: AXUIElement
  static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
  func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

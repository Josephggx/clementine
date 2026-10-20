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
  private var stage = ""
  private var stageStarted = Date()
  private var deadline = Date()
  private var handedOff = false
  private var nativePicker: AXUIElement?
  private var runID = UUID()
  private var lastChromeActivation = Date.distantPast
  private var preferredChromeWindow: AXUIElement?
  private var requestedChromeTab = false
  private var requestedDocumentTab = false
  private var pendingExistingTab: AXUIElement?
  private var clickedExistingTab = false
  private var attributeCache: [AXNodeKey: [String: AnyObject]] = [:]
  var onCompletion: ((Bool, String) -> Void)?
  var onStageChange: ((String) -> Void)?
  var onDiagnostic: ((String) -> Void)?
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
    queue = urls
    completed = 0; nativePicker = nil
    organization = nil; cancelled = false; handedOff = false
    runID = UUID()
    let currentRun = runID
    preferredChromeWindow = nil; requestedChromeTab = false; requestedDocumentTab = false
    pendingExistingTab = nil; clickedExistingTab = false
    attributeCache.removeAll()
    lastChromeActivation = .distantPast
    busy = true
    showProgress()
    chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first
    if let chrome, focusAuthenticatedFinovoxTab(chrome) {
      begin("ready", seconds: 15)
    } else if let chrome, focusExistingFinovoxTab(chrome) {
      begin(pendingExistingTab == nil ? "ready" : "existing-tab", seconds:15)
    } else if let chrome, prepareFinovoxTabInPreferredProfile(chrome) {
      begin("new-tab", seconds: 15)
    } else {
      begin("opening", seconds: 25)
      let config = NSWorkspace.OpenConfiguration(); config.activates = true
      NSWorkspace.shared.open([URL(string: "https://app.finovox.com/")!], withApplicationAt: appURL, configuration: config) { [weak self] app, error in
        DispatchQueue.main.async {
          guard let self, self.busy, self.runID == currentRun else { return }
          guard let app, error == nil else { self.fail("Impossible d’ouvrir Chrome."); return }
          self.chrome = app; self.begin("opening", seconds: 25)
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
    onStageChange?(next)
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
    // AX objects are live: cache only within this observation, never across navigation.
    attributeCache.removeAll(keepingCapacity: true)
    if Date() > deadline {
      if handedOff {
        fail("Le sélecteur a accepté le fichier, mais sa fermeture n’a pas pu être confirmée. Vérifiez la fenêtre Chrome avant de réessayer.")
      } else if ["ready", "opening", "new-tab", "existing-tab"].contains(stage) {
        fail("Le bouton « Importer des documents » n’est pas disponible. Vérifiez que la liste des documents Finovox est chargée dans le bon profil Chrome. Aucun fichier n’a été envoyé.")
      } else {
        fail("Le sélecteur de fichiers de Chrome n’a pas répondu. Fermez tout sélecteur déjà ouvert puis relancez l’action. Aucun fichier n’a été envoyé.")
      }
      return
    }
    let root = AXUIElementCreateApplication(chrome.processIdentifier)
    if stage == "existing-tab" {
      guard let window=preferredChromeWindow, let tab=pendingExistingTab else {return}
      if !clickedExistingTab {
        focus(chrome,window:window)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier,
          Date().timeIntervalSince(stageStarted)>0.7 else {return}
        guard clickCenter(tab) else {return}
        clickedExistingTab=true
        onDiagnostic?("Clicked existing Finovox tab; awaiting its document view")
        return
      }
      guard Date().timeIntervalSince(stageStarted)>1.2 else {return}
      if let context=finovoxContext(chrome),
        FinovoxImportPage.route(for:webURL(context.web)) == .documents
          || webURL(context.web)?.path.hasSuffix("/preview") == true {
        pendingExistingTab=nil;begin("ready",seconds:15)
      }
    } else if stage == "new-tab" {
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
        isAddressField(focused) else { return }
      guard AXUIElementSetAttributeValue(
        focused, kAXValueAttribute as CFString, "https://app.finovox.com/" as CFString) == .success
      else { return }
      key(36)
      begin("opening", seconds: 20)
    } else if stage == "opening" {
      guard let context = authenticatedFinovoxContext(chrome) ?? finovoxContext(chrome) else { return }
      let route = FinovoxImportPage.route(for: webURL(context.web))
      if route == .signIn {
        fail("Connectez-vous à Finovox dans Chrome puis relancez l’import. Aucun fichier n’a été envoyé.")
        return
      }
      guard route == .documents else { return }
      focus(chrome, window: context.window)
      preferredChromeWindow = context.window
      begin("ready", seconds: 15)
    } else if stage == "ready" {
      label?.stringValue = "Recherche du bouton d’import…\n\(completed + 1) / \(completed + queue.count) · \(file.lastPathComponent)"
      guard let context = authenticatedFinovoxContext(chrome) else {
        if let existing = finovoxContext(chrome) {
          switch FinovoxImportPage.route(for: webURL(existing.web)) {
          case .signIn:
            fail("Connectez-vous à Finovox dans Chrome puis relancez l’import. Aucun fichier n’a été envoyé.")
          case .other where !requestedDocumentTab:
            if focusExistingFinovoxTab(chrome), pendingExistingTab != nil {
              begin("existing-tab",seconds:15);return
            }
            requestedDocumentTab = true
            // Close only the document viewer, through its own control. A second
            // SaaS tab can block uploads in a synchronised workspace.
            if webURL(existing.web)?.path.hasSuffix("/preview") == true,
              let close = descendants(existing.web, until: { self.isViewerCloseButton($0) })
                .first(where: isViewerCloseButton) {
              focus(chrome, window:existing.window)
              if press(close) { begin("opening", seconds:20);return }
            }
            preferredChromeWindow = existing.window; requestedChromeTab = false
            focus(chrome, window: existing.window)
            begin("new-tab", seconds: 10)
          default: break
          }
          return
        }
        if focusExistingFinovoxTab(chrome), pendingExistingTab != nil {
          begin("existing-tab",seconds:15)
        }
        return
      }
      focus(chrome, window: context.window)
      preferredChromeWindow = context.window
      let web = context.web
      let nodes = descendants(web, until: isImportButton)
      guard let button = importButton(nodes) else { return }
      guard (attr(button,kAXEnabledAttribute) as? Bool) != false else {return}
      let org = nodes.first(where: { normalizedName($0).contains("changer d’organisation") })
        .map { string($0, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
      guard !org.isEmpty else { fail("L’organisation Finovox n’a pas pu être identifiée. Aucun fichier n’a été envoyé."); return }
      if let organization, organization != org { fail("L’organisation active a changé. Import arrêté pour éviter un envoi dans le mauvais espace."); return }
      organization = org
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
        fail("Import interrompu : une autre application a pris la main sur le sélecteur. Aucun fichier n’a été envoyé.");return
      }
      guard let picker = openPanel(root) else { return }
      guard pickerBelongsToImportWindow(picker) else { return }
      nativePicker = picker
      guard !descendants(picker).contains(where: { role($0) == kAXTextFieldRole && name($0).contains("mot de passe") }) else { fail("Sélecteur inattendu."); return }
      onDiagnostic?("Native picker focused: \(role(picker)) / \(string(picker,kAXIdentifierAttribute))")
      key(5, flags: [.maskCommand, .maskShift]) // Go to Folder, only inside the verified Open panel.
      begin("path", seconds: 10)
    } else if stage == "path" {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
        fail("Import interrompu : une autre application a pris la main sur le sélecteur. Aucun fichier n’a été envoyé.");return
      }
      guard let picker=openPanel(root), let nativePicker, CFEqual(picker,nativePicker) else {return}
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
        fail("Import interrompu : une autre application a pris la main sur le sélecteur. Aucun fichier n’a été envoyé.");return
      }
      guard let picker = openPanel(root), let nativePicker, CFEqual(picker,nativePicker) else { return }
      let nodes = descendants(picker)
      // Do not confirm until macOS has resolved and selected the exact requested filename.
      guard nodes.contains(where: { role($0) == kAXRowRole && (attr($0, kAXSelectedAttribute) as? Bool) == true && descendants($0).contains(where: { name($0) == file.lastPathComponent || string($0, kAXValueAttribute) == file.lastPathComponent }) }),
        let open = nodes.first(where: { string($0, kAXIdentifierAttribute) == "OKButton" }),
        (attr(open, kAXEnabledAttribute) as? Bool) == true else { return }
      guard press(open) else { fail("Le sélecteur n’a pas accepté le fichier."); return }
      handedOff = true
      label?.stringValue = "Envoi dans \(organization ?? "Finovox")…\n\(file.lastPathComponent)"
      begin("verify", seconds: 12)
    } else if stage == "verify" {
      // Confirm delivery to the SaaS, not its analysis or table rendering.
      // Finovox owns validation, duplicate handling and ZIP expansion.
      guard openPanel(root) == nil else { return }
      guard Date().timeIntervalSince(stageStarted)>0.7,
        finovoxContext(chrome) != nil else {return}
      completed += 1; queue.removeFirst(); handedOff = false
      nativePicker = nil
      if queue.isEmpty {
        finish("\(completed) fichier\(completed>1 ? "s" : "") remis à Finovox. Le SaaS gère la suite de l’import.",success:true)
      }
      else { begin("ready", seconds: 20) }
    }
  }
  private func focus(_ chrome: NSRunningApplication, window: AXUIElement) {
    let isFrontmost=NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier
    if isFrontmost {
      let root=AXUIElementCreateApplication(chrome.processIdentifier)
      if let current=element(root,kAXFocusedWindowAttribute), CFEqual(current,window) {return}
    }
    guard Date().timeIntervalSince(lastChromeActivation) >= 0.7 else { return }
    lastChromeActivation = Date()
    // Activating through NSWorkspace may raise another Chrome profile/window.
    // Activate the process, then explicitly raise the window that owns Finovox.
    if !isFrontmost { _ = chrome.activate(options: []) }
    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  }
  private func finish(_ message: String, success: Bool = false) {
    timer?.invalidate(); timer = nil; busy = false
    runID = UUID()
    preferredChromeWindow = nil; requestedChromeTab = false
    nativePicker = nil
    pendingExistingTab = nil
    attributeCache.removeAll()
    onCompletion?(success, message)
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
  private func fail(_ message: String) {
    guard completed>0 else {finish(message);return}
    let remaining=message.replacingOccurrences(of:"Aucun fichier n’a été envoyé.",with:"Aucun fichier restant n’a été envoyé.")
    finish("\(completed) fichier\(completed>1 ? "s" : "") déjà remis à Finovox. \(remaining)")
  }
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
  private func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    let node = AXNodeKey(element: e)
    if let cached = attributeCache[node]?[key] { return cached is NSNull ? nil : cached }
    let common = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
      kAXValueAttribute, kAXIdentifierAttribute, kAXChildrenAttribute]
    if common.contains(key) {
      var values: CFArray?
      if AXUIElementCopyMultipleAttributeValues(e, common as CFArray, [], &values) == .success,
        let results = values as? [AnyObject], results.count == common.count {
        for (attribute, value) in zip(common, results) {
          let isError = CFGetTypeID(value) == AXValueGetTypeID()
            && AXValueGetType(value as! AXValue) == .axError
          attributeCache[node, default: [:]][attribute] = isError ? NSNull() : value
        }
        return attributeCache[node]?[key].flatMap { $0 is NSNull ? nil : $0 }
      }
    }
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(e, key as CFString, &value)
    attributeCache[node, default: [:]][key] = status == .success ? value : NSNull()
    return status == .success ? value : nil
  }
  private func element(_ e: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attr(e, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }; return (value as! AXUIElement)
  }
  private func string(_ e: AXUIElement, _ key: String) -> String { (attr(e, key) as? String) ?? "" }
  private func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) }
  private func name(_ e: AXUIElement) -> String { let title = string(e, kAXTitleAttribute); return title.isEmpty ? string(e, kAXDescriptionAttribute) : title }
  private func descendants(_ e: AXUIElement, stoppingAtWebAreas: Bool = false,
    until stop: ((AXUIElement) -> Bool)? = nil) -> [AXUIElement] {
    var result: [AXUIElement] = []; var stack = [e]
    var visited = Set<AXNodeKey>()
    while let current = stack.popLast(), result.count < 6000 {
      guard visited.insert(AXNodeKey(element: current)).inserted else { continue }
      result.append(current)
      if stop?(current) == true { break }
      if stoppingAtWebAreas && role(current) == "AXWebArea" { continue }
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
  private func browserWindows(_ root: AXUIElement) -> [AXUIElement] {
    if let preferredChromeWindow {return [preferredChromeWindow]}
    var seen = Set<AXNodeKey>()
    return ([element(root, kAXFocusedWindowAttribute), preferredChromeWindow].compactMap { $0 }
      + windows(root)).filter { seen.insert(AXNodeKey(element:$0)).inserted }
  }
  private func finovoxContext(_ app: NSRunningApplication) -> (window: AXUIElement, web: AXUIElement)? {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let candidates = browserWindows(root)
    for window in candidates {
      if let web = activeFinovoxWebAreas(window).first {
        return (window, web)
      }
    }
    return nil
  }
  private func authenticatedFinovoxContext(_ app: NSRunningApplication) -> (window: AXUIElement, web: AXUIElement)? {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let candidates = browserWindows(root)
    for window in candidates {
      for web in activeFinovoxWebAreas(window) {
        if importButton(descendants(web, until:isImportButton)) != nil { return (window, web) }
      }
    }
    return nil
  }
  private func activeFinovoxWebAreas(_ window: AXUIElement) -> [AXUIElement] {
    let native=descendants(window,stoppingAtWebAreas:true)
    guard let address=native.first(where:isAddressField) else {return []}
    let raw=string(address,kAXValueAttribute).trimmingCharacters(in:.whitespacesAndNewlines)
    guard let active=URL(string:raw.contains("://") ? raw : "https://"+raw),
      active.scheme == "https", active.host == "app.finovox.com" else {return []}
    return native.filter {
      guard role($0) == "AXWebArea", isFinovox($0), let url=webURL($0) else {return false}
      // Chrome can retain accessibility objects for a background tab. A cached
      // upload button is usable only when its page matches the actual omnibox.
      return url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        == active.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
    }
  }
  private func focusAuthenticatedFinovoxTab(_ app: NSRunningApplication) -> Bool {
    guard let context = authenticatedFinovoxContext(app) else { return false }
    preferredChromeWindow = context.window
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
    if let context = finovoxContext(app),
      FinovoxImportPage.route(for:webURL(context.web)) != .other
        || webURL(context.web)?.path.hasSuffix("/preview") == true {
      preferredChromeWindow = context.window
      focus(app, window: context.window)
      return true
    }
    // Search per window so the exact Chrome window can be raised after its
    // Finovox tab is selected. This also works with several Chrome profiles.
    for window in browserWindows(root) {
      if let tab = descendants(window, stoppingAtWebAreas:true).first(where: {
        [kAXRadioButtonRole, "AXTab"].contains(role($0))
          && normalizedName($0).hasPrefix("finovox")
      }) {
        preferredChromeWindow = window
        pendingExistingTab = tab;clickedExistingTab=false
        focus(app, window: window)
        return true
      }
    }
    if let context = finovoxContext(app) {
      preferredChromeWindow = context.window
      focus(app, window:context.window)
      return true
    }
    return false
  }
  private func isViewerCloseButton(_ node: AXUIElement) -> Bool {
    role(node) == kAXButtonRole && ["fermer", "close"].contains(normalizedName(node))
  }
  private func webURL(_ web: AXUIElement) -> URL? {
    let raw = string(web, "AXURL").trimmingCharacters(in: .whitespacesAndNewlines)
    let value = attr(web, "AXURL")
    let url = (value as? URL) ?? (value as? NSURL).map { $0 as URL }
      ?? URL(string: raw.contains("://") ? raw : "https://" + raw)
    return url
  }
  private func isFinovox(_ web: AXUIElement) -> Bool {
    let url = webURL(web)
    return url?.scheme == "https" && url?.host == "app.finovox.com"
  }
  private func isAddressField(_ field: AXUIElement) -> Bool {
    guard [kAXTextFieldRole, "AXComboBox"].contains(role(field)) else { return false }
    let label = normalizedName(field)
    return label.contains("adresse") || label.contains("address")
      || string(field, kAXIdentifierAttribute).lowercased().contains("omnibox")
  }
  private func normalizedName(_ element: AXUIElement) -> String {
    name(element).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }
  private func importButton(_ nodes: [AXUIElement]) -> AXUIElement? {
    nodes.first(where:isImportButton)
  }
  private func isImportButton(_ node: AXUIElement) -> Bool {
    role(node) == kAXButtonRole && ["importer des documents", "import documents", "upload documents"]
      .contains(where: normalizedName(node).contains)
  }
  private func openPanel(_ root: AXUIElement) -> AXUIElement? {
    // Native dialogs may not be in the browser's window list. Follow the
    // focused field's ancestors first, before traversing a large web document.
    var ancestor = element(root, kAXFocusedUIElementAttribute)
    for _ in 0..<16 {
      guard let current = ancestor else { break }
      if string(current, kAXIdentifierAttribute) == "open-panel" { return current }
      if ["AXSheet", "AXDialog"].contains(role(current)), isNativePicker(current) { return current }
      ancestor = element(current, kAXParentAttribute)
    }
    // Never send Go to Folder to an unrelated Chrome window: there it means
    // Find Previous. A browser window containing a hidden picker is not itself
    // a focused native file chooser.
    return nil
  }
  private func isNativePicker(_ node: AXUIElement) -> Bool {
    let ids = Set(descendants(node,stoppingAtWebAreas:true).map { string($0,kAXIdentifierAttribute) })
    return ids.contains("OKButton") && ids.contains("CancelButton")
  }
  private func pickerBelongsToImportWindow(_ picker: AXUIElement) -> Bool {
    guard let expected=preferredChromeWindow else {return false}
    var node: AXUIElement? = picker
    for _ in 0..<20 {
      guard let current=node else {break}
      if CFEqual(current,expected) {return true}
      node=element(current,kAXParentAttribute)
    }
    return false
  }
  private func clickCenter(_ element: AXUIElement) -> Bool {
    guard let positionValue = attr(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
      let sizeValue = attr(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return false }
    var position = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return false }
    guard size.width>2, size.height>2 else {return false}
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

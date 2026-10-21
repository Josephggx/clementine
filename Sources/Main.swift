import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let state = AppState()
  var window: NSWindow!
  var status: NSStatusItem!
  var wheel: WheelController!
  var modules: [UUID: ModuleWindowController] = [:]
  var floats: [FloatController] = []
  var appearanceObserver: NSObjectProtocol?
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Clémentine behaves as a menu-bar utility while its main window is
    // closed. `show()` restores the regular Dock presence when needed.
    NSApp.setActivationPolicy(.accessory)
    state.applyAppearance()
    appearanceObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil,
      queue: .main
    ) { [weak self] _ in
      guard self?.state.appearance == "system" else { return }
      self?.state.applyAppearance()
    }
    let view = MainView(state: state)
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1136, height: 790),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = "Clémentine"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.acceptsMouseMovedEvents = true
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: view)
    window.center()
    window.setFrameAutosaveName("ClementineMain")
    state.showModule = { [weak self] tool, files in
      guard let self else { return }
      guard !files.isEmpty else { return }
      guard files.count == 1 || !["strip", "metadata"].contains(tool) else {
        self.state.error = "Sélectionnez un seul fichier pour consulter ses métadonnées."
        return
      }
      if ["mute", "extract", "mergepdf", "archive"].contains(tool),
        (tool == "mute" || tool == "extract" || tool == "archive" || (tool == "mergepdf" && Family.of(files[0]) == .image)) {
        let previous = self.state.jobs.first?.id
        self.state.submit(tool, files:files)
        if let job = self.state.jobs.first, job.id != previous { self.wheel.showProgress(job) }
        return
      }
      let module = ModuleWindowController(tool:tool, files:files, defaults:self.state.options, reveal:self.state.reveal)
      self.modules[module.session.id] = module
      module.onClose = { [weak self, weak module] in if let id = module?.session.id { self?.modules.removeValue(forKey:id) } }
      module.show()
    }
    state.showWindow = { [weak self] in self?.show() }
    state.showFloat = { [weak self] urls in self?.float(urls) }
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.image = ClementineMarkImage.statusItem()
    let menu = NSMenu()
    menu.addItem(withTitle: "Ouvrir l’atelier", action: #selector(openMain), keyEquivalent: "o")
      .target = self
    menu.addItem(
      withTitle: "Ajouter des fichiers…", action: #selector(addFiles), keyEquivalent: "n"
    ).target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Réglages…", action: #selector(settings), keyEquivalent: ",").target =
      self
    menu.addItem(withTitle: "Rechercher des mises à jour…",
      action: #selector(AppUpdates.checkForUpdates(_:)), keyEquivalent: "")
      .target = AppUpdates.shared
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quitter Clémentine", action: #selector(quit), keyEquivalent: "q")
      .target = self
    status.menu = menu
    let mainMenu = NSMenu()
    let appMenu = NSMenuItem()
    let submenu = NSMenu()
    submenu.addItem(
      withTitle: "À propos de Clémentine", action: #selector(openMain), keyEquivalent: ""
    ).target = self
    let wheelPreview = submenu.addItem(withTitle: "Aperçu de la roue…", action: #selector(demoWheel), keyEquivalent: "r")
    wheelPreview.keyEquivalentModifierMask = [.command, .shift]
    wheelPreview.target = self
    submenu.addItem(withTitle: "Rechercher des mises à jour…",
      action: #selector(AppUpdates.checkForUpdates(_:)), keyEquivalent: "")
      .target = AppUpdates.shared
    submenu.addItem(withTitle: "Quitter Clémentine", action: #selector(quit), keyEquivalent: "q")
      .target = self
    appMenu.submenu = submenu
    mainMenu.addItem(appMenu)
    let editItem = NSMenuItem()
    editItem.title = "Édition"
    let edit = NSMenu(title: "Édition")
    edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu
    wheel = WheelController(state: state)
    wheel.start()
    AppUpdates.shared.start(isBusy: { [weak self] in
      guard let self else { return false }
      return self.state.running || self.modules.values.contains { $0.session.busy }
    },
      isOnboarding: { [weak self] in self?.state.showingOnboarding ?? false })
    DispatchQueue.main.async { [weak self] in self?.state.registerLaunchAtLoginIfNeeded() }
    // A document-open launch must stay in the Finder's current Space. The
    // files are queued in the Atelier, and the main window is shown only for
    // a normal app launch or an explicit request from the Dock/menu bar.
    let isDefaultLaunch =
      (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
    if isDefaultLaunch { show() }
    #if CLEMENTINE_INTERNAL_TESTS
    if let root = Bundle.main.object(forInfoDictionaryKey: "ClementineValidationRoot") as? String {
      try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
      setenv("CLEMENTINE_TEST_DIR", root, 1)
      freopen(root + "/tests.log", "w", stdout)
      freopen(root + "/tests-errors.log", "w", stderr)
      DispatchQueue.global(qos: .userInitiated).async { SelfTests.run() }
    }
    #endif
    if CommandLine.arguments.contains("--native-self-test") {
      var root: URL?
      if let index = CommandLine.arguments.firstIndex(of: "--native-test-dir"),
        CommandLine.arguments.count > index + 1
      {
        root = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
      }
      state.verifyNativeExports(root: root)
    }
    if let i = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > i + 1 {
      state.add([URL(fileURLWithPath: CommandLine.arguments[i + 1])])
    }
  }
  func show() {
    if state.page == "permissions" || (state.showingOnboarding && state.onboardingPage == 4) {
      PermissionCenter.shared.resumeMonitoring()
    }
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func openMain() { show() }
  @objc func addFiles() {
    show()
    state.browse()
  }
  @objc func settings() {
    state.page = "settings"
    show()
  }
  @objc func demoWheel() {
    if state.files.isEmpty { state.browse() }
    if !state.files.isEmpty { wheel.show(state.files, mode: "formats") }
  }
  @objc func quit() {
    if state.running {
      let alert = NSAlert()
      alert.messageText = "Des traitements sont en cours"
      alert.informativeText = "Quitter interrompra les opérations. Les originaux sont conservés."
      alert.addButton(withTitle: "Continuer les traitements")
      alert.addButton(withTitle: "Quitter")
      if alert.runModal() == .alertFirstButtonReturn { return }
    }
    NSApp.terminate(nil)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    // A drag panel can cause an incidental reopen event. It must never bring
    // the main window (and its Space) forward while the wheel is visible.
    guard wheel?.panel == nil else { return false }
    show()
    return true
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    state.add(filenames.map { URL(fileURLWithPath: $0) })
    sender.reply(toOpenOrPrint: .success)
  }
  func applicationWillTerminate(_ notification: Notification) {
    state.persist()
    wheel?.stop()
    PermissionCenter.shared.suspendMonitoring()
  }
  func windowWillClose(_ notification: Notification) {
    PermissionCenter.shared.suspendMonitoring()
    state.persist()
    DispatchQueue.main.async {
      guard !self.window.isVisible else { return }
      NSApp.setActivationPolicy(.accessory)
    }
  }
  func float(_ urls: [URL]) {
    guard !urls.isEmpty else {return}
    if state.floatBehavior == "append",let last=floats.last(where:{$0.panel.isVisible}) {
      last.add(urls);return
    }
    let controller=FloatController(files:urls,state:state)
    controller.onClose={ [weak self,weak controller] in
      guard let controller else{return}
      self?.floats.removeAll{$0 === controller}
    }
    floats.append(controller);controller.show()
  }

}
@main struct Clementine {
  static func main() {
    #if CLEMENTINE_INTERNAL_TESTS
    if CommandLine.arguments.contains("--conversion-self-test") {
      ConversionParityTests.run()
      return
    }
    if CommandLine.arguments.contains("--self-test") {
      SelfTests.run()
      return
    }
    #endif
    let app = NSApplication.shared
    if ApplicationInstallation.handleDiskImageLaunch() { return }
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

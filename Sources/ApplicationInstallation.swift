import AppKit

enum ApplicationInstallation {
  static let applicationName = "Clémentine.app"

  static func needsInstallationHandoff(source: URL, readOnlyVolume: Bool) -> Bool {
    let path = source.standardizedFileURL.path
    return path.contains("/AppTranslocation/") || (path.hasPrefix("/Volumes/") && readOnlyVolume)
  }

  /// Never replace an installed app from a disk-image launch. Finder and
  /// Sparkle own upgrades; this path only installs a first copy or opens it.
  static func copyFirstInstallation(from source: URL, to destination: URL) throws {
    let manager = FileManager.default
    guard !manager.fileExists(atPath: destination.path) else { return }
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".Clementine-install-\(UUID().uuidString).app", isDirectory: true)
    defer { try? manager.removeItem(at: temporary) }
    try manager.copyItem(at: source, to: temporary)
    guard let bundle = Bundle(url: temporary),
      bundle.bundleIdentifier == Bundle(url: source)?.bundleIdentifier,
      let executable = bundle.executableURL,
      manager.isExecutableFile(atPath: executable.path) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    // moveItem fails safely if another installation has appeared meanwhile.
    try manager.moveItem(at: temporary, to: destination)
  }

  /// Called before creating AppState, login items, wheels or permission probes.
  static func handleDiskImageLaunch() -> Bool {
    let source = Bundle.main.bundleURL
    let readOnly = (try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
    guard needsInstallationHandoff(source: source, readOnlyVolume: readOnly) else { return false }
    let destination = URL(fileURLWithPath: "/Applications", isDirectory: true)
      .appendingPathComponent(applicationName, isDirectory: true)
    NSApp.setActivationPolicy(.regular)

    if FileManager.default.fileExists(atPath: destination.path) {
      openInstalledApplication(destination)
    } else {
      let alert = NSAlert()
      alert.icon = NSImage(named: NSImage.applicationIconName)
      alert.messageText = "Installer Clémentine"
      alert.informativeText = "Clémentine doit être placée dans Applications pour conserver vos autorisations et recevoir ses mises à jour."
      alert.addButton(withTitle: "Installer et ouvrir")
      alert.addButton(withTitle: "Annuler")
      NSApp.activate(ignoringOtherApps: true)
      guard alert.runModal() == .alertFirstButtonReturn else { return true }

      let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 132),
        styleMask: [.titled], backing: .buffered, defer: false)
      progress.title = "Installation de Clémentine"
      progress.isReleasedWhenClosed = false
      let label = NSTextField(labelWithString: "Copie dans Applications…")
      label.font = .systemFont(ofSize: 15, weight: .medium)
      label.frame = NSRect(x: 28, y: 76, width: 334, height: 22)
      let spinner = NSProgressIndicator(frame: NSRect(x: 28, y: 38, width: 334, height: 10))
      spinner.style = .bar
      spinner.isIndeterminate = true
      spinner.startAnimation(nil)
      progress.contentView?.addSubview(label)
      progress.contentView?.addSubview(spinner)
      progress.center()
      progress.makeKeyAndOrderFront(nil)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try copyFirstInstallation(from: source, to: destination)
          DispatchQueue.main.async {
            progress.close()
            openInstalledApplication(destination)
          }
        } catch {
          DispatchQueue.main.async {
            progress.close()
            showInstallationError(error, destination: destination)
          }
        }
      }
    }
    NSApp.run()
    return true
  }

  private static func openInstalledApplication(_ destination: URL) {
    guard let installed = Bundle(url: destination),
      installed.bundleIdentifier == Bundle.main.bundleIdentifier,
      let executable = installed.executableURL,
      FileManager.default.isExecutableFile(atPath: executable.path) else {
      showInstallationError(CocoaError(.fileReadCorruptFile), destination: destination)
      return
    }
    if let running = NSWorkspace.shared.runningApplications.first(where: {
      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
      $0.bundleURL?.standardizedFileURL == destination.standardizedFileURL
    }) {
      running.activate(options: [])
      DispatchQueue.main.async { NSApp.terminate(nil) }
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    // The disk-image process has the same bundle ID. Explicitly launch the
    // installed executable rather than accidentally reactivating this one.
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
      DispatchQueue.main.async {
        if let error { showInstallationError(error, destination: destination) }
        else { NSApp.terminate(nil) }
      }
    }
  }

  private static func showInstallationError(_ error: Error, destination: URL) {
    let alert = NSAlert()
    alert.messageText = "Clémentine n’a pas pu être ouverte depuis Applications"
    alert.informativeText = "Glissez Clémentine dans Applications, attendez la fin de la copie, puis ouvrez-la depuis ce dossier.\n\n" + error.localizedDescription
    alert.addButton(withTitle: "Afficher Applications")
    alert.addButton(withTitle: "Fermer")
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(destination.deletingLastPathComponent())
    }
    // This can run before the temporary installer event loop has started.
    DispatchQueue.main.async { NSApp.terminate(nil) }
  }
}

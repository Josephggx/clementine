import AppKit
import Combine
import SwiftUI
import Sparkle

/// The test chooses the same actions as the native Install buttons. The real
/// Sparkle downloader, delta patcher, installer and relaunch helper still run.
final class AutomaticUpdateDriver: NSObject, SPUUserDriver {
  private func trace(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
  }
  func show(_ request: SPUUpdatePermissionRequest,
    reply: @escaping (SUUpdatePermissionResponse) -> Void) {
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
  }
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void) {
    if CommandLine.arguments.contains("--simulate-stale-process"),
      let app = NSApp.delegate as? UpdateCheckApp, let updater = app.automaticUpdater {
      reply(.dismiss)
      AppUpdates.shared.updater(updater, willInstallUpdate: appcastItem)
      app.simulateInstalledFilesWithOldProcessStillRunning()
      return
    }
    trace("found update"); reply(.install)
  }
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    trace("no update"); acknowledgement()
  }
  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    trace("FAIL updater error: \(error)"); acknowledgement()
  }
  func showDownloadInitiated(cancellation: @escaping () -> Void) { trace("download started") }
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    trace("download bytes=\(expectedContentLength)")
  }
  func showDownloadDidReceiveData(ofLength length: UInt64) {}
  func showDownloadDidStartExtractingUpdate() { trace("extracting") }
  func showExtractionReceivedProgress(_ progress: Double) {}
  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    trace("install and relaunch requested"); reply(.install)
  }
  func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void) {
    trace("installing; app terminated=\(applicationTerminated)")
  }
  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    trace("installation finished; relaunched=\(relaunched)"); acknowledgement()
  }
  func dismissUpdateInstallation() { trace("update dismissed") }
}

final class UpdateCheckApp: NSObject, NSApplicationDelegate {
  let state = AppState()
  var window: NSWindow!
  var observations = Set<AnyCancellable>()
  var quitRequests = 0
  var automaticUpdater: SPUUpdater?
  var automaticDriver: AutomaticUpdateDriver?
  let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestRoot") as! String)

  func record(_ text: String) {
    let line = "\(AppUpdates.installedVersion): \(text)\n"
    let path = root.appendingPathComponent("trace.log")
    if !FileManager.default.fileExists(atPath: path.path) {
      FileManager.default.createFile(atPath: path.path, contents: nil)
    }
    let file = try! FileHandle(forWritingTo: path)
    file.seekToEndOfFile(); file.write(Data(line.utf8)); try! file.close()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    state.showingOnboarding = false
    state.appearance = "dark"; state.applyAppearance()
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1136, height: 790),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "Vérification des mises à jour Clémentine"
    window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
    window.contentView = NSHostingView(rootView: MainView(state: state))
    window.center(); window.makeKeyAndOrderFront(nil)
    record("launch; CTA hidden=\(AppUpdates.shared.availableVersion == nil)")
    AppUpdates.shared.$availableVersion.dropFirst().sink { [weak self] version in
      self?.record("available=\(version ?? "none")")
    }.store(in: &observations)
    if Bundle.main.object(forInfoDictionaryKey: "TestAutomaticUpdate") as? Bool == true
      && AppUpdates.installedVersion == "1.0.0" {
      let driver = AutomaticUpdateDriver()
      automaticDriver = driver
      let updater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main,
        userDriver: driver, delegate: AppUpdates.shared)
      automaticUpdater = updater
      do { try updater.start(); updater.checkForUpdates() }
      catch { record("FAIL: \(error)") }
    } else {
      AppUpdates.shared.start(isBusy: { false }, isOnboarding: { false })
    }
    if AppUpdates.installedVersion == (Bundle.main.object(forInfoDictionaryKey:"TestExpectedVersion") as? String ?? "1.0.1") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
        precondition(AppUpdates.shared.availableVersion == nil)
        precondition(AppUpdates.shared.installationWarning == nil)
        record("PASS: relaunch on latest version; CTA hidden")
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    quitRequests += 1
    record("quit-request=\(quitRequests)")
    if (CommandLine.arguments.contains("--reject-first-quit") ||
        Bundle.main.object(forInfoDictionaryKey: "TestAutomaticUpdate") as? Bool == true)
      && quitRequests == 1 {
      record("Simulated missed first macOS termination request")
      return .terminateCancel
    }
    return .terminateNow
  }

  func simulateInstalledFilesWithOldProcessStillRunning() {
    let installed = Bundle.main.bundleURL
    let source = root.appendingPathComponent("release/Clémentine.app")
    DispatchQueue.global(qos: .userInitiated).async {
      let stage = self.root.appendingPathComponent("stale-process-new.app")
      let backup = self.root.appendingPathComponent("stale-process-old.app")
      let manager = FileManager.default
      do {
        if manager.fileExists(atPath: stage.path) { try manager.removeItem(at: stage) }
        if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
        try manager.copyItem(at: source, to: stage)
        try manager.moveItem(at: installed, to: backup)
        try manager.moveItem(at: stage, to: installed)
        self.record("Simulated new files installed while old process remains alive")
      } catch { self.record("FAIL stale process fixture: \(error)") }
    }
  }
}

@main struct UpdateCheckMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = UpdateCheckApp()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

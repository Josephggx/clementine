import AppKit
import Combine
import SwiftUI
import OSLog
#if canImport(Sparkle)
import Sparkle
#endif

/// Sparkle owns the update check schedule, downloads, signature verification,
/// replacement and relaunch. Scheduled checks only expose our sidebar CTA.
final class AppUpdates: NSObject, ObservableObject {
  static let shared = AppUpdates()
  @Published private(set) var availableVersion: String?
  @Published private(set) var canCheckForUpdates = false
  private var isBusy: () -> Bool = { false }
  private var isOnboarding: () -> Bool = { false }
  private var started = false
  private var installationTimer: Timer?
  private var terminationTimer: Timer?
  private var installedCopyTimer: Timer?
  private let receipt = UpdateInstallationReceipt()
  private let logger = Logger(subsystem: "io.joseph.clementine.updates", category: "installation")
  private var activationObserver: NSObjectProtocol?
  private var isRestartingInstalledCopy = false
  @Published private(set) var needsRelaunch = false
  @Published private(set) var installationWarning: String?
  private let runningBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  #if canImport(Sparkle)
  private lazy var controller = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
  private var checkObservation: NSKeyValueObservation?
  #endif

  static var installedVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  }

  func start(isBusy: @escaping () -> Bool, isOnboarding: @escaping () -> Bool) {
    guard !started else { return }
    started = true
    self.isBusy = isBusy
    self.isOnboarding = isOnboarding
    switch receipt.verify(runningBuild: runningBuild) {
    case .installed(let version):
      logger.info("Installation confirmed after launch: \(version, privacy: .public)")
    case .interrupted(let version):
      installationWarning = "La mise à jour vers \(version) n’a pas été terminée."
      logger.error("Installation interrupted; current build: \(self.runningBuild, privacy: .public)")
    case .none: break
    }
    refreshInstalledCopy()
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
    ) { [weak self] _ in self?.refreshInstalledCopy() }
    #if canImport(Sparkle)
    checkObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
      [weak self] updater, _ in
      let enabled = updater.canCheckForUpdates
      DispatchQueue.main.async { self?.canCheckForUpdates = enabled }
    }
    controller.startUpdater()
    if controller.updater.automaticallyChecksForUpdates {
      controller.updater.checkForUpdatesInBackground()
    }
    #endif
  }

  @objc func checkForUpdates(_ sender: Any? = nil) {
    refreshInstalledCopy()
    if needsRelaunch {
      relaunchInstalledCopy()
      return
    }
    #if canImport(Sparkle)
    controller.checkForUpdates(sender)
    #endif
  }

  private func refreshInstalledCopy() {
    // Read the plist directly: Bundle.main deliberately caches the version of
    // this process even if an installer has already replaced the files.
    guard let data = try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")),
      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
      let diskBuild = info["CFBundleVersion"] as? String else { return }
    needsRelaunch = diskBuild.compare(runningBuild, options: .numeric) == .orderedDescending
  }

  private func relaunchInstalledCopy(asking: Bool = true) {
    guard !isBusy(), !isRestartingInstalledCopy else { return }
    if asking {
      let alert = NSAlert()
      alert.messageText = tr("La nouvelle version est déjà installée")
      alert.informativeText = tr("Relancez Clémentine pour l’utiliser. Aucun nouveau téléchargement n’est nécessaire.")
      alert.addButton(withTitle: tr("Relancer Clémentine"))
      alert.addButton(withTitle: tr("Plus tard"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    isRestartingInstalledCopy = true
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
      DispatchQueue.main.async {
        if let error {
          self?.isRestartingInstalledCopy = false
          self?.installedCopyTimer?.invalidate()
          self?.installedCopyTimer = nil
          self?.installationWarning = "La nouvelle version est installée. Relancez Clémentine pour l’utiliser."
          if asking { NSAlert(error: error).runModal() }
        } else { self?.finishInstalledCopyRelaunch() }
      }
    }
  }

  private func finishInstalledCopyRelaunch() {
    terminationTimer?.invalidate()
    var retries = 0
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      guard !self.isBusy() else { return }
      retries += 1
      if retries > 3 {
        timer.invalidate()
        self.installationWarning = "La nouvelle version est ouverte. Fermez l’ancienne fenêtre de Clémentine."
        return
      }
      NSApp.terminate(nil)
    }
    terminationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    NSApp.terminate(nil)
  }

  deinit {
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    terminationTimer?.invalidate()
    installedCopyTimer?.invalidate()
    installationTimer?.invalidate()
  }
}

#if canImport(Sparkle)
extension AppUpdates: SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
  var supportsGentleScheduledUpdateReminders: Bool { true }

  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
  ) -> Bool { false }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
  ) {
    availableVersion = update.displayVersionString
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    availableVersion = item.displayVersionString
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    availableVersion = nil
  }

  func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
    receipt.begin(build: item.versionString, version: item.displayVersionString)
    installationWarning = nil
    logger.info("Installing build \(item.versionString, privacy: .public)")
    installedCopyTimer?.invalidate()
    let deadline = Date().addingTimeInterval(15 * 60)
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      if Date() > deadline {
        timer.invalidate()
        self.installedCopyTimer = nil
        self.installationWarning = "La mise à jour n’a pas été terminée. Réessayez depuis Réglages."
        return
      }
      self.refreshInstalledCopy()
      if self.needsRelaunch && !self.isBusy() {
        self.logger.notice("New build is on disk; recovering a stale application process")
        self.relaunchInstalledCopy(asking: false)
      }
    }
    installedCopyTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    terminationTimer?.invalidate()
    // Sparkle first asks its helper to send a normal macOS quit event. A
    // second normal termination initiated by our process handles the case
    // where that first external request is ignored. Never force-kill.
    let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
      guard let self, !self.isBusy() else { return }
      self.terminationTimer?.invalidate()
      self.terminationTimer = nil
      self.logger.notice("Completing the requested update relaunch")
      NSApp.terminate(nil)
    }
    terminationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    terminationTimer?.invalidate()
    terminationTimer = nil
    installedCopyTimer?.invalidate()
    installedCopyTimer = nil
    let error = error as NSError
    guard !(error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue) else { return }
    receipt.cancel()
    logger.error("Update aborted: \(error.domain, privacy: .public) / \(error.code)")
    if error.domain == SUSparkleErrorDomain && error.code != SUError.installationCanceledError.rawValue
      && error.code != SUError.installationAuthorizeLaterError.rawValue {
      installationWarning = "La mise à jour n’a pas abouti. Votre version actuelle est conservée."
    }
  }

  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    terminationTimer?.invalidate()
    terminationTimer = nil
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    if isBusy() || (isOnboarding() && updateCheck != .updates) {
      throw NSError(domain: "io.joseph.clementine.updates", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "La vérification reprendra après l’opération en cours."
      ])
    }
  }

  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    guard isBusy() else { return false }
    installationTimer?.invalidate()
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
      guard let self, !self.isBusy() else { return }
      timer.invalidate()
      self.installationTimer = nil
      installHandler()
    }
    installationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    return true
  }
}
#endif

private final class UpdateHover: ObservableObject {
  @Published var active = false
}

struct UpdateSidebarButton: View {
  @ObservedObject var updates = AppUpdates.shared
  @StateObject private var hover = UpdateHover()
  var body: some View {
    if updates.availableVersion != nil || updates.needsRelaunch {
      Button { updates.checkForUpdates() } label: {
        Label(trString(updates.needsRelaunch ? "Relancer Clémentine" : "Mettre à jour"),
          systemImage: updates.needsRelaunch ? "arrow.clockwise" : "arrow.down.to.line")
          .font(.system(size: 13, weight: .semibold))
          .padding(11)
          .foregroundStyle(citrus)
          .background(citrus.opacity(hover.active ? 0.20 : 0.12),
            in: RoundedRectangle(cornerRadius: 9))
      }
      .buttonStyle(StableInteractionButtonStyle())
      .disabled(!updates.canCheckForUpdates && !updates.needsRelaunch)
      .help(trString(updates.needsRelaunch ? "Ouvrir la version déjà installée" : "Installer Clémentine \(updates.availableVersion ?? "")"))
      .onHover { hover.active = $0 }
      .animation(.easeInOut(duration: 0.18), value: hover.active)
    }
  }
}

struct AppVersionLabel: View {
  @ObservedObject var updates = AppUpdates.shared
  @StateObject private var hover = UpdateHover()
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
    HStack(spacing: 6) {
      ClementineMark(size: 13).saturation(0).opacity(0.6)
      Text(tr("Clémentine version \(AppUpdates.installedVersion)"))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Button { updates.checkForUpdates() } label: {
        Text(tr("Chercher une mise à jour"))
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6).padding(.vertical, 4)
          .background(Color.primary.opacity(hover.active ? 0.065 : 0),
            in: RoundedRectangle(cornerRadius: 5))
      }
      .buttonStyle(StableInteractionButtonStyle())
      .disabled(!updates.canCheckForUpdates && !updates.needsRelaunch)
      .onHover { hover.active = $0 }
      .animation(.easeInOut(duration: 0.18), value: hover.active)
    }
    if let warning = updates.installationWarning {
      Text(trString(warning)).font(.system(size: 11)).foregroundStyle(.secondary)
    }
    }
    .padding(.top, 8)
  }
}

import AppKit
import Combine
import SwiftUI
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
    #if canImport(Sparkle)
    controller.checkForUpdates(sender)
    #endif
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
    if let version = updates.availableVersion {
      Button { updates.checkForUpdates() } label: {
        Label("Mettre à jour", systemImage: "arrow.down.to.line")
          .font(.system(size: 13, weight: .semibold))
          .padding(11)
          .foregroundStyle(citrus)
          .background(citrus.opacity(hover.active ? 0.20 : 0.12),
            in: RoundedRectangle(cornerRadius: 9))
      }
      .buttonStyle(StableInteractionButtonStyle())
      .disabled(!updates.canCheckForUpdates)
      .help("Installer Clémentine \(version)")
      .onHover { hover.active = $0 }
      .animation(.easeInOut(duration: 0.18), value: hover.active)
    }
  }
}

struct AppVersionLabel: View {
  @ObservedObject var updates = AppUpdates.shared
  @StateObject private var hover = UpdateHover()
  var body: some View {
    HStack(spacing: 6) {
      ClementineMark(size: 13).saturation(0).opacity(0.6)
      Text("Clémentine version \(AppUpdates.installedVersion)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Button { updates.checkForUpdates() } label: {
        Text("Chercher une mise à jour")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6).padding(.vertical, 4)
          .background(Color.primary.opacity(hover.active ? 0.065 : 0),
            in: RoundedRectangle(cornerRadius: 5))
      }
      .buttonStyle(StableInteractionButtonStyle())
      .disabled(!updates.canCheckForUpdates)
      .onHover { hover.active = $0 }
      .animation(.easeInOut(duration: 0.18), value: hover.active)
    }
    .padding(.top, 8)
  }
}

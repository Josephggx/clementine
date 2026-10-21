import AppKit
import ApplicationServices
import CoreServices
import OSLog
import SwiftUI

enum ClementinePermission: String, CaseIterable, Identifiable {
  case accessibility, pages, numbers, keynote

  var id: String { rawValue }
  static func automation(bundleID: String) -> Self? {
    switch bundleID {
    case "com.apple.Pages", "com.apple.iWork.Pages": return .pages
    case "com.apple.Numbers", "com.apple.iWork.Numbers": return .numbers
    case "com.apple.Keynote", "com.apple.iWork.Keynote": return .keynote
    default: return nil
    }
  }
  var title: String {
    switch self {
    case .accessibility: return tr("Accessibilité")
    case .pages: return tr("Pages")
    case .numbers: return tr("Numbers")
    case .keynote: return tr("Keynote")
    }
  }
  var icon: String {
    switch self {
    case .accessibility: return "accessibility"
    case .pages: return "doc.richtext"
    case .numbers: return "tablecells"
    case .keynote: return "rectangle.on.rectangle.angled"
    }
  }
  var detail: String {
    switch self {
    case .accessibility:
      return tr("Permet d’afficher les roues pendant un glisser-déposer et de piloter le bouton d’import de Chrome pour Finovox.")
    case .pages:
      return tr("Permet de créer et d’exporter des documents Pages lorsque vous choisissez un format Apple natif.")
    case .numbers:
      return tr("Permet de créer, lire et exporter des tableurs Numbers, notamment une feuille CSV par onglet.")
    case .keynote:
      return tr("Permet de créer et d’exporter des présentations Keynote lorsque vous choisissez un format Apple natif.")
    }
  }
}

enum ClementinePermissionStatus: Equatable {
  case notRequested, granted, denied, unavailable

  var label: String {
    switch self {
    case .notRequested: return tr("À autoriser")
    case .granted: return tr("Accordée")
    case .denied: return tr("Non accordée")
    case .unavailable: return tr("App non installée")
    }
  }
  var icon: String {
    switch self {
    case .notRequested: return "exclamationmark.circle.fill"
    case .granted: return "checkmark.circle.fill"
    case .denied: return "xmark.circle.fill"
    case .unavailable: return "minus.circle.fill"
    }
  }
  var color: Color {
    switch self {
    case .notRequested: return citrus
    case .granted: return Color(red: 0.24, green: 0.67, blue: 0.39)
    case .denied: return Color(red: 0.88, green: 0.31, blue: 0.25)
    case .unavailable: return .secondary
    }
  }
}

/// Injectable system boundary for first-run tests; production uses macOS below.
struct PermissionEnvironment {
  var accessibilityGranted: () -> Bool
  var requestAccessibility: () -> Void
  var installedApplication: (ClementinePermission) -> (url: URL, bundleID: String)?
  var requestAutomation: (ClementinePermission, @escaping (OSStatus) -> Void) -> Void
}

final class PermissionCenter: ObservableObject {
  static let shared = PermissionCenter()
  static let onboardingKey = "didRequestSystemPermissions20261019v3"
  static var needsOnboarding: Bool { !UserDefaults.standard.bool(forKey: onboardingKey) }

  @Published private(set) var revision = 0
  @Published private(set) var isRequestingAll = false
  @Published private var accessibilityGranted = AXIsProcessTrusted()
  @Published private var automationStatuses: [ClementinePermission: ClementinePermissionStatus] = [:]
  private var monitor: Timer?
  private var activationObserver: NSObjectProtocol?
  private var windowActivationObserver: NSObjectProtocol?
  private var targetActivationObserver: NSObjectProtocol?
  private var probesInFlight = Set<ClementinePermission>()
  private(set) var monitoring = false
  private var monitoringOwners = Set<UUID>()
  private var lastAutomationProbe = Date.distantPast
  private var requestGeneration = UUID()
  private var requestCompletion: (() -> Void)?
  @Published private(set) var automationIssues: [ClementinePermission: String] = [:]
  private var timedOutRequests: [ClementinePermission: Int] = [:]
  private var requestDeadlines: [ClementinePermission: DispatchWorkItem] = [:]
  private var requestLeases: [ClementinePermission: PermissionApplicationLeases] = [:]
  private let environment: PermissionEnvironment?
  private let requestTimeout: TimeInterval
  private var monitorLaunches = Set<ClementinePermission>()
  private var monitorPreexistingApps = Set<ClementinePermission>()
  private var applicationLeases = PermissionApplicationLeases()
  private var activatedProcessIdentifiers = Set<pid_t>()
  private var monitorProbeAttempts: [ClementinePermission: Int] = [:]
  private let defaults: UserDefaults
  private let recoveryOverride: ((ClementinePermission) -> Void)?
  private var automationEpochs: [ClementinePermission: Int] = [:]
  private var automationRequests: [ClementinePermission: [() -> Void]] = [:]
  private var workflowRecoveries = Set<ClementinePermission>()
  private var workflowObserver: NSObjectProtocol?
  private var workflowUseObserver: NSObjectProtocol?
  private let accessibilityRequestKey = "didRequestAccessibility20261019"
  private let wouldRequireConsent: OSStatus = -1744
  private let eventNotPermitted: OSStatus = -1743
  private let processNotFound: OSStatus = -600
  private let logger = Logger(subsystem: "io.joseph.clementine.permissions", category: "automation")
  private var lastPassiveResults: [ClementinePermission: OSStatus] = [:]

  init(defaults: UserDefaults = .standard,
    recovery: ((ClementinePermission) -> Void)? = nil,
    environment: PermissionEnvironment? = nil, requestTimeout: TimeInterval = 45) {
    self.defaults = defaults
    self.environment = environment
    self.requestTimeout = requestTimeout
    self.accessibilityGranted = environment?.accessibilityGranted() ?? AXIsProcessTrusted()
    recoveryOverride = recovery
    for permission in [ClementinePermission.pages, .numbers, .keynote] {
      switch defaults.string(forKey: "permissionStatus.\(permission.id)") {
      case "granted": automationStatuses[permission] = .granted
      case "denied": automationStatuses[permission] = .denied
      default: break
      }
    }
    workflowObserver = NotificationCenter.default.addObserver(
      forName: NativeOfficeScript.permissionResult, object: nil, queue: .main
    ) { [weak self] notification in
      guard let result = notification.object as? NativeOfficePermissionResult else { return }
      self?.recordWorkflowResult(bundleID: result.bundleID, result: result.result)
    }
    workflowUseObserver = NotificationCenter.default.addObserver(
      forName: NativeOfficeScript.willUseApplication, object: nil, queue: .main
    ) { [weak self] notification in
      guard let id = notification.object as? String else { return }
      self?.applicationLeases.protect(bundleID: id)
    }
    targetActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        let id = app.bundleIdentifier else { return }
      self?.activatedProcessIdentifiers.insert(app.processIdentifier)
      self?.applicationLeases.protect(bundleID: id)
      if id == Bundle.main.bundleIdentifier { self?.recheckAfterActivation() }
    }
  }

  deinit {
    if let workflowObserver { NotificationCenter.default.removeObserver(workflowObserver) }
    if let workflowUseObserver { NotificationCenter.default.removeObserver(workflowUseObserver) }
    if let targetActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(targetActivationObserver) }
    if let windowActivationObserver { NotificationCenter.default.removeObserver(windowActivationObserver) }
  }

  var allRequiredGranted: Bool {
    ClementinePermission.allCases.allSatisfy {
      let value = status($0)
      return value == .granted || value == .unavailable
    }
  }

  func status(_ permission: ClementinePermission) -> ClementinePermissionStatus {
    switch permission {
    case .accessibility:
      if accessibilityGranted { return .granted }
      return defaults.bool(forKey: accessibilityRequestKey) ? .denied : .notRequested
    case .pages, .numbers, .keynote:
      guard installedApplication(for: permission) != nil else { return .unavailable }
      return automationStatuses[permission] ?? .notRequested
    }
  }

  func refresh() {
    refreshAccessibility()
    revision &+= 1
  }

  private func refreshAccessibility() {
    let granted = environment?.accessibilityGranted() ?? AXIsProcessTrusted()
    if accessibilityGranted != granted { accessibilityGranted = granted }
  }

  func startMonitoring(owner: UUID) {
    monitoringOwners.insert(owner)
    resumeMonitoring()
  }

  func resumeMonitoring() {
    guard !monitoringOwners.isEmpty else { return }
    refreshAccessibility()
    guard !monitoring else { return }
    monitoring = true
    logger.notice("Permission monitoring started")
    applicationLeases = PermissionApplicationLeases()
    monitorProbeAttempts.removeAll()
    // A pre-existing app that the user closes must not be reopened by polling.
    monitorLaunches = Set([ClementinePermission.pages, .numbers, .keynote].filter {
      guard let installed = installedApplication(for: $0) else { return false }
      return !NSRunningApplication.runningApplications(withBundleIdentifier: installed.bundleID).isEmpty
    })
    monitorPreexistingApps = monitorLaunches
    refresh()
    probeAutomationPermissions()
    lastAutomationProbe = Date()
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.refreshAccessibility()
      if Date().timeIntervalSince(self.lastAutomationProbe) >= 1 {
        self.lastAutomationProbe = Date()
        self.probeAutomationPermissions()
      }
    }
    // Keep polling while a menu, slider or another tracking loop is active.
    RunLoop.main.add(timer, forMode: .common)
    monitor = timer
    if activationObserver == nil {
      activationObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
      ) { [weak self] _ in
        guard let self, self.monitoring else { return }
        self.recheckAfterActivation()
      }
    }
    if windowActivationObserver == nil {
      windowActivationObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.recheckAfterActivation() }
    }
  }

  private func recheckAfterActivation() {
    guard monitoring else { return }
    refreshAccessibility()
    for permission in [ClementinePermission.pages, .numbers, .keynote]
      where !monitorPreexistingApps.contains(permission) {
      guard let installed = installedApplication(for: permission),
        !applicationLeases.isProtected(bundleID: installed.bundleID),
        !probesInFlight.contains(permission), automationRequests[permission] == nil,
        NSRunningApplication.runningApplications(withBundleIdentifier: installed.bundleID).isEmpty
      else { continue }
      monitorLaunches.remove(permission)
      monitorProbeAttempts[permission] = 0
    }
    probeAutomationPermissions()
  }

  func stopMonitoring(owner: UUID) {
    monitoringOwners.remove(owner)
    if monitoringOwners.isEmpty { suspendMonitoring() }
  }

  func suspendMonitoring() {
    monitoring = false
    logger.notice("Permission monitoring stopped")
    cancelRequests()
    monitorLaunches.removeAll()
    applicationLeases.finishAll()
    monitor?.invalidate()
    monitor = nil
    if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    activationObserver = nil
    if let windowActivationObserver { NotificationCenter.default.removeObserver(windowActivationObserver) }
    windowActivationObserver = nil
  }

  func request(_ permission: ClementinePermission) {
    switch permission {
    case .accessibility:
      defaults.set(true, forKey: accessibilityRequestKey)
      if let environment { environment.requestAccessibility() }
      else {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
      }
    case .pages, .numbers, .keynote:
      requestAutomation(permission)
    }
    refresh()
  }

  func retry(_ permission: ClementinePermission) {
    guard permission == .accessibility else {
      request(permission)
      return
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    task.arguments = [
      "reset", "Accessibility", Bundle.main.bundleIdentifier ?? "io.joseph.clementine.desktop",
    ]
    do {
      try task.run()
      task.terminationHandler = { [weak self] task in
        DispatchQueue.main.async {
          guard let self else { return }
          guard task.terminationStatus == 0 else {
            self.openSettings(for: .accessibility)
            return
          }
          self.defaults.set(false, forKey: self.accessibilityRequestKey)
          self.request(.accessibility)
        }
      }
    } catch {
      openSettings(for: .accessibility)
    }
  }

  func requestAll(completion: (() -> Void)? = nil) {
    guard !isRequestingAll else { return }
    refreshAccessibility()
    isRequestingAll = true
    requestGeneration = UUID()
    requestCompletion = completion
    if status(.accessibility) != .granted {
      let denied = status(.accessibility) == .denied
      request(.accessibility)
      if denied && environment == nil { openSettings(for: .accessibility) }
      // Accessibility has no completion callback. A refusal, closed prompt or
      // trip to Settings must never leave the onboarding CTA spinning forever.
      finishConfiguration(generation: requestGeneration)
      return
    }
    continueConfiguration(generation: requestGeneration)
  }

  func cancelRequests() {
    requestGeneration = UUID()
    requestCompletion = nil
    timedOutRequests.removeAll()
    for permission in Array(automationRequests.keys) {
      automationEpochs[permission, default: 0] += 1
      requestDeadlines.removeValue(forKey: permission)?.cancel()
      releaseRequestLease(permission)
    }
    automationRequests.removeAll()
    workflowRecoveries.removeAll()
    if isRequestingAll { isRequestingAll = false }
  }

  private func continueConfiguration(generation: UUID) {
    guard generation == requestGeneration, isRequestingAll else { return }
    let automation = [ClementinePermission.pages, .numbers, .keynote].filter {
      // A passive Apple Event can report "not permitted" before the first
      // consent prompt. Always explicitly request every missing native-app
      // permission during configuration, including this ambiguous state.
      status($0) != .granted && status($0) != .unavailable
    }
    requestAutomationSequence(automation, generation: generation) { [weak self] in
      self?.finishConfiguration(generation: generation)
    }
  }

  private func finishConfiguration(generation: UUID) {
    guard generation == requestGeneration, isRequestingAll else { return }
    defaults.set(allRequiredGranted, forKey: Self.onboardingKey)
    isRequestingAll = false
    let completion = requestCompletion
    requestCompletion = nil
    refresh()
    completion?()
  }

  func openSettings(for permission: ClementinePermission) {
    let anchor = permission == .accessibility ? "Privacy_Accessibility" : "Privacy_Automation"
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
    NSWorkspace.shared.open(url)
  }

  private func installedApplication(for permission: ClementinePermission) -> (url: URL, bundleID: String)? {
    if let environment { return environment.installedApplication(permission) }
    let names: [String]
    switch permission {
    case .accessibility: return nil
    case .pages: names = ["com.apple.Pages", "com.apple.iWork.Pages"]
    case .numbers: names = ["com.apple.Numbers", "com.apple.iWork.Numbers"]
    case .keynote: names = ["com.apple.Keynote", "com.apple.iWork.Keynote"]
    }
    for id in names {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
        let bundle = Bundle(url: url), let executable = bundle.executableURL,
        FileManager.default.isExecutableFile(atPath: executable.path) {
        return (url, Bundle(url: url)?.bundleIdentifier ?? id)
      }
    }
    return nil
  }

  private func probeAutomationPermissions() {
    for permission in [ClementinePermission.pages, .numbers, .keynote] {
      probeAutomation(permission)
    }
  }

  private func probeAutomation(_ permission: ClementinePermission) {
    guard environment == nil else { return }
    guard !probesInFlight.contains(permission), automationRequests[permission] == nil,
      let installed = installedApplication(for: permission) else { return }
    if NSRunningApplication.runningApplications(withBundleIdentifier: installed.bundleID).isEmpty {
      guard monitoring else { return }
      if monitorLaunches.contains(permission) {
        // Read TCC's decision without relaunching an app the probe has already
        // closed. Transient/process errors preserve the last known decision.
        probesInFlight.insert(permission)
        let epoch = automationEpochs[permission, default: 0]
        DispatchQueue.global(qos: .utility).async { [weak self] in
          guard let self else { return }
          let result = self.appleEventPermission(bundleID: installed.bundleID, ask: false)
          DispatchQueue.main.async {
            if self.automationEpochs[permission, default: 0] == epoch,
              self.automationRequests[permission] == nil,
              result == self.eventNotPermitted || result == self.wouldRequireConsent {
              self.recordPassiveAutomationResult(result, for: permission)
            }
            self.probesInFlight.remove(permission)
          }
        }
        return
      }
      monitorLaunches.insert(permission)
      probesInFlight.insert(permission)
      let leases = applicationLeases
      withRunningApplication(for: permission, failure: { [weak self] in
        self?.probesInFlight.remove(permission)
      }) { [weak self] bundleID, app, launched in
        guard let self else { return }
        if self.activatedProcessIdentifiers.contains(app.processIdentifier) { leases.protect(bundleID: bundleID) }
        leases.track(app, bundleID: bundleID, launched: launched)
        self.probesInFlight.remove(permission)
        if self.monitoring && self.applicationLeases === leases { self.probeAutomation(permission) }
        else { leases.finish(bundleID: bundleID) }
      }
      return
    }
    // Use a real, read-only Apple Event. Busy-app failures preserve the last
    // permission decision; only an explicit grant/refusal changes its status.
    probesInFlight.insert(permission)
    let epoch = automationEpochs[permission, default: 0]
    let leases = applicationLeases
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      let result = self.passiveAutomationResult(bundleID: installed.bundleID)
      DispatchQueue.main.async {
        if self.automationEpochs[permission, default: 0] == epoch,
          self.automationRequests[permission] == nil {
          self.recordPassiveAutomationResult(result, for: permission)
        }
        self.probesInFlight.remove(permission)
        self.monitorProbeAttempts[permission, default: 0] += 1
        if self.automationRequests[permission] == nil &&
          (self.status(forAppleEventResult: result) != nil || self.monitorProbeAttempts[permission, default: 0] >= 3) {
          leases.finish(bundleID: installed.bundleID)
        }
      }
    }
  }

  func recordPassiveAutomationResult(_ result: OSStatus, for permission: ClementinePermission) {
    if lastPassiveResults[permission] != result {
      lastPassiveResults[permission] = result
      logger.notice("Passive \(permission.id, privacy: .public): \(result)")
    }
    guard let status = status(forAppleEventResult: result) else { return }
    recordAutomationStatus(status, for: permission)
  }

  /// Native workflows are authoritative. Permission errors request access for
  /// that exact app, and a successful script immediately restores its grant.
  func recordWorkflowResult(bundleID: String, result: OSStatus) {
    let update = { [self] in
      guard let permission = ClementinePermission.automation(bundleID: bundleID),
        let status = status(forAppleEventResult: result) else { return }
      if automationRequests[permission] != nil {
        completeAutomationRequest(permission, epoch: automationEpochs[permission, default: 0], result: result)
      } else { recordAutomationStatus(status, for: permission) }
      guard result == eventNotPermitted || result == wouldRequireConsent else { return }
      if let recoveryOverride { recoveryOverride(permission); return }
      guard workflowRecoveries.insert(permission).inserted else { return }
      requestAutomation(permission) { [weak self] in
        guard let self else { return }
        self.workflowRecoveries.remove(permission)
        if self.status(permission) == .denied { self.openSettings(for: permission) }
      }
    }
    if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
  }

  private func requestAutomation(_ permission: ClementinePermission, completion: (() -> Void)? = nil) {
    guard installedApplication(for: permission) != nil else { completion?(); return }
    if automationRequests[permission] != nil {
      if let completion { automationRequests[permission]?.append(completion) }
      return
    }
    timedOutRequests.removeValue(forKey: permission)
    automationRequests[permission] = completion.map { [$0] } ?? []
    automationEpochs[permission, default: 0] += 1
    let epoch = automationEpochs[permission, default: 0]
    automationIssues.removeValue(forKey: permission)
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, self.automationEpochs[permission, default: 0] == epoch,
        self.automationRequests[permission] != nil else { return }
      self.automationEpochs[permission, default: 0] += 1
      self.timedOutRequests[permission] = epoch
      self.automationIssues[permission] = "La demande n’a pas abouti. Réessayez ou vérifiez Automatisation dans Réglages Système."
      self.releaseRequestLease(permission)
      // Do not chain three unresponsive system prompts after a timeout.
      self.finishConfiguration(generation: self.requestGeneration)
      self.finishAutomationRequest(permission)
    }
    requestDeadlines[permission] = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + requestTimeout, execute: deadline)
    if let environment {
      environment.requestAutomation(permission) { [weak self] result in
        DispatchQueue.main.async { self?.completeAutomationRequest(permission, epoch: epoch, result: result) }
      }
      return
    }
    let leases = monitoring ? applicationLeases : PermissionApplicationLeases()
    requestLeases[permission] = leases
    withRunningApplication(for: permission, failure: { [weak self] in
      self?.completeAutomationRequest(permission, epoch: epoch, result: -600)
    }) { [weak self] bundleID, app, launched in
      guard let self else { return }
      if self.activatedProcessIdentifiers.contains(app.processIdentifier) { leases.protect(bundleID: bundleID) }
      leases.track(app, bundleID: bundleID, launched: launched)
      guard self.automationEpochs[permission, default: 0] == epoch,
        self.automationRequests[permission] != nil else { leases.finish(bundleID: bundleID); return }
      guard !leases.isClosed else { self.completeAutomationRequest(permission, epoch: epoch, result: -600); return }
      self.determineAutomationPermission(bundleID: bundleID, ask: true) { result in
        DispatchQueue.main.async {
          if self.activatedProcessIdentifiers.contains(app.processIdentifier) { leases.protect(bundleID: bundleID) }
          if self.automationEpochs[permission, default: 0] == epoch { leases.finish(bundleID: bundleID) }
          self.completeAutomationRequest(permission, epoch: epoch, result: result)
        }
      }
    }
  }

  private func completeAutomationRequest(_ permission: ClementinePermission, epoch: Int, result: OSStatus) {
    if timedOutRequests[permission] == epoch,
      automationEpochs[permission, default: 0] == epoch + 1,
      automationRequests[permission] == nil,
      let status = status(forAppleEventResult: result) {
      timedOutRequests.removeValue(forKey: permission)
      recordAutomationStatus(status, for: permission)
      automationIssues.removeValue(forKey: permission)
      refresh()
      return
    }
    guard automationEpochs[permission, default: 0] == epoch,
      automationRequests[permission] != nil else { return }
    if let status = status(forAppleEventResult: result) {
      recordAutomationStatus(status, for: permission)
      automationIssues.removeValue(forKey: permission)
    } else {
      automationEpochs[permission, default: 0] += 1
      automationIssues[permission] = "Impossible de vérifier \(permission.title). Réessayez ; votre dernier choix est conservé."
    }
    requestLeases.removeValue(forKey: permission)
    refresh()
    finishAutomationRequest(permission)
  }

  private func finishAutomationRequest(_ permission: ClementinePermission) {
    requestDeadlines.removeValue(forKey: permission)?.cancel()
    let callbacks = automationRequests.removeValue(forKey: permission) ?? []
    callbacks.forEach { $0() }
  }

  private func releaseRequestLease(_ permission: ClementinePermission) {
    guard let leases = requestLeases.removeValue(forKey: permission) else { return }
    if let installed = installedApplication(for: permission) { leases.finish(bundleID: installed.bundleID) }
    else if leases !== applicationLeases { leases.finishAll() }
  }

  private func requestAutomationSequence(
    _ permissions: [ClementinePermission], generation: UUID, completion: @escaping () -> Void
  ) {
    guard generation == requestGeneration, isRequestingAll else { return }
    guard let first = permissions.first else { completion(); return }
    requestAutomation(first) { [weak self] in
      self?.requestAutomationSequence(Array(permissions.dropFirst()), generation: generation, completion: completion)
    }
  }

  private func withRunningApplication(
    for permission: ClementinePermission,
    failure: (() -> Void)? = nil,
    completion: @escaping (String, NSRunningApplication, Bool) -> Void
  ) {
    guard let installed = installedApplication(for: permission) else { failure?(); return }
    if let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: installed.bundleID).first {
      completion(installed.bundleID, running, false)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = false
    configuration.hides = true
    NSWorkspace.shared.openApplication(at: installed.url, configuration: configuration) {
      [weak self] app, error in
      DispatchQueue.main.async {
        guard let self else { return }
        guard let app, error == nil else {
          failure?()
          return
        }
        self.completeWhenApplicationIsReady(
          app, bundleID: installed.bundleID, launched: true, attempt: 0,
          completion: completion)
      }
    }
  }

  private func completeWhenApplicationIsReady(
    _ app: NSRunningApplication, bundleID: String, launched: Bool, attempt: Int,
    completion: @escaping (String, NSRunningApplication, Bool) -> Void
  ) {
    if app.isFinishedLaunching || attempt >= 50 {
      completion(bundleID, app, launched)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.completeWhenApplicationIsReady(
        app, bundleID: bundleID, launched: launched, attempt: attempt + 1,
        completion: completion)
    }
  }

  private func determineAutomationPermission(
    bundleID: String, ask: Bool, attempt: Int = 0, completion: @escaping (OSStatus) -> Void
  ) {
    DispatchQueue.global(qos: ask ? .userInitiated : .utility).async { [weak self] in
      guard let self else { return }
      let result = self.appleEventPermission(bundleID: bundleID, ask: ask)
      if result == self.processNotFound && attempt < 20 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
          self?.determineAutomationPermission(
            bundleID: bundleID, ask: ask, attempt: attempt + 1, completion: completion)
        }
      } else {
        // Check the actual event after the explicit consent request too: the
        // preflight can lag behind a change in System Settings.
        let observed = self.passiveAutomationResult(bundleID: bundleID)
        // A real event is authoritative when TCC's preflight cached a grant.
        // Keep an explicit refusal even if a stale read-only probe says yes.
        if result == self.eventNotPermitted { completion(result) }
        else { completion(self.status(forAppleEventResult: observed) != nil ? observed : result) }
      }
    }
  }

  private func status(forAppleEventResult result: OSStatus) -> ClementinePermissionStatus? {
    if result == noErr { return .granted }
    if result == eventNotPermitted { return .denied }
    if result == wouldRequireConsent { return .notRequested }
    // A launch race or an unavailable Apple Event service is not a permission
    // decision. Keep the last reliable value and retry the next time the page
    // becomes active instead of showing a false request.
    return nil
  }

  private func recordAutomationStatus(
    _ status: ClementinePermissionStatus, for permission: ClementinePermission
  ) {
    automationEpochs[permission, default: 0] += 1
    guard automationStatuses[permission] != status else { return }
    automationStatuses[permission] = status
    let value: String?
    switch status {
    case .granted: value = "granted"
    case .denied: value = "denied"
    case .notRequested, .unavailable: value = nil
    }
    defaults.set(value, forKey: "permissionStatus.\(permission.id)")
    refresh()
  }

  /// PID targeting cannot launch an app. No consent prompt or target UI is allowed.
  private func passiveAutomationResult(bundleID: String) -> OSStatus {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
      return processNotFound
    }
    let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
    let property = NSAppleEventDescriptor.record()
    property.setDescriptor(NSAppleEventDescriptor(enumCode: UInt32(formPropertyID)), forKeyword: UInt32(keyAEKeyForm))
    property.setDescriptor(NSAppleEventDescriptor(typeCode: typeProperty), forKeyword: UInt32(keyAEDesiredClass))
    property.setDescriptor(NSAppleEventDescriptor(typeCode: pVersion), forKeyword: UInt32(keyAEKeyData))
    property.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: UInt32(keyAEContainer))
    guard let specifier = property.coerce(toDescriptorType: typeObjectSpecifier) else { return -1 }
    let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAEGetData,
      targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(specifier, forKeyword: keyDirectObject)
    do {
      let options = NSAppleEventDescriptor.SendOptions(rawValue:
        UInt(kAEWaitReply | kAENeverInteract | kAEDoNotPromptForUserConsent))
      let reply = try event.sendEvent(options: options, timeout: 1)
      return reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? noErr
    } catch { return OSStatus((error as NSError).code) }
  }

  private func appleEventPermission(bundleID: String, ask: Bool) -> OSStatus {
    var target = AEAddressDesc()
    let data = bundleID.data(using: .utf8)! as NSData
    let created = AECreateDesc(typeApplicationBundleID, data.bytes, data.length, &target)
    guard created == noErr else { return OSStatus(created) }
    defer { AEDisposeDesc(&target) }
    let eventClass = kAECoreSuite
    let eventID = kAEGetData
    let result = AEDeterminePermissionToAutomateTarget(&target, eventClass, eventID, ask)
    if ask { logger.notice("Automation request \(bundleID, privacy: .public): \(result)") }
    return result
  }


}

private final class PermissionHover: ObservableObject {
  let monitoringOwner = UUID()
  @Published var id: String?
}

struct PermissionsView: View {
  @StateObject private var center = PermissionCenter.shared
  @StateObject private var hover = PermissionHover()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if PermissionCenter.needsOnboarding {
          onboardingCard
        }
        VStack(spacing: 12) {
          ForEach(ClementinePermission.allCases) { permission in
            permissionRow(permission)
          }
        }

      }
      .padding(28)
      .frame(maxWidth: 850)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .onAppear { center.startMonitoring(owner: hover.monitoringOwner) }
    .onDisappear { center.stopMonitoring(owner: hover.monitoringOwner) }
  }

  private let permissionGreen = Color(red: 0.24, green: 0.67, blue: 0.39)

  private var onboardingCard: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(spacing: 12) {
        ClementineMark(size: 38)
        VStack(alignment: .leading, spacing: 3) {
          Text(tr("Configurer Clémentine"))
            .font(.system(size: 20, weight: .bold, design: .rounded))
          Text(tr("Pour activer la fonctionnalité Finovox et les formats Apple natifs."))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
      }
      Text(tr("Activez d’abord Clémentine dans Accessibilité. macOS présentera ensuite les demandes pour Pages, Numbers et Keynote, l’une après l’autre. Les applications Apple absentes seront simplement ignorées."))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        center.requestAll()
      } label: {
        HStack(spacing: 8) {
          if center.isRequestingAll { ProgressView().controlSize(.small).tint(citrus) }
          else { Image(systemName: "checkmark.shield.fill") }
          Text(trString(center.isRequestingAll ? "Configuration en cours…" : "Configurer Clémentine"))
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
      }
      .buttonStyle(.borderedProminent)
      .tint(citrus)
      .disabled(center.isRequestingAll)
      if center.isRequestingAll {
        Button(tr("Annuler")) { center.cancelRequests() }
          .buttonStyle(.bordered)
      }
    }
    .padding(18)
    .background(citrus.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
    .overlay(RoundedRectangle(cornerRadius: 15).stroke(citrus.opacity(0.42)))
  }

  @ViewBuilder private func permissionRow(_ permission: ClementinePermission) -> some View {
    let status = center.status(permission)
    let controlHovered = hover.id == "permission-\(permission.id)"
    HStack(spacing: 15) {
      Image(systemName: permission.icon)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(status == .unavailable ? Color.secondary : citrus)
        .frame(width: 42, height: 42)
        .background(citrus.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
      VStack(alignment: .leading, spacing: 4) {
        Text(trString(permission.title)).font(.system(size: 15, weight: .semibold))
        Text(trString(status == .unavailable ? "Application non installée · aucune autorisation nécessaire." : permission.detail))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 18)
      permissionControl(permission, status: status, hovered: controlHovered)
    }
    .padding(.horizontal, 16).padding(.vertical, 15)
    .background(Color.clementineGroupedSurface, in: RoundedRectangle(cornerRadius: 15))
    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.clementineBorder))
  }

  @ViewBuilder private func permissionControl(
    _ permission: ClementinePermission, status: ClementinePermissionStatus, hovered: Bool
  ) -> some View {
    if status == .unavailable {
      Image(systemName: "minus.circle.fill")
        .font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
        .frame(width: 36, height: 36)
        .accessibilityLabel(tr("\(permission.title) : app non installée"))
        .help(tr("Application non installée · aucune autorisation à demander"))
    } else {
    let granted = status == .granted
    let color = granted ? permissionGreen : Color.red
    Button {
      if status == .notRequested { center.request(permission) }
      else { center.openSettings(for: permission) }
    } label: {
      Image(systemName: granted ? "checkmark.shield.fill" : "xmark.shield.fill")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 36, height: 36)
        .background(color.opacity(hovered ? 0.2 : 0.11), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tr("\(permission.title) : \(status.label)"))
    .help(trString(center.automationIssues[permission] ?? permissionHelp(permission, status: status)))
    .onHover { hover.id = $0 ? "permission-\(permission.id)" : nil }
    .animation(.easeInOut(duration: 0.18), value: hovered)
    }
  }

  private func permissionHelp(
    _ permission: ClementinePermission, status: ClementinePermissionStatus
  ) -> String {
    switch status {
    case .granted:
      return "Autorisation accordée · Ouvrir les réglages système"
    case .notRequested:
      return "Autorisation jamais demandée · Cliquer pour l’autoriser"
    case .denied:
      return "Autorisation refusée · Ouvrir les réglages système"
    case .unavailable:
      return "\(permission.title) n’est pas installée"
    }
  }
}

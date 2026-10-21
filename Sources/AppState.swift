import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class AppState: ObservableObject {
  static let productOnboardingKey = "didCompleteProductOnboarding20261019v1"
  @Published private(set) var login = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
  private var appliedIconResource: String?
  private var appearanceIcons: [String: NSImage] = [:]
  @Published var files: [URL] = []
  @Published var jobs: [Job] = []
  @Published var options = Options()
  @Published var selectedTool: String? = nil
  @Published var format = "jpg"
  @Published var page = "workspace"
  @Published var search = ""
  @Published var hoverDrop = false
  @Published var error: String? = nil
  @Published var wheelEnabled = true
  @Published var reveal = true
  @Published var sound = UserDefaults.standard.object(forKey: "sound") as? Bool ?? true
  @Published var haptics = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true
  @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "dark"
  @Published var floatBehavior = UserDefaults.standard.string(forKey: "floatBehavior") ?? "append"
  @Published var conversionModifier =
    UserDefaults.standard.string(forKey: "conversionModifier") ?? "shift"
  @Published var toolModifier = UserDefaults.standard.string(forKey: "toolModifier") ?? "command"
  @Published var actionModifier =
    UserDefaults.standard.string(forKey: "actionModifier") ?? "option"
  @Published var showingOnboarding =
    !UserDefaults.standard.bool(forKey: AppState.productOnboardingKey)
  @Published var onboardingPage = 0
  var nativeVerificationRoot: URL?
  var nativeVerificationIDs = Set<UUID>()
  var showWindow: (() -> Void)?
  var showFloat: (([URL]) -> Void)?
  private var tokens: [UUID: CancellationToken] = [:]
  private let queue = DispatchQueue(label: "io.joseph.clementine.jobs", qos: .userInitiated)
  init() {
    let defaults = UserDefaults.standard
    // These two behaviours are part of Clémentine's core Finder workflow and
    // are no longer optional preferences.
    wheelEnabled = true
    reveal = true
    defaults.set(true, forKey: "wheelEnabled")
    defaults.set(true, forKey: "reveal")
    // The wheel surface now follows the selected appearance directly. Remove
    // the retired pre-release preference so it cannot affect future builds.
    defaults.removeObject(forKey: "solid")
    if !defaults.bool(forKey:"didEnableWheelHoverClick20261018") {
      sound = true
      defaults.set(true,forKey:"sound")
      defaults.set(true,forKey:"didEnableWheelHoverClick20261018")
    }
    if !sound && !haptics {
      sound = true; haptics = true
      defaults.set(true, forKey: "sound")
      defaults.set(true, forKey: "haptics")
    }
    if defaults.object(forKey: "launchAtLogin") == nil { defaults.set(true, forKey: "launchAtLogin") }
    // Adopt native-text editing for existing pre-release installations once.
    if !defaults.bool(forKey: "didAdoptAutomaticPDFOffice20261018") {
      defaults.set("automatic", forKey: "pdfOfficeLayout")
      defaults.set(true, forKey: "didAdoptAutomaticPDFOffice20261018")
    }
    options.pdfOfficeLayout = defaults.string(forKey: "pdfOfficeLayout") ?? "automatic"
    options.epubLayout = defaults.string(forKey: "epubLayout") ?? "adjustableText"
    if defaults.object(forKey: "conversionQuality") != nil {
      options.quality = min(1, max(0.3, defaults.double(forKey: "conversionQuality")))
    }
    options.strip = defaults.object(forKey: "stripConversionMetadata") as? Bool ?? false
    let savedArchiveFormat = defaults.string(forKey: "archiveFormat") ?? "zip"
    options.archiveFormat = ["zip", "tar", "gz", "rar"].contains(savedArchiveFormat)
      ? savedArchiveFormat : "zip"
    let original = wheelModifiers
    let normalized = WheelShortcutAssignments.normalized(original)
    if normalized != original { applyWheelModifiers(normalized) }
  }
  private var wheelModifiers: [String: String] {
    ["formats": conversionModifier, "tools": toolModifier, "actions": actionModifier]
  }
  private func applyWheelModifiers(_ values: [String: String]) {
    conversionModifier = values["formats"]!
    toolModifier = values["tools"]!
    actionModifier = values["actions"]!
    persist()
  }
  func wheelModifierBinding(_ role: String) -> Binding<String> {
    Binding(get: { self.wheelModifiers[role] ?? "none" }, set: { value in
      self.applyWheelModifiers(WheelShortcutAssignments.assigning(value, to: role, in: self.wheelModifiers))
    })
  }
  var formats: [String] { Compatibility.targets(files) }
  var tools: [Tool] {
    Tool.available(files).filter {
      search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
    }
  }
  var running: Bool { jobs.contains { !$0.done } }
  var activeTool: Tool? { Tool.available(files).first { $0.id == selectedTool } }
  func persist() {
    let d = UserDefaults.standard
    d.set(options.pdfOfficeLayout, forKey: "pdfOfficeLayout")
    d.set(options.epubLayout, forKey: "epubLayout")
    d.set(options.archiveFormat, forKey: "archiveFormat")
    d.set(options.quality, forKey: "conversionQuality")
    d.set(options.strip, forKey: "stripConversionMetadata")
    d.set(true, forKey: "wheelEnabled")
    d.set(true, forKey: "reveal")
    d.set(sound, forKey: "sound")
    d.set(haptics, forKey: "haptics")
    d.set(appearance, forKey: "appearance")
    d.set(floatBehavior, forKey: "floatBehavior")
    d.set(conversionModifier, forKey: "conversionModifier")
    d.set(toolModifier, forKey: "toolModifier")
    d.set(actionModifier, forKey: "actionModifier")
  }
  func registerLaunchAtLoginIfNeeded() {
    guard login, Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications",
      SMAppService.mainApp.status == .notRegistered else { return }
    // Registration runs after the app and its icon have finished loading. A
    // failed attempt remains eligible for retry on the next normal launch.
    do { try SMAppService.mainApp.register() }
    catch { NSLog("Clémentine: launch-at-login registration failed: %@", error.localizedDescription) }
  }
  func setLaunchAtLogin(_ enabled: Bool) {
    guard enabled != login else { return }
    do {
      if enabled { try SMAppService.mainApp.register() }
      else { try SMAppService.mainApp.unregister() }
      login = enabled
      UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
    } catch { self.error = error.localizedDescription }
  }
  func applyAppearance() {
    NSApp.appearance = ClementineAppearance(rawValue: appearance)?.nsAppearance
    let usesDarkIcon: Bool
    switch appearance {
    case "dark": usesDarkIcon = true
    case "light": usesDarkIcon = false
    default:
      usesDarkIcon = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    let resource = usesDarkIcon ? "AppIcon" : "AppIconLight"
    guard appliedIconResource != resource else { return }
    if appearanceIcons[resource] == nil,
      let url = Bundle.main.url(forResource: resource, withExtension: "icns"),
      let icon = NSImage(contentsOf: url) { appearanceIcons[resource] = icon }
    guard let icon = appearanceIcons[resource] else { return }
    NSApp.applicationIconImage = icon
    appliedIconResource = resource
  }
  func completeProductOnboarding() {
    UserDefaults.standard.set(true, forKey: Self.productOnboardingKey)
    files = []
    selectedTool = nil
    let permissionsReady = PermissionCenter.shared.allRequiredGranted
    if permissionsReady {
      UserDefaults.standard.set(true, forKey: PermissionCenter.onboardingKey)
    }
    page = permissionsReady ? "workspace" : "permissions"
    showingOnboarding = false
  }
  func add(_ urls: [URL], replace: Bool = false) {
    let clean = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    if replace { files = [] }
    for u in clean where !files.contains(u) { files.append(u) }
    if !Tool.available(files).contains(where: { $0.id == selectedTool }) { selectedTool = nil }
    if !formats.contains(format) { format = formats.first ?? "png" }
  }
  func browse() {
    let p = NSOpenPanel()
    p.allowsMultipleSelection = true
    p.canChooseDirectories = true
    p.message = tr("Choisissez les fichiers à traiter localement")
    if p.runModal() == .OK { add(p.urls) }
  }
  func folder() {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.prompt = tr("Choisir")
    if p.runModal() == .OK { options.outputFolder = p.url!.path }
  }
  var showModule: ((String,[URL]) -> Void)?
  func configure(_ tool: String) {
    guard !files.isEmpty else { return }
    showModule?(tool, files)
  }
  func submit(_ action: String, files selected: [URL]? = nil, overrideOptions: Options? = nil) {
    let inputs = selected ?? files
    guard !inputs.isEmpty else { return }
    if action.hasPrefix("convert:") {
      let target = String(action.dropFirst(8))
      guard Compatibility.targets(inputs).contains(target) else {
        error = "Cette conversion n’est pas proposée pour cette sélection."
        return
      }
    }
    if !action.hasPrefix("convert:"), !Tool.available(inputs).contains(where: { $0.id == action }) {
      error = "Cet outil n’est pas proposé pour cette sélection."
      return
    }
    let settings = overrideOptions ?? options
    let title =
      action.hasPrefix("convert:")
      ? "Conversion en \(action.dropFirst(8).uppercased())"
      : (Tool.all.first { $0.id == action }?.name ?? action)
    let job = Job(title: title, files: inputs)
    let id = job.id
    jobs.insert(job, at: 0)
    let token = CancellationToken()
    tokens[id] = token
    queue.async { [weak self] in
      let engine = Engine(token: token) { fraction, message in
        DispatchQueue.main.async {
          guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
          self.jobs[i].progress = fraction
          self.jobs[i].state = message
        }
      }
      do {
        let outputs = try engine.run(inputs, action: action, options: settings)
        DispatchQueue.main.async {
          guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
          self.jobs[i].done = true
          self.jobs[i].progress = 1
          self.jobs[i].state = "Terminé"
          self.jobs[i].outputs = outputs
          self.tokens.removeValue(forKey: id)
          self.writeNativeVerification()
          if self.reveal { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
          if self.sound { NSSound(named: "Glass")?.play() }
        }
      } catch {
        let message = error.localizedDescription
        DispatchQueue.main.async {
          guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
          self.jobs[i].done = true
          self.jobs[i].failed = true
          self.jobs[i].state = message
          self.jobs[i].log = message
          self.tokens.removeValue(forKey: id)
          self.writeNativeVerification()
        }
      }
    }
  }
  func cancel(_ id: UUID) { tokens[id]?.cancel() }
  func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        let u: URL? =
          (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
        if let u { DispatchQueue.main.async { self.add([u]) } }
      }
    }
    return true
  }
  func fileAction(_ action: String, urls: [URL]) {
    guard !urls.isEmpty else { return }
    switch action {
    case "finovox": FinovoxUploader.shared.start(urls)
    case "float": showFloat?(urls)
    case "reveal": NSWorkspace.shared.activateFileViewerSelecting(urls)
    case "path":
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    case "copy":
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects(urls as [NSURL])
    case "airdrop": NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    case "terminal":
      TerminalAction.open(urls) { [weak self] error in
        if let error { self?.error = error.localizedDescription }
      }
    case "copyto", "moveto":
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.message = action == "copyto" ? "Copier vers…" : "Déplacer vers…"
      guard panel.runModal() == .OK, let folder = panel.url else { return }
      do {
        for u in urls {
          let dest = folder.appendingPathComponent(u.lastPathComponent)
          if action == "copyto" {
            try FileManager.default.copyItem(at: u, to: dest)
          } else {
            try FileManager.default.moveItem(at: u, to: dest)
          }
        }
        NSWorkspace.shared.activateFileViewerSelecting(
          urls.map { folder.appendingPathComponent($0.lastPathComponent) })
      } catch { self.error = error.localizedDescription }
    default: break
    }
  }
}

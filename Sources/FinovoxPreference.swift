import Foundation

enum FinovoxPreference {
  static let key = "finovoxEnabled"
  static let migrationKey = "didMigrateFinovoxDefault20261022"

  static func load(in defaults: UserDefaults = .standard) -> Bool {
    if defaults.bool(forKey: migrationKey) { return defaults.bool(forKey: key) }
    // Older builds persisted the new switch's implicit false value without
    // distinguishing it from a user choice. Restore the previously available
    // action once for existing installations, before AppState seeds defaults.
    let existingInstallation = [
      "didEnableWheelHoverClick20261018", "didAdoptAutomaticPDFOffice20261018",
      "launchAtLogin", "appearance", "conversionQuality",
      "didCompleteProductOnboarding20261019v1"
    ].contains { defaults.object(forKey: $0) != nil }
    let enabled = defaults.bool(forKey: key) || existingInstallation
    defaults.set(enabled, forKey: key)
    defaults.set(true, forKey: migrationKey)
    return enabled
  }
}

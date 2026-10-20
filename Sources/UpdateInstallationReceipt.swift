import Foundation

/// A download is not a successful installation. Confirm only after a new
/// process has actually started on the expected build (or a newer one).
final class UpdateInstallationReceipt {
  enum Result: Equatable {
    case none
    case installed(String)
    case interrupted(String)
  }
  private let defaults: UserDefaults
  private let key = "pendingUpdateInstallation"
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func begin(build: String, version: String) {
    defaults.set(["build": build, "version": version], forKey: key)
  }

  func cancel() { defaults.removeObject(forKey: key) }

  func verify(runningBuild: String) -> Result {
    guard let pending = defaults.dictionary(forKey: key) as? [String: String],
      let build = pending["build"], let version = pending["version"] else { return .none }
    cancel()
    return runningBuild.compare(build, options: .numeric) != .orderedAscending
      ? .installed(version) : .interrupted(version)
  }
}

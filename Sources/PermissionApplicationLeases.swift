import AppKit

protocol PermissionProbeApplication: AnyObject {
  var processIdentifier: pid_t { get }
  var isActive: Bool { get }
  var isTerminated: Bool { get }
  @discardableResult func terminate() -> Bool
}

extension NSRunningApplication: PermissionProbeApplication {}

/// Owns only the apps started by a permission check. Taking an app into use
/// permanently releases that session's ownership; cleanup never force-quits.
final class PermissionApplicationLeases {
  private var applications: [String: PermissionProbeApplication] = [:]
  private var protectedBundleIDs = Set<String>()
  private var closed = false
  var isClosed: Bool { closed }
  func isProtected(bundleID: String) -> Bool { protectedBundleIDs.contains(bundleID) }

  func track(_ app: PermissionProbeApplication, bundleID: String, launched: Bool) {
    guard launched, !app.isActive, !app.isTerminated,
      !protectedBundleIDs.contains(bundleID) else { return }
    applications[bundleID] = app
    if closed { finish(bundleID: bundleID) }
  }

  func protect(bundleID: String) {
    protectedBundleIDs.insert(bundleID)
    applications.removeValue(forKey: bundleID)
  }

  func finish(bundleID: String) {
    guard let app = applications.removeValue(forKey: bundleID), !app.isTerminated else { return }
    guard !app.isActive else { protect(bundleID: bundleID); return }
    if !app.terminate() { applications[bundleID] = app }
  }

  func finishAll() {
    closed = true
    for bundleID in Array(applications.keys) { finish(bundleID: bundleID) }
  }
}

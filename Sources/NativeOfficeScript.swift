import AppKit

struct NativeOfficePermissionResult {
  let bundleID: String
  let result: OSStatus
}

/// All native iWork operations report actual Apple Event permission outcomes
/// through this boundary, including reading Numbers sheets and exporting copies.
enum NativeOfficeScript {
  static let permissionResult = Notification.Name("ClementineNativeAutomationPermissionResult")
  static let willUseApplication = Notification.Name("ClementineNativeAutomationWillUseApplication")
  static func run(_ script: String, bundleID: String, operation: String,
    report: (String, OSStatus) -> Void = {
      NotificationCenter.default.post(name: NativeOfficeScript.permissionResult,
        object: NativeOfficePermissionResult(bundleID: $0, result: $1))
    }) throws -> NSAppleEventDescriptor
  {
    var failure: NSDictionary?
    var result: NSAppleEventDescriptor?
    let execute = {
      NotificationCenter.default.post(name: willUseApplication, object: bundleID)
      guard let appleScript = NSAppleScript(source: script) else { return }
      result = appleScript.executeAndReturnError(&failure)
    }
    if Thread.isMainThread { execute() } else { DispatchQueue.main.sync(execute: execute) }
    if let failure {
      let code = (failure[NSAppleScript.errorNumber] as? NSNumber)?.int32Value
      if code == -1743 || code == -1744 {
        report(bundleID, code!)
        let app = bundleID.split(separator: ".").last.map(String.init) ?? "l’application Apple"
        throw ClementineError("L’accès à \(app) doit être autorisé. Accordez l’autorisation demandée ou activez-la dans Réglages Système → Confidentialité et sécurité → Automatisation, puis relancez l’opération.")
      }
      throw ClementineError(operation + " : " + String(describing: failure[NSAppleScript.errorMessage] ?? failure))
    }
    guard let result else { throw ClementineError(operation + " : le script Apple n’a pas pu être exécuté.") }
    report(bundleID, noErr)
    return result
  }
}

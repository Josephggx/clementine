import AppKit

final class ProbeApp: PermissionProbeApplication {
  var processIdentifier: pid_t = 123
  var isActive = false
  var isTerminated = false
  var acceptsTermination = true
  var terminationRequests = 0
  func terminate() -> Bool {
    terminationRequests += 1
    if acceptsTermination { isTerminated = true }
    return acceptsTermination
  }
}

let id = "io.example.probe"
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.track(app, bundleID: id, launched: true)
  lease.finish(bundleID: id)
  lease.finishAll()
  precondition(app.terminationRequests == 1)
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.track(app, bundleID: id, launched: false)
  lease.finishAll()
  precondition(app.terminationRequests == 0, "Pre-existing apps belong to the user")
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.track(app, bundleID: id, launched: true)
  lease.protect(bundleID: id)
  lease.finishAll()
  precondition(app.terminationRequests == 0, "Activation/workflows transfer ownership to the user")
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.protect(bundleID: id)
  lease.track(app, bundleID: id, launched: true)
  lease.finishAll()
  precondition(app.terminationRequests == 0, "A late launch callback must respect prior user activation")
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.track(app, bundleID: id, launched: true)
  app.isActive = true
  lease.finish(bundleID: id)
  app.isActive = false
  lease.finishAll()
  precondition(app.terminationRequests == 0, "Once taken into use the app remains user-owned")
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.finishAll()
  precondition(lease.isClosed)
  lease.track(app, bundleID: id, launched: true)
  precondition(app.terminationRequests == 1, "Late launches are cleaned up after the page closes")
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  app.acceptsTermination = false
  lease.track(app, bundleID: id, launched: true)
  lease.finish(bundleID: id)
  precondition(!app.isTerminated)
  app.acceptsTermination = true
  lease.finishAll()
  precondition(app.terminationRequests == 2 && app.isTerminated, "Normal termination can be retried, never forced")
}
do {
  let lease = PermissionApplicationLeases(), app = ProbeApp()
  lease.track(app, bundleID: id, launched: true)
  app.isTerminated = true
  lease.finishAll()
  precondition(app.terminationRequests == 0)
}
print("PASS: fermeture après vérification, app préexistante préservée, prise en main utilisateur/workflow, changement de page, lancement tardif et refus de fermeture")

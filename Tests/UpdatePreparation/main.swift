import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
}
var state = UpdatePreparation()
var installed = 0
check(state.phase == .idle, "Starts idle")
check(state.requestInstallation(isBusy: false) == nil, "No unprepared install")
state.downloading()
check(state.isPreparing && !state.canInstall, "Downloading is not ready")
check(state.requestInstallation(isBusy: false) == nil, "Cannot install incomplete bytes")
state.extracting()
check(state.isPreparing && !state.canInstall, "Extraction is not ready")
check(state.requestInstallation(isBusy: false) == nil, "Wait for verification and preparation")
state.ready { installed += 1 }
check(installed == 0 && state.canInstall, "Preparation never quits the app")
let install = state.requestInstallation(isBusy: false)
check(state.phase == .installing, "Consume before invocation")
install?()
check(installed == 1, "User click installs")
check(state.requestInstallation(isBusy: false) == nil, "Repeated click ignored")
check(state.continueInstallation(isBusy: false) == nil, "No duplicate continuation")
state.ready { installed += 1 }
check(state.requestInstallation(isBusy: true) == nil, "Busy task defers install")
check(state.phase == .waitingForWork, "Waiting state")
for _ in 0..<20 { check(state.continueInstallation(isBusy: true) == nil, "Wait until task completes") }
let deferred = state.continueInstallation(isBusy: false)
deferred?()
check(installed == 2, "Exactly once after task completes")
check(state.continueInstallation(isBusy: false) == nil, "Timer cannot restart twice")
for clear: (inout UpdatePreparation) -> Void in [{ $0.fail() }, { $0.reset() }, { $0.needsInteraction() }, { $0.downloading() }, { $0.extracting() }] {
  state.ready { fatalError("Stale callback") }
  _ = state.requestInstallation(isBusy: true)
  clear(&state)
  check(state.continueInstallation(isBusy: false) == nil, "Clearing drops waiting callback")
  check(state.requestInstallation(isBusy: false) == nil, "Clearing drops ready callback")
}
state.ready { fatalError("Superseded callback") }
state.ready { installed += 1; state.reset() }
let reentrant = state.requestInstallation(isBusy: false)
reentrant?()
check(installed == 3 && state.phase == .idle, "Callback can synchronously update its owner")
print("\(checks) update preparation checks passed")

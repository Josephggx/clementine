import AppKit

@MainActor enum PermissionMatrix {
  static func run() async {
    let apps: [ClementinePermission] = [.pages, .numbers, .keynote]
    var cases = 0
    func freshDefaults() -> (UserDefaults, String) {
      let suite = "io.joseph.clementine.permission-matrix." + UUID().uuidString
      return (UserDefaults(suiteName: suite)!, suite)
    }
    func installed(_ permission: ClementinePermission) -> (url: URL, bundleID: String) {
      (URL(fileURLWithPath: "/Applications/" + permission.title + ".app"), "com.apple." + permission.title)
    }
    for availableMask in 0..<8 {
      for grantedMask in 0..<8 {
        for accessibility in [false, true] {
          let (defaults, suite) = freshDefaults()
          var prompts = 0, requested: [ClementinePermission] = [], completions = 0
          let environment = PermissionEnvironment(
            accessibilityGranted: { accessibility }, requestAccessibility: { prompts += 1 },
            installedApplication: { permission in
              guard let index = apps.firstIndex(of: permission), availableMask & (1 << index) != 0 else { return nil }
              return installed(permission)
            }, requestAutomation: { permission, reply in
              requested.append(permission)
              reply(grantedMask & (1 << apps.firstIndex(of: permission)!) != 0 ? 0 : -1743)
            })
          let center = PermissionCenter(defaults: defaults, environment: environment, requestTimeout: 0.1)
          await withCheckedContinuation { continuation in
            center.requestAll { completions += 1; continuation.resume() }
          }
          precondition(!center.isRequestingAll && completions == 1)
          precondition(prompts == (accessibility ? 0 : 1))
          let expected = accessibility ? apps.enumerated().filter { availableMask & (1 << $0.offset) != 0 }.map(\.element) : []
          precondition(requested == expected, "Only installed apps, sequentially and after Accessibility")
          for (index, app) in apps.enumerated() {
            let expected: ClementinePermissionStatus = availableMask & (1 << index) == 0 ? .unavailable :
              !accessibility ? .notRequested : grantedMask & (1 << index) != 0 ? .granted : .denied
            precondition(center.status(app) == expected)
          }
          precondition(center.allRequiredGranted == (accessibility && (grantedMask & availableMask) == availableMask))
          center.cancelRequests()
          defaults.removePersistentDomain(forName: suite)
          cases += 1
        }
      }
    }

    // A system callback which never arrives must release the CTA and preserve
    // the latest reliable decision. A late result must not overwrite a retry.
    do {
      let (defaults, suite) = freshDefaults()
      var pending: [(OSStatus) -> Void] = []
      let environment = PermissionEnvironment(accessibilityGranted: { true }, requestAccessibility: {},
        installedApplication: { $0 == .pages ? installed($0) : nil },
        requestAutomation: { _, reply in pending.append(reply) })
      let center = PermissionCenter(defaults: defaults, environment: environment, requestTimeout: 0.04)
      await withCheckedContinuation { continuation in center.requestAll { continuation.resume() } }
      precondition(!center.isRequestingAll && center.automationIssues[.pages] != nil)
      var finished = 0
      center.requestAll { finished += 1 }
      precondition(center.isRequestingAll && pending.count == 2)
      pending[0](-1743)
      try? await Task.sleep(for: .milliseconds(5))
      precondition(center.isRequestingAll && finished == 0)
      pending[1](0)
      try? await Task.sleep(for: .milliseconds(5))
      precondition(!center.isRequestingAll && finished == 1 && center.status(.pages) == .granted)
      precondition(center.automationIssues[.pages] == nil)
      defaults.removePersistentDomain(forName: suite)
      cases += 1
    }

    do {
      let (defaults, suite) = freshDefaults()
      var pending: [(OSStatus) -> Void] = [], finished = 0
      var trusted = true, present = true
      let environment = PermissionEnvironment(accessibilityGranted: { trusted }, requestAccessibility: {},
        installedApplication: { present && $0 == .pages ? installed($0) : nil },
        requestAutomation: { _, reply in pending.append(reply) })
      let center = PermissionCenter(defaults: defaults, environment: environment, requestTimeout: 0.2)
      center.requestAll { finished += 1 }
      center.cancelRequests()
      pending[0](0)
      try? await Task.sleep(for: .milliseconds(5))
      precondition(!center.isRequestingAll && finished == 0 && center.status(.pages) == .notRequested)
      center.requestAll { finished += 1 }
      pending[1](-1743)
      try? await Task.sleep(for: .milliseconds(5))
      precondition(finished == 1 && center.status(.pages) == .denied)
      center.requestAll { finished += 1 }
      pending[2](0)
      try? await Task.sleep(for: .milliseconds(5))
      precondition(finished == 2 && center.status(.pages) == .granted)
      trusted = false; center.refresh()
      precondition(center.status(.accessibility) != .granted)
      trusted = true; center.refresh()
      precondition(center.status(.accessibility) == .granted)
      present = false; center.refresh()
      precondition(center.status(.pages) == .unavailable && center.allRequiredGranted)
      defaults.removePersistentDomain(forName: suite)
      cases += 1
    }
    do {
      let (defaults, suite) = freshDefaults()
      var requests = 0
      let environment = PermissionEnvironment(accessibilityGranted: { true }, requestAccessibility: {},
        installedApplication: { installed($0) }, requestAutomation: { _, _ in requests += 1 })
      let center = PermissionCenter(defaults: defaults, environment: environment, requestTimeout: 0.03)
      await withCheckedContinuation { continuation in center.requestAll { continuation.resume() } }
      precondition(!center.isRequestingAll && requests == 1, "A timeout stops the sequence instead of hanging for each remaining app")
      defaults.removePersistentDomain(forName: suite)
      cases += 1
    }
    for decision: OSStatus in [0, -1743] {
      let (defaults, suite) = freshDefaults()
      var pending: ((OSStatus) -> Void)?
      let environment = PermissionEnvironment(accessibilityGranted: { true }, requestAccessibility: {},
        installedApplication: { $0 == .pages ? installed($0) : nil }, requestAutomation: { _, reply in pending = reply })
      let center = PermissionCenter(defaults: defaults, environment: environment, requestTimeout: 0.03)
      var completions = 0
      await withCheckedContinuation { continuation in center.requestAll { completions += 1; continuation.resume() } }
      pending?(decision)
      try? await Task.sleep(for: .milliseconds(5))
      precondition(center.status(.pages) == (decision == 0 ? .granted : .denied))
      precondition(completions == 1 && center.automationIssues[.pages] == nil && !center.isRequestingAll)
      defaults.removePersistentDomain(forName: suite)
      cases += 1
    }
    for code: OSStatus in [-600, -1712, -1, -1744] {
      let (defaults, suite) = freshDefaults()
      let environment = PermissionEnvironment(accessibilityGranted: { true }, requestAccessibility: {},
        installedApplication: { $0 == .numbers ? installed($0) : nil }, requestAutomation: { _, reply in reply(code) })
      let center = PermissionCenter(defaults: defaults, environment: environment, requestTimeout: 0.1)
      await withCheckedContinuation { continuation in center.requestAll { continuation.resume() } }
      precondition(!center.isRequestingAll && center.status(.numbers) == .notRequested)
      defaults.removePersistentDomain(forName: suite)
      cases += 1
    }
    print("PASS \(cases) first-run permission scenarios: installed/absent apps, grants/refusals, Accessibility denied, timeout, cancellation, late callbacks, retry, revoke and uninstall")
  }
}

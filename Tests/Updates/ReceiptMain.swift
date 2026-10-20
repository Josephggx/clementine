import Foundation

@main struct ReceiptCheck {
  static func main() {
    let suite = "io.joseph.clementine.receipt-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let receipt = UpdateInstallationReceipt(defaults: defaults)
    precondition(receipt.verify(runningBuild: "12") == .none)
    receipt.begin(build: "13", version: "1.0.3")
    precondition(receipt.verify(runningBuild: "12") == .interrupted("1.0.3"))
    precondition(receipt.verify(runningBuild: "12") == .none, "Report an interruption only once")
    receipt.begin(build: "13", version: "1.0.3")
    precondition(receipt.verify(runningBuild: "13") == .installed("1.0.3"))
    receipt.begin(build: "13", version: "1.0.3")
    precondition(receipt.verify(runningBuild: "14") == .installed("1.0.3"))
    receipt.begin(build: "13", version: "1.0.3")
    receipt.cancel()
    precondition(receipt.verify(runningBuild: "12") == .none)
    print("PASS: installation confirmée au redémarrage, interruption détectée, annulation et mise à jour plus récente")
  }
}

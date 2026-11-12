import AppKit
import SwiftUI
import Sparkle

// UI stand-ins keep this executable headless: it never opens an app or window.
func tr(_ value: String) -> String { value }
func trString(_ value: String) -> String { value }
let citrus = Color.orange
struct ClementineMark: View { var size: CGFloat; var body: some View { EmptyView() } }
struct StableInteractionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View { configuration.label }
}

@main struct AdapterChecks {
  static func main() {
    let updates = AppUpdates()
    let selectors = [
      "updater:didFindValidUpdate:", "updater:willDownloadUpdate:withRequest:",
      "updater:didDownloadUpdate:", "updater:willInstallUpdateOnQuit:immediateInstallationBlock:",
      "updater:userDidMakeChoice:forUpdate:state:", "updater:willInstallUpdate:",
      "updater:didAbortWithError:", "updaterDidNotFindUpdate:"
    ]
    for name in selectors {
      precondition(updates.responds(to: NSSelectorFromString(name)), "Missing Sparkle callback: \(name)")
    }
    let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    let updater = controller.updater
    let item = SUAppcastItem(dictionary: ["enclosure": ["url": "https://example.invalid/update.zip", "sparkle:version": "999", "sparkle:shortVersionString": "9.9.9"]])!
    updates.updater(updater, didFindValidUpdate: item)
    precondition(!updates.updateActionEnabled && updates.preparation.isPreparing)
    updates.updater(updater, didDownloadUpdate: item)
    precondition(!updates.updateActionEnabled && updates.updateActionTitle == "Préparation…")
    var installs = 0
    let owned = updates.updater(updater, willInstallUpdateOnQuit: item, immediateInstallationBlock: { installs += 1 })
    precondition(owned && installs == 0 && updates.updateActionEnabled)
    precondition(updates.updateActionTitle == "Redémarrer pour mettre à jour")
    updates.checkForUpdates()
    precondition(installs == 1 && !updates.updateActionEnabled)
    updates.checkForUpdates()
    precondition(installs == 1)
    updates.updater(updater, didAbortWithError: NSError(domain: "test", code: 1))
    precondition(!updates.preparation.canInstall)
    updates.updaterDidNotFindUpdate(updater)
    precondition(updates.availableVersion == nil && updates.preparation.phase == .idle)
    print("Sparkle callbacks and prepared restart integration passed (headless, no download or installation)")
  }
}

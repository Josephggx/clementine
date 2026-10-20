import AppKit
import Combine
import SwiftUI

final class UpdateCheckApp: NSObject, NSApplicationDelegate {
  let state = AppState()
  var window: NSWindow!
  var observations = Set<AnyCancellable>()
  let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestRoot") as! String)

  func record(_ text: String) {
    let line = "\(AppUpdates.installedVersion): \(text)\n"
    let path = root.appendingPathComponent("trace.log")
    if !FileManager.default.fileExists(atPath: path.path) {
      FileManager.default.createFile(atPath: path.path, contents: nil)
    }
    let file = try! FileHandle(forWritingTo: path)
    file.seekToEndOfFile(); file.write(Data(line.utf8)); try! file.close()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    state.showingOnboarding = false
    state.appearance = "dark"; state.applyAppearance()
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1136, height: 790),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "Vérification des mises à jour Clémentine"
    window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
    window.contentView = NSHostingView(rootView: MainView(state: state))
    window.center(); window.makeKeyAndOrderFront(nil)
    record("launch; CTA hidden=\(AppUpdates.shared.availableVersion == nil)")
    AppUpdates.shared.$availableVersion.dropFirst().sink { [weak self] version in
      self?.record("available=\(version ?? "none")")
    }.store(in: &observations)
    AppUpdates.shared.start(isBusy: { false }, isOnboarding: { false })
    if AppUpdates.installedVersion == "1.0.1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
        precondition(AppUpdates.shared.availableVersion == nil)
        record("PASS: relaunch on latest version; CTA hidden")
      }
    }
  }
}

@main struct UpdateCheckMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = UpdateCheckApp()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

import Foundation

/// Opt-in beta diagnostics. Contains event states/counts only, never paths or file contents.
enum WheelDiagnostics {
  private static let enabled = Bundle.main.object(forInfoDictionaryKey: "ClementineWheelDiagnostics") as? Bool == true
  static let url = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-Wheel-Diagnostic.log")
  private static let lock = NSLock()
  static func record(_ message: String) {
    guard enabled else { return }
    lock.lock(); defer { lock.unlock() }
    let data = Data(String(format: "%.3f %@\n", ProcessInfo.processInfo.systemUptime, message).utf8)
    if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    if let size = try? handle.seekToEnd(), size > 524288 { try? handle.truncate(atOffset: 0); try? handle.seek(toOffset: 0) }
    try? handle.write(contentsOf: data)
  }
}

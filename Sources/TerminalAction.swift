import Foundation

enum TerminalAction {
  static func directories(for urls: [URL]) throws -> [URL] {
    var seen = Set<String>()
    return try urls.map { url in
      let values = try url.resourceValues(forKeys: [.isDirectoryKey])
      return (values.isDirectory == true ? url : url.deletingLastPathComponent()).standardizedFileURL
    }.filter { seen.insert($0.path).inserted }
  }

  static func open(_ urls: [URL], completion: @escaping (Error?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let folders = try directories(for: urls)
        guard !folders.isEmpty else { DispatchQueue.main.async { completion(nil) }; return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Pass paths as separate arguments, never as shell commands. Terminal
        // opens one session per distinct folder, including selected folders.
        process.arguments = ["-b", "com.apple.Terminal"] + folders.map(\.path)
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
          let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
          throw NSError(domain: "Clementine.Terminal", code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: detail?.isEmpty == false ? detail! : "Impossible d’ouvrir Terminal."])
        }
        DispatchQueue.main.async { completion(nil) }
      } catch {
        DispatchQueue.main.async { completion(error) }
      }
    }
  }
}

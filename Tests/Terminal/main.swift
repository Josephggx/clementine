import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent(".build/terminal-check/fixtures", isDirectory: true)
let first = root.appendingPathComponent("Été et espaces ' $(echo test) ;", isDirectory: true)
let second = root.appendingPathComponent("Autre dossier", isDirectory: true)
for folder in [first, second] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
let a = first.appendingPathComponent("Image 1.png")
let b = first.appendingPathComponent("Document.pdf")
let c = second.appendingPathComponent("Tableur.csv")
for file in [a, b, c] { try Data().write(to: file) }
func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
check(try TerminalAction.directories(for: []) == [], "Empty selection")
check(try TerminalAction.directories(for: [a]) == [first], "Single file")
check(try TerminalAction.directories(for: [first]) == [first], "Selected folder itself")
check(try TerminalAction.directories(for: [a, b]) == [first], "Shared folder opens once")
check(try TerminalAction.directories(for: [a, b, c, first, second]) == [first, second], "Mixed selection preserves distinct folders")
do {
  _ = try TerminalAction.directories(for: [root.appendingPathComponent("missing.txt")])
  fatalError("Missing file should report an error")
} catch {}
print("PASS: single file, folder, multiple files, mixed folders, special characters and missing file")
if CommandLine.arguments.contains("--launch") {
  var finished = false
  var failure: Error?
  TerminalAction.open([a, b, c, first]) { error in failure = error; finished = true }
  let deadline = Date().addingTimeInterval(20)
  while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
  precondition(finished && failure == nil, "Terminal launch failed: \(String(describing: failure))")
  print("PASS: Terminal accepted the multiple-selection launch")
  for folder in [first, second] { print(folder.path) }
}

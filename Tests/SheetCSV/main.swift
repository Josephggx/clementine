import AppKit
import Foundation

func checkSheets() throws {
  let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHEET_CSV_ROOT"]!, isDirectory: true)
  let engine = Engine(), fm = FileManager.default
  let source = root.appendingPathComponent("Classeur.xlsx")
  let output = root.appendingPathComponent("Exports", isDirectory: true)
  try fm.createDirectory(at: output, withIntermediateDirectories: true)
  var options = Options(); options.outputFolder = output.path
  var checks: [String: Bool] = [:]
  let files = try engine.run([source], action: "convert:csv", options: options)
  checks["twoCSVFiles"] = files.count == 2
  checks["sheetNames"] = Set(files.map(\.lastPathComponent)) == ["Classeur-Clients.csv", "Classeur-Factures.csv"]
  checks["sheetContents"] = files.contains { (try? String(contentsOf: $0))?.contains("Alice,101") == true }
    && files.contains { (try? String(contentsOf: $0))?.contains("Bob,202") == true }
  let again = try engine.run([source], action: "convert:csv", options: options)
  checks["safeCollisionNames"] = again.count == 2 && Set(again.map(\.lastPathComponent)) == ["Classeur-Clients (1).csv", "Classeur-Factures (1).csv"]
  checks["originalUnchanged"] = fm.fileExists(atPath: source.path)
  for ext in ["xls", "ods"] {
    let converted = root.appendingPathComponent("Classeur." + ext)
    _ = try Documents.office(source, to: converted, engine: engine)
    let csvs = try engine.run([converted], action: "convert:csv", options: options)
    checks[ext + "Sheets"] = csvs.count == 2 && csvs.contains { (try? String(contentsOf: $0))?.contains("Alice,101") == true }
      && csvs.contains { (try? String(contentsOf: $0))?.contains("Bob,202") == true }
  }
  let report: [String: Any] = ["checks": checks, "passed": checks.values.filter { $0 }.count, "total": checks.count]
  try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("validation.json"))
}

if let root = Bundle.main.object(forInfoDictionaryKey: "SheetCSVRoot") as? String {
  let app = NSApplication.shared; app.setActivationPolicy(.regular)
  let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
  window.title = "Clémentine — Feuilles CSV"
  let label = NSTextField(wrappingLabelWithString: "Export des feuilles Excel et ODS…")
  label.frame = CGRect(x: 20, y: 45, width: 460, height: 90); window.contentView?.addSubview(label)
  let quit = NSButton(title: "Fermer le test", target: app, action: #selector(NSApplication.terminate(_:)))
  quit.frame = CGRect(x: 340, y: 10, width: 140, height: 30); window.contentView?.addSubview(quit)
  window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
  let sourceRoot = Bundle.main.object(forInfoDictionaryKey: "ClementineSourceRoot") as! String
  setenv("SHEET_CSV_ROOT", root, 1)
  setenv("CLEMENTINE_RESOURCES", sourceRoot + "/Resources", 1)
  setenv("CLEMENTINE_TOOLS", sourceRoot + "/Resources/Tools", 1)
  setenv("CLEMENTINE_OFFICE", "/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice", 1)
  DispatchQueue.global(qos: .userInitiated).async {
    do { try checkSheets(); DispatchQueue.main.async { label.stringValue = "Export terminé. Rapport disponible." } }
    catch {
      try? error.localizedDescription.write(toFile: root + "/failure.txt", atomically: true, encoding: .utf8)
      DispatchQueue.main.async { label.stringValue = "Échec : " + error.localizedDescription }
    }
  }
  app.run()
} else { try checkSheets() }

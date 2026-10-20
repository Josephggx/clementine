import AppKit
import Foundation
import PDFKit

enum ConversionParityTests {
  static func run() {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLEMENTINE_TEST_DIR"] ?? NSTemporaryDirectory() + "ClementineConversionChecks")
    let fixtures = root.appendingPathComponent("fixtures")
    let results = root.appendingPathComponent("results")
    let engine = Engine()
    var options = Options(); options.outputFolder = results.path
    var report: [[String: Any]] = []
    func require(_ condition: Bool, _ message: String) throws {
      if !condition { throw ClementineError(message) }
    }
    func test(_ name: String, _ body: () throws -> Void) {
      do { try body(); report.append(["name": name, "passed": true]); print("PASS \(name)") }
      catch { report.append(["name": name, "passed": false, "error": error.localizedDescription]); print("FAIL \(name): \(error.localizedDescription)") }
      fflush(stdout)
    }
    do {
      try engine.fm.createDirectory(at: fixtures, withIntermediateDirectories: true)
      try engine.fm.createDirectory(at: results, withIntermediateDirectories: true)
      let gif = fixtures.appendingPathComponent("Animation.gif")
      try engine.ff(["-f", "lavfi", "-i", "testsrc=size=128x96:rate=8", "-t", "1", gif.path])
      test("GIF animé vers MP4 en conservant l’animation") {
        let output = try engine.run([gif], action: "convert:mp4", options: options)[0]
        try require(engine.mediaDuration(output) > 0.7, "Animation perdue")
        let info = try engine.probe(output)
        try require((info["streams"] as? [[String: Any]])?.first?["codec_type"] as? String == "video", "Vidéo attendue")
      }
      if CommandLine.arguments.contains("--media-only") {
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("conversion-validation.json"))
        return
      }
      let text = fixtures.appendingPathComponent("Multipage.txt")
      try String(repeating: "Document de validation — Joseph — 123,45 €\n", count: 110).write(to: text, atomically: true, encoding: .utf8)
      let pdf = try engine.run([text], action: "convert:pdf", options: options)[0]
      guard let document = PDFDocument(url: pdf) else { throw ClementineError("PDF invalide") }
      test("PDF multipage vers PNG à 300 DPI") {
        let pages = try engine.run([pdf], action: "convert:png", options: options)
        try require(pages.count == document.pageCount, "Toutes les pages doivent être exportées")
        let image = try engine.loadImage(pages[0])
        let page = document.page(at: 0)!.bounds(for: .mediaBox)
        try require(abs(Double(image.width) - page.width * 300 / 72) < 2, "Résolution 300 DPI")
      }
      test("Document texte vers JPG, toutes les pages et noms lisibles") {
        let pages = try engine.run([text], action: "convert:jpg", options: options)
        try require(pages.count == document.pageCount, "Nombre de pages incorrect")
        try require(pages.allSatisfy { $0.lastPathComponent.hasPrefix("Multipage-") }, "Nom de source conservé")
      }
      test("PDF vers XLSX contenant le texte extrait") {
        let output = try engine.run([pdf], action: "convert:xlsx", options: options)[0]
        let xml = try engine.process("/usr/bin/unzip", ["-p", output.path, "xl/worksheets/sheet1.xml"])
        try require(xml.contains("Joseph"), "Le classeur doit contenir les cellules extraites")
      }
      test("PDF vers PPTX avec une diapositive par page") {
        let output = try engine.run([pdf], action: "convert:pptx", options: options)[0]
        let files = try engine.process("/usr/bin/unzip", ["-Z1", output.path])
        let slides = files.components(separatedBy: .newlines).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
        try require(slides.count == document.pageCount, "Toutes les pages doivent être présentes")
      }

    } catch { report.append(["name": "Préparation", "passed": false, "error": error.localizedDescription]); print("FAIL Préparation: \(error)") }
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: root.appendingPathComponent("conversion-validation.json"))
    }
    print("\(report.filter { $0["passed"] as? Bool == true }.count)/\(report.count) conversions vérifiées")
  }
}

import Foundation

extension AppState {
  func verifyNativeExports(root requested: URL? = nil) {
    let root =
      requested
      ?? FileManager.default.temporaryDirectory.appendingPathComponent(
        "Clémentine-exports-Apple-" + UUID().uuidString, isDirectory: true)
    page = "workspace"
    showWindow?()
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let fm = FileManager.default
        let engine = Engine()
        let input = root.appendingPathComponent("Sources", isDirectory: true)
        let output = root.appendingPathComponent("Résultats", isDirectory: true)
        try fm.createDirectory(at: input, withIntermediateDirectories: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let doc = input.appendingPathComponent("Démonstration.docx")
        let csv = input.appendingPathComponent("Démonstration.csv")
        let sheet = input.appendingPathComponent("Démonstration.xlsx")
        let slides = input.appendingPathComponent("Démonstration.odp")
        try Documents.write(
          "Clémentine — vérification des exports Apple\nCe document de démonstration a été créé automatiquement.\nAucun document personnel n’est utilisé.",
          to: doc, engine: engine)
        try "Module,Statut\nImages,Prêt\nAudio,Prêt\nPDF,Prêt\n".write(
          to: csv, atomically: true, encoding: .utf8)
        _ = try Documents.sheet(csv, to: sheet, engine: engine)
        let content = """
          <?xml version="1.0" encoding="UTF-8"?>
          <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" office:version="1.2"><office:body><office:presentation><draw:page draw:name="Clémentine" draw:master-page-name="Default"><draw:frame svg:x="2cm" svg:y="3cm" svg:width="22cm" svg:height="5cm"><draw:text-box><text:p>Clémentine</text:p><text:p>Vérification locale de l’export Keynote</text:p></draw:text-box></draw:frame></draw:page></office:presentation></office:body></office:document-content>
          """
        let styles = """
          <?xml version="1.0"?><office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" office:version="1.2"><office:automatic-styles><style:page-layout style:name="PM1"><style:page-layout-properties fo:page-width="28cm" fo:page-height="15.75cm" style:print-orientation="landscape"/></style:page-layout></office:automatic-styles><office:master-styles><style:master-page style:name="Default" style:page-layout-name="PM1"/></office:master-styles></office:document-styles>
          """
        let manifest = """
          <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.presentation"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/><manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/></manifest:manifest>
          """
        try Documents.package(
          [
            "mimetype": "application/vnd.oasis.opendocument.presentation", "content.xml": content,
            "styles.xml": styles, "META-INF/manifest.xml": manifest,
          ], to: slides, engine: engine)
        DispatchQueue.main.async {
          self.nativeVerificationRoot = root
          var settings = Options()
          settings.outputFolder = output.path
          for (file, ext) in [(doc, "pages"), (sheet, "numbers"), (slides, "key")] {
            self.submit("convert:" + ext, files: [file], overrideOptions: settings)
            if let id = self.jobs.first?.id { self.nativeVerificationIDs.insert(id) }
          }
          self.writeNativeVerification()
        }
      } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
    }
  }
  func writeNativeVerification() {
    guard let root = nativeVerificationRoot else { return }
    let report = jobs.filter { nativeVerificationIDs.contains($0.id) }.map { j -> [String: Any] in
      [
        "title": j.title, "done": j.done, "passed": j.done && !j.failed, "state": j.state,
        "outputs": j.outputs.map(\.path),
      ]
    }
    if let data = try? JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    {
      try? data.write(to: root.appendingPathComponent("verification.json"), options: .atomic)
    }
  }
}

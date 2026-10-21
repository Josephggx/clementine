import AppKit
import CoreText
import Foundation
import PDFKit

/// Local document conversion. Rich outputs keep artwork rather than passing through plain text.
enum Documents {
  /// CSV has no workbook container: export every sheet as its own file.
  static func sheetCSVs(_ source: URL, stage: URL, engine: Engine) throws -> [URL] {
    if source.pathExtension.lowercased() == "numbers" {
      let sheets = try NativeOffice.readNumbersSheets(source, engine: engine)
      let base = source.deletingPathExtension().lastPathComponent
      var used = Set<String>()
      func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
          ? "\"" + escaped + "\"" : escaped
      }
      return try sheets.enumerated().map { index, sheet in
        let rawName = sheet.name.replacingOccurrences(of: "/", with: "-")
          .replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = rawName.isEmpty ? "Feuille \(index + 1)" : rawName
        let stem = sheets.count == 1 ? base : base + "-" + label
        var name = stem + ".csv"
        var suffix = 2
        while used.contains(name.lowercased()) || engine.fm.fileExists(atPath: stage.appendingPathComponent(name).path) {
          name = stem + "-" + String(suffix) + ".csv"
          suffix += 1
        }
        used.insert(name.lowercased())
        let target = stage.appendingPathComponent(name)
        var lines: [String] = []
        for (tableIndex, rows) in sheet.tables.enumerated() {
          let nonempty = rows.indices.filter { rows[$0].contains(where: { !$0.isEmpty }) }
          guard let lastRow = nonempty.last else { continue }
          let width = rows[0...lastRow].flatMap { $0.enumerated().filter { !$0.element.isEmpty }.map(\.offset) }.max().map { $0 + 1 } ?? 0
          if tableIndex > 0 && !lines.isEmpty { lines.append("") }
          for row in rows[0...lastRow] {
            lines.append((0..<width).map { column in csvField(column < row.count ? row[column] : "") }.joined(separator: ","))
          }
        }
        try (lines.joined(separator: "\r\n") + "\r\n").write(to: target, atomically: true, encoding: .utf8)
        return target
      }
    }
    guard let binary = libreOffice else {
      throw ClementineError(tr("Le moteur bureautique est nécessaire pour exporter les feuilles en CSV."))
    }
    let root = stage.appendingPathComponent("sheets-" + UUID().uuidString, isDirectory: true)
    let out = root.appendingPathComponent("output", isDirectory: true)
    let profile = root.appendingPathComponent("profile", isDirectory: true)
    try engine.fm.createDirectory(at: out, withIntermediateDirectories: true)
    defer { try? engine.fm.removeItem(at: root) }

    let workbook: URL
    if source.pathExtension.lowercased() == "xlsx" {
      workbook = source
    } else {
      workbook = root.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".xlsx")
      _ = try office(source, to: workbook, engine: engine)
    }
    let workbookXML = try engine.process("/usr/bin/unzip", ["-p", workbook.path, "xl/workbook.xml"])
    let xml = try XMLDocument(xmlString: workbookXML, options: [])
    let sheetCount = try xml.nodes(forXPath: "//*[local-name()='sheets']/*[local-name()='sheet']").count
    guard sheetCount > 0 else { throw ClementineError(tr("Ce tableur ne contient aucune feuille.")) }

    // The twelfth Calc CSV filter option exports every sheet, including sheets after the first.
    let filter = "csv:Text - txt - csv (StarCalc):44,34,76,1,,0,false,true,true,false,false,-1"
    _ = try engine.process(binary, [
      "-env:UserInstallation=" + profile.absoluteString,
      "--headless", "--nologo", "--nodefault", "--norestore", "--nofirststartwizard",
      "--convert-to", filter, "--outdir", out.path, workbook.path,
    ], at: root, timeoutSeconds: 300)
    let produced = try engine.fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension.lowercased() == "csv" }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    guard produced.count == sheetCount else {
      throw ClementineError(tr("L’export CSV a produit \(produced.count) feuille(s) sur \(sheetCount). Aucun fichier incomplet n’a été enregistré."))
    }
    let base = source.deletingPathExtension().lastPathComponent
    return try produced.map { file in
      let name = sheetCount == 1 ? base + ".csv" : file.lastPathComponent
      let target = stage.appendingPathComponent(name)
      try engine.fm.moveItem(at: file, to: target)
      return target
    }
  }
  static func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
  static var libreOffice: String? {
    let candidates = [
      ProcessInfo.processInfo.environment["CLEMENTINE_OFFICE"] ?? "",
      Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice"
      ).path, "/Applications/LibreOffice.app/Contents/MacOS/soffice",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }
  @discardableResult static func office(_ source: URL, to dest: URL, engine: Engine, options: Options = Options(), rawHTML: Bool = false, nativePDFLayout: Bool = false) throws -> URL {
    let input = source.pathExtension.lowercased()
    let output = dest.pathExtension.lowercased()
    if ["pages", "numbers", "key"].contains(output) {
      try NativeOffice.convert(source, to: dest, engine: engine, options: options)
      return dest
    }
    if input == "pdf", !nativePDFLayout { return try DocumentFidelity.pdf(source, to: dest, options: options, engine: engine) }
    if input == "pages" {
      if ["docx", "pdf"].contains(output) { try NativeOffice.export(source, to: dest, engine: engine); return dest }
      let temp = dest.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".docx")
      defer { try? engine.fm.removeItem(at: temp) }
      try NativeOffice.export(source, to: temp, engine: engine)
      return try office(temp, to: dest, engine: engine, options: options)
    }
    if input == "numbers" {
      if ["xlsx", "pdf"].contains(output) {
        try NativeOffice.export(source, to: dest, engine: engine)
        return dest
      }
      let temp = dest.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".xlsx")
      defer { try? engine.fm.removeItem(at: temp) }
      try NativeOffice.export(source, to: temp, engine: engine)
      return try office(temp, to: dest, engine: engine, options: options)
    }
    if input == "key" {
      if ["pptx", "pdf"].contains(output) {
        try NativeOffice.export(source, to: dest, engine: engine)
        return dest
      }
      let temp = dest.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".pptx")
      defer { try? engine.fm.removeItem(at: temp) }
      try NativeOffice.export(source, to: temp, engine: engine)
      return try office(temp, to: dest, engine: engine, options: options)
    }
    if ["md", "epub", "rtfd", "textclipping"].contains(input) || output == "md" || (output == "html" && !rawHTML) {
      return try RichDocuments.convert(source, to: dest, options: options, engine: engine)
    }
    if Family.of(source) == .presentation, ["txt", "md", "epub"].contains(output) {
      if input == "pptx" {
        try write(read(source, engine: engine), to: dest, engine: engine)
        return dest
      }
      let temp = dest.deletingLastPathComponent().appendingPathComponent(
        UUID().uuidString + ".pptx")
      defer { try? engine.fm.removeItem(at: temp) }
      try office(source, to: temp, engine: engine, options: options)
      try write(read(temp, engine: engine), to: dest, engine: engine)
      return dest
    }
    if ["csv", "tsv"].contains(input), output == "xls" {
      let temp = dest.deletingLastPathComponent().appendingPathComponent(
        UUID().uuidString + ".xlsx")
      defer { try? engine.fm.removeItem(at: temp) }
      _ = try sheet(source, to: temp, engine: engine)
      return try office(temp, to: dest, engine: engine, options: options)
    }
    if ["pages", "numbers", "key"].contains(input), ["txt", "md", "epub"].contains(output) {
      let temp = dest.deletingLastPathComponent().appendingPathComponent(
        UUID().uuidString + "." + (Family.of(source) == .sheet ? "csv" : "docx"))
      defer { try? engine.fm.removeItem(at: temp) }
      try office(source, to: temp, engine: engine, options: options)
      try write(read(temp, engine: engine), to: dest, engine: engine)
      return dest
    }
    let officeInputs = [
      "doc", "docx", "rtf", "rtfd", "odt", "pages", "ppt", "pptx", "odp", "key", "xls", "xlsx",
      "ods", "numbers", "html",
    ]
    if let binary = libreOffice, (officeInputs.contains(input) || (input == "pdf" && (output == "pptx" || nativePDFLayout && output == "docx"))), output != "md" {
      let root = dest.deletingLastPathComponent().appendingPathComponent(
        "office-" + UUID().uuidString)
      let profile = root.appendingPathComponent("profile")
      let out = root.appendingPathComponent("output")
      let temporary = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("clo-" + String(UUID().uuidString.prefix(8)))
      defer { try? engine.fm.removeItem(at: temporary) }
      try engine.fm.createDirectory(at: temporary, withIntermediateDirectories: true)
      try engine.fm.createDirectory(at: out, withIntermediateDirectories: true)
      defer { try? engine.fm.removeItem(at: root) }
      var target = output
      if output == "epub" { target = "epub:EPUB" }
      if output == "docx" { target = "docx:Office Open XML Text" }
      if output == "csv" { target = "csv:Text - txt - csv (StarCalc):44,34,76" }
      if output == "tsv" { target = "csv:Text - txt - csv (StarCalc):9,34,76" }
      if output == "txt", Family.of(source) == .sheet {
        target = "txt:Text - txt - csv (StarCalc):9,34,76"
      }
      let importOptions = input == "html" ? ["--infilter=HTML (StarWriter)"] : input == "pdf" && nativePDFLayout ? ["--infilter=writer_pdf_import"] : []
      if input == "pdf", output == "pptx" { target = "pptx:Impress MS PowerPoint 2007 XML" }
      let log = try engine.process(
        binary,
        [
          "-env:UserInstallation=" + profile.absoluteString, "--headless", "--nologo",
          "--nodefault", "--norestore", "--nofirststartwizard",
        ] + importOptions + ["--convert-to", target, "--outdir",
          out.path, source.path,
        ], at: root, environment: ["TMPDIR": temporary.path + "/", "TMP": temporary.path, "TEMP": temporary.path], timeoutSeconds: 300)
      let name =
        source.deletingPathExtension().lastPathComponent + "." + (output == "tsv" ? "csv" : output)
      let generated = out.appendingPathComponent(name)
      guard engine.fm.fileExists(atPath: generated.path) else {
        throw ClementineError(
          tr("Le moteur bureautique ne peut pas convertir ce document vers \(output.uppercased()). \(log.suffix(1000))")
        )
      }
      if output == "html" {
        let folder = dest.deletingLastPathComponent().appendingPathComponent(
          dest.deletingPathExtension().lastPathComponent + "-HTML", isDirectory: true)
        try engine.fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in try engine.fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil) {
          try engine.fm.moveItem(
            at: item, to: folder.appendingPathComponent(item.lastPathComponent))
        }
        return folder
      }
      try engine.fm.moveItem(at: generated, to: dest)
      if nativePDFLayout && output == "docx" {try normalizePDFLayout(dest,engine:engine)}
      return dest
    }
    if output == "epub", ["txt", "rtf", "rtfd"].contains(input) {
      return try RichDocuments.convert(source, to: dest, options: options, engine: engine)
    }
    if Family.of(source) == .sheet { return try sheet(source, to: dest, engine: engine) }
    try convert(source, to: dest, engine: engine)
    return dest
  }
  static func convert(_ source: URL, to dest: URL, engine: Engine) throws {
    let input = source.pathExtension.lowercased()
    let output = dest.pathExtension.lowercased()
    let native = ["txt", "rtf", "rtfd", "doc", "docx", "odt", "html"]
    if native.contains(input), ["txt", "rtf", "doc", "docx", "odt", "html"].contains(output) {
      try engine.process(
        "/usr/bin/textutil", ["-convert", output, "-output", dest.path, source.path])
      return
    }
    try write(read(source, engine: engine), to: dest, engine: engine)
  }
  static func read(_ source: URL, engine: Engine) throws -> String {
    let ext = source.pathExtension.lowercased()
    if ["txt", "md", "srt", "vtt", "csv", "tsv"].contains(ext) {
      let data = try Data(contentsOf: source)
      guard
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
          ?? String(data: data, encoding: .isoLatin1)
      else { throw ClementineError(tr("Encodage texte inconnu")) }
      return text
    }
    if ext == "pdf" {
      guard let pdf = PDFDocument(url: source), !pdf.isLocked else {
        throw ClementineError(tr("PDF verrouillé"))
      }
      return try PDFText.text(pdf, engine: engine)
    }
    if ["doc", "docx", "odt", "rtf", "rtfd", "html", "textclipping"].contains(ext) {
      return try engine.process("/usr/bin/textutil", ["-convert", "txt", "-stdout", source.path])
    }
    if ext == "epub" || ext == "pptx" || ext == "pages" {
      let temp = engine.fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try engine.fm.createDirectory(at: temp, withIntermediateDirectories: true)
      defer { try? engine.fm.removeItem(at: temp) }
      let extracted = try engine.extract(source, stage: temp)
      if ext == "pages" {
        let preview = extracted.appendingPathComponent("QuickLook/Preview.pdf")
        if let pdf = PDFDocument(url: preview), let text = pdf.string { return text }
        throw ClementineError(
          tr("Ce fichier Pages ne contient pas d’aperçu PDF. Exportez-le en DOCX depuis Pages."))
      }
      guard let en = engine.fm.enumerator(at: extracted, includingPropertiesForKeys: nil) else {
        throw ClementineError(tr("Archive illisible"))
      }
      let files = en.compactMap { $0 as? URL }.filter {
        ext == "pptx"
          ? ($0.path.contains("/ppt/slides/slide") && $0.pathExtension == "xml"
            && !$0.path.contains("_rels")) : ["xhtml", "html", "htm"].contains($0.pathExtension)
      }.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
      return try files.map { try xmlText($0) }.joined(separator: "\n\n")
    }
    throw ClementineError(
      tr("L’import \(ext.uppercased()) nécessite un export intermédiaire DOCX, XLSX ou PDF."))
  }
  static func xmlText(_ u: URL) throws -> String {
    let data = try Data(contentsOf: u)
    if let xml = try? XMLDocument(data: data, options: [.documentTidyHTML]) {
      let nodes =
        (try? xml.nodes(
          forXPath:
            "//*[local-name()='t' or local-name()='p' or local-name()='h1' or local-name()='h2' or local-name()='li']"
        )) ?? []
      if !nodes.isEmpty {
        return nodes.filter { node in
          !(node.children ?? []).contains {
            ["p", "t"].contains($0.name?.components(separatedBy: ":").last ?? "")
          }
        }.compactMap(\.stringValue).joined(separator: "\n")
      }
      return xml.rootElement()?.stringValue ?? ""
    }
    return String(data: data, encoding: .utf8)?.replacingOccurrences(
      of: "<[^>]+>", with: "", options: .regularExpression) ?? ""
  }
  static func write(_ text: String, to dest: URL, engine: Engine) throws {
    let ext = dest.pathExtension.lowercased()
    if ["txt", "md"].contains(ext) {
      try text.write(to: dest, atomically: true, encoding: .utf8)
    } else if ext == "pdf" {
      try pdf(text, to: dest)
    } else if ext == "html" {
      let html =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>Document</title></head><body><main style=\"white-space:pre-wrap;font:16px system-ui;max-width:800px;margin:40px auto\">\(escape(text))</main></body></html>"
      try html.write(to: dest, atomically: true, encoding: .utf8)
    } else if ["doc", "docx", "odt", "rtf"].contains(ext) {
      let temp = dest.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".txt")
      defer { try? engine.fm.removeItem(at: temp) }
      try text.write(to: temp, atomically: true, encoding: .utf8)
      try engine.process("/usr/bin/textutil", ["-convert", ext, "-output", dest.path, temp.path])
    } else if ext == "epub" {
      try epub(text, to: dest, engine: engine)
    } else {
      throw ClementineError(tr("Export \(ext) non disponible"))
    }
  }
  static func pdf(_ text: String, to dest: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let c = CGContext(dest as CFURL, mediaBox: &box, nil) else {
      throw ClementineError(tr("Création du PDF impossible"))
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    let a = NSAttributedString(
      string: text.isEmpty ? " " : text,
      attributes: [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph,
      ])
    let framesetter = CTFramesetterCreateWithAttributedString(a)
    var offset = 0
    while offset < a.length {
      c.beginPDFPage(nil)
      let path = CGPath(rect: box.insetBy(dx: 44, dy: 44), transform: nil)
      let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: offset, length: 0), path, nil)
      CTFrameDraw(frame, c)
      let range = CTFrameGetVisibleStringRange(frame)
      c.endPDFPage()
      guard range.length > 0 else { throw ClementineError(tr("La pagination du document a échoué")) }
      offset += range.length
    }
    c.closePDF()
  }
  static func package(_ files: [String: String], to dest: URL, engine: Engine) throws {
    let root = dest.deletingLastPathComponent().appendingPathComponent(
      "package-" + UUID().uuidString)
    try engine.fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? engine.fm.removeItem(at: root) }
    for (name, value) in files {
      let file = root.appendingPathComponent(name)
      try engine.fm.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try value.write(to: file, atomically: true, encoding: .utf8)
    }
    try engine.process(
      "/usr/bin/zip",
      ["-q", "-X", "-0", dest.path, "mimetype"].filter {
        $0 != "mimetype" || files["mimetype"] != nil
      }, at: root)
    try engine.process(
      "/usr/bin/zip", ["-q", "-X", "-r", dest.path, ".", "-x", "mimetype"], at: root)
  }
  static func epub(_ text: String, to dest: URL, engine: Engine) throws {
    let id = UUID().uuidString
    let files = [
      "mimetype": "application/epub+zip",
      "META-INF/container.xml":
        "<?xml version=\"1.0\"?><container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"EPUB/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>",
      "EPUB/content.opf":
        "<?xml version=\"1.0\"?><package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"id\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"id\">urn:uuid:\(id)</dc:identifier><dc:title>Document</dc:title><dc:language>fr</dc:language><meta property=\"dcterms:modified\">2026-10-18T00:00:00Z</meta></metadata><manifest><item id=\"chapter\" href=\"chapter.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/></manifest><spine><itemref idref=\"chapter\"/></spine></package>",
      "EPUB/chapter.xhtml":
        "<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Document</title></head><body>\(text.components(separatedBy:"\n").map{"<p>\(escape($0))</p>"}.joined())</body></html>",
      "EPUB/nav.xhtml":
        "<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>Sommaire</title></head><body><nav epub:type=\"toc\"><ol><li><a href=\"chapter.xhtml\">Document</a></li></ol></nav></body></html>",
    ]
    try package(files, to: dest, engine: engine)
  }
  static func csvParse(_ text: String, delimiter: Character) throws -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c == "\"" {
        if quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
          field.append("\"")
          i += 1
        } else {
          quoted.toggle()
        }
      } else if c == delimiter && !quoted {
        row.append(field)
        field = ""
      } else if (c == "\n" || c == "\r") && !quoted {
        row.append(field)
        rows.append(row)
        row = []
        field = ""
        if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
      } else {
        field.append(c)
      }
      i += 1
    }
    guard !quoted else {
      throw ClementineError(tr("Le CSV contient un champ entre guillemets non fermé"))
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }
  static func csvWrite(_ rows: [[String]], delimiter: String) -> String {
    rows.map {
      $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(
        separator: delimiter)
    }.joined(separator: "\r\n")
  }
  static func sheet(_ source: URL, to dest: URL, engine: Engine) throws -> URL {
    let ext = source.pathExtension.lowercased()
    var rows: [[String]] = []
    if ext == "csv" || ext == "tsv" {
      let text = try read(source, engine: engine)
      let delim: Character =
        ext == "tsv"
        ? "\t"
        : ((text.components(separatedBy: .newlines).first ?? "").filter { $0 == ";" }.count
          > (text.components(separatedBy: .newlines).first ?? "").filter { $0 == "," }.count
          ? ";" : ",")
      rows = try csvParse(text, delimiter: delim)
    } else if ext == "xlsx" || ext == "ods" {
      let temp = engine.fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try engine.fm.createDirectory(at: temp, withIntermediateDirectories: true)
      defer { try? engine.fm.removeItem(at: temp) }
      let root = try engine.extract(source, stage: temp)
      if ext == "xlsx" {
        var shared: [String] = []
        if let xml = try? XMLDocument(
          contentsOf: root.appendingPathComponent("xl/sharedStrings.xml"), options: [])
        {
          shared = ((try? xml.nodes(forXPath: "//*[local-name()='si']")) ?? []).map {
            $0.stringValue ?? ""
          }
        }
        let sheetURL = root.appendingPathComponent("xl/worksheets/sheet1.xml")
        let xml = try XMLDocument(contentsOf: sheetURL, options: [])
        for row in (try xml.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']"))
        {
          var values: [String] = []
          for node in row.children ?? [] {
            guard let c = node as? XMLElement, c.name?.components(separatedBy: ":").last == "c"
            else { continue }
            let ref = c.attribute(forName: "r")?.stringValue ?? "A1"
            let letters = ref.prefix { $0.isLetter }
            let index = letters.reduce(0) { $0 * 26 + Int($1.asciiValue ?? 65) - 64 } - 1
            guard index >= 0, index < 16384 else { throw ClementineError(tr("Colonne XLSX invalide")) }
            while values.count <= index { values.append("") }
            let v =
              (try? c.nodes(forXPath: ".//*[local-name()='v' or local-name()='t']"))?.first?
              .stringValue ?? ""
            if c.attribute(forName: "t")?.stringValue == "s", let j = Int(v),
              shared.indices.contains(j)
            {
              values[index] = shared[j]
            } else {
              values[index] = v
            }
          }
          rows.append(values)
        }
      } else {
        let xml = try XMLDocument(
          contentsOf: root.appendingPathComponent("content.xml"), options: [])
        for row in try xml.nodes(
          forXPath: "//*[local-name()='table'][1]/*[local-name()='table-row']")
        {
          var values: [String] = []
          for c in (row.children ?? []).compactMap({ $0 as? XMLElement }) {
            let repeated =
              Int(c.attribute(forName: "table:number-columns-repeated")?.stringValue ?? "1") ?? 1
            guard repeated <= 16384, values.count + repeated <= 16384 else {
              throw ClementineError(tr("Trop de colonnes dans le fichier ODS"))
            }
            let v =
              (try? c.nodes(forXPath: ".//*[local-name()='p']"))?.compactMap(\.stringValue).joined(
                separator: "\n") ?? ""
            values += Array(repeating: v, count: repeated)
          }
          rows.append(values)
        }
      }
    } else {
      throw ClementineError(
        tr("Exportez ce tableur en XLSX ou CSV avant conversion. Les formats XLS et Numbers ne sont pas encore importés.")
      )
    }
    guard rows.count <= 1_048_576 else { throw ClementineError(tr("Trop de lignes")) }
    switch dest.pathExtension {
    case "csv", "tsv", "txt":
      try csvWrite(rows, delimiter: dest.pathExtension == "csv" ? "," : "\t").write(
        to: dest, atomically: true, encoding: .utf8)
    case "pdf":
      try pdf(rows.map { $0.joined(separator: "  |  ") }.joined(separator: "\n"), to: dest)
    case "xlsx":
      var files: [String: String] = [:]
      files["[Content_Types].xml"] =
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"
      files["_rels/.rels"] =
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
      files["xl/workbook.xml"] =
        "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Feuille 1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
      files["xl/_rels/workbook.xml.rels"] =
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
      files["xl/worksheets/sheet1.xml"] =
        "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        + rows.enumerated().map { i, row in
          "<row r=\"\(i+1)\">"
            + row.enumerated().map { j, value in
              "<c r=\"\(column(j))\(i+1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
            }.joined() + "</row>"
        }.joined() + "</sheetData></worksheet>"
      try zipPackage(files, to: dest, engine: engine)
    case "ods":
      let content =
        "<?xml version=\"1.0\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" office:version=\"1.2\"><office:body><office:spreadsheet><table:table table:name=\"Feuille 1\">"
        + rows.map { row in
          "<table:table-row>"
            + row.map {
              "<table:table-cell office:value-type=\"string\"><text:p>\(escape($0))</text:p></table:table-cell>"
            }.joined() + "</table:table-row>"
        }.joined() + "</table:table></office:spreadsheet></office:body></office:document-content>"
      try package(
        [
          "mimetype": "application/vnd.oasis.opendocument.spreadsheet", "content.xml": content,
          "META-INF/manifest.xml":
            "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\"><manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.spreadsheet\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>",
        ], to: dest, engine: engine)
    default: throw ClementineError(tr("Format tableur inconnu"))
    }
    return dest
  }
  static func zipPackage(_ files: [String: String], to dest: URL, engine: Engine) throws {
    let root = dest.deletingLastPathComponent().appendingPathComponent(
      "package-" + UUID().uuidString)
    try engine.fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? engine.fm.removeItem(at: root) }
    for (name, value) in files {
      let f = root.appendingPathComponent(name)
      try engine.fm.createDirectory(
        at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
      try value.write(to: f, atomically: true, encoding: .utf8)
    }
    try engine.process("/usr/bin/zip", ["-q", "-X", "-r", dest.path, "."], at: root)
  }
  static func column(_ index: Int) -> String {
    var n = index + 1
    var value = ""
    while n > 0 {
      n -= 1
      value = String(UnicodeScalar(65 + n % 26)!) + value
      n /= 26
    }
    return value
  }
}

extension Documents {
  /// Writer's PDF importer retains native shapes and fonts but uses paragraph-relative
  /// anchors with default margins. PDF coordinates are page-relative instead.
  static func normalizePDFLayout(_ file:URL,engine:Engine) throws {
    let root=file.deletingLastPathComponent().appendingPathComponent("layout-"+UUID().uuidString)
    try engine.fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? engine.fm.removeItem(at:root)}
    try engine.process("/usr/bin/unzip",["-q",file.path,"-d",root.path])
    let path=root.appendingPathComponent("word/document.xml")
    let doc=try XMLDocument(contentsOf:path,options:.nodeLoadExternalEntitiesNever)
    func nodes(_ name:String)throws->[XMLElement] {try doc.nodes(forXPath:"//*[local-name()='\(name)']").compactMap{$0 as? XMLElement}}
    func set(_ e:XMLElement,_ name:String,_ value:String) {
      if let attribute=e.attribute(forName:name) {attribute.stringValue=value}
      else {e.addAttribute(XMLNode.attribute(withName:name,stringValue:value) as! XMLNode)}
    }
    for margin in try nodes("pgMar") {for edge in ["top","right","bottom","left","header","footer","gutter"] {set(margin,"w:"+edge,"0")}}
    for name in ["positionH","positionV"] {for position in try nodes(name) {set(position,"relativeFrom","page")}}
    for (index,anchor) in try nodes("anchor").enumerated() {
      if !(try anchor.nodes(forXPath:".//*[local-name()='txbxContent']")).isEmpty {
        set(anchor,"behindDoc","0")
        set(anchor,"relativeHeight",String(251658240+index))
      }
      for wrap in try anchor.nodes(forXPath:"./*[local-name()='wrapSquare' or local-name()='wrapTopAndBottom' or local-name()='wrapTight']") {
        let index=wrap.index
        wrap.detach();anchor.insertChild(XMLElement(name:"wp:wrapNone"),at:index)
      }
    }
    for body in try nodes("bodyPr") {set(body,"wrap","none")}
    for font in try nodes("rFonts") {
      for key in ["ascii","hAnsi","cs","eastAsia"] {
        let current=font.attribute(forName:"w:"+key)?.stringValue ?? ""
        let mapped=["Helvetica":"Arial","Times":"Times New Roman","Courier":"Courier New"][current]
        if let mapped,NSFont(name:mapped,size:12) != nil {set(font,"w:"+key,mapped)}
      }
    }
    for (index,shape) in try nodes("shape").enumerated() {
      let style=shape.attribute(forName:"style")?.stringValue ?? ""
      if style.contains("position:absolute") {
        let text = !(try shape.nodes(forXPath:".//*[local-name()='txbxContent']")).isEmpty
        let fill = shape.attribute(forName:"fillcolor")?.stringValue?.lowercased() ?? ""
        let layer = text ? ";z-index:\(251658240+index)" : (fill == "white" ? ";z-index:-1000" : ";z-index:-999")
        set(shape,"style",style+";mso-position-horizontal-relative:page;mso-position-vertical-relative:page"+layer)
      }
    }
    try doc.xmlData(options:.nodeCompactEmptyElement).write(to:path)
    let normalized=file.deletingLastPathComponent().appendingPathComponent("normalized-"+UUID().uuidString+".docx")
    defer {try? engine.fm.removeItem(at:normalized)}
    try DocumentFidelity.zip(root,to:normalized,engine:engine)
    try engine.fm.removeItem(at:file);try engine.fm.moveItem(at:normalized,to:file)
  }
}

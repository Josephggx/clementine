import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit

enum SelfTests {
  static func run() {
    let fm = FileManager.default
    let root = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["CLEMENTINE_TEST_DIR"]
        ?? NSTemporaryDirectory() + "ClementineValidation-" + UUID().uuidString, isDirectory: true)
    let fixtures = root.appendingPathComponent("fixtures")
    let results = root.appendingPathComponent("results")
    var checks: [[String: Any]] = []
    func test(_ name: String, _ body: () throws -> Void) {
      do {
        try body()
        checks.append(["name": name, "passed": true])
        print("PASS \(name)")
        fflush(stdout)
      } catch {
        checks.append(["name": name, "passed": false, "error": error.localizedDescription])
        print("FAIL \(name) : \(error.localizedDescription)")
        fflush(stdout)
      }
    }
    func require(_ condition: Bool, _ message: String = "Résultat invalide") throws {
      if !condition { throw ClementineError(message) }
    }
    let e = Engine()
    var options = Options()
    options.outputFolder = results.path
    do {
      try fm.createDirectory(at: fixtures, withIntermediateDirectories: true)
      try fm.createDirectory(at: results, withIntermediateDirectories: true)
      let source = fixtures.appendingPathComponent("Image source.png")
      let image = try e.canvas(width: 960, height: 640) { c in
        for y in stride(from: 0, to: 640, by: 8) {
          for x in stride(from: 0, to: 960, by: 8) {
            c.setFillColor(
              CGColor(
                red: Double((x * 13 + y * 7) % 255) / 255, green: Double((x + y * 11) % 255) / 255,
                blue: Double((x * 3 + y) % 255) / 255, alpha: 1))
            c.fill(CGRect(x: x, y: y, width: 8, height: 8))
          }
        }
      }
      try e.saveImage(image, to: source, o: options)
      let text = fixtures.appendingPathComponent("Document.txt")
      try
        ("Clémentine — document de validation\nÉté, accents et caractères : € 漢字\n"
        + String(repeating: "Une conversion locale protège les fichiers.\n", count: 100)).write(
          to: text, atomically: true, encoding: .utf8)
      let csv = fixtures.appendingPathComponent("Tableau.csv")
      try "nom,note,description\r\nJoseph,42,\"deux, mots\"\r\nLéa,7,\"une ligne\nune autre\"\r\n"
        .write(to: csv, atomically: true, encoding: .utf8)
      let vtt = fixtures.appendingPathComponent("Sous-titres.vtt")
      try
        "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nBonjour\n\n00:00:03.000 --> 00:00:04.000\nClémentine\n"
        .write(to: vtt, atomically: true, encoding: .utf8)
      let video = fixtures.appendingPathComponent("Vidéo.mp4")
      let audio = fixtures.appendingPathComponent("Audio.wav")
      try e.ff([
        "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=24:duration=4", "-f", "lavfi", "-i",
        "sine=frequency=440:duration=4", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
        "-shortest", video.path,
      ])
      try e.ff(["-f", "lavfi", "-i", "sine=frequency=660:duration=4", "-ac", "2", audio.path])
      func run(_ inputs: [URL], _ action: String, _ settings: Options? = nil) throws -> [URL] {
        try e.run(inputs, action: action, options: settings ?? options)
      }
      for ext in ["jpg", "webp", "heic", "tiff", "bmp", "gif", "avif", "svg"] {
        test("Image PNG → \(ext)") {
          let files = try run([source], "convert:" + ext)
          try require(e.bytes(files[0]) > 0)
          if ext != "svg" {
            let decoded = try e.loadImage(files[0])
            try require(decoded.width == 960 && decoded.height == 640)
          }
        }
      }
      test("Lot + noms non écrasés") {
        let a = try run([source, source], "convert:jpg")
        try require(a.count == 2 && Set(a).count == 2)
        let b = try run([source], "convert:jpg")
        try require(!a.contains(b[0]))
        try require(fm.fileExists(atPath: source.path))
      }
      test("Recadrage exact") {
        var o = options
        o.x = 30
        o.y = 20
        o.width = 200
        o.height = 100
        let u = try run([source], "crop", o)[0]
        let im = try e.loadImage(u)
        try require(im.width == 200 && im.height == 100)
      }
      test("Recadrage hors limites refusé") {
        var o = options
        o.width = 2000
        o.height = 2000
        do {
          _ = try run([source], "crop", o)
          throw ClementineError("Le rectangle invalide a été accepté")
        } catch let err as ClementineError { try require(err.message.contains("dépasse")) }
      }
      test("Redimensionnement avec proportions") {
        var o = options
        o.width = 240
        o.height = 0
        let u = try run([source], "resize", o)[0]
        let im = try e.loadImage(u)
        try require(im.width == 240 && im.height == 160)
      }
      test("Rotation image 90°") {
        var o = options
        o.rotation = 90
        let u = try run([source], "rotate", o)[0]
        let im = try e.loadImage(u)
        try require(im.width == 640 && im.height == 960)
      }
      test("Ajustements image") {
        var o = options
        o.brightness = 0.2
        o.saturation = 0
        let u = try run([source], "adjust", o)[0]
        try require(e.bytes(u) > 0)
      }
      test("Annotation aplatie") {
        var o = options
        o.text = "Clémentine"
        o.x = 10
        o.y = 10
        let u = try run([source], "annotate", o)[0]
        try require(e.bytes(u) > 0)
      }
      test("Caviardage rectangle") {
        var o = options
        o.x = 10
        o.y = 10
        o.width = 200
        o.height = 100
        let u = try run([source], "redact", o)[0]
        try require(e.bytes(u) > 0)
      }
      test("Cadre et dimensions") {
        var o = options
        o.padding = 20
        let u = try run([source], "frame", o)[0]
        let im = try e.loadImage(u)
        try require(im.width == 1000 && im.height == 680)
      }
      test("Collage") {
        let u = try run([source, source, source], "collage")[0]
        let im = try e.loadImage(u)
        try require(im.width > 1000 && im.height > 1000)
      }
      test("Image taille cible vérifiée") {
        var o = options
        o.targetMB = 0.08
        let u = try run([source], "target", o)[0]
        try require(e.bytes(u) <= 80000)
      }
      test("Lecture métadonnées image") {
        let u = try run([source], "metadata")[0]
        try require((try String(contentsOf: u, encoding: .utf8)).contains("960"))
      }
      test("Écriture métadonnées image") {
        var o = options
        o.title = "Validation"
        o.author = "Joseph"
        let u = try run([source], "metadata", o)[0]
        let s = CGImageSourceCreateWithURL(u as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil)!
        try require(String(describing: p).contains("Joseph"))
      }
      test("Retrait métadonnées image") {
        let u = try run([source], "strip")[0]
        try require(e.bytes(u) > 0)
      }
      test("QR code") {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue("https://example.com/clementine".data(using: .utf8), forKey: "inputMessage")
        let ci = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let image = CIContext().createCGImage(ci, from: ci.extent)!
        let u = fixtures.appendingPathComponent("QR.png")
        try e.saveImage(image, to: u, o: options)
        let result = try run([u], "qr")[0]
        try require(
          (try String(contentsOf: result, encoding: .utf8)).contains("example.com/clementine"))
      }
      var generatedPDF: URL?
      test("Texte → PDF paginé") {
        let u = try run([text], "convert:pdf")[0]
        guard let pdf = PDFDocument(url: u) else { throw ClementineError("PDF invalide") }
        try require(pdf.pageCount >= 2)
        try require(pdf.string?.contains("Clémentine") == true)
        generatedPDF = u
      }
      for ext in ["doc", "docx", "odt", "rtf", "html", "epub", "md"] {
        test("Texte → \(ext)") {
          let u = try run([text], "convert:" + ext)[0]
          try require(e.bytes(u) > 0)
          if ext == "epub" {
            let decoded = try Documents.read(u, engine: e)
            try require(decoded.contains("Clémentine"))
          }
          if ext == "docx" {
            let decoded = try Documents.read(u, engine: e)
            try require(decoded.contains("Clémentine"))
          }
        }
      }
      if let pdf = generatedPDF {
        test("PDF → PNG") {
          let files = try run([pdf], "convert:png")
          try require(files.count == (PDFDocument(url: pdf)?.pageCount ?? 0))
        }
        test("PDF division") {
          let files = try run([pdf], "split")
          try require(files.count >= 2)
          try require(files.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 })
        }
        test("PDF réorganisation et rotation") {
          var o = options
          o.pages = "2,1"
          o.rotation = 90
          let u = try run([pdf], "organize", o)[0]
          try require(PDFDocument(url: u)?.pageCount == 2)
          try require(PDFDocument(url: u)?.page(at: 0)?.rotation == 90)
        }
        test("Fusion PDF et image") {
          let u = try run([pdf, source], "mergepdf")[0]
          try require(PDFDocument(url: u)?.pageCount == (PDFDocument(url: pdf)?.pageCount ?? 0) + 1)
        }
        test("Métadonnées PDF") {
          var o = options
          o.title = "Titre PDF"
          o.author = "Joseph"
          let u = try run([pdf], "metadata", o)[0]
          try require(
            PDFDocument(url: u)?.documentAttributes?[PDFDocumentAttribute.authorAttribute]
              as? String == "Joseph")
        }
        test("PDF → DOCX") {
          let u = try run([pdf], "convert:docx")[0]
          try require((try Documents.read(u, engine: e)).contains("Clémentine"))
        }
      }
      test("CSV avec guillemets et retours ligne") {
        let rows = try Documents.csvParse(
          try String(contentsOf: csv, encoding: .utf8), delimiter: ",")
        try require(rows.count == 3 && rows[1][2] == "deux, mots" && rows[2][2].contains("\n"))
      }
      for ext in ["xlsx", "xls", "ods", "tsv", "pdf"] {
        test("CSV → \(ext)") {
          let u = try run([csv], "convert:" + ext)[0]
          try require(e.bytes(u) > 0)
          if ext == "xlsx" || ext == "ods" {
            let out = try run([u], "convert:csv")[0]
            let decoded = try String(contentsOf: out, encoding: .utf8)
            try require(decoded.contains("Joseph") && decoded.contains("deux, mots"))
          }
        }
      }
      test("DOCX → PDF via LibreOffice") {
        let docx = try run([text], "convert:docx")[0]
        let pdf = try run([docx], "convert:pdf")[0]
        try require(PDFDocument(url: pdf)?.string?.contains("Clémentine") == true)
      }
      test("DOCX → ODT → DOCX via LibreOffice") {
        let docx = try run([text], "convert:docx")[0]
        let odt = try run([docx], "convert:odt")[0]
        let back = try run([odt], "convert:docx")[0]
        try require((try Documents.read(back, engine: e)).contains("Clémentine"))
      }
      test("XLSX → XLS → PDF via LibreOffice") {
        let xlsx = try run([csv], "convert:xlsx")[0]
        let xls = try run([xlsx], "convert:xls")[0]
        let pdf = try run([xls], "convert:pdf")[0]
        try require(PDFDocument(url: pdf)?.pageCount ?? 0 > 0)
      }
      test("VTT → SRT → VTT") {
        let srt = try run([vtt], "convert:srt")[0]
        let content = try String(contentsOf: srt, encoding: .utf8)
        try require(content.contains("00:00:01,000"))
        let out = try run([srt], "convert:vtt")[0]
        try require((try String(contentsOf: out, encoding: .utf8)).hasPrefix("WEBVTT"))
      }
      for ext in ["mov", "mkv", "avi", "wmv", "webm", "gif", "mp3"] {
        test("Vidéo → \(ext)") {
          let u = try run([video], "convert:" + ext)[0]
          try require(e.bytes(u) > 0)
          _ = try e.probe(u)
        }
      }
      for ext in ["mp3", "m4a", "flac", "ogg", "opus", "aiff", "wma"] {
        test("Audio WAV → \(ext)") {
          let u = try run([audio], "convert:" + ext)[0]
          try require(try e.mediaDuration(u) > 3.8)
        }
      }
      test("Vidéo découpe") {
        var o = options
        o.start = 1
        o.duration = 1.5
        let u = try run([video], "trim", o)[0]
        try require(abs(try e.mediaDuration(u) - 1.5) < 0.2)
      }
      test("Vidéo segments") {
        var o = options
        o.times = "1,2"
        let files = try run([video], "split", o)
        try require(files.count == 3)
      }
      test("Audio segments") {
        var o = options
        o.times = "1,2"
        let files = try run([audio], "split", o)
        try require(files.count == 3)
      }
      test("Vidéo vitesse avec audio") {
        var o = options
        o.speed = 2
        let u = try run([video], "speed", o)[0]
        try require(abs(try e.mediaDuration(u) - 2) < 0.3)
      }
      test("Vidéo capture d’images") {
        var o = options
        o.times = "0,2"
        let files = try run([video], "snapshot", o)
        try require(files.count == 2)
        try require(try e.loadImage(files[0]).width == 320)
      }
      test("Vidéo retrait piste audio") {
        let u = try run([video], "mute")[0]
        let p = try e.probe(u)
        let streams = p["streams"] as? [[String: Any]] ?? []
        try require(!streams.contains { $0["codec_type"] as? String == "audio" })
      }
      test("Vidéo recadrage") {
        var o = options
        o.width = 160
        o.height = 120
        let u = try run([video], "crop", o)[0]
        let p = try e.probe(u)
        let stream = (p["streams"] as! [[String: Any]])[0]
        try require(stream["width"] as? Int == 160)
      }
      test("Vidéo caviardage temporisé") {
        var o = options
        o.width = 100
        o.height = 100
        o.duration = 2
        let u = try run([video], "redact", o)[0]
        try require(e.bytes(u) > 0)
      }
      test("Rotation vidéo 90°") {
        var o = options
        o.rotation = 90
        let u = try run([video], "rotate", o)[0]
        let p = try e.probe(u)
        let s = (p["streams"] as! [[String: Any]])[0]
        try require(s["width"] as? Int == 240 && s["height"] as? Int == 320)
      }
      test("Redimensionnement vidéo proportionnel") {
        var o = options
        o.width = 160
        o.height = 0
        let u = try run([video], "resize", o)[0]
        let p = try e.probe(u)
        let s = (p["streams"] as! [[String: Any]])[0]
        try require(s["width"] as? Int == 160 && s["height"] as? Int == 120)
      }
      test("Normalisation audio") {
        let u = try run([audio], "normalize")[0]
        try require(try e.mediaDuration(u) > 3.8)
      }
      test("Bip audio") {
        var o = options
        o.start = 1
        o.duration = 1
        let u = try run([audio], "bleep", o)[0]
        try require(abs(try e.mediaDuration(u) - 4) < 0.2)
      }
      test("Canaux mono") {
        var o = options
        o.channels = 1
        let u = try run([audio], "channels", o)[0]
        let p = try e.probe(u)
        let s = (p["streams"] as! [[String: Any]])[0]
        try require(s["channels"] as? Int == 1)
      }
      test("Retrait silences") {
        let u = try run([audio], "silence")[0]
        try require(e.bytes(u) > 0)
      }
      test("Audio visualisation vidéo") {
        let u = try run([audio], "visualize")[0]
        try require(try e.mediaDuration(u) > 3.8)
      }
      test("Assemblage audio") {
        let u = try run([audio, audio], "join")[0]
        try require(abs(try e.mediaDuration(u) - 8) < 0.3)
      }
      test("Assemblage vidéo") {
        let u = try run([video, video], "join")[0]
        try require(abs(try e.mediaDuration(u) - 8) < 0.4)
      }
      test("Vidéo taille cible") {
        var o = options
        o.targetMB = 0.08
        let u = try run([video], "target", o)[0]
        try require(e.bytes(u) <= 80000)
      }
      test("Audio taille cible") {
        var o = options
        o.targetMB = 0.04
        let u = try run([audio], "target", o)[0]
        try require(e.bytes(u) <= 40000)
      }
      test("Métadonnées vidéo") {
        var o = options
        o.title = "Clémentine validation"
        let u = try run([video], "metadata", o)[0]
        let p = try e.probe(u)
        let format = p["format"] as? [String: Any]
        let tags = format?["tags"] as? [String: Any]
        try require(
          (tags?["title"] as? String)?.precomposedStringWithCanonicalMapping
            == "Clémentine validation")
      }
      for ext in ["zip", "tar", "gz", "rar"] {
        test("Archive \(ext) création et extraction") {
          var o = options
          o.archiveFormat = ext
          let u = try run([source, text], "archive", o)[0]
          let extracted = try run([u], "extract")[0]
          try require(
            fm.fileExists(atPath: extracted.appendingPathComponent(source.lastPathComponent).path))
          try require(
            fm.fileExists(atPath: extracted.appendingPathComponent(text.lastPathComponent).path))
        }
      }
      test("Archive avec lien symbolique refusée") {
        let folder = fixtures.appendingPathComponent("Liens")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent("raccourci")
        if !fm.fileExists(atPath: link.path) {
          try fm.createSymbolicLink(at: link, withDestinationURL: text)
        }
        var o = options
        o.archiveFormat = "tar"
        let a = try run([folder], "archive", o)[0]
        do {
          _ = try run([a], "extract")
          throw ClementineError("Lien accepté")
        } catch let error as ClementineError { try require(error.message.contains("liens")) }
      }
      test("Annulation sans résultat partiel") {
        let token = CancellationToken()
        token.cancel()
        let engine = Engine(token: token)
        do {
          _ = try engine.run([source], action: "convert:jpg", options: options)
          throw ClementineError("Annulation ignorée")
        } catch let error as ClementineError { try require(error.message.contains("annulée")) }
      }
      test("Ordre des pages invalide") {
        do {
          _ = try e.pageOrder("0,999", count: 2)
          throw ClementineError("Ordre accepté")
        } catch let error as ClementineError { try require(error.message.contains("n’existe")) }
      }
      test("Valeurs invalides rejetées") {
        var o = options
        o.speed = 0
        do {
          _ = try run([video], "speed", o)
          throw ClementineError("Valeur acceptée")
        } catch let error as ClementineError { try require(error.message.contains("paramètres")) }
      }
      let report = root.appendingPathComponent("validation.json")
      try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys])
        .write(to: report)
      let failed = checks.filter { $0["passed"] as? Bool == false }.count
      print("\(checks.count-failed)/\(checks.count) tests réussis. Rapport : \(report.path)")
      exit(failed == 0 ? 0 : 1)
    } catch {
      print("Erreur des fixtures : \(error.localizedDescription)")
      exit(2)
    }
  }
}

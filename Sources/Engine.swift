import AVFoundation
import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

final class Engine {
  let token: CancellationToken
  var progress: (Double, String) -> Void
  let fm = FileManager.default
  init(
    token: CancellationToken = CancellationToken(),
    progress: @escaping (Double, String) -> Void = { _, _ in }
  ) {
    self.token = token
    self.progress = progress
  }
  static func executable(_ name: String) throws -> String {
    let candidates: [String?] = [
      Bundle.main.resourceURL?.appendingPathComponent("Tools/\(name)").path,
      ProcessInfo.processInfo.environment["CLEMENTINE_TOOLS"].map { $0 + "/" + name },
      "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)",
    ]
    if let p = candidates.compactMap({ $0 }).first(where: {
      FileManager.default.isExecutableFile(atPath: $0)
    }) {
      return p
    }
    throw ClementineError("Le moteur \(name) est absent. Consultez le guide d’installation.")
  }
  @discardableResult func process(_ path: String, _ args: [String], at directory: URL? = nil, environment: [String: String]? = nil, timeoutSeconds: TimeInterval = 900) throws
    -> String
  {
    try token.check()
    let log = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    fm.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    defer {
      try? handle.close()
      try? fm.removeItem(at: log)
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.currentDirectoryURL = directory
    if let environment { p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value } }
    p.standardOutput = handle
    p.standardError = handle
    p.standardInput = FileHandle.nullDevice
    try token.attach(p)
    try p.run()
    let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
    p.waitUntilExit()
    timeout.cancel()
    try handle.synchronize()
    let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    try token.check()
    guard p.terminationStatus == 0 else {
      if let folder = ProcessInfo.processInfo.environment["CLEMENTINE_DIAGNOSTICS"] {
        try? output.write(to: URL(fileURLWithPath:folder).appendingPathComponent("process-"+UUID().uuidString+".log"), atomically:true, encoding:.utf8)
      }
      throw ClementineError(
        "\(URL(fileURLWithPath:path).lastPathComponent) (\(p.terminationStatus)) : \(output.suffix(3000))")
    }
    return output
  }
  func ff(_ args: [String]) throws {
    try process(
      Self.executable("ffmpeg"), ["-hide_banner", "-nostdin", "-y", "-loglevel", "error"] + args)
  }
  func probe(_ url: URL) throws -> [String: Any] {
    let json = try process(
      Self.executable("ffprobe"),
      ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", url.path])
    guard let d = json.data(using: .utf8),
      let result = try JSONSerialization.jsonObject(with: d) as? [String: Any]
    else { throw ClementineError("Impossible de lire le média") }
    return result
  }
  func mediaDuration(_ url: URL) throws -> Double {
    let info = try probe(url)
    guard let format = info["format"] as? [String: Any], let s = format["duration"] as? String,
      let value = Double(s), value > 0
    else { throw ClementineError("Durée du média inconnue") }
    return value
  }
  func bytes(_ u: URL) -> Int64 {
    ((try? fm.attributesOfItem(atPath: u.path)[.size]) as? NSNumber)?.int64Value ?? 0
  }
  func output(_ source: URL, _ ext: String, _ stage: URL, suffix: String = "") -> URL {
    stage.appendingPathComponent(source.deletingPathExtension().lastPathComponent + suffix)
      .appendingPathExtension(ext)
  }
  func run(_ urls: [URL], action: String, options o: Options) throws -> [URL] {
    guard !urls.isEmpty else { throw ClementineError("Ajoutez au moins un fichier") }
    if o.moduleEditor { try validateModuleOptions(o) }
    guard
      [
        o.quality, o.start, o.duration, o.speed, o.targetMB, o.volume, o.left, o.right,
        o.brightness, o.contrast, o.saturation, o.fontSize, o.padding,
      ].allSatisfy({ $0.isFinite }),
      o.width <= 30000, o.height <= 30000, o.x <= 30000, o.y <= 30000, o.padding >= 0,
      o.padding <= 2000, o.fontSize > 0, o.fontSize <= 2000,
      o.targetMB.isFinite, o.targetMB > 0, o.quality > 0, o.quality <= 1, o.start >= 0,
      o.duration > 0, o.speed >= 0.25, o.speed <= 4, o.width >= 0, o.height >= 0, o.x >= 0, o.y >= 0
    else {
      throw ClementineError(
        "Vérifiez les paramètres : taille, durée et vitesse doivent être positives.")
    }
    let destination =
      o.outputFolder.isEmpty
      ? urls[0].deletingLastPathComponent()
      : URL(fileURLWithPath: o.outputFolder, isDirectory: true)
    let stage = destination.appendingPathComponent(
      ".clementine-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: stage) }
    var generated: [URL] = []
    let groupIDs = ["mergepdf", "collage", "join", "archive"]
    if groupIDs.contains(action) {
      progress(0.05, "Préparation")
      switch action {
      case "mergepdf": generated = [try pdfMerge(urls, stage: stage)]
      case "collage": generated = [try collage(urls, stage: stage, o: o)]
      case "join": generated = [try join(urls, stage: stage, o: o)]
      default: generated = [try archive(urls, stage: stage, format: o.archiveFormat)]
      }
    } else {
      for (index, url) in urls.enumerated() {
        try token.check()
        progress(Double(index) / Double(urls.count), url.lastPathComponent)
        let itemStage = stage.appendingPathComponent("item-\(index)", isDirectory: true)
        try fm.createDirectory(at: itemStage, withIntermediateDirectories: true)
        if action.hasPrefix("convert:") {
          generated += try convert(url, to: String(action.dropFirst(8)), stage: itemStage, o: o)
        } else {
          generated += try tool(url, action: action, stage: itemStage, o: o)
        }
      }
    }
    try token.check()
    var committed: [URL] = []
    var exported: [URL] = []
    do {
      for file in generated {
        guard fm.fileExists(atPath: file.path) else {
          throw ClementineError("Aucun fichier généré")
        }
        let base = destination.appendingPathComponent(file.lastPathComponent)
        let imageFolder=RichDocuments.markdownAssets(for:file)
        let hasImages=file.pathExtension.lowercased() == "md" && fm.fileExists(atPath:imageFolder.path)
        var candidate = base
        var n = 1
        while fm.fileExists(atPath: candidate.path) || (hasImages && fm.fileExists(atPath:RichDocuments.markdownAssets(for:candidate).path)) {
          candidate = destination.appendingPathComponent(
            base.deletingPathExtension().lastPathComponent + " (\(n))"
          ).appendingPathExtension(base.pathExtension)
          n += 1
        }
        if hasImages {
          let publishedImages=RichDocuments.markdownAssets(for:candidate)
          if publishedImages.lastPathComponent != imageFolder.lastPathComponent {
            var markdown=try String(contentsOf:file,encoding:.utf8)
            // Only rewrite generated image destinations, never matching prose or code.
            let filenames=try fm.contentsOfDirectory(atPath:imageFolder.path)
            for filename in filenames {
              let old=RichDocuments.markdownImagePath(folder:imageFolder.lastPathComponent,file:filename)
              let new=RichDocuments.markdownImagePath(folder:publishedImages.lastPathComponent,file:filename)
              markdown=markdown.replacingOccurrences(of:"]("+old+")",with:"]("+new+")")
            }
            try markdown.write(to:file,atomically:true,encoding:.utf8)
          }
          try fm.moveItem(at:imageFolder,to:publishedImages)
          committed.append(publishedImages)
        }
        try fm.moveItem(at: file, to: candidate)
        committed.append(candidate)
        exported.append(candidate)
      }
    } catch {
      for f in committed { try? fm.removeItem(at: f) }
      throw error
    }
    progress(1, "Terminé")
    return exported
  }
  func convert(_ url: URL, to ext: String, stage: URL, o: Options) throws -> [URL] {
    let family = Family.of(url)
    if ext == url.pathExtension.lowercased() {
      throw ClementineError("Le fichier est déjà au format \(ext.uppercased()).")
    }
    if ["zip", "tar", "gz", "rar"].contains(ext) {
      if family == .archive {
        let extracted = try extract(url, stage: stage)
        return [
          try archive(
            try fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil),
            stage: stage, format: ext)
        ]
      }
      return [try archive([url], stage: stage, format: ext)]
    }
    let dest = output(url, ext, stage)
    switch family {
    case .image:
      if ext == "pdf" { return [try pdfMerge([url], stage: stage)] }
      if ext == "gif" && url.pathExtension.lowercased() == "gif" {
        try fm.copyItem(at: url, to: dest)
      } else {
        try saveImage(loadImage(url), to: dest, o: o, source: o.strip ? nil : url)
      }
    case .video, .audio:
      if ext == "mp4" && family == .audio { return [try visualize(url, stage: stage, o: o)] }
      if ext == "gif" {
        try ff([
          "-i", url.path, "-vf",
          "fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
          dest.path,
        ])
      } else {
        try ff(
          ["-i", url.path] + mediaEncoding(ext, o: o) + (o.strip ? ["-map_metadata", "-1"] : []) + [
            dest.path
          ])
      }
    case .pdf:
      guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
        throw ClementineError("PDF illisible ou protégé")
      }
      guard !pdf.isLocked else {
        throw ClementineError("Déverrouillez le PDF avant de le convertir")
      }
      if ["png", "jpg", "tiff"].contains(ext) {
        var files: [URL] = []
        for i in 0..<pdf.pageCount {
          try token.check()
          guard let p = pdf.page(at: i) else { continue }
          let image = try renderPage(p, scale: 300.0 / 72.0)
          let d = output(url, ext, stage, suffix: "-\(i+1)")
          try saveImage(image, to: d, o: o, dpi: 300)
          files.append(d)
        }
        return files
      }
      return [try DocumentFidelity.pdf(url, to: dest, options: o, engine: self)]
    case .subtitle: try subtitle(url, to: dest)
    case .sheet:
      if ext == "csv" && ["xls", "xlsx", "ods", "numbers"].contains(url.pathExtension.lowercased()) {
        return try Documents.sheetCSVs(url, stage: stage, engine: self)
      }
      return [try Documents.office(url, to: dest, engine: self, options: o)]
    case .document, .presentation:
      if ["jpg", "png"].contains(ext) {
        let intermediate = stage.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".pdf")
        defer { try? fm.removeItem(at: intermediate) }
        try Documents.office(url, to: intermediate, engine: self, options: o)
        return try convert(intermediate, to: ext, stage: stage, o: o)
      }
      return [try Documents.office(url, to: dest, engine: self, options: o)]
    default: throw ClementineError("Ce type de fichier ne peut pas être converti en \(ext).")
    }
    return [dest]
  }
  func mediaEncoding(_ ext: String, o: Options) -> [String] {
    let crf = o.strong ? "32" : String(Int(18 + (1 - o.quality) * 24))
    switch ext {
    case "mp4", "mov", "mkv":
      return ["-c:v", "libx264", "-crf", crf, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k"]
        + (ext == "mp4" ? ["-movflags", "+faststart"] : [])
    case "webm": return ["-c:v", "libvpx-vp9", "-crf", crf, "-b:v", "0", "-c:a", "libopus"]
    case "avi": return ["-c:v", "mpeg4", "-q:v", "5", "-c:a", "libmp3lame"]
    case "wmv": return ["-c:v", "wmv2", "-c:a", "wmav2"]
    case "mp3": return ["-vn", "-c:a", "libmp3lame", "-q:a", o.strong ? "6" : "2"]
    case "m4a": return ["-vn", "-c:a", "aac", "-b:a", o.strong ? "96k" : "192k"]
    case "flac": return ["-vn", "-c:a", "flac"]
    case "wav": return ["-vn", "-c:a", "pcm_s16le"]
    case "aiff": return ["-vn", "-c:a", "pcm_s16be"]
    case "ogg": return ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
    case "opus": return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
    case "wma": return ["-vn", "-c:a", "wmav2", "-b:a", "160k"]
    default: return []
    }
  }
  func tool(_ u: URL, action: String, stage: URL, o: Options) throws -> [URL] {
    var o = o
    if let reduction = o.compressionReduction {
      guard reduction.isFinite,reduction>0,reduction<100 else {throw ClementineError("Réduction invalide")}
      o.targetMB = Double(bytes(u))*(1-reduction/100)/1_000_000
    }
    if o.moduleEditor,action == "crop",let crop=o.moduleCrops[u.path] {o.x=crop.x;o.y=crop.y;o.width=crop.width;o.height=crop.height}
    let family = Family.of(u)
    let ext = u.pathExtension.lowercased()
    var d = output(u, ext, stage, suffix: "-\(action)")
    if o.moduleEditor {
      if action == "strip" { return [try moduleMetadata(u, stage:stage, options:o)] }
      if action == "split", family == .video { return [try moduleSplit(u,stage:stage,options:o)] }
      if action == "organize" { return [try moduleOrganize(u, stage:stage, options:o)] }
      if family == .image, ["adjust","redact","annotate","frame"].contains(action) {
        let image = try moduleImage(loadImage(u),action:action,options:o)
        try saveImage(image,to:d,o:o,source:action == "redact" || o.strip ? nil : u)
        return [d]
      }
      if (family == .video || family == .audio), ["normalize","channels","bleep","redact","visualize","trim","speed"].contains(action) {
        return [try moduleMedia(u,action:action,stage:stage,options:o)]
      }
    }
    if action == "metadata" { return [try metadata(u, stage: stage, o: o)] }
    if action == "strip", [Family.image, .video, .audio].contains(family), let exif = Self.exiftool
    {
      try fm.copyItem(at: u, to: d)
      try process("/usr/bin/perl", [exif, "-overwrite_original", "-all=", d.path])
      return [d]
    }
    if action == "qr" { return [try qr(u, stage: stage)] }
    if action == "extract" { return [try extract(u, stage: stage)] }
    if family == .pdf { return try pdfTool(u, action: action, stage: stage, o: o) }
    if family == .image {
      if action == "target", !o.moduleEditor { d = output(u, "jpg", stage, suffix: "-\(action)") }
      var image = try loadImage(u)
      switch action {
      case "compress", "target":
        var settings = o
        settings.quality = o.strong ? 0.45 : o.quality
        if action == "target" {
          let limit = Int64(o.targetMB * 1_000_000)
          for iteration in 0..<(o.moduleEditor ? 40 : 16) {
            try token.check()
            settings.quality = max(0.08, 0.92 - Double(iteration % 6) * 0.15)
            if iteration > 0 && iteration % 6 == 0 {
              image = try resize(
                image, width: max(1, image.width * 3 / 4), height: max(1, image.height * 3 / 4))
            }
            try saveImage(image, to: d, o: settings)
            if bytes(d) <= limit { return [d] }
          }
          throw ClementineError("La taille cible est trop faible pour cette image.")
        }
        if o.width > 0 || o.height > 0 {
          image = try resize(image, width: o.width, height: o.height)
        }
        try saveImage(image, to: d, o: settings, source: o.strip ? nil : u)
        if bytes(d) >= bytes(u) {
          throw ClementineError(
            "Cette image est déjà optimisée. Essayez Taille cible ou une qualité inférieure.")
        }
      case "resize":
        guard o.width > 0 || o.height > 0 else {
          throw ClementineError("Indiquez une largeur ou une hauteur.")
        }
        image = try resize(image, width: o.width, height: o.height)
        try saveImage(image, to: d, o: o, source: o.strip ? nil : u)
      case "rotate":
        let angle = o.rotation
        let swap = angle == 90 || angle == 270
        let w = swap ? image.height : image.width
        let h = swap ? image.width : image.height
        image = try canvas(width: w, height: h) { c in
          c.translateBy(x: Double(w) / 2, y: Double(h) / 2)
          c.rotate(by: -Double(angle) * Double.pi / 180)
          if o.blur { c.scaleBy(x: -1, y: 1) }
          let rect = CGRect(
            x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
            width: CGFloat(image.width), height: CGFloat(image.height))
          c.draw(image, in: rect)
        }
        try saveImage(image, to: d, o: o, source: o.strip ? nil : u)
      case "crop":
        if o.width > 0 && o.height > 0 {
          let r = CGRect(x: o.x, y: o.y, width: o.width, height: o.height)
          guard CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(r),
            let crop = image.cropping(to: r)
          else { throw ClementineError("Le rectangle dépasse les dimensions de l’image.") }
          image = crop
        } else {
          throw ClementineError("Indiquez la largeur et la hauteur du recadrage.")
        }
        try saveImage(image, to: d, o: o, source: o.strip ? nil : u)
      case "adjust":
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(o.brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(o.contrast, forKey: kCIInputContrastKey)
        filter.setValue(o.saturation, forKey: kCIInputSaturationKey)
        image = try adjustedImage(filter, width: image.width, height: image.height)
        try saveImage(image, to: d, o: o, source: o.strip ? nil : u)
      case "redact":
        if o.autoDetect {
          image = try redactDetected(image)
        } else {
          guard o.width > 0, o.height > 0, o.x + o.width <= image.width,
            o.y + o.height <= image.height
          else { throw ClementineError("Sélectionnez une zone dans l’aperçu.") }
          image = try draw(image) { context in
            let r = CGRect(
              x: o.x, y: image.height - o.y - o.height, width: o.width, height: o.height)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(r)
          }
        }
        // Flattened pixels: concealed content is not kept in the output.
        try saveImage(image, to: d, o: o)
      case "annotate":
        guard !o.text.isEmpty else { throw ClementineError("Saisissez le texte de l’annotation.") }
        image = try draw(image) { context in
          NSGraphicsContext.saveGraphicsState()
          NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
          let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: o.fontSize),
            .foregroundColor: NSColor(hex: o.color),
          ]
          (o.text as NSString).draw(
            at: NSPoint(x: o.x, y: max(0, image.height - o.y - Int(o.fontSize * 1.5))),
            withAttributes: a)
          NSGraphicsContext.restoreGraphicsState()
        }
        try saveImage(image, to: d, o: o, source: o.strip ? nil : u)
      case "frame":
        let p = Int(o.padding)
        image = try canvas(width: image.width + 2 * p, height: image.height + 2 * p) { c in
          c.setFillColor(NSColor(hex: o.color).cgColor)
          c.fill(CGRect(x: 0, y: 0, width: image.width + 2 * p, height: image.height + 2 * p))
          c.draw(image, in: CGRect(x: p, y: p, width: image.width, height: image.height))
        }
        try saveImage(image, to: d, o: o, source: o.strip ? nil : u)
      case "strip": try saveImage(image, to: d, o: o)
      default: throw ClementineError("Outil non applicable à cette image")
      }
      return [d]
    }
    if family == .audio || family == .video {
      if action == "visualize" { return [try visualize(u, stage: stage, o: o)] }
      if action == "snapshot" {
        var results: [URL] = []
        let timestamps = try numbers(o.times)
        for (i, t) in timestamps.enumerated() {
          let file = output(u, "png", stage, suffix: "-image-\(i+1)")
          try ff(["-ss", String(t), "-i", u.path, "-frames:v", "1", file.path])
          guard bytes(file) > 0 else {
            throw ClementineError("L’instant \(t) s dépasse la durée de la vidéo.")
          }
          results.append(file)
        }
        return results
      }
      if action == "split" {
        let duration = try mediaDuration(u)
        let boundaries = [0.0] + (try numbers(o.times)) + [duration]
        guard boundaries == boundaries.sorted(), Set(boundaries).count == boundaries.count,
          boundaries.allSatisfy({ $0 >= 0 && $0 <= duration })
        else {
          throw ClementineError(
            "Indiquez des points de coupe croissants, compris dans la durée du média.")
        }
        var result: [URL] = []
        for i in 0..<boundaries.count - 1 {
          let file = output(u, ext, stage, suffix: "-segment-\(i+1)")
          try ff(
            [
              "-ss", String(boundaries[i]), "-i", u.path, "-t",
              String(boundaries[i + 1] - boundaries[i]),
            ] + mediaEncoding(ext, o: o) + [file.path])
          result.append(file)
        }
        return result
      }
      var args = ["-i", u.path]
      var vf: [String] = []
      var af: [String] = []
      switch action {
      case "compress": break
      case "target": return [try targetMedia(u, stage: stage, o: o)]
      case "trim":
        let total = try mediaDuration(u)
        guard o.start < total, o.start + o.duration <= total + 0.1 else {
          throw ClementineError("L’intervalle dépasse la durée du média.")
        }
        args = ["-ss", String(o.start), "-i", u.path, "-t", String(o.duration)]
      case "resize":
        guard o.width > 0 || o.height > 0 else {
          throw ClementineError("Indiquez une largeur ou une hauteur.")
        }
        vf = ["scale=\(o.width>0 ? o.width : -2):\(o.height>0 ? o.height : -2)"]
      case "rotate":
        if o.rotation == 90 {
          vf = ["transpose=1"]
        } else if o.rotation == 270 {
          vf = ["transpose=2"]
        } else if o.rotation == 180 {
          vf = ["hflip", "vflip"]
        }
        if o.blur { vf.append("hflip") }
      case "crop":
        guard o.width > 0, o.height > 0 else {
          throw ClementineError("Définissez une zone de recadrage.")
        }
        vf = ["crop=\(o.width):\(o.height):\(o.x):\(o.y)"]
      case "speed":
        if family == .video { vf = ["setpts=PTS/\(o.speed)"] }
        var rate = o.speed
        while rate > 2 {
          af.append("atempo=2")
          rate /= 2
        }
        while rate < 0.5 {
          af.append("atempo=0.5")
          rate *= 2
        }
        af.append("atempo=\(rate)")
      case "mute": args += ["-an"]
      case "normalize": af = ["loudnorm=I=\(o.volume):TP=-1.5:LRA=11"]
      case "channels":
        args += ["-ac", String(o.channels)]
        if o.channels == 2 {
          af = ["aformat=channel_layouts=stereo", "pan=stereo|c0=\(o.left)*c0|c1=\(o.right)*c1"]
        }
      case "silence":
        af = [
          "silenceremove=start_periods=1:start_duration=0.1:start_threshold=-40dB:stop_periods=-1:stop_duration=0.3:stop_threshold=-40dB"
        ]
      case "bleep":
        let end = o.start + o.duration
        args += [
          "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=\(end)",
          "-filter_complex",
          "[0:a]volume=enable='between(t,\(o.start),\(end))':volume=0[a];[1:a]volume=0.15,atrim=start=\(o.start):end=\(end),asetpts=PTS-STARTPTS,adelay=\(Int(o.start*1000)):all=1[b];[a][b]amix=inputs=2:duration=first:normalize=0[out]",
          "-map", "0:v?", "-map", "[out]",
        ]
      case "redact":
        guard o.width > 0, o.height > 0 else {
          throw ClementineError("Définissez une zone de caviardage.")
        }
        vf = [
          "drawbox=x=\(o.x):y=\(o.y):w=\(o.width):h=\(o.height):color=black:t=fill:enable='between(t,\(o.start),\(o.start+o.duration))'"
        ]
      case "strip": args += ["-map_metadata", "-1", "-map_chapters", "-1"]
      default: throw ClementineError("Outil non applicable à ce média")
      }
      if !vf.isEmpty { args += ["-vf", vf.joined(separator: ",")] }
      if !af.isEmpty { args += ["-af", af.joined(separator: ",")] }
      try ff(args + mediaEncoding(ext, o: o) + [d.path])
      if action == "compress" && bytes(d) >= bytes(u) {
        throw ClementineError("Le média est déjà optimisé. Utilisez Taille cible.")
      }
      return [d]
    }
    throw ClementineError("Outil non applicable à ce fichier")
  }
  func targetMedia(_ u: URL, stage: URL, o: Options) throws -> URL {
    let duration = try mediaDuration(u)
    let isVideo = Family.of(u) == .video
    let d = output(u, isVideo ? "mp4" : "m4a", stage, suffix: "-cible")
    let budget = Int64(o.targetMB * 1_000_000)
    var bits = Double(budget) * 8 / duration * 0.90
    guard bits > (isVideo ? 40_000 : 8_000) else {
      throw ClementineError("Cette cible est trop faible pour la durée du média.")
    }
    for _ in 0..<4 {
      try token.check()
      var args = ["-i", u.path]
      if isVideo {
        let audio = min(96000, bits * 0.2)
        args += [
          "-c:v", "libx264", "-preset", o.targetEncoding == "Fast" ? "ultrafast" : "medium", "-b:v", String(Int(bits - audio)), "-maxrate",
          String(Int(bits - audio)), "-bufsize", String(Int(bits * 2)), "-pix_fmt", "yuv420p",
          "-c:a", "aac", "-b:a", String(Int(audio)),
        ]
      } else {
        args += ["-vn", "-c:a", "aac", "-b:a", String(Int(min(bits, 320000)))]
      }
      try ff(args + [d.path])
      if bytes(d) <= budget { return d }
      bits *= Double(budget) / Double(bytes(d)) * 0.90
    }
    throw ClementineError("La taille cible n’a pas pu être atteinte. Augmentez la limite.")
  }
  func numbers(_ s: String) throws -> [Double] {
    let values = s.split(separator: ",").compactMap {
      Double($0.trimmingCharacters(in: .whitespaces))
    }
    guard !values.isEmpty, values.count == s.split(separator: ",").count,
      values.allSatisfy({ $0.isFinite && $0 >= 0 })
    else {
      throw ClementineError("Indiquez des secondes séparées par des virgules, par exemple 5,10,15.")
    }
    return values
  }
  func loadImage(_ u: URL) throws -> CGImage {
    if let s = CGImageSourceCreateWithURL(u as CFURL, nil) {
      let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] ?? [:]
      let w = p[kCGImagePropertyPixelWidth] as? Int ?? 30000
      let h = p[kCGImagePropertyPixelHeight] as? Int ?? 30000
      if let image = CGImageSourceCreateThumbnailAtIndex(
        s, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ] as CFDictionary)
      {
        return image
      }
    }
    if let n = NSImage(contentsOf: u),
      let i = n.cgImage(forProposedRect: nil, context: nil, hints: nil)
    {
      return i
    }
    throw ClementineError("Image illisible ou format non reconnu")
  }
  func saveImage(_ image: CGImage, to u: URL, o: Options, source: URL? = nil, dpi: Double? = nil) throws {
    let e = u.pathExtension.lowercased()
    if e == "svg" {
      let data = NSMutableData()
      guard
        let dst = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
      else { throw ClementineError("Encodage PNG indisponible") }
      CGImageDestinationAddImage(dst, image, nil)
      guard CGImageDestinationFinalize(dst) else { throw ClementineError("Encodage impossible") }
      let xml =
        "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"\(image.width)\" height=\"\(image.height)\" viewBox=\"0 0 \(image.width) \(image.height)\"><image width=\"100%\" height=\"100%\" xlink:href=\"data:image/png;base64,\((data as Data).base64EncodedString())\"/></svg>"
      try xml.write(to: u, atomically: true, encoding: .utf8)
      return
    }
    let map = [
      "jpg": UTType.jpeg.identifier, "jpeg": UTType.jpeg.identifier, "png": UTType.png.identifier,
      "heic": UTType.heic.identifier, "tiff": UTType.tiff.identifier, "tif": UTType.tiff.identifier,
      "bmp": UTType.bmp.identifier, "gif": UTType.gif.identifier,
    ]
    if let type = map[e],
      let dest = CGImageDestinationCreateWithURL(u as CFURL, type as CFString, 1, nil)
    {
      var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: o.quality]
      if let dpi {props[kCGImagePropertyDPIWidth] = dpi; props[kCGImagePropertyDPIHeight] = dpi}
      if let source, let s = CGImageSourceCreateWithURL(source as CFURL, nil),
        let dict = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any]
      {
        props.merge(dict) { old, _ in old }
        props.removeValue(forKey: kCGImagePropertyOrientation)
      }
      CGImageDestinationAddImage(dest, image, props as CFDictionary)
      guard CGImageDestinationFinalize(dest) else {
        throw ClementineError("L’encodage \(e) a échoué.")
      }
      return
    }
    let temp = u.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
    defer { try? fm.removeItem(at: temp) }
    try saveImage(image, to: temp, o: o)
    if e == "webp" {
      try ff(["-i", temp.path, "-c:v", "libwebp", "-quality", String(Int(o.quality * 100)), u.path])
    } else if e == "avif" {
      try ff([
        "-i", temp.path, "-c:v", "libaom-av1", "-still-picture", "1", "-crf",
        String(Int(15 + (1 - o.quality) * 45)), "-cpu-used", "6", u.path,
      ])
    } else {
      throw ClementineError("Format image non disponible : \(e)")
    }
  }
  func canvas(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
    guard width > 0, height > 0, width <= 30000, height <= 30000,
      Int64(width) * Int64(height) <= 150_000_000,
      let c = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ClementineError("Dimensions de l’image trop grandes") }
    c.interpolationQuality = .high
    draw(c)
    guard let i = c.makeImage() else { throw ClementineError("Rendu impossible") }
    return i
  }
  func adjustedImage(_ filter: CIFilter, width: Int, height: Int) throws -> CGImage {
    guard let ci = filter.outputImage,
      let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(
        ci, from: CGRect(x: 0, y: 0, width: width, height: height))
    else { throw ClementineError("Le rendu des couleurs est indisponible dans cette session.") }
    return image
  }
  func draw(_ image: CGImage, body: (CGContext) -> Void) throws -> CGImage {
    try canvas(width: image.width, height: image.height) { c in
      c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      body(c)
    }
  }
  func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    let w =
      width > 0 ? width : max(1, Int(Double(image.width) * Double(height) / Double(image.height)))
    let h =
      height > 0 ? height : max(1, Int(Double(image.height) * Double(width) / Double(image.width)))
    return try canvas(width: w, height: h) {
      $0.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
  }
  func collage(_ urls: [URL], stage: URL, o: Options) throws -> URL {
    guard urls.count <= 100 else { throw ClementineError("Maximum : 100 images par collage") }
    if o.moduleEditor {
      let image = try moduleCollage(urls,options:o)
      let destination = stage.appendingPathComponent("Collage.png")
      try saveImage(image,to:destination,o:o); return destination
    }
    let cols = max(1, min(o.columns, 10))
    let rows = (urls.count + cols - 1) / cols
    let cell = o.width > 0 ? min(o.width, 2000) : 600
    let gap = max(0, min(Int(o.padding), 200))
    let images = try urls.map { try loadImage($0) }
    let image = try canvas(
      width: cols * cell + (cols + 1) * gap, height: rows * cell + (rows + 1) * gap
    ) { c in
      c.setFillColor(NSColor(hex: o.color).cgColor)
      c.fill(CGRect(x: 0, y: 0, width: c.width, height: c.height))
      for (i, img) in images.enumerated() {
        let scale = min(Double(cell) / Double(img.width), Double(cell) / Double(img.height))
        let w = Double(img.width) * scale
        let h = Double(img.height) * scale
        c.draw(
          img,
          in: CGRect(
            x: Double(gap + (i % cols) * (cell + gap)) + (Double(cell) - w) / 2,
            y: Double(c.height - gap - (i / cols) * (cell + gap) - cell) + (Double(cell) - h) / 2,
            width: w, height: h))
      }
    }
    let d = stage.appendingPathComponent("Collage.png")
    try saveImage(image, to: d, o: o)
    return d
  }
  func redactDetected(_ image: CGImage) throws -> CGImage {
    var rects: [CGRect] = []
    let face = VNDetectFaceRectanglesRequest()
    let text = VNRecognizeTextRequest()
    text.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: image).perform([face, text])
    rects += (face.results ?? []).map(\.boundingBox)
    rects += (text.results ?? []).map(\.boundingBox)
    guard !rects.isEmpty else {
      throw ClementineError("Aucun visage ni texte détecté. Sélectionnez une zone manuellement.")
    }
    return try draw(image) { c in
      c.setFillColor(CGColor(gray: 0, alpha: 1))
      for r in rects {
        c.fill(
          CGRect(
            x: r.minX * Double(image.width), y: r.minY * Double(image.height),
            width: r.width * Double(image.width), height: r.height * Double(image.height)
          ).insetBy(dx: -3, dy: -3))
      }
    }
  }
  func qr(_ u: URL, stage: URL) throws -> URL {
    var images: [CGImage] = []
    if Family.of(u) == .pdf {
      guard let doc = PDFDocument(url: u), !doc.isLocked else {
        throw ClementineError("PDF illisible")
      }
      for i in 0..<doc.pageCount {
        if let p = doc.page(at: i) { images.append(try renderPage(p, scale: 2)) }
      }
    } else {
      images = [try loadImage(u)]
    }
    var result: [String] = []
    for (i, img) in images.enumerated() {
      try token.check()
      let request = VNDetectBarcodesRequest()
      request.symbologies = [.qr]
      try VNImageRequestHandler(cgImage: img).perform([request])
      result += (request.results ?? []).compactMap {
        $0.payloadStringValue.map { "Page \(i+1) : \($0)" }
      }
    }
    guard !result.isEmpty else { throw ClementineError("Aucun QR code détecté") }
    let d = output(u, "txt", stage, suffix: "-QR")
    try result.joined(separator: "\n").write(to: d, atomically: true, encoding: .utf8)
    return d
  }
  func renderPage(_ page: PDFPage, scale: Double) throws -> CGImage {
    let size = try DocumentFidelity.pageSize(page)
    guard let reference = page.pageRef else { throw ClementineError("Page PDF illisible") }
    let width=max(1,Int((size.width*scale).rounded())), height=max(1,Int((size.height*scale).rounded()))
    let transform=try DocumentFidelity.drawingTransform(page,canvas:CGSize(width:width,height:height))
    return try canvas(width:width,height:height) { c in
      let bounds = CGRect(x: 0, y: 0, width: c.width, height: c.height)
      c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(bounds)
      c.concatenate(transform)
      c.drawPDFPage(reference)
    }
  }
  func pdfMerge(_ urls: [URL], stage: URL) throws -> URL {
    let doc = PDFDocument()
    for u in urls {
      try token.check()
      if Family.of(u) == .pdf {
        guard let pdf = PDFDocument(url: u), !pdf.isLocked else {
          throw ClementineError("PDF illisible ou verrouillé : \(u.lastPathComponent)")
        }
        for i in 0..<pdf.pageCount {
          if let p = pdf.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) }
        }
      } else {
        let img = try loadImage(u)
        guard let p = PDFPage(image: NSImage(cgImage: img, size: .zero)) else {
          throw ClementineError("Création de page impossible")
        }
        doc.insert(p, at: doc.pageCount)
      }
    }
    let d = output(urls[0], "pdf", stage, suffix: "-assemblé")
    guard doc.write(to: d) else { throw ClementineError("Écriture du PDF impossible") }
    return d
  }
  func pdfTool(_ u: URL, action: String, stage: URL, o: Options) throws -> [URL] {
    guard let doc = PDFDocument(url: u), !doc.isLocked else {
      throw ClementineError("PDF illisible ou verrouillé")
    }
    if action == "split" {
      return try splitPDF(doc, source:u, stage:stage, options:o)
    }
    let d = output(u, "pdf", stage, suffix: "-\(action)")
    if action == "organize" {
      let order = try pageOrder(o.pages, count: doc.pageCount)
      let arranged = PDFDocument()
      for i in order {
        let p = doc.page(at: i)!.copy() as! PDFPage
        p.rotation = (p.rotation + o.rotation) % 360
        arranged.insert(p, at: arranged.pageCount)
      }
      guard arranged.write(to: d) else { throw ClementineError("Écriture impossible") }
      return [d]
    }
    if action == "strip" {
      doc.documentAttributes = [:]
      guard doc.write(to: d) else { throw ClementineError("Écriture impossible") }
      return [d]
    }
    if action == "compress" || action == "target" {
      // Explicitly rasterized; the UI warns that searchable text and links are removed.
      var scale = o.strong ? 0.8 : 1.3
      for iteration in 0..<(action == "target" ? 8 : 1) {
        let compressed = PDFDocument()
        for i in 0..<doc.pageCount {
          try token.check()
          let p = doc.page(at: i)!
          let image = try renderPage(p, scale: scale)
          let jpeg = stage.appendingPathComponent("page-temp.jpg")
          var settings = o
          settings.quality = o.strong ? 0.45 : max(0.25, o.quality - Double(iteration) * 0.08)
          try saveImage(image, to: jpeg, o: settings)
          guard let n = NSImage(contentsOf: jpeg), let newPage = PDFPage(image: n) else {
            throw ClementineError("Rendu impossible")
          }
          newPage.setBounds(p.bounds(for: .mediaBox), for: .mediaBox)
          compressed.insert(newPage, at: compressed.pageCount)
        }
        guard compressed.write(to: d) else { throw ClementineError("Écriture impossible") }
        if action == "target" && bytes(d) <= Int64(o.targetMB * 1_000_000) { return [d] }
        scale *= 0.75
      }
      if action == "target" {
        throw ClementineError("La taille cible du PDF n’a pas pu être atteinte.")
      }
      guard bytes(d) < bytes(u) else {
        throw ClementineError("Le PDF est déjà optimisé. Essayez Taille cible.")
      }
      return [d]
    }
    throw ClementineError("Outil PDF non applicable")
  }
  func pageOrder(_ value: String, count: Int) throws -> [Int] {
    if value.trimmingCharacters(in: .whitespaces).isEmpty { return Array(0..<count) }
    var result: [Int] = []
    for s in value.split(separator: ",") {
      let bounds = s.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap {
        Int($0)
      }
      if bounds.count == 1 {
        result.append(bounds[0] - 1)
      } else if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 10000 {
        result += (bounds[0]...bounds[1]).map { $0 - 1 }
      } else {
        throw ClementineError("Ordre des pages invalide")
      }
    }
    guard !result.isEmpty, result.allSatisfy({ $0 >= 0 && $0 < count }) else {
      throw ClementineError("Une page demandée n’existe pas")
    }
    return result
  }
  static var exiftool: String? {
    let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Tools/ExifTool/exiftool").path,
      ProcessInfo.processInfo.environment["CLEMENTINE_TOOLS"].map { $0 + "/ExifTool/exiftool" }]
    return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath:$0) }
  }
  func metadata(_ u: URL, stage: URL, o: Options) throws -> URL {
    let family = Family.of(u)
    if let exif = Self.exiftool {
      if o.title.isEmpty && o.author.isEmpty && o.subject.isEmpty {
        let data = try process("/usr/bin/perl", [exif, "-json", "-G1", "-a", "-s", u.path])
        let dest = output(u, "json", stage, suffix: "-métadonnées")
        try data.write(to: dest, atomically: true, encoding: .utf8)
        return dest
      }
      let dest = output(u, u.pathExtension, stage, suffix: "-métadonnées")
      try fm.copyItem(at: u, to: dest)
      try process(
        "/usr/bin/perl",
        [
          exif, "-overwrite_original", "-Title=" + o.title, "-Author=" + o.author,
          "-Artist=" + o.author, "-Subject=" + o.subject,
        ]
          + ((family == .video || family == .audio)
            ? [
              "-Keys:Title=" + o.title, "-ItemList:Title=" + o.title,
              "-ItemList:Artist=" + o.author,
            ] : []) + [dest.path])
      return dest
    }
    if o.title.isEmpty && o.author.isEmpty && o.subject.isEmpty {
      var info: [String: Any] = ["name": u.lastPathComponent, "bytes": bytes(u)]
      if family == .image, let source = CGImageSourceCreateWithURL(u as CFURL, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      {
        info["image"] = props
      } else if family == .pdf, let doc = PDFDocument(url: u) {
        info["pdf"] = doc.documentAttributes?.reduce(into: [String: String]()) {
          $0[String(describing: $1.key)] = String(describing: $1.value)
        }
        info["pages"] = doc.pageCount
      } else if family == .video || family == .audio {
        info["media"] = try probe(u)
      }
      let d = output(u, "txt", stage, suffix: "-métadonnées")
      try String(describing: info).write(to: d, atomically: true, encoding: .utf8)
      return d
    }
    let d = output(u, u.pathExtension, stage, suffix: "-métadonnées")
    if family == .pdf {
      guard let doc = PDFDocument(url: u), !doc.isLocked else {
        throw ClementineError("PDF illisible")
      }
      var a = doc.documentAttributes ?? [:]
      a[PDFDocumentAttribute.titleAttribute] = o.title
      a[PDFDocumentAttribute.authorAttribute] = o.author
      a[PDFDocumentAttribute.subjectAttribute] = o.subject
      doc.documentAttributes = a
      guard doc.write(to: d) else { throw ClementineError("Écriture impossible") }
    } else if family == .image {
      guard let source = CGImageSourceCreateWithURL(u as CFURL, nil),
        let type = CGImageSourceGetType(source),
        let dest = CGImageDestinationCreateWithURL(
          d as CFURL, type, CGImageSourceGetCount(source), nil)
      else { throw ClementineError("Métadonnées non modifiables pour ce format") }
      for i in 0..<CGImageSourceGetCount(source) {
        var props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] ?? [:]
        props[kCGImagePropertyTIFFDictionary] = [
          kCGImagePropertyTIFFArtist: o.author, kCGImagePropertyTIFFImageDescription: o.title,
          kCGImagePropertyTIFFCopyright: o.subject,
        ]
        CGImageDestinationAddImageFromSource(dest, source, i, props as CFDictionary)
      }
      guard CGImageDestinationFinalize(dest) else {
        throw ClementineError("Écriture des métadonnées impossible")
      }
    } else {
      try ff([
        "-i", u.path, "-map", "0", "-c", "copy", "-metadata", "title=\(o.title)", "-metadata",
        "artist=\(o.author)", "-metadata", "comment=\(o.subject)", d.path,
      ])
    }
    return d
  }
  func join(_ urls: [URL], stage: URL, o: Options) throws -> URL {
    guard urls.count > 1 else { throw ClementineError("Ajoutez au moins deux médias") }
    let video = Family.of(urls[0]) == .video
    var canvasWidth = 1280, canvasHeight = 720
    if o.moduleEditor, video {
      let size=Self.videoDisplaySize(try probe(urls[0]))
      canvasWidth=max(2,Int(size.width)/2*2);canvasHeight=max(2,Int(size.height)/2*2)
    }
    var normalized: [URL] = []
    for (i, u) in urls.enumerated() {
      try token.check()
      progress(Double(i) / Double(urls.count + 1), "Préparation du segment \(i+1)")
      let temp = stage.appendingPathComponent("part-\(i).\(video ? "mp4" : "wav")")
      if video {
        let info = try probe(u)
        let streams = info["streams"] as? [[String: Any]] ?? []
        let hasAudio = streams.contains { $0["codec_type"] as? String == "audio" }
        var args = ["-i", u.path]
        if !hasAudio { args += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-shortest"] }
        args += [
          "-map", "0:v:0", "-map", hasAudio ? "0:a:0" : "1:a:0", "-vf",
          "scale=\(canvasWidth):\(canvasHeight):force_original_aspect_ratio=decrease,pad=\(canvasWidth):\(canvasHeight):(ow-iw)/2:(oh-ih)/2,fps=30,setsar=1",
          "-ar", "48000", "-ac", "2",
        ]
        try ff(args + mediaEncoding("mp4", o: o) + [temp.path])
      } else {
        try ff(["-i", u.path, "-vn", "-ar", "48000", "-ac", "2", temp.path])
      }
      normalized.append(temp)
    }
    let list = stage.appendingPathComponent("concat.txt")
    try normalized.map { "file '\($0.lastPathComponent)'" }.joined(separator: "\n").write(
      to: list, atomically: true, encoding: .utf8)
    let d = output(urls[0], video ? "mp4" : "m4a", stage, suffix: "-assemblé")
    try ff(
      ["-f", "concat", "-safe", "1", "-i", list.path]
        + (video ? ["-c", "copy"] : mediaEncoding("m4a", o: o)) + [d.path])
    return d
  }
  func visualize(_ u: URL, stage: URL, o: Options) throws -> URL {
    let d = output(u, "mp4", stage, suffix: "-visualisation")
    try ff([
      "-i", u.path, "-filter_complex",
      "[0:a]showwaves=s=1280x720:mode=cline:colors=0xf47637:rate=30,format=yuv420p[v]", "-map",
      "[v]", "-map", "0:a", "-c:v", "libx264", "-c:a", "aac", "-shortest", d.path,
    ])
    return d
  }
  func archive(_ urls: [URL], stage: URL, format: String) throws -> URL {
    guard !urls.isEmpty else { throw ClementineError("L’archive est vide") }
    if format == "rar" {
      let dest = output(urls[0], "rar", stage, suffix: "-archive")
      try RARStore.write(urls, to: dest, engine: self)
      return dest
    }
    let root = stage.appendingPathComponent("archive-input-" + UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    for (i, u) in urls.enumerated() {
      try token.check()
      var d = root.appendingPathComponent(u.lastPathComponent)
      if fm.fileExists(atPath: d.path) {
        d = root.appendingPathComponent("\(i)-" + u.lastPathComponent)
      }
      try fm.copyItem(at: u, to: d)
    }
    let dest = output(urls[0], format, stage, suffix: "-archive")
    if format == "zip" {
      try process("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", root.path, dest.path])
    } else {
      try process(
        "/usr/bin/tar", [format == "gz" ? "-czf" : "-cf", dest.path, "-C", root.path, "."])
    }
    return dest
  }
  func extract(_ u: URL, stage: URL) throws -> URL {
    let names = try process("/usr/bin/tar", ["-tf", u.path]).split(separator: "\n").map(String.init)
    guard names.count <= 100000 else { throw ClementineError("Archive trop volumineuse") }
    guard
      names.allSatisfy({
        !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && !$0.contains("\\")
      })
    else { throw ClementineError("L’archive contient des chemins dangereux.") }
    let listing = try process("/usr/bin/tar", ["-tvf", u.path])
    guard
      !listing.split(separator: "\n").contains(where: {
        $0.first == "l" || $0.first == "h" || $0.first == "b" || $0.first == "c" || $0.first == "p"
      })
    else {
      throw ClementineError(
        "Les archives contenant des liens ou fichiers spéciaux ne sont pas extraites.")
    }
    let dest = stage.appendingPathComponent(
      u.deletingPathExtension().lastPathComponent + "-extrait", isDirectory: true)
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    try process(
      "/usr/bin/tar", ["-xf", u.path, "-C", dest.path, "--no-same-owner", "--no-same-permissions"])
    return dest
  }
  func subtitle(_ u: URL, to dest: URL) throws {
    var value = try String(contentsOf: u, encoding: .utf8).replacingOccurrences(
      of: "\r\n", with: "\n")
    if dest.pathExtension == "vtt" {
      value = value.replacingOccurrences(
        of: "(\\d{2}:\\d{2}:\\d{2}),(\\d{3})", with: "$1.$2", options: .regularExpression)
      if !value.hasPrefix("WEBVTT") { value = "WEBVTT\n\n" + value }
    } else if dest.pathExtension == "srt" {
      value = value.replacingOccurrences(
        of: "^WEBVTT[^\\n]*\\n", with: "", options: .regularExpression)
      let blocks = value.components(separatedBy: "\n\n").filter { $0.contains("-->") }
      value =
        blocks.enumerated().map { i, block in
          var lines = block.components(separatedBy: "\n")
          while let first = lines.first, !first.contains("-->") { lines.removeFirst() }
          if !lines.isEmpty {
            lines[0] = lines[0].replacingOccurrences(
              of: "(?<![\\d:])(\\d{2}:\\d{2}\\.\\d{3})", with: "00:$1", options: .regularExpression
            ).replacingOccurrences(
              of: "(\\d{2}:\\d{2}:\\d{2})\\.(\\d{3})", with: "$1,$2", options: .regularExpression)
          }
          return "\(i+1)\n" + lines.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    } else {
      value = value.components(separatedBy: "\n").filter {
        !$0.contains("-->") && $0 != "WEBVTT" && Int($0.trimmingCharacters(in: .whitespaces)) == nil
      }.joined(separator: "\n")
    }
    try value.write(to: dest, atomically: true, encoding: .utf8)
  }
}
extension NSColor {
  convenience init(hex: String) {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    let n = UInt64(clean, radix: 16) ?? 0xF47637
    self.init(
      srgbRed: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255,
      blue: Double(n & 255) / 255, alpha: 1)
  }
}

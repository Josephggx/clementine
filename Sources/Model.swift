import AppKit
import Foundation
import SwiftUI

let imageFormats = ["jpg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif", "svg", "pdf"]
let videoFormats = ["mp4", "mov", "mkv", "avi", "wmv", "webm", "gif"]
let audioFormats = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
let documentFormats = ["pages", "pdf", "txt", "docx", "doc", "odt", "rtf", "html", "md", "epub"]
let sheetFormats = ["numbers", "csv", "tsv", "xlsx", "xls", "ods"]
enum Family: String, CaseIterable {
  case presentation = "Présentations"
  case image = "Images"
  case video = "Vidéo"
  case audio = "Audio"
  case pdf = "PDF"
  case document = "Documents"
  case sheet = "Tableurs"
  case subtitle = "Sous-titres"
  case archive = "Archives"
  case other = "Autres"
  static func of(_ url: URL) -> Family {
    let e = url.pathExtension.lowercased()
    if e == "gif" { return .video }
    if ["pdf"].contains(e) { return .pdf }
    if ["ppt", "pptx", "odp", "key"].contains(e) { return .presentation }
    if ["srt", "vtt"].contains(e) { return .subtitle }
    if ["zip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z"].contains(e) { return .archive }
    if ["csv", "tsv", "xlsx", "xls", "ods", "numbers"].contains(e) { return .sheet }
    if [
      "jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "bmp", "gif", "avif", "svg",
      "ico",
    ].contains(e) {
      return .image
    }
    if videoFormats.contains(e) { return .video }
    if audioFormats.contains(e) { return .audio }
    if (documentFormats + ["doc", "pages", "ppt", "pptx", "rtfd", "textclipping"]).contains(e) {
      return .document
    }
    return .other
  }
  var icon: String {
    switch self {
    case .presentation: return "rectangle.on.rectangle"
    case .image: return "photo"
    case .video: return "film"
    case .audio: return "waveform"
    case .pdf: return "doc.richtext"
    case .document: return "doc.text"
    case .sheet: return "tablecells"
    case .subtitle: return "captions.bubble"
    case .archive: return "archivebox"
    case .other: return "doc"
    }
  }
  var singularName: String {
    switch self {
    case .presentation: return "Présentation"
    case .image: return "Image"
    case .video: return "Vidéo"
    case .audio: return "Audio"
    case .pdf: return "PDF"
    case .document: return "Document"
    case .sheet: return "Tableur"
    case .subtitle: return "Sous-titre"
    case .archive: return "Archive"
    case .other: return "Autre"
    }
  }
  var formats: [String] {
    switch self {
    case .presentation: return ["pdf", "pptx", "ppt", "odp", "key", "txt", "html"]
    case .image: return imageFormats
    case .video: return videoFormats + audioFormats
    case .audio: return audioFormats + ["mp4"]
    case .pdf: return ["png", "jpg", "tiff"] + documentFormats
    case .document: return documentFormats
    case .sheet: return sheetFormats + ["pdf", "txt"]
    case .subtitle: return ["srt", "vtt", "txt"]
    case .archive: return ["zip", "tar", "gz", "rar"]
    case .other: return ["zip", "tar", "gz", "rar"]
    }
  }
}
struct Tool: Identifiable, Hashable {
  let id: String, name: String, icon: String
  let families: [Family]
  let group: Bool
  init(_ id: String, _ name: String, _ icon: String, _ families: [Family], group: Bool = false) {
    self.id = id
    self.name = name
    self.icon = icon
    self.families = families
    self.group = group
  }
  static let all: [Tool] = [
    Tool(
      "compress", "Compresser", "arrow.down.right.and.arrow.up.left",
      [.image, .video, .audio, .pdf]),
    Tool("target", "Taille cible", "target", [.image, .video, .audio, .pdf]),
    Tool("resize", "Redimensionner", "arrow.up.left.and.arrow.down.right", [.image, .video]),
    Tool("rotate", "Rotation / miroir", "rotate.right", [.image, .video]),
    Tool("crop", "Recadrer", "crop", [.image, .video]),
    Tool("adjust", "Ajuster les couleurs", "slider.horizontal.3", [.image]),
    Tool("annotate", "Annoter", "pencil.tip", [.image]),
    Tool("redact", "Caviarder", "eye.slash", [.image, .video]),
    Tool("frame", "Ajouter un cadre", "square.dashed.inset.filled", [.image]),
    Tool("collage", "Créer un collage", "square.grid.2x2", [.image], group: true),
    Tool("qr", "Lire les QR codes", "qrcode.viewfinder", [.image, .pdf]),
    Tool(
      "metadata", "Lire / modifier les métadonnées", "info.circle", Array(Family.allCases)),
    Tool("strip", "Métadonnées", "eraser", Array(Family.allCases)),
    Tool("trim", "Découper", "scissors", [.video, .audio]),
    Tool("split", "Diviser en segments", "rectangle.split.3x1", [.video, .audio, .pdf]),
    Tool("join", "Assembler", "link", [.video, .audio], group: true),
    Tool("speed", "Changer la vitesse", "speedometer", [.video, .audio]),
    Tool("snapshot", "Extraire des images", "camera", [.video]),
    Tool("mute", "Retirer la piste audio", "speaker.slash", [.video]),
    Tool("normalize", "Normaliser le volume", "waveform.path", [.audio, .video]),
    Tool("bleep", "Masquer un passage audio", "speaker.badge.exclamationmark", [.audio, .video]),
    Tool("channels", "Canaux et balance", "hifispeaker.2", [.audio]),
    Tool("silence", "Retirer les silences", "waveform.slash", [.audio]),
    Tool("visualize", "Audio vers vidéo", "waveform.path.ecg.rectangle", [.audio]),
    Tool("mergepdf", "Fusionner / créer un PDF", "doc.on.doc", [.pdf, .image], group: true),
    Tool("organize", "Réorganiser les pages", "rectangle.3.group", [.pdf]),
    Tool("extract", "Extraire l’archive", "archivebox", [.archive]),
    Tool("archive", "ZIP", "doc.zipper", Family.allCases.filter { $0 != .archive }, group: true),
  ]
  var wheelTitle: String {
    ["compress": "COMPRESS", "strip": "METADATA", "adjust": "EDIT", "annotate": "ANNOTATE",
     "frame": "ADD BG", "crop": "CROP", "redact": "REDACT", "normalize": "NORMALIZE",
     "mute": "MUTE", "trim": "TRIM", "split": "SPLIT", "organize": "ORGANIZE",
     "extract": "EXTRACT", "mergepdf": "MERGE PDF", "speed": "SPEED", "join": "JOIN",
     "snapshot": "SNAPSHOT", "visualize": "VISUALIZE", "channels": "CHANNELS",
     "collage": "COLLAGE", "archive": "ZIP", "qr": "READ QR", "bleep": "BLEEP"][id] ?? name.uppercased()
  }
  static func available(_ urls: [URL]) -> [Tool] {
    guard let first = urls.first else { return [] }
    let group = urls.count > 1
    func ids(_ format: String) -> [String] {
      switch format {
      case "jpg", "png", "webp", "heic", "tiff":
        return group ? ["compress", "strip", "crop", "mergepdf", "collage"]
          : ["compress", "strip", "adjust", "annotate", "frame", "crop", "redact"]
      case "svg": return group ? ["strip", "mergepdf", "collage"] : ["strip"]
      case "mp3", "m4a", "wav", "flac":
        return group ? ["compress", "strip", "normalize"]
          : ["compress", "strip", "normalize", "visualize", "trim", "channels", "bleep"]
      case "mp4", "mov", "mkv":
        return group ? ["compress", "strip", "mute", "join"]
          : ["compress", "strip", "mute", "trim", "crop", "speed", "snapshot", "split", "redact"]
      case "gif": return ["strip"]
      case "pdf": return group ? ["compress", "strip", "split", "mergepdf"]
        : ["compress", "strip", "split", "organize"]
      case "zip", "tar", "gz", "rar": return ["strip", "extract"]
      default: return ["strip"]
      }
    }
    var compatible = ids(Compatibility.format(first)).filter { id in
      urls.allSatisfy { ids(Compatibility.format($0)).contains(id) }
    }
    if !urls.contains(where: { Family.of($0) == .archive }), !compatible.contains("archive") {
      compatible.append("archive")
    }
    return compatible.compactMap { id in all.first { $0.id == id } }
  }
  static func batchCandidates(_ urls: [URL]) -> [Tool] {
    guard urls.count >= 2 else { return [] }
    let families = urls.map(Family.of)
    var ids: [String] = []
    if families.allSatisfy({ $0 == .pdf || $0 == .image }) { ids.append("mergepdf") }
    if families.allSatisfy({ $0 == .image }) { ids.append("collage") }
    if families.allSatisfy({ $0 == .video }) || families.allSatisfy({ $0 == .audio }) { ids.append("join") }
    if !families.contains(.archive) { ids.append("archive") }
    return ids.compactMap { id in all.first { $0.id == id } }
  }
  /// Complete feature catalogue for a format; the live drag wheel stays selection-dependent.
  static func catalogue(for source: URL) -> [Tool] {
    let pair = [source, source.deletingLastPathComponent().appendingPathComponent(
      "second." + source.pathExtension)]
    let candidates = available([source]) + available(pair) + batchCandidates(pair)
    var seen = Set<String>()
    var result = candidates.filter { $0.id != "archive" && seen.insert($0.id).inserted }
    if candidates.contains(where: { $0.id == "archive" }), let archive = all.first(where: { $0.id == "archive" }) {
      result.append(archive)
    }
    return result
  }
}
struct ModulePoint: Codable, Equatable { var x: Double; var y: Double }
struct ModuleMark: Codable, Identifiable, Equatable {
  var id = UUID()
  var kind = "rectangle"
  var x = 0.1, y = 0.1, width = 0.3, height = 0.2
  var color = "#000000", text = ""
  var size = 4.0
  var font = "System"
  var magnification = 2.0
  var blur = false
  var start = 0.0, end = 1.0
  var points: [ModulePoint] = []
  var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct ModuleCrop: Codable { var x: Int; var y: Int; var width: Int; var height: Int }
struct ModulePage: Codable, Identifiable, Equatable {
  var id = UUID()
  var index: Int
  var rotation = 0
}

struct Options: Codable {
  var moduleEditor = false
  var compressionReduction: Double? = nil
  var targetEncoding = "Accurate"
  var splitRemoved: [Int] = [], splitExportMode = "Clips"
  var silenceThreshold = -40.0
  var photoAdjustments: [String: Double] = [:]
  var marks: [ModuleMark] = []
  var modulePages: [ModulePage] = []
  var moduleCrops: [String:ModuleCrop] = [:]
  var metadataChanges: [String: String] = [:]
  var metadataRemoveAll = false
  var loudnessRange = 11.0, truePeak = -1.5
  var trimSilence = false
  var previewChannel = ""
  var background = "Citrus", backgroundImage = "", backgroundBlur = 0.0
  var corners = 24.0, shadow = 24.0
  var canvasRatio = "Auto", collageStyle = "Grid", imageFit = "Fill cells (crop edges)"
  var collageSpacing = 8.0, collagePadding = 0.0
  var annotationFont = "System", annotationMagnification = 2.0
  var visualizerStyle = "Waveform", visualizerShape = "Landscape · 16:9"
  var pdfOfficeLayout = "automatic"
  var epubLayout = "adjustableText"
  var quality = 0.80
  var width = 0, height = 0, x = 0, y = 0
  var start = 0.0, duration = 5.0, speed = 1.0
  var targetMB = 5.0, volume = -16.0, left = 1.0, right = 1.0
  var brightness = 0.0, contrast = 1.0, saturation = 1.0
  var text = "", times = "5,10", pages = "", color = "#F47637"
  var title = "", author = "", subject = ""
  var fontSize = 36.0, padding = 40.0, columns = 2
  var rotation = 0, channels = 2
  var strip = false, strong = false, blur = false, autoDetect = false
  var archiveFormat = "zip"
  var outputFolder: String = ""
}
struct Job: Identifiable {
  let id = UUID()
  var title: String
  var files: [URL]
  var outputs: [URL] = []
  var state = "En attente"
  var progress = 0.0
  var log = ""
  var failed = false
  var done = false
}
struct ClementineError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
final class CancellationToken: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var process: Process?
  func check() throws {
    lock.lock()
    let c = cancelled
    lock.unlock()
    if c { throw ClementineError("Opération annulée") }
  }
  func attach(_ p: Process) throws {
    lock.lock()
    defer { lock.unlock() }
    if cancelled { throw ClementineError("Opération annulée") }
    process = p
  }
  func cancel() {
    lock.lock()
    cancelled = true
    let p = process
    lock.unlock()
    if p?.isRunning == true { p?.terminate() }
  }
}

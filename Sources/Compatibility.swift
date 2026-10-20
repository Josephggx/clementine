import Foundation

// Directed Tangerine 2.0.2 catalogue plus native iWork input routes.
enum Compatibility {
  static let conversions: [String: [String]] = [
    "jpg": ["png", "webp", "heic", "tiff", "avif", "bmp", "pdf"],
    "png": ["jpg", "webp", "heic", "tiff", "avif", "bmp", "pdf"],
    "webp": ["jpg", "png", "heic", "tiff", "avif", "bmp", "pdf"],
    "heic": ["jpg", "png", "webp", "tiff", "avif", "bmp", "pdf"],
    "tiff": ["jpg", "png", "webp", "heic", "avif", "bmp", "pdf"],
    "svg": ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "pdf"],
    "avif": ["jpg", "png", "webp", "heic", "tiff", "bmp", "pdf"],
    "bmp": ["jpg", "png", "webp", "heic", "tiff", "avif", "pdf"],
    "pdf": ["docx", "pages", "pptx", "xlsx", "jpg", "png", "epub", "txt", "md"],
    "mp3": ["m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"],
    "m4a": ["mp3", "wav", "flac", "ogg", "opus", "aiff", "wma"],
    "wav": ["mp3", "m4a", "flac", "ogg", "opus", "aiff", "wma"],
    "flac": ["mp3", "m4a", "wav", "ogg", "opus", "aiff", "wma"],
    "ogg": ["mp3", "m4a", "wav", "flac", "opus", "aiff", "wma"],
    "opus": ["mp3", "m4a", "wav", "flac", "ogg", "aiff", "wma"],
    "aiff": ["mp3", "m4a", "wav", "flac", "ogg", "opus", "wma"],
    "wma": ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"],
    "mp4": ["mov", "mkv", "webm", "avi", "wmv", "gif", "mp3"],
    "mov": ["mp4", "mkv", "webm", "avi", "wmv", "gif", "mp3"],
    "mkv": ["mp4", "mov", "webm", "avi", "wmv", "gif", "mp3"],
    "webm": ["mp4", "mov", "mkv", "avi", "wmv", "gif", "mp3"],
    "avi": ["mp4", "mov", "mkv", "webm", "wmv", "gif", "mp3"],
    "wmv": ["mp4", "mov", "mkv", "webm", "avi", "gif", "mp3"],
    "gif": ["mp4", "mov", "mkv", "webm", "avi", "wmv"],
    "docx": ["pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"],
    "pages": ["docx", "pdf", "txt", "md", "html", "epub", "png", "jpg"],
    "ppt": ["pdf", "jpg", "png"],
    "pptx": ["pdf", "jpg", "png"],
    "key": ["pptx", "pdf", "jpg", "png"],
    "txt": ["docx", "pages", "pdf", "md", "html", "epub", "jpg", "png"],
    "md": ["docx", "pages", "pdf", "txt", "html", "epub", "png", "jpg"],
    "rtf": ["docx", "pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"],
    "rtfd": ["docx", "pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"],
    "textclipping": ["docx", "pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"],
    "html": [],
    "epub": ["pdf", "docx", "pages", "txt", "md", "html"],
    "xlsx": ["ods", "csv", "tsv", "pdf"],
    "xls": ["xlsx", "ods", "csv", "tsv", "pdf"],
    "ods": ["xlsx", "csv", "tsv", "pdf"],
    "numbers": ["xlsx", "ods", "csv", "tsv", "pdf"],
    "csv": ["xlsx", "ods", "tsv", "pdf"],
    "tsv": ["xlsx", "ods", "csv", "pdf"],
    "srt": ["vtt", "txt"],
    "vtt": ["srt", "txt"],
    "zip": ["tar", "gz"],
    "tar": ["zip", "gz"],
    "gz": ["zip", "tar"],
    "rar": ["zip", "tar", "gz"],
  ]
  static func format(_ url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    return ["jpeg": "jpg", "tif": "tiff", "heif": "heic", "gzip": "gz", "tgz": "gz"][ext] ?? ext
  }
  static func targets(_ urls: [URL]) -> [String] {
    guard let first = urls.first, !urls.contains(where: Family.isFolder) else { return [] }
    return (conversions[format(first)] ?? []).filter { target in
      urls.allSatisfy { (conversions[format($0)] ?? []).contains(target) }
    }
  }
  static func label(_ format: String) -> String { format == "gz" ? "GZIP" : format.uppercased() }

  /// Mirrors the category icons used by the Fonctionnalités tabs.
  static func categoryIcon(_ format: String) -> String {
    let value = format.lowercased()
    if value == "pdf" { return "doc.richtext" }
    if value == "epub" { return "book.closed" }
    if ["jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "avif", "bmp", "svg"].contains(value) {
      return "photo"
    }
    if ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"].contains(value) {
      return "play.rectangle"
    }
    if ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"].contains(value) {
      return "music.note"
    }
    if ["xlsx", "xls", "ods", "csv", "tsv", "numbers"].contains(value) {
      return "tablecells"
    }
    if ["ppt", "pptx", "key", "odp"].contains(value) {
      return "rectangle.on.rectangle"
    }
    if ["zip", "tar", "gz", "rar", "7z", "bz2", "xz"].contains(value) {
      return "doc.zipper"
    }
    if ["srt", "vtt"].contains(value) { return "captions.bubble" }
    return "doc.text"
  }

  /// Category order shared with the Fonctionnalités page.
  static func categoryRank(_ format: String) -> Int {
    let value = format.lowercased()
    if value == "pdf" { return 0 }
    if value == "epub" { return 9 }
    if ["doc", "docx", "pages", "txt", "md", "rtf", "rtfd", "textclipping", "html", "odt"].contains(value) { return 1 }
    if ["xlsx", "xls", "ods", "csv", "tsv", "numbers"].contains(value) { return 2 }
    if ["jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "avif", "bmp", "svg"].contains(value) { return 3 }
    if ["ppt", "pptx", "key", "odp"].contains(value) { return 4 }
    if ["zip", "tar", "gz", "rar", "7z", "bz2", "xz"].contains(value) { return 5 }
    if ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"].contains(value) { return 6 }
    if ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"].contains(value) { return 7 }
    if ["srt", "vtt"].contains(value) { return 8 }
    return 10
  }
}

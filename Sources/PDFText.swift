import Foundation
import PDFKit
import Vision

// PDFKit text is preferred; OCR supplies text for scanned pages.
enum PDFText {
  struct Line {
    let text: String
    let box: CGRect
  }
  static func lines(_ page: PDFPage, engine: Engine, allowOCR: Bool = true) throws -> [Line] {
    if let selection = page.selection(for: page.bounds(for: .mediaBox)) {
      let lines = selection.selectionsByLine().compactMap { selected -> Line? in
        guard let text = selected.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return Line(text: text, box: selected.bounds(for: page))
      }
      if !lines.isEmpty { return lines }
    }
    guard allowOCR else { return [] }
    let image = try engine.renderPage(page, scale: 300.0 / 72.0)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: image).perform([request])
    let bounds = page.bounds(for: .mediaBox)
    return (request.results ?? []).compactMap { result in
      guard let candidate = result.topCandidates(1).first else { return nil }
      let box = result.boundingBox
      return Line(text: candidate.string, box: CGRect(x: box.minX * bounds.width, y: box.minY * bounds.height,
        width: box.width * bounds.width, height: box.height * bounds.height))
    }
  }
  static func text(_ pdf: PDFDocument, engine: Engine) throws -> String {
    try (0..<pdf.pageCount).map { index in
      try engine.token.check()
      guard let page = pdf.page(at: index) else { return "" }
      return try lines(page, engine: engine).sorted { $0.box.midY > $1.box.midY }.map(\.text).joined(separator: "\n")
    }.joined(separator: "\n\n")
  }
  static func spreadsheet(_ pdf: PDFDocument, destination: URL, engine: Engine) throws {
    var rows: [[String]] = []
    for index in 0..<pdf.pageCount {
      try engine.token.check()
      guard let page = pdf.page(at: index) else { continue }
      let lines = try lines(page, engine: engine).sorted { $0.box.midY > $1.box.midY }
      var groups: [[Line]] = []
      for line in lines {
        if let last = groups.indices.last, let first = groups[last].first,
           abs(first.box.midY - line.box.midY) < max(3, min(first.box.height, line.box.height) * 0.4) {
          groups[last].append(line)
        } else { groups.append([line]) }
      }
      rows += groups.map { group in
        group.sorted { $0.box.minX < $1.box.minX }.flatMap { line in
          line.text.components(separatedBy: "\t").flatMap {
            $0.components(separatedBy: "  ").filter { !$0.isEmpty }
          }
        }
      }
      rows.append([])
    }
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".csv")
    defer { try? engine.fm.removeItem(at: temporary) }
    try Documents.csvWrite(rows, delimiter: ",").write(to: temporary, atomically: true, encoding: .utf8)
    _ = try Documents.sheet(temporary, to: destination, engine: engine)
  }
}

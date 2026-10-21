import AppKit
import PDFKit

/// Every source page belongs to exactly one output. Empty drop zones are allowed
/// while editing, and disappear at export without discarding any source page.
enum PDFSplitLayout {
  static func individual(count: Int) -> [[Int]] { (0..<max(0,count)).map { [$0] } }

  static func isComplete(_ groups: [[Int]], count: Int) -> Bool {
    count > 0 && groups.flatMap { $0 }.sorted() == Array(0..<count)
  }

  static func moving(_ page: Int, in groups: [[Int]], to target: Int, before: Int? = nil) -> [[Int]] {
    guard groups.indices.contains(target), groups.flatMap({ $0 }).filter({ $0 == page }).count == 1,
      before == nil || groups[target].contains(before!), before != page else { return groups }
    var result = groups.map { $0.filter { $0 != page } }
    let offset = before.flatMap { result[target].firstIndex(of:$0) } ?? result[target].count
    result[target].insert(page, at:offset)
    return result
  }
}

extension Engine {
  func splitPDF(_ document: PDFDocument, source: URL, stage: URL, options: Options) throws -> [URL] {
    guard document.pageCount > 0, ["pdf","jpg","png"].contains(options.pdfSplitFormat) else {
      throw ClementineError(tr("Choisissez PDF ou Image pour séparer les pages."))
    }
    if options.pdfSplitFormat != "pdf" {
      return try (0..<document.pageCount).map { index in
        try token.check()
        guard let page = document.page(at:index) else { throw ClementineError(tr("Page PDF illisible")) }
        let destination = output(source,options.pdfSplitFormat,stage,suffix:"-page-\(index+1)")
        try saveImage(renderPage(page,scale:2),to:destination,o:options)
        return destination
      }
    }
    guard ["pages","custom"].contains(options.pdfSplitMode) else { throw ClementineError(tr("Mode Split invalide")) }
    let groups = options.pdfSplitMode == "custom"
      ? options.pdfSplitGroups[source.path] ?? []
      : PDFSplitLayout.individual(count:document.pageCount)
    guard PDFSplitLayout.isComplete(groups,count:document.pageCount) else {
      throw ClementineError(tr("Chaque page doit apparaître exactement une fois dans les PDF à créer."))
    }
    return try groups.filter { !$0.isEmpty }.enumerated().map { index, pages in
      try token.check()
      let part = PDFDocument()
      for number in pages {
        guard let page = document.page(at:number)?.copy() as? PDFPage else { throw ClementineError(tr("Page PDF illisible")) }
        part.insert(page,at:part.pageCount)
      }
      let suffix = pages.count == 1 ? "-page-\(pages[0]+1)" : "-partie-\(index+1)"
      let destination = output(source,"pdf",stage,suffix:suffix)
      guard part.write(to:destination) else { throw ClementineError(tr("Écriture du PDF impossible")) }
      return destination
    }
  }
}


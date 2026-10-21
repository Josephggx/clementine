import AppKit
import PDFKit

/// Stable page-instance IDs keep duplicates distinct from their source page.
/// Empty destinations are retained until filled; moving the last page removes its old group.
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
    let emptied = groups.indices.filter { $0 != target && !groups[$0].isEmpty && result[$0].isEmpty }
    for index in emptied.reversed() { result.remove(at:index) }
    return result
  }

  static func isValid(_ groups:[[Int]], count:Int, edits:[Int:ModulePage]?) -> Bool {
    guard let edits else { return isComplete(groups,count:count) }
    let ids = groups.flatMap { $0 }
    return !ids.isEmpty && Set(ids).count == ids.count && Set(ids) == Set(edits.keys)
      && edits.values.allSatisfy { (0..<count).contains($0.index) && $0.rotation % 90 == 0 }
  }

  static func inserting(_ page:Int?, in groups:[[Int]], at index:Int) -> [[Int]] {
    guard (0...groups.count).contains(index) else { return groups }
    var result = groups
    result.insert([],at:index)
    return page.map { moving($0,in:result,to:index) } ?? result
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
    let edits = options.pdfSplitMode == "custom" ? options.pdfSplitEdits[source.path] : nil
    guard PDFSplitLayout.isValid(groups,count:document.pageCount,edits:edits) else {
      throw ClementineError(tr("Placez au moins une page valide dans les PDF à créer."))
    }
    return try groups.filter { !$0.isEmpty }.enumerated().map { index, pages in
      try token.check()
      let part = PDFDocument()
      for number in pages {
        let edit = edits?[number]
        guard let page = document.page(at:edit?.index ?? number)?.copy() as? PDFPage else { throw ClementineError(tr("Page PDF illisible")) }
        page.rotation = (page.rotation + (edit?.rotation ?? 0)) % 360
        part.insert(page,at:part.pageCount)
      }
      let suffix = options.pdfSplitMode == "custom" ? "-partie-\(index+1)" : "-page-\(pages[0]+1)"
      let destination = output(source,"pdf",stage,suffix:suffix)
      guard part.write(to:destination) else { throw ClementineError(tr("Écriture du PDF impossible")) }
      return destination
    }
  }
}


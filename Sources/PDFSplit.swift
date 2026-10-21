import AppKit
import SwiftUI
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
    guard document.pageCount > 0, ["pdf","png"].contains(options.pdfSplitFormat) else {
      throw ClementineError("Choisissez PDF ou Image pour séparer les pages.")
    }
    if options.pdfSplitFormat == "png" {
      return try (0..<document.pageCount).map { index in
        try token.check()
        guard let page = document.page(at:index) else { throw ClementineError("Page PDF illisible") }
        let destination = output(source,"png",stage,suffix:"-page-\(index+1)")
        try saveImage(renderPage(page,scale:2),to:destination,o:options)
        return destination
      }
    }
    guard ["pages","custom"].contains(options.pdfSplitMode) else { throw ClementineError("Mode Split invalide") }
    let groups = options.pdfSplitMode == "custom"
      ? options.pdfSplitGroups[source.path] ?? []
      : PDFSplitLayout.individual(count:document.pageCount)
    guard PDFSplitLayout.isComplete(groups,count:document.pageCount) else {
      throw ClementineError("Chaque page doit apparaître exactement une fois dans les PDF à créer.")
    }
    return try groups.filter { !$0.isEmpty }.enumerated().map { index, pages in
      try token.check()
      let part = PDFDocument()
      for number in pages {
        guard let page = document.page(at:number)?.copy() as? PDFPage else { throw ClementineError("Page PDF illisible") }
        part.insert(page,at:part.pageCount)
      }
      let suffix = pages.count == 1 ? "-page-\(pages[0]+1)" : "-partie-\(index+1)"
      let destination = output(source,"pdf",stage,suffix:suffix)
      guard part.write(to:destination) else { throw ClementineError("Écriture du PDF impossible") }
      return destination
    }
  }
}

private final class PDFSplitHover: ObservableObject { @Published var group: Int? }

struct PDFSplitControls: View {
  @ObservedObject var session: ModuleSession
  @StateObject private var hover = PDFSplitHover()
  private var source: URL { session.files[session.activeFile] }
  private var thumbnails: [Int:NSImage] { session.splitThumbnails[source] ?? [:] }
  private var custom: Bool { session.options.pdfSplitMode == "custom" }
  private var groups: [[Int]] {
    custom ? session.options.pdfSplitGroups[source.path] ?? [] : PDFSplitLayout.individual(count:thumbnails.count)
  }

  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      if session.files.count > 1 {
        Picker("Document",selection:$session.activeFile) {
          ForEach(session.files.indices,id:\.self) { index in Text(session.files[index].lastPathComponent).tag(index) }
        }
      }
      Picker("Format de sortie",selection:$session.options.pdfSplitFormat) {
        Text("PDF").tag("pdf")
        Text("Image · PNG").tag("png")
      }.pickerStyle(.segmented)
      if session.options.pdfSplitFormat == "pdf" {
        Picker("Séparation",selection:$session.options.pdfSplitMode) {
          Text("Une page par PDF").tag("pages")
          Text("Personnalisé").tag("custom")
        }.pickerStyle(.segmented)
        if custom {
          HStack {
            Text("Glissez les pages dans les PDF à créer.").foregroundStyle(.secondary)
            Spacer()
            Button("Réinitialiser") { session.options.pdfSplitGroups[source.path] = PDFSplitLayout.individual(count:thumbnails.count) }
              .buttonStyle(.borderless).disabled(session.busy)
          }
          LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
            ForEach(groups.indices,id:\.self) { index in group(index) }
          }
          newGroup
        } else {
          pageGrid
          Text("\(thumbnails.count) page\(thumbnails.count == 1 ? "" : "s") · un PDF par page")
            .foregroundStyle(.secondary)
        }
      } else {
        pageGrid
        Text("Une image PNG par page, en haute résolution.").foregroundStyle(.secondary)
      }
    }
    .disabled(session.loading || session.busy)
  }

  private var pageGrid: some View {
    LazyVGrid(columns:[GridItem(.adaptive(minimum:90,maximum:130))],spacing:12) {
      ForEach(thumbnails.keys.sorted(),id:\.self) { page in thumbnail(page) }
    }
  }

  private func thumbnail(_ page: Int) -> some View {
    VStack(spacing:6) {
      if let image = thumbnails[page] {
        Image(nsImage:image).resizable().scaledToFit().frame(height:100)
          .shadow(color:.black.opacity(0.12),radius:3,y:1)
      }
      Text("Page \(page+1)").font(.system(size:10)).foregroundStyle(.secondary)
    }.frame(maxWidth:.infinity).padding(8)
      .background(Color.clementineRaisedSurface,in:RoundedRectangle(cornerRadius:9))
  }

  private func group(_ index: Int) -> some View {
    VStack(alignment:.leading,spacing:10) {
      HStack {
        Label("PDF \(index+1)",systemImage:"doc.richtext").fontWeight(.medium)
        Spacer()
        if groups[index].isEmpty {
          Button { session.options.pdfSplitGroups[source.path]?.remove(at:index) } label: { Image(systemName:"xmark") }
            .buttonStyle(.borderless).help("Retirer cette zone vide")
        } else { Text("\(groups[index].count) p.").foregroundStyle(.secondary) }
      }
      if groups[index].isEmpty {
        Text("Déposez des pages ici").foregroundStyle(.secondary)
          .frame(maxWidth:.infinity,minHeight:118)
      } else {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:80))],spacing:8) {
          ForEach(groups[index],id:\.self) { page in
            thumbnail(page)
              .draggable(payload(page))
              .dropDestination(for:String.self) { items,_ in move(items,to:index,before:page) }
          }
        }
      }
    }
    .padding(12).frame(maxWidth:.infinity,alignment:.topLeading)
    .background(citrus.opacity(hover.group == index ? 0.15 : 0.045),in:RoundedRectangle(cornerRadius:12))
    .overlay(RoundedRectangle(cornerRadius:12).stroke(citrus.opacity(hover.group == index ? 0.8 : 0.25)))
    .contentShape(Rectangle())
    .dropDestination(for:String.self) { items,_ in move(items,to:index) } isTargeted: { inside in
      hover.group = inside ? index : (hover.group == index ? nil : hover.group)
    }
    .animation(.easeOut(duration:0.14),value:hover.group)
  }

  private var newGroup: some View {
    Button { session.options.pdfSplitGroups[source.path,default:[]].append([]) } label: {
      Label("Ajouter un PDF · ou déposer une page ici",systemImage:"plus")
        .frame(maxWidth:.infinity,minHeight:44)
        .background(citrus.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(citrus.opacity(0.4),style:StrokeStyle(lineWidth:1,dash:[5,4])))
    }.buttonStyle(.plain).foregroundStyle(citrus)
      .dropDestination(for:String.self) { items,_ in
        guard let page = decodedPage(items) else { return false }
        var updated = groups
        updated.append([])
        session.options.pdfSplitGroups[source.path] = PDFSplitLayout.moving(page,in:updated,to:updated.count-1)
        return true
      }
  }

  private func payload(_ page:Int) -> String { "clementine-split:\(session.id):\(source.path):\(page)" }
  private func decodedPage(_ items:[String]) -> Int? {
    guard !session.busy, items.count == 1,
      let page = thumbnails.keys.first(where:{ payload($0) == items[0] }) else { return nil }
    return page
  }
  private func move(_ items:[String],to group:Int,before:Int? = nil) -> Bool {
    guard let page = decodedPage(items) else { return false }
    session.options.pdfSplitGroups[source.path] = PDFSplitLayout.moving(page,in:groups,to:group,before:before)
    return true
  }
}

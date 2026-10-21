import AppKit
import SwiftUI

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
        Picker(tr("Document"),selection:$session.activeFile) {
          ForEach(session.files.indices,id:\.self) { index in Text(session.files[index].lastPathComponent).tag(index) }
        }
      }
      Picker(tr("Format de sortie"),selection:$session.options.pdfSplitFormat) {
        Text(tr("PDF")).tag("pdf")
        Text("JPEG").tag("jpg")
        Text("PNG").tag("png")
      }.pickerStyle(.menu)
      if session.options.pdfSplitFormat == "pdf" {
        Picker(tr("Séparation"),selection:$session.options.pdfSplitMode) {
          Text(tr("1 par 1")).tag("pages")
          Text(tr("Personnalisé")).tag("custom")
        }.pickerStyle(.segmented)
        if custom {
          HStack {
            Text(tr("Glissez les pages dans les PDF à créer.")).foregroundStyle(.secondary)
            Spacer()
            Button(tr("Réinitialiser")) { session.options.pdfSplitGroups[source.path] = PDFSplitLayout.individual(count:thumbnails.count) }
              .buttonStyle(.borderless).disabled(session.busy)
          }
          LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
            ForEach(groups.indices,id:\.self) { index in group(index) }
          }
          newGroup
        } else {
          pageGrid
          Text(tr("\(thumbnails.count) page\(thumbnails.count == 1 ? "" : "s") · un PDF par page"))
            .foregroundStyle(.secondary)
        }
      } else {
        pageGrid
        Text(session.options.pdfSplitFormat == "jpg"
          ? tr("Une image JPEG par page.")
          : tr("Une image PNG par page, en haute résolution.")).foregroundStyle(.secondary)
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
      Text(tr("Page \(page+1)")).font(.system(size:10)).foregroundStyle(.secondary)
    }.frame(maxWidth:.infinity).padding(8)
      .background(Color.clementineRaisedSurface,in:RoundedRectangle(cornerRadius:9))
  }

  private func group(_ index: Int) -> some View {
    VStack(alignment:.leading,spacing:10) {
      HStack {
        Label(tr("PDF \(index+1)"),systemImage:"doc.richtext").fontWeight(.medium)
        Spacer()
        if groups[index].isEmpty {
          Button { session.options.pdfSplitGroups[source.path]?.remove(at:index) } label: { Image(systemName:"xmark") }
            .buttonStyle(.borderless).help(tr("Retirer cette zone vide"))
        } else { Text(tr("\(groups[index].count) p.")).foregroundStyle(.secondary) }
      }
      if groups[index].isEmpty {
        Text(tr("Déposez des pages ici")).foregroundStyle(.secondary)
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
      Label(tr("Ajouter un PDF · ou déposer une page ici"),systemImage:"plus")
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

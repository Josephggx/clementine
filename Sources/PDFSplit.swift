import AppKit
import SwiftUI
import UniformTypeIdentifiers

private final class PDFSplitHover: ObservableObject {
  @Published var group: Int?
  @Published var insertion: String?
}

struct PDFSplitControls: View {
  @ObservedObject var session: ModuleSession
  @StateObject private var hover = PDFSplitHover()
  private var source: URL { session.files[session.activeFile] }
  private var thumbnails: [Int:NSImage] { session.splitThumbnails[source] ?? [:] }
  private var custom: Bool { session.options.pdfSplitMode == "custom" }
  private var groups: [[Int]] { session.options.pdfSplitGroups[source.path] ?? [] }
  private var edits: [Int:ModulePage] {
    session.options.pdfSplitEdits[source.path] ?? Dictionary(uniqueKeysWithValues:thumbnails.keys.map { ($0,ModulePage(index:$0)) })
  }

  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      if session.files.count > 1 {
        Picker(tr("Document"),selection:$session.activeFile) {
          ForEach(session.files.indices,id:\.self) { index in Text(session.files[index].lastPathComponent).tag(index) }
        }
      }
      Picker(tr("Format de sortie"),selection:$session.options.pdfSplitFormat) {
        Text(tr("PDF")).tag("pdf"); Text("JPEG").tag("jpg"); Text("PNG").tag("png")
      }.pickerStyle(.menu)
      if session.options.pdfSplitFormat == "pdf" {
        Picker(tr("Séparation"),selection:$session.options.pdfSplitMode) {
          Text(tr("1 par 1")).tag("pages"); Text(tr("Personnalisé")).tag("custom")
        }.pickerStyle(.segmented)
      }
      if session.options.pdfSplitFormat == "pdf" && custom {
        HStack {
          Text(tr("Glissez les pages dans les PDF à créer.")).foregroundStyle(.secondary)
          Spacer()
          Button(tr("Réinitialiser")) {
            withAnimation(.snappy(duration:0.2)) {
              session.options.pdfSplitGroups[source.path] = PDFSplitLayout.individual(count:thumbnails.count)
              session.options.pdfSplitEdits.removeValue(forKey:source.path)
            }
          }.buttonStyle(.borderless)
        }
        VStack(spacing:0) {
          ForEach(0...groups.count,id:\.self) { index in
            PDFSplitInsertZone {
              update(PDFSplitLayout.inserting(nil,in:groups,at:index))
            } dropped: { items in
              guard let page=decodedPage(items) else {return false}
              update(PDFSplitLayout.inserting(page,in:groups,at:index));return true
            }
            if index < groups.count { group(index) }
          }
        }
      } else {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:90,maximum:130))],spacing:12) {
          ForEach(thumbnails.keys.sorted(),id:\.self) { page in
            PDFSplitPageCard(image:thumbnails[page],rotation:0,
              title:session.options.pdfSplitFormat == "pdf" ? tr("PDF \(page+1)") : tr("Image \(page+1)"))
          }
        }
      }
    }
    .disabled(session.loading || session.busy)
  }

  private func group(_ index:Int) -> some View {
    VStack(alignment:.leading,spacing:10) {
      HStack {
        Label(tr("PDF \(index+1)"),systemImage:"doc.richtext").fontWeight(.medium)
        Spacer()
        if groups[index].isEmpty {
          Button { var updated=groups; updated.remove(at:index); update(updated) } label: { Image(systemName:"xmark") }
            .buttonStyle(.borderless).help(tr("Retirer cette zone vide"))
        } else { Text(tr("\(groups[index].count) p.")).foregroundStyle(.secondary) }
      }.frame(height:18)
      if groups[index].isEmpty {
        Text(tr("Déposez des pages ici")).foregroundStyle(.secondary)
          .frame(maxWidth:.infinity).frame(height:152)
      } else {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:104,maximum:132))],spacing:10) {
          ForEach(groups[index],id:\.self) { page in
            let edit = edits[page] ?? ModulePage(index:page)
            PDFSplitPageCard(image:thumbnails[edit.index],rotation:edit.rotation,
              title:tr("Page \(edit.index+1)"),editable:true,
              rotate:{ changePage(page,action:"rotate") },
              duplicate:{ changePage(page,action:"duplicate") },
              remove:{ changePage(page,action:"remove") })
              .draggable(payload(page))
              .offset(x:hover.insertion == "\(index):\(page)" ? 7 : 0)
              .animation(.easeOut(duration:0.16),value:hover.insertion)
              .overlay(alignment:.leading) {
                Capsule().fill(citrus).frame(width:3).padding(.vertical,4)
                  .opacity(hover.insertion == "\(index):\(page)" ? 1 : 0).offset(x:-5)
              }
              .dropDestination(for:String.self) { items,_ in
                guard let dragged=decodedPage(items) else {return false}
                move(dragged,to:index,before:page);return true
              } isTargeted: { inside in hover.insertion=inside ? "\(index):\(page)" : nil }

          }
        }.frame(minHeight:152,alignment:.topLeading)
      }
    }
    .padding(12).frame(maxWidth:.infinity,alignment:.topLeading)
    .background(citrus.opacity(hover.group == index ? 0.13 : 0.045),in:RoundedRectangle(cornerRadius:12))
    .overlay(RoundedRectangle(cornerRadius:12).stroke(citrus.opacity(hover.group == index ? 0.7 : 0.25)))
    .contentShape(Rectangle())
    .dropDestination(for:String.self) { items,_ in
      guard let page=decodedPage(items) else {return false}
      move(page,to:index);return true
    } isTargeted: {inside in hover.group=inside ? index : nil}
    .animation(.easeOut(duration:0.16),value:hover.group)
    .animation(.easeOut(duration:0.14),value:hover.insertion)
  }

  private func update(_ groups:[[Int]]) {
    withAnimation(.snappy(duration:0.24)) { session.options.pdfSplitGroups[source.path] = groups }
  }
  private func changePage(_ page:Int,action:String) {
    var mapping=edits, updated=groups
    guard let group=updated.firstIndex(where:{$0.contains(page)}),
      let offset=updated[group].firstIndex(of:page), var entry=mapping[page] else { return }
    switch action {
    case "rotate": entry.rotation=(entry.rotation+90)%360; mapping[page]=entry
    case "duplicate":
      let id=(mapping.keys.max() ?? -1)+1
      mapping[id]=ModulePage(index:entry.index,rotation:entry.rotation)
      updated[group].insert(id,at:offset+1)
    default:
      mapping.removeValue(forKey:page); updated[group].remove(at:offset)
      if updated[group].isEmpty { updated.remove(at:group) }
    }
    session.options.pdfSplitEdits[source.path]=mapping
    update(updated)
  }
  private func payload(_ page:Int) -> String { "clementine-split:\(session.id):\(source.path):\(page)" }
  private func decodedPage(_ items:[String]) -> Int? {
    guard !session.busy, items.count == 1 else {return nil}
    return edits.keys.first {payload($0) == items[0]}
  }
  private func move(_ page:Int,to target:Int,before:Int?=nil) {
    update(PDFSplitLayout.moving(page,in:groups,to:target,before:before))
  }
}

private final class PDFSplitInsertState: ObservableObject {
  @Published var hovered=false
  @Published var targeted=false
}
private final class PDFSplitCardState: ObservableObject {@Published var menu=false}

private struct PDFSplitInsertZone: View {
  var create:()->Void
  var dropped:([String])->Bool
  @StateObject private var hover=PDFSplitInsertState()
  var body: some View {
    HStack(spacing:8) {
        Rectangle().frame(height:1)
        Image(systemName:"plus.circle.fill")
        if hover.hovered || hover.targeted { Text(tr("Nouveau PDF")).font(.caption2) }
        Rectangle().frame(height:1)
      }
      .foregroundStyle(citrus.opacity(hover.hovered || hover.targeted ? 1 : 0.28))
      .frame(height:28).contentShape(Rectangle())
      .onTapGesture(perform:create)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(tr("Insérer un PDF ici"))
      .accessibilityAction(.default) { create() }
      .help(tr("Insérer un PDF ici"))
      .onHover { hover.hovered=$0 }
      .onDrop(of:[UTType.text.identifier],isTargeted:$hover.targeted) { providers in
        guard let provider=providers.first, provider.canLoadObject(ofClass:NSString.self) else {return false}
        _ = provider.loadObject(ofClass:NSString.self) { value,_ in
          guard let value=value as? String else {return}
          DispatchQueue.main.async {_ = dropped([value])}
        }
        return true
      }
      .animation(.easeInOut(duration:0.16),value:hover.hovered || hover.targeted)
  }
}

private struct PDFSplitPageCard: View {
  var image:NSImage?
  var rotation:Int
  var title:String
  var editable=false
  var rotate:()->Void = {}
  var duplicate:()->Void = {}
  var remove:()->Void = {}
  @StateObject private var hover=PDFSplitCardState()
  var body: some View {
    VStack(spacing:6) {
      ZStack(alignment:.topTrailing) {
        if let image {
          let turns=rotation%180 != 0
          Image(nsImage:image).resizable().scaledToFit()
            .frame(width:turns ? 116 : 82,height:turns ? 82 : 116)
            .rotationEffect(.degrees(Double(rotation)))
            .frame(maxWidth:.infinity).frame(height:116).clipped()
            .shadow(color:.black.opacity(0.12),radius:3,y:1)
        }
        if editable {
          HStack(spacing:2) {
            if hover.menu {
              control("arrow.clockwise",title:"Pivoter",action:rotate)
              control("plus.square.on.square",title:"Dupliquer",action:duplicate)
              control("trash",title:"Supprimer",action:remove)
            } else {
              Button {hover.menu=true} label:{Image(systemName:"ellipsis").frame(width:22,height:24)}
                .buttonStyle(.plain).help(tr("Options de la page"))
            }
          }.padding(2).background(.regularMaterial,in:Capsule())
            .onHover { hover.menu=$0 }.animation(.easeOut(duration:0.14),value:hover.menu)
        }
      }.frame(height:116)
      Text(title).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
    }.padding(8).frame(maxWidth:.infinity).frame(height:152)
      .background(Color.clementineRaisedSurface,in:RoundedRectangle(cornerRadius:9))
  }
  private func control(_ icon:String,title:String,action:@escaping()->Void) -> some View {
    Button(action:action) {Image(systemName:icon).font(.system(size:10)).frame(width:22,height:24)}
      .buttonStyle(.borderless).help(trString(title)).accessibilityLabel(trString(title))
  }
}

import AVKit
import AppKit
import PDFKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

let citrus = Color(red: 0.96, green: 0.43, blue: 0.19)
private final class MainHover: ObservableObject {
  @Published var navID: String?
  @Published var actionID: String?
}
private final class WorkspaceFileSelection: ObservableObject {
  @Published var selectedFile: URL?
  @Published var documentsHovered = false
  @Published var hoveredControlID: String?
  @Published var copiedPath: String?
  private var copyFeedbackToken = UUID()

  func copyPath(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
    let token = UUID()
    copyFeedbackToken = token
    copiedPath = path
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
      guard let self, self.copyFeedbackToken == token else { return }
      self.copiedPath = nil
    }
  }
}
struct MainView: View {
  @ObservedObject var state: AppState
  @StateObject private var hover = MainHover()
  @StateObject private var permissionCenter = PermissionCenter.shared
  var body: some View {
    if state.showingOnboarding {
      OnboardingView(state: state)
    } else {
      mainContent
    }
  }

  private var mainContent: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 26) {
        HStack(spacing: 10) {
          ClementineMark(size: 31)
          Text("Clémentine").font(.system(size: 21, weight: .bold, design: .rounded))
        }.padding(.top, 18)
        VStack(spacing: 7) {
          nav("workspace", "Atelier", "square.stack.3d.up")
          nav("settings", "Réglages", "slider.horizontal.3")
          nav("coverage", "Fonctionnalités", "square.grid.3x3")
          nav("permissions", "Autorisations", "lock.shield")
        }
        Spacer()
        UpdateSidebarButton()
      }.padding(20).frame(width: 236).background(.ultraThinMaterial)
      Rectangle()
        .fill(Color.clementineBorder)
        .frame(width:1)
        .ignoresSafeArea(edges:.top)
      VStack(spacing: 0) {
        HStack {
          Text(title).font(.system(size: 27, weight: .semibold, design: .rounded))
          Spacer()
          if state.page == "workspace" {
            let isHovered = hover.actionID == "add-files"
            Button {
              state.browse()
            } label: {
              Label("Ajouter des fichiers", systemImage: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15).frame(height: 34)
                .background(isHovered ? citrus.opacity(0.78) : citrus,
                  in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hover.actionID = $0 ? "add-files" : nil }
            .animation(.easeInOut(duration: 0.18), value: isHovered)
          }
        }.padding(28)
        Divider()
        Group {
          switch state.page {
          case "settings": SettingsView(state: state)
          case "coverage": FeaturesView(state: state)
          case "permissions": PermissionsView()
          default: WorkspaceView(state: state)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.clementinePageBackground)
      }
    }.frame(minWidth: 1076, minHeight: 720)
      .background(Color.clementineCanvas)
      .alert(
        "Impossible de terminer",
        isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })
      ) {
        Button("Fermer", role: .cancel) {}
      } message: {
        Text(state.error ?? "")
      }
  }
  var title: String {
    [
      "workspace": "Atelier",
      "settings": "Réglages", "coverage": "Fonctionnalités",
      "permissions": "Autorisations",
    ][state.page] ?? "Atelier"
  }
  func nav(_ id: String, _ label: String, _ icon: String) -> some View {
    let isSelected = state.page == id
    let isHovered = hover.navID == id && !isSelected
    return Button {
      state.page = id
    } label: {
      HStack(spacing: 11) {
        Image(systemName: icon).frame(width: 20)
        Text(label).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        Spacer()
        if id == "permissions" {
          let hasMissingPermission = ClementinePermission.allCases.contains {
            let status = permissionCenter.status($0)
            return status != .granted && status != .unavailable
          }
          if hasMissingPermission {
            Image(systemName: "xmark.shield.fill")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.red)
              .accessibilityLabel("Autorisations à vérifier")
          }
        }
      }.padding(11).contentShape(Rectangle()).foregroundStyle(
        isSelected ? citrus : Color.primary
      ).background(
        isSelected ? citrus.opacity(0.12) : isHovered ? citrus.opacity(0.12) : .clear,
        in: RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(StableInteractionButtonStyle())
    .onHover { hover.navID = $0 ? id : nil }
    .animation(.easeInOut(duration: 0.2), value: isHovered)
  }
}
struct WorkspaceView: View {
  @ObservedObject var state: AppState
  @StateObject private var fileSelection = WorkspaceFileSelection()
  private var previewFile: URL? {
    if let selectedFile = fileSelection.selectedFile, state.files.contains(selectedFile) { return selectedFile }
    return state.files.first
  }
  private var workspaceTools: [Tool] {
    var seen = Set<String>()
    return (Tool.available(state.files) + Tool.batchCandidates(state.files))
      .filter { seen.insert($0.id).inserted }
  }
  private var workspaceActions: [WheelItem] { WheelActionItems.forURLs(state.files) }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      if state.files.isEmpty {
        empty
          .frame(maxHeight: .infinity)
      } else {
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 20) {
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Text("\(state.files.count) fichier\(state.files.count>1 ? "s" : "")").font(
                    .headline)
                  Spacer()
                  if state.files.count > 1 {
                    let clearHovered = fileSelection.hoveredControlID == "clear-files"
                    Button {
                      state.files = []
                      state.selectedTool = nil
                    } label: {
                      Text("Vider").foregroundStyle(.secondary)
                        .padding(.horizontal,9).padding(.vertical,5)
                        .background(clearHovered ? citrus.opacity(0.14) : .clear,
                          in:RoundedRectangle(cornerRadius:7,style:.continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover {fileSelection.hoveredControlID=$0 ? "clear-files" : nil}
                    .animation(.easeInOut(duration:0.18),value:clearHovered)
                  }
                }
                ScrollView {
                  VStack(spacing: 7) {
                    ForEach(state.files, id: \.self) { u in
                      fileRow(u)
                    }
                  }
                  .padding(.horizontal, 2).padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
              }.frame(maxWidth: .infinity, maxHeight: .infinity)
              if let previewFile {
                PreviewPane(url: previewFile, options: $state.options, selection: false)
                  .frame(width: 270, height: 220)
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                  .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(citrus.opacity(0.24)))
                  .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                  .onTapGesture(count: 2) { NSWorkspace.shared.open(previewFile) }
              }
            }
            if let previewFile {
              let pathHoverID = "path:" + previewFile.path
              let copyHoverID = "copy-path:" + previewFile.path
              let pathHovered = fileSelection.hoveredControlID == pathHoverID
              let copyHovered = fileSelection.hoveredControlID == copyHoverID
              let pathCopied = fileSelection.copiedPath == previewFile.path
              HStack(spacing: 4) {
                Button {
                  NSWorkspace.shared.activateFileViewerSelecting([previewFile])
                } label: {
                  HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(verbatim: previewFile.path).lineLimit(1).truncationMode(.middle)
                  }
                  .font(.system(size: 10))
                  .foregroundStyle(Color.secondary)
                  .padding(.horizontal, 7).padding(.vertical, 4)
                  .background(pathHovered ? citrus.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Afficher dans le Finder")
                .onHover { fileSelection.hoveredControlID = $0 ? pathHoverID : nil }
                .animation(.easeInOut(duration: 0.18), value: pathHovered)
                Button {
                  fileSelection.copyPath(previewFile.path)
                } label: {
                  Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 25, height: 25)
                    .background(copyHovered ? citrus.opacity(0.14) : .clear,
                      in: Circle())
                }
                .buttonStyle(.plain)
                .help(pathCopied ? "Chemin copié" : "Copier le chemin")
                .accessibilityLabel(pathCopied ? "Chemin copié" : "Copier le chemin")
                .onHover { fileSelection.hoveredControlID = $0 ? copyHoverID : nil }
                .animation(.easeInOut(duration: 0.18), value: copyHovered)
                .animation(.easeInOut(duration: 0.15), value: pathCopied)
                Spacer(minLength: 0)
              }
              .opacity(fileSelection.documentsHovered ? 1 : 0)
              .allowsHitTesting(fileSelection.documentsHovered)
              .accessibilityHidden(!fileSelection.documentsHovered)
            }
          }
          .padding(16)
          .frame(height: 284)
          .background(citrus.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(citrus.opacity(0.55), lineWidth: 1.2))
          .contentShape(RoundedRectangle(cornerRadius: 16))
          .onHover { fileSelection.documentsHovered = $0 }
          .animation(.easeInOut(duration: 0.18), value: fileSelection.documentsHovered)

          HStack(alignment: .top, spacing: 14) {
            actionColumn("Conversion") {
              if state.formats.isEmpty {columnEmpty("Aucune conversion disponible")}
              else {
                ForEach(state.formats.sorted { lhs, rhs in
                  let leftRank = Compatibility.categoryRank(lhs)
                  let rightRank = Compatibility.categoryRank(rhs)
                  if leftRank != rightRank { return leftRank < rightRank }
                  return Compatibility.label(lhs).localizedStandardCompare(Compatibility.label(rhs)) == .orderedAscending
                }, id: \.self) { format in
                  workspaceButton(Compatibility.label(format), icon: Compatibility.categoryIcon(format)) {
                    state.submit("convert:" + format)
                  }
                }
              }
            }
            actionColumn("Outils") {
              if workspaceTools.isEmpty {columnEmpty("Aucun outil disponible")}
              else {
                ForEach(workspaceTools.sorted {
                  $0.wheelTitle.localizedStandardCompare($1.wheelTitle) == .orderedAscending
                }) { tool in
                  workspaceButton(tool.wheelTitle, icon: tool.icon) { state.configure(tool.id) }
                }
              }
            }
            actionColumn("Actions") {
              if workspaceActions.isEmpty {columnEmpty("Aucune action disponible")}
              else {
                ForEach(workspaceActions.sorted {
                  $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }, id: \.action) { item in
                  workspaceButton(item.title, wheelIcon: item.icon) {
                    state.fileAction(String(item.action.dropFirst(7)), urls: state.files)
                  }
                }
              }
            }
          }
          .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: 16)
        .fill(state.hoverDrop ? citrus.opacity(0.08) : .clear)
        .padding(10)
    }
    .contentShape(Rectangle())
    .onDrop(
      of: [UTType.fileURL.identifier], isTargeted: $state.hoverDrop, perform: state.acceptDrop
    )
    .animation(.easeInOut(duration: 0.18), value: state.hoverDrop)
    .onChange(of: state.files) { _, files in
      if let selectedFile = fileSelection.selectedFile, !files.contains(selectedFile) { fileSelection.selectedFile = files.first }
      else if fileSelection.selectedFile == nil { fileSelection.selectedFile = files.first }
    }
  }
  var empty: some View {
    let chooseHovered = fileSelection.hoveredControlID == "empty-choose-files"
    return Button { state.browse() } label: {
      VStack(spacing: 20) {
        ZStack {
          Circle().fill(citrus.opacity(0.04)).frame(width: 320, height: 320)
          ForEach(0..<8) { i in
            let angle = Double(i) * Double.pi / 4 - Double.pi / 2
            RoundedRectangle(cornerRadius: 18).fill(citrus.opacity(0.08)).overlay {
              Text(["JPG", "PNG", "WEBP", "HEIC", "PDF", "MP4", "MP3", "ZIP"][i]).font(
                .system(size: 11, weight: .bold, design: .rounded)
              ).foregroundStyle(citrus.opacity(0.8))
            }.frame(width: 69, height: 62).rotationEffect(.degrees(Double(i) * 45)).overlay {
              EmptyView()
            }.offset(x: cos(angle) * 111, y: sin(angle) * 111)
          }
          Image(systemName: "doc.badge.arrow.up").font(.system(size: 52, weight: .ultraLight))
            .foregroundStyle(citrus)
        }.frame(height: 320)
        Text("Déposez vos fichiers ici").font(.system(size: 25, weight: .semibold, design: .rounded))
        Text("Choisir des fichiers")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 17)
          .frame(height: 38)
          .background(chooseHovered ? citrus.opacity(0.76) : citrus, in: Capsule(style: .continuous))
          .onHover { hovering in
            fileSelection.hoveredControlID = hovering ? "empty-choose-files" : nil
          }
          .animation(.easeInOut(duration: 0.18), value: chooseHovered)
      }
      .foregroundStyle(Color.primary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.vertical, 20)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .accessibilityLabel("Choisir des fichiers")
  }
  func size(_ u: URL) -> String {
    let n = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) + " · "
      + Family.of(u).singularName
  }

  private func fileRow(_ url: URL) -> some View {
    let selectable = state.files.count > 1
    let selected = selectable && previewFile == url
    let previewHoverID = "preview:" + url.path
    let finderHoverID = "finder:" + url.path
    let openHoverID = "open:" + url.path
    let removeHoverID = "remove:" + url.path
    let previewHovered = fileSelection.hoveredControlID == previewHoverID
    let finderHovered = fileSelection.hoveredControlID == finderHoverID
    let openHovered = fileSelection.hoveredControlID == openHoverID
    let removeHovered = fileSelection.hoveredControlID == removeHoverID
    return HStack {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 30, height: 30)
      VStack(alignment: .leading) {
        Text(url.lastPathComponent).lineLimit(1)
        Text(size(url)).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if selectable {
        Button {
          fileSelection.selectedFile = url
        } label: {
          Image(systemName: "eye").foregroundStyle(selected ? citrus : Color.secondary)
            .frame(width: 25, height: 25)
            .background(previewHovered ? citrus.opacity(0.16) : .clear,
              in: Circle())
        }
        .buttonStyle(.plain).help(selected ? "Document prévisualisé" : "Afficher l’aperçu")
        .accessibilityLabel(selected ? "Document prévisualisé : \(url.lastPathComponent)" : "Afficher l’aperçu de \(url.lastPathComponent)")
        .onHover { fileSelection.hoveredControlID = $0 ? previewHoverID : nil }
        .animation(.easeInOut(duration: 0.18), value: previewHovered)
        .animation(.easeInOut(duration: 0.18), value: selected)
      }
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      } label: {
        Image(systemName: "folder").foregroundStyle(.secondary)
          .frame(width: 25, height: 25)
          .background(finderHovered ? citrus.opacity(0.16) : .clear,
            in: Circle())
      }
      .buttonStyle(.plain).help("Afficher dans le Finder")
      .onHover { fileSelection.hoveredControlID = $0 ? finderHoverID : nil }
      .animation(.easeInOut(duration: 0.18), value: finderHovered)
      Button {
        NSWorkspace.shared.open(url)
      } label: {
        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
          .frame(width: 25, height: 25)
          .background(openHovered ? citrus.opacity(0.16) : .clear,
            in: Circle())
      }
      .buttonStyle(.plain).help("Ouvrir le document")
      .accessibilityLabel("Ouvrir \(url.lastPathComponent)")
      .onHover { fileSelection.hoveredControlID = $0 ? openHoverID : nil }
      .animation(.easeInOut(duration: 0.18), value: openHovered)
      Button {
        state.files.removeAll { $0 == url }
        if fileSelection.selectedFile == url { fileSelection.selectedFile = state.files.first }
      } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
          .frame(width: 25, height: 25)
          .background(removeHovered ? citrus.opacity(0.16) : .clear,
            in: Circle())
      }
      .buttonStyle(.plain)
      .onHover { fileSelection.hoveredControlID = $0 ? removeHoverID : nil }
      .animation(.easeInOut(duration: 0.18), value: removeHovered)
    }
    .padding(8)
    .background(Color.clementineRaisedSurface.opacity(selectable ? 0.72 : 0.46),
      in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectable ? citrus.opacity(0.10) : Color.clear))
  }

  private func actionColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.system(size: 13, weight: .semibold))
      ViewThatFits(in: .vertical) {
        VStack(alignment: .leading, spacing: 9) {
          content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .fixedSize(horizontal: false, vertical: true)

        ScrollView {
          VStack(alignment: .leading, spacing: 9) {
            content()
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func columnEmpty(_ message:String)->some View {
    Text(message).font(.system(size:11,weight:.light)).foregroundStyle(.tertiary)
      .padding(.horizontal,3).padding(.top,8)
      .frame(maxWidth:.infinity,alignment:.leading)
  }

  private func workspaceButton(_ title: String, icon: String? = nil, wheelIcon: String? = nil,
                               action: @escaping () -> Void) -> some View {
    let hoverID = "workspace:" + title
    let isHovered = fileSelection.hoveredControlID == hoverID
    return Button(action: action) {
      HStack(spacing: 9) {
        if let wheelIcon {
          WheelGlyphView(key: wheelIcon).frame(width: 19, height: 19).foregroundStyle(citrus)
        } else if let icon {
          Image(systemName: icon).font(.system(size: 14)).foregroundStyle(citrus).frame(width: 19)
        }
        Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
        Spacer(minLength: 2)
        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .background(isHovered ? citrus.opacity(0.14) : Color.primary.opacity(0.045),
        in: RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .onHover { fileSelection.hoveredControlID = $0 ? hoverID : nil }
    .animation(.easeInOut(duration: 0.18), value: isHovered)
  }
}

struct WheelGlyphView: NSViewRepresentable {
  let key: String
  func makeNSView(context: Context) -> NSView { GlyphHost(key: key) }
  func updateNSView(_ view: NSView, context: Context) { (view as? GlyphHost)?.key = key; view.needsDisplay = true }
  private final class GlyphHost: NSView {
    var key: String
    init(key: String) { self.key = key; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
      guard let context = NSGraphicsContext.current?.cgContext else { return }
      WheelGlyph.draw(key, in: bounds.insetBy(dx: 0.5, dy: 0.5), color: NSColor(hex: "F56D30"), context: context)
    }
  }
}
final class PreviewSelection: ObservableObject { @Published var rect: CGRect = .zero }
final class MovieThumbnail: ObservableObject {
  @Published var image: NSImage?
  private var generation = UUID()
  func load(_ url: URL, at seconds: Double) {
    let id = UUID()
    generation = id
    DispatchQueue.global(qos: .userInitiated).async {
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
      generator.appliesPreferredTrackTransform = true
      let frame = try? generator.copyCGImage(
        at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
      DispatchQueue.main.async {
        guard self.generation == id else { return }
        self.image = frame.map {
          NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }
      }
    }
  }
}
struct PreviewPane: View {
  let url: URL
  @Binding var options: Options
  var selection: Bool
  @StateObject private var selectionModel = PreviewSelection()
  @StateObject private var movieThumbnail = MovieThumbnail()
  var previewImage: NSImage? {
    Family.of(url) == .video ? movieThumbnail.image : NSImage(contentsOf: url)
  }
  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color.black.opacity(0.04)
        if let image = previewImage,
          Family.of(url) == .image || (Family.of(url) == .video && selection)
        {
          Image(nsImage: image).resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(8)
          if selection {
            Rectangle().fill(citrus.opacity(0.22)).overlay(Rectangle().stroke(citrus, lineWidth: 2))
              .frame(width: selectionModel.rect.width, height: selectionModel.rect.height).position(
                x: selectionModel.rect.midX, y: selectionModel.rect.midY)
            Color.clear.contentShape(Rectangle()).gesture(
              DragGesture(minimumDistance: 1).onChanged { value in
                let bounds = imageBounds(image, geo.size)
                let origin = CGPoint(
                  x: min(max(value.startLocation.x, bounds.minX), bounds.maxX),
                  y: min(max(value.startLocation.y, bounds.minY), bounds.maxY))
                let end = CGPoint(
                  x: min(max(value.location.x, bounds.minX), bounds.maxX),
                  y: min(max(value.location.y, bounds.minY), bounds.maxY))
                selectionModel.rect = CGRect(
                  x: min(origin.x, end.x), y: min(origin.y, end.y), width: abs(origin.x - end.x),
                  height: abs(origin.y - end.y))
                var proposed = CGRect.zero
                let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
                let pixelWidth = Double(cg?.width ?? Int(image.size.width))
                let pixelHeight = Double(cg?.height ?? Int(image.size.height))
                options.x = Int(
                  (selectionModel.rect.minX - bounds.minX) / bounds.width * pixelWidth)
                options.y = Int(
                  (selectionModel.rect.minY - bounds.minY) / bounds.height * pixelHeight)
                options.width = Int(selectionModel.rect.width / bounds.width * pixelWidth)
                options.height = Int(selectionModel.rect.height / bounds.height * pixelHeight)
              })
          }
        } else if Family.of(url) == .pdf {
          PDFPreview(url: url)
        } else if Family.of(url) == .video || Family.of(url) == .audio {
          MediaPreview(url: url)
        } else {
          VStack(spacing: 8) {
            Image(systemName: Family.of(url).icon).font(.system(size: 45, weight: .ultraLight))
              .foregroundStyle(citrus)
            Text(previewFormatLabel).font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 10).padding(.vertical, 5)
              .background(Color.primary.opacity(0.065), in: Capsule())
          }
        }
      }
    }.onAppear { loadMovie() }.onChange(of: url) { _, _ in loadMovie() }.onChange(of: options.start)
    { _, _ in loadMovie() }.onChange(of: selection) { _, _ in loadMovie() }
  }
  func loadMovie() {
    if Family.of(url) == .video && selection { movieThumbnail.load(url, at: options.start) }
  }
  private var previewFormatLabel: String {
    let format = Compatibility.format(url)
    let names = ["md": "Markdown", "pages": "Pages", "numbers": "Numbers", "key": "Keynote"]
    return names[format] ?? (format.isEmpty ? Family.of(url).singularName : Compatibility.label(format))
  }
  func imageBounds(_ image: NSImage, _ size: CGSize) -> CGRect {
    let scale = min((size.width - 16) / image.size.width, (size.height - 16) / image.size.height)
    let s = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    return CGRect(
      x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width,
      height: s.height)
  }
}
struct PDFPreview: NSViewRepresentable {
  let url: URL
  func makeNSView(context: Context) -> PDFView {
    let v = PDFView()
    v.autoScales = true
    v.document = PDFDocument(url: url)
    return v
  }
  func updateNSView(_ view: PDFView, context: Context) {
    if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
  }
}
struct MediaPreview: NSViewRepresentable {
  let url: URL
  func makeNSView(context: Context) -> AVPlayerView {
    let v = AVPlayerView()
    v.player = AVPlayer(url: url)
    return v
  }
  func updateNSView(_ v: AVPlayerView, context: Context) {
    if (v.player?.currentItem?.asset as? AVURLAsset)?.url != url {
      v.player?.pause()
      v.player = AVPlayer(url: url)
    }
  }
  static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause() }
}
struct SettingsView: View {
  @ObservedObject var state: AppState

  var body: some View {
    Form {
      Section("Clémentine") {
        Toggle("Lancer au démarrage", isOn: Binding(
          get: { state.login }, set: { state.setLaunchAtLogin($0) }))
        Picker("Apparence", selection: $state.appearance) {
          Text("Selon le système").tag("system")
          Text("Clair").tag("light")
          Text("Sombre").tag("dark")
        }
        modifier("Roue des formats", state.wheelModifierBinding("formats"))
        modifier("Roue des outils", state.wheelModifierBinding("tools"))
        modifier("Roue des actions", state.wheelModifierBinding("actions"))
        Picker("Survol de la Clémentine", selection: hoverFeedback) {
          Text("Son + retour haptique").tag("both")
          Text("Son").tag("sound")
          Text("Retour haptique").tag("haptic")
        }
        Button {
          state.onboardingPage = 0
          withAnimation(.easeInOut(duration: 0.24)) { state.showingOnboarding = true }
        } label: {
          Label("Voir l’onboarding", systemImage: "play.rectangle")
        }
      }
      Section {
        Picker("Nouveau float", selection: $state.floatBehavior) {
          Text("Créer une fenêtre").tag("new")
          Text("Ajouter à la dernière fenêtre").tag("append")
        }
        LabeledContent("Qualité des conversions") {
          Slider(value: $state.options.quality, in: 0.3...1)
            .frame(width: 240)
          Text("\(Int(state.options.quality*100)) %")
        }
        Toggle("Retirer les métadonnées lors des conversions", isOn: $state.options.strip)
        Picker("Format d’archivage par défaut", selection: $state.options.archiveFormat) {
          Text("ZIP").tag("zip")
          Text("TAR").tag("tar")
          Text("TAR + GZIP").tag("gz")
          Text("RAR").tag("rar")
        }
        Picker("PDF → DOCX / Pages", selection: $state.options.pdfOfficeLayout) {
          Text("Automatique · texte éditable, scans en images").tag("automatic")
          Text("Fidélité visuelle · pages en images").tag("preservePages")
          Text("Texte éditable · OCR des scans").tag("editable")
        }
        Picker("PDF → EPUB", selection: $state.options.epubLayout) {
          Text("Texte adaptable à l’écran").tag("adjustableText")
          Text("Fidélité visuelle · pages en images").tag("preservePages")
        }
      } header: {
        Text("Préférences")
      } footer: {
        AppVersionLabel()
      }
    }.formStyle(.grouped).onDisappear { state.persist() }
      .onChange(of: state.sound) { _, _ in state.persist() }
      .onChange(of: state.haptics) { _, _ in state.persist() }
      .onChange(of: state.options.quality) { _, _ in state.persist() }
      .onChange(of: state.options.strip) { _, _ in state.persist() }
      .onChange(of: state.appearance) { _, _ in state.persist(); state.applyAppearance() }
      .onChange(of: state.options.archiveFormat) { _, _ in state.persist() }
  }
  var hoverFeedback: Binding<String> {
    Binding(get: {
      if state.sound && state.haptics { return "both" }
      if state.sound { return "sound" }
      if state.haptics { return "haptic" }
      return "both"
    }, set: { value in
      state.sound = value == "both" || value == "sound"
      state.haptics = value == "both" || value == "haptic"
      state.persist()
    })
  }
  func modifier(_ title: String, _ value: Binding<String>) -> some View {
    Picker(title, selection: value) {
      Text("⌥ Option").tag("option")
      Text("⇧ Maj").tag("shift")
      Text("⌘ Commande").tag("command")
      Text("⌃ Contrôle").tag("control")
      Text("fn / 🌐").tag("fn")
      Text("fn + ⇧ Maj").tag("fnShift")
      Text("Désactivée").tag("none")
    }
  }
}

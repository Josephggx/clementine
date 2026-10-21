import AppKit
import SwiftUI

private struct FeatureCategory: Identifiable {
  let id: String
  let title: String
  let icon: String
  let example: String
  let formats: [String]

  static let all: [FeatureCategory] = [
    .init(id: "pdf", title: "PDF", icon: "doc.richtext", example: "pdf", formats: ["pdf"]),
    .init(id: "documents", title: "Documents", icon: "doc.text", example: "docx",
      formats: ["docx", "pages", "txt", "md", "rtf", "rtfd", "textclipping", "html"]),
    .init(id: "sheets", title: "Tableurs", icon: "tablecells", example: "xlsx",
      formats: ["xlsx", "xls", "ods", "csv", "tsv", "numbers"]),
    .init(id: "images", title: "Images", icon: "photo", example: "jpg",
      formats: ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "svg"]),
    .init(id: "slides", title: "Présentations", icon: "rectangle.on.rectangle", example: "pptx",
      formats: ["ppt", "pptx", "key"]),
    .init(id: "archives", title: "ZIP", icon: "doc.zipper", example: "zip",
      formats: ["zip", "tar", "gz", "rar"]),
    .init(id: "folders", title: "Dossier", icon: "folder", example: "", formats: []),
    .init(id: "video", title: "Vidéo", icon: "play.rectangle", example: "mp4",
      formats: ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]),
    .init(id: "audio", title: "Audio", icon: "music.note", example: "mp3",
      formats: ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]),
    .init(id: "subtitles", title: "Sous-titres", icon: "captions.bubble", example: "srt",
      formats: ["srt", "vtt"]),
    .init(id: "epub", title: "EPUB", icon: "book.closed", example: "epub", formats: ["epub"]),
  ]
}

/// Uses the same drawing and geometry as the drag wheel, without offering a fake drop target.
struct FeatureWheelPreview: NSViewRepresentable {
  let items: [WheelItem]
  let appearance: String
  let soundFeedback: Bool
  let hapticFeedback: Bool
  var idleLabel: String? = nil
  var previewSelection: Int? = nil
  var drivesSelection = false
  var allowsPointerInteraction = true
  var animateOpening = false
  var onChoose: ((WheelItem) -> Void)? = nil
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> WheelSurface {
    let view = WheelSurface(frame: NSRect(x: 0, y: 0, width: WheelGeometry.side, height: WheelGeometry.side),
      files: [], items: items, preview: true)
    view.appearance = ClementineAppearance(rawValue: appearance)?.nsAppearance
    view.wheel.previewLabel = idleLabel ?? (onChoose == nil ? nil : "Cliquez pour\ndécouvrir")
    view.wheel.showsIdleCenter = idleLabel != nil || onChoose != nil
    view.wheel.previewDefaultSelection = nil
    view.wheel.allowsPointerInteraction = allowsPointerInteraction
    if drivesSelection { view.wheel.setPreviewSelection(previewSelection) }
    if animateOpening && !context.coordinator.openingVisible { view.wheel.beginOpening() }
    context.coordinator.openingVisible = animateOpening
    context.coordinator.onChoose = onChoose
    view.wheel.onChoose = { [weak coordinator = context.coordinator] item, _, _ in
      coordinator?.onChoose?(item)
      return false
    }
    view.wheel.onHoverFeedback = { [weak coordinator = context.coordinator] in
      guard let coordinator else { return }
      WheelHoverFeedback.shared.perform(sound: coordinator.soundFeedback,
        haptic: coordinator.hapticFeedback)
    }
    context.coordinator.soundFeedback = soundFeedback
    context.coordinator.hapticFeedback = hapticFeedback
    return view
  }
  func updateNSView(_ view: WheelSurface, context: Context) {
    view.wheel.allowsPointerInteraction = allowsPointerInteraction
    view.appearance = ClementineAppearance(rawValue: appearance)?.nsAppearance
    view.wheel.needsDisplay = true
    if animateOpening && !context.coordinator.openingVisible { view.wheel.beginOpening() }
    context.coordinator.openingVisible = animateOpening
    context.coordinator.onChoose = onChoose
    context.coordinator.soundFeedback = soundFeedback
    context.coordinator.hapticFeedback = hapticFeedback
    if view.wheel.items.map(\.action) != items.map(\.action) {
      view.update(items)
      view.wheel.previewDefaultSelection = nil
      if animateOpening { view.wheel.beginOpening() }
    }
    if drivesSelection { view.wheel.setPreviewSelection(previewSelection) }
    view.wheel.previewLabel = idleLabel ?? (onChoose == nil ? nil : "Cliquez pour\ndécouvrir")
    view.wheel.showsIdleCenter = idleLabel != nil || onChoose != nil
  }
  final class Coordinator {
    var onChoose: ((WheelItem) -> Void)?
    var openingVisible = false
    var soundFeedback = true
    var hapticFeedback = true
  }
}

private final class FeatureSelection: ObservableObject {
  @Published var selectedID = "pdf"
  @Published var selectedFormat = ""
  @Published var hoveredTabID: String?
  @Published var inspectedTool: Tool?
}

struct FeaturesView: View {
  @ObservedObject var state: AppState
  @Environment(\.colorScheme) private var colorScheme
  @StateObject private var selection = FeatureSelection()
  private var category: FeatureCategory {
    FeatureCategory.all.first { $0.id == selection.selectedID } ?? FeatureCategory.all[0]
  }
  private func exampleURL(_ format: String) -> URL { URL(fileURLWithPath: "/exemple.\(format)") }
  private var exampleURL: URL {
    category.id == "folders" ? URL(fileURLWithPath: "/Dossier", isDirectory: true)
      : exampleURL(selection.selectedFormat.isEmpty ? category.example : selection.selectedFormat)
  }
  private var sourceFormats: [String] {
    selection.selectedFormat.isEmpty ? category.formats : [selection.selectedFormat]
  }
  private var conversions: [String] {
    var seen = Set<String>()
    return sourceFormats.flatMap { Compatibility.targets([exampleURL($0)]) }
      .filter { seen.insert($0).inserted }
  }
  private var tools: [Tool] {
    if category.id == "folders" { return Tool.catalogue(for: exampleURL) }
    var seen = Set<String>()
    return sourceFormats.flatMap { Tool.catalogue(for: exampleURL($0)) }
      .filter { seen.insert($0.id).inserted }
  }
  private var formatItems: [WheelItem] {
    conversions.map { WheelItem(title: Compatibility.label($0), icon: "", action: "convert:" + $0) }
  }
  private var toolItems: [WheelItem] {
    tools.map { WheelItem(title: $0.wheelTitle, icon: WheelGlyph.key($0.id, family: Family.of(exampleURL)), action: $0.id) }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 23) {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(FeatureCategory.all) { item in
              let isSelected = selection.selectedID == item.id
              let isHovered = selection.hoveredTabID == item.id && !isSelected
              Button { selection.selectedID = item.id; selection.selectedFormat = "" } label: {
                Label(trString(item.title), systemImage: item.icon)
                  .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                  .foregroundStyle(isSelected ? citrus : Color.secondary)
                  .padding(.horizontal, 15).padding(.vertical, 11)
                  .background(isSelected ? citrus.opacity(0.14) :
                    isHovered ? citrus.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 13))
                  .shadow(color: .black.opacity(isSelected || isHovered ? 0.08 : 0), radius: 8, y: 2)
              }
              .buttonStyle(StableInteractionButtonStyle())
              .onHover { selection.hoveredTabID = $0 ? item.id : nil }
              .animation(.easeInOut(duration: 0.22).delay(0.04),
                value: isHovered)
            }
          }.padding(.horizontal, 12).padding(.vertical, 14)
        }.scrollIndicators(.hidden)

        if category.formats.count > 1 {
          HStack {
            Picker("", selection: $selection.selectedFormat) {
              Text(tr("Choisir un format")).tag("")
              ForEach(category.formats.sorted {
                Compatibility.label($0).localizedStandardCompare(Compatibility.label($1)) == .orderedAscending
              }, id: \.self) { format in
                Text(trString(Compatibility.label(format))).tag(format)
              }
            }
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(alignment: .top, spacing: 20) {
          wheelCard(title: "Conversion", symbol: state.conversionModifier, items: formatItems)
          wheelCard(title: "Outils", symbol: state.toolModifier, items: toolItems) { item in
              guard let tool = tools.first(where: { $0.id == item.action }) else { return }
              DispatchQueue.main.async {
                if selection.inspectedTool?.id != tool.id {
                  withAnimation(.easeInOut(duration: 0.18)) { selection.inspectedTool = tool }
                }
              }
          }
        }
        wheelCard(title: "Actions", symbol: state.actionModifier,
          items: WheelActionItems.forURLs([exampleURL], preview: true))
      }.padding(24)
    }
      .overlay {
        if let tool = selection.inspectedTool {
          ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
              .onTapGesture { closeTool() }
            FeatureToolSheet(tool: tool, family: Family.of(exampleURL),
              onClose: { closeTool() }, onTry: { urls in
          let eligible = tool.id == "archive"
            ? Tool.available(urls)
            : tool.group ? Tool.batchCandidates(urls) : Tool.available(urls)
          guard eligible.contains(where: { $0.id == tool.id }) else {
            return false
          }
          selection.inspectedTool = nil
          state.add(urls, replace: true)
          state.page = "workspace"
          let opensWithoutSettings = tool.id == "mute" || tool.id == "extract" || tool.id == "archive"
            || (tool.id == "mergepdf" && Family.of(urls[0]) == .image)
          if opensWithoutSettings { state.selectedTool = tool.id }
          else { DispatchQueue.main.async { state.configure(tool.id) } }
          return true
              })
          }
          .transition(.opacity)
          .onExitCommand { closeTool() }
        }
      }
      .animation(.easeInOut(duration: 0.18), value: selection.inspectedTool?.id)
  }

  private func closeTool() {
    withAnimation(.easeInOut(duration: 0.18)) { selection.inspectedTool = nil }
  }

  private func wheelColumn(title: String, items: [WheelItem], onChoose: ((WheelItem) -> Void)? = nil) -> some View {
    FeatureWheelPreview(items: items, appearance: state.appearance,
      soundFeedback: state.sound, hapticFeedback: state.haptics, onChoose: onChoose)
      .frame(width: WheelGeometry.side, height: WheelGeometry.side)
      .id(state.appearance)
    .frame(maxWidth: .infinity)
  }

  private func shortcutName(_ symbol: String) -> String {
    switch symbol {
    case "fnShift": return "Fn + Maj"
    case "shift": return "Maj"
    case "command": return "Commande"
    case "option": return "Option"
    case "control": return "Contrôle"
    case "none": return "Désactivé"
    default: return symbol.capitalized
    }
  }

  private func typeIcon(_ title: String) -> String {
    switch title {
    case "Conversion": return "arrow.left.arrow.right"
    case "Outils": return "slider.horizontal.3"
    default: return "bolt"
    }
  }

  private func cornerBadge(icon: String, text: String, accent: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon).font(.system(size: 10, weight: .semibold))
      Text(trString(text)).font(.system(size: 10.5, weight: .semibold))
    }
    .foregroundStyle(accent ? citrus : Color.secondary)
    .padding(.horizontal, 10).frame(height: 28)
    .background(accent ? citrus.opacity(0.10) : Color.primary.opacity(0.055),
      in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
      .stroke(accent ? citrus.opacity(0.28) : Color.clementineBorder, lineWidth: 0.8))
  }

  private func wheelCard(title: String, symbol: String, items: [WheelItem], onChoose: ((WheelItem) -> Void)? = nil) -> some View {
    wheelColumn(title: title, items: items, onChoose: onChoose)
      .padding(.top, 55).padding(.bottom, 24)
      .frame(maxWidth: .infinity)
      .background(Color.clementineGroupedSurface,
        in: RoundedRectangle(cornerRadius: 24))
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.clementineBorder))
      .overlay(alignment: .topLeading) {
        cornerBadge(icon: typeIcon(title), text: title, accent: false).padding(16)
      }
      .overlay(alignment: .topTrailing) {
        HStack(spacing: 6) {
          Text(trString(WheelShortcutAssignments.symbol(symbol)))
            .font(.system(size: 12, weight: .semibold))
          Text(trString(shortcutName(symbol))).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(citrus)
        .padding(.horizontal, 10).frame(height: 28)
        .background(citrus.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(citrus.opacity(0.28), lineWidth: 0.8))
        .padding(16)
      }
  }
}

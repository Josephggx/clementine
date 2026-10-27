import AppKit
import SwiftUI

struct FeatureToolCopy {
  let summary: String
  let benefits: [String]

  static func forTool(_ tool: Tool) -> FeatureToolCopy {
    let entries: [String: (String, String, String)] = [
      "compress": ("Réduisez la taille du fichier en préservant l’original.", "Choisissez le niveau de compression", "Contrôlez la taille du résultat"),
      "crop": ("Gardez précisément la zone utile du visuel.", "Ajustez le cadrage", "Choisissez un format de sortie"),
      "adjust": ("Retouchez la lumière, les couleurs et les détails.", "Voyez le résultat en direct", "Réglez chaque effet séparément"),
      "annotate": ("Recadrez et annotez votre image dans le même éditeur.", "Passez de Crop à Annotate sans perdre vos modifications", "Enregistrez le cadrage et les annotations ensemble"),
      "redact": ("Masquez les éléments sensibles d’une image ou vidéo.", "Déplacez les zones de masquage", "Choisissez le flou ou un aplat"),
      "frame": ("Placez une image sur un nouveau fond.", "Choisissez une couleur ou une image", "Ajustez les marges et les coins"),
      "collage": ("Réunissez plusieurs images sur une planche.", "Choisissez la disposition", "Réglez l’espacement et le fond"),
      "metadata": ("Inspectez les informations intégrées au fichier.", "Parcourez les champs", "Repérez les données techniques"),
      "strip": ("Consultez et retirez les métadonnées du fichier.", "Recherchez les champs", "Supprimez les données souhaitées"),
      "trim": ("Gardez un passage précis d’un média.", "Déplacez les points de début et de fin", "Prévisualisez avant l’export"),
      "split": ("Divisez le fichier en plusieurs parties.", "Placez les points de coupe", "Exportez les parties séparément"),
      "join": ("Assemblez plusieurs médias dans un seul fichier.", "Réordonnez les éléments", "Vérifiez l’ordre avant export"),
      "speed": ("Accélérez ou ralentissez une vidéo.", "Réglez précisément la vitesse", "Prévisualisez le mouvement"),
      "snapshot": ("Exportez des images prises dans une vidéo.", "Choisissez les instants exacts", "Gardez la résolution d’origine"),
      "mute": ("Retirez la piste sonore d’une vidéo.", "Conservez l’image intacte", "Créez directement une nouvelle copie"),
      "normalize": ("Équilibrez le volume d’un enregistrement.", "Fixez le niveau cible", "Évitez les pics trop forts"),
      "bleep": ("Masquez un passage audio sensible.", "Positionnez le signal sonore", "Écoutez le résultat avant export"),
      "channels": ("Réglez les canaux gauche et droit.", "Passez en mono ou en stéréo", "Ajustez chaque canal"),
      "visualize": ("Transformez un audio en vidéo animée.", "Choisissez l’apparence de l’onde", "Réglez le format de la vidéo"),
      "mergepdf": ("Combinez des PDF et des images en un document.", "Réordonnez les fichiers", "Exportez un seul PDF"),
      "organize": ("Modifiez l’ordre et la structure d’un PDF.", "Déplacez ou pivotez les pages", "Supprimez celles qui sont inutiles"),
      "extract": ("Ouvrez une archive et récupérez son contenu.", "Parcourez les fichiers", "Choisissez leur destination"),
      "archive": ("Compressez un ou plusieurs fichiers dans un ZIP.", "Utilisez votre format préféré", "Gardez les fichiers d’origine"),
    ]
    let value = entries[tool.id] ?? ("Traitez ce fichier directement sur votre Mac.", "Ajustez les réglages", "Exportez une nouvelle copie")
    return .init(summary: value.0, benefits: [value.1, value.2])
  }
}

/// The catalogue embeds the real module view with deterministic demo data. Any production module
/// change is therefore reflected here automatically instead of being copied by hand.
private final class FeatureToolSheetState: ObservableObject {
  @Published var invalidSelection = false
  @Published var closeHovered = false
}

struct FeatureToolSheet: View {
  let tool: Tool
  let family: Family
  let onClose: () -> Void
  let onTry: ([URL]) -> Bool
  @StateObject private var previewSession: ModuleSession
  @StateObject private var viewState = FeatureToolSheetState()

  init(tool: Tool, family: Family, onClose: @escaping () -> Void,
       onTry: @escaping ([URL]) -> Bool) {
    self.tool = tool
    self.family = family
    self.onClose = onClose
    self.onTry = onTry
    _previewSession = StateObject(wrappedValue: ModuleSession(
      tool: tool.id, files: Self.previewFiles(tool: tool, family: family),
      defaults: Options(), reveal: false, cataloguePreview: true))
  }

  private var copy: FeatureToolCopy {
    if tool.id == "split", family == .pdf {
      return .init(summary: "Séparez les pages en PDF ou en images.",
        benefits: ["Une page par fichier par défaut", "Regroupez les pages par glisser-déposer"])
    }
    return .forTool(tool)
  }
  private var specification: ModuleSpecification { .get(tool.id, family: family) }
  private var hasNativeModule: Bool {
    !(tool.id == "mute" || tool.id == "extract" || tool.id == "archive" ||
      (tool.id == "mergepdf" && family == .image))
  }

  var body: some View {
    HStack(alignment: .top, spacing: 34) {
      if hasNativeModule { scaledModule }
      else { directActionIllustration.frame(width: 430, height: 500) }
      VStack(alignment: .leading, spacing: 18) {
        Text(trString(family.rawValue.uppercased()))
          .font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(citrus)
        Text(trString(tool.name)).font(.system(size: 31, weight: .semibold, design: .rounded))
        Text(trString(copy.summary)).font(.system(size: 15)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Divider()
        ForEach(copy.benefits, id: \.self) { benefit in
          Label(trString(benefit), systemImage: "checkmark")
            .font(.system(size: 13)).labelStyle(.titleAndIcon)
        }
        if viewState.invalidSelection {
          Text(trString(tool.id == "archive"
            ? "Choisissez au moins un fichier à compresser."
            : "Choisissez \(tool.group ? "au moins deux fichiers" : "un fichier") compatible\(tool.group ? "s" : "") avec cet outil."))
            .font(.caption).foregroundStyle(.red)
        }
        Button(action: chooseFiles) {
          Label(tr("Essayer"), systemImage: "arrow.up.doc")
        }
        .buttonStyle(.borderedProminent).tint(citrus).controlSize(.large)
      }
      .padding(.top, 22)
      .frame(maxWidth: .infinity, minHeight: 355, alignment: .topLeading)
    }
    .padding(30)
    .frame(width: 900)
    .tint(citrus)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.clementineBorder, lineWidth: 0.8))
    .overlay(alignment: .topTrailing) { closeButton.padding(16) }
    .shadow(color: .black.opacity(0.13), radius: 25, y: 10)
  }

  private var closeButton: some View {
    Button(action: onClose) {
      Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
        .frame(width: 30, height: 30)
        .background(viewState.closeHovered ? citrus.opacity(0.16) : Color.clear, in: Circle())
        .foregroundStyle(viewState.closeHovered ? citrus : Color.secondary)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { viewState.closeHovered = $0 }
    .animation(.easeOut(duration: 0.16), value: viewState.closeHovered)
    .help(tr("Fermer"))
  }

  private var scaledModule: some View {
    GeometryReader { proxy in
      let native = CGSize(width: specification.width, height: specification.height)
      let scale = min(proxy.size.width / native.width, proxy.size.height / native.height, 1)
      ModuleRoot(session: previewSession)
        .frame(width: native.width, height: native.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .scaleEffect(scale, anchor: .center)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .frame(width: 430, height: 500)
    .clipped()
  }

  private var directActionIllustration: some View {
    VStack(spacing: 18) {
      Image(systemName: tool.icon).font(.system(size: 65, weight: .ultraLight))
      Text(trString(tool.name)).font(.system(size: 19, weight: .semibold, design: .rounded))
    }
    .foregroundStyle(citrus)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(citrus.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(citrus.opacity(0.65), lineWidth: 1.5))
  }

  private func chooseFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = tool.group || tool.id == "annotate"
    panel.canChooseDirectories = false
    panel.message = panel.allowsMultipleSelection ? tr("Choisissez les fichiers à tester") : tr("Choisissez le fichier à tester")
    guard panel.runModal() == .OK else { return }
    viewState.invalidSelection = !onTry(panel.urls)
  }

  private static func previewFiles(tool: Tool, family: Family) -> [URL] {
    let name: String
    switch family {
    case .image: name = "Image.jpg"
    case .pdf: name = "Document.pdf"
    case .video: name = "Vidéo.mp4"
    case .audio: name = "Audio.mp3"
    case .archive: name = "Archive.zip"
    case .document: name = "Document.docx"
    case .sheet: name = "Tableau.xlsx"
    case .presentation: name = "Présentation.pptx"
    case .subtitle: name = "Sous-titres.srt"
    case .other: name = "Fichier.dat"
    }
    let count = tool.id == "collage" ? 2 : tool.group ? 3 : 1
    let base = URL(fileURLWithPath: "/Catalogue")
    return (1...count).map { index in
      guard count > 1 else { return base.appendingPathComponent(name) }
      let stem = (name as NSString).deletingPathExtension
      let ext = (name as NSString).pathExtension
      return base.appendingPathComponent("\(stem)-\(index).\(ext)")
    }
  }
}

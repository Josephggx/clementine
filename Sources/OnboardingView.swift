import AppKit
import SwiftUI

private final class OnboardingState: ObservableObject {
  let permissionOwner = UUID()
  @Published var direction = 1
  @Published var hoveredControl: String?
}

struct OnboardingView: View {
  @ObservedObject var state: AppState
  @StateObject private var flow = OnboardingState()
  @StateObject private var permissions = PermissionCenter.shared

  private let pageCount = 5

  var body: some View {
    ZStack {
      Color.clementineCanvas.ignoresSafeArea()
      ambientBackground
      VStack(spacing: 0) {
        header
        ZStack {
          slide
            .id(state.onboardingPage)
            .transition(.asymmetric(
              insertion: .move(edge: flow.direction > 0 ? .trailing : .leading).combined(with: .opacity),
              removal: .move(edge: flow.direction > 0 ? .leading : .trailing).combined(with: .opacity)))
        }
        .frame(maxWidth: 1040, maxHeight: 570)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        footer
      }
      .padding(.horizontal, 38)
      .padding(.vertical, 24)
    }
    .frame(minWidth: 1076, minHeight: 720)
    .onAppear { if state.onboardingPage == 4 { permissions.startMonitoring(owner: flow.permissionOwner) } }
    .onChange(of: state.onboardingPage) { _, page in
      if page == 4 { permissions.startMonitoring(owner: flow.permissionOwner) }
      else { permissions.stopMonitoring(owner: flow.permissionOwner) }
    }
    .onDisappear { permissions.stopMonitoring(owner: flow.permissionOwner) }
    .background(OnboardingArrowKeys { direction in
      move(to: state.onboardingPage + direction)
    }.frame(width: 0, height: 0))
    .gesture(DragGesture(minimumDistance: 35).onEnded { value in
      if value.translation.width < -70 { move(to: state.onboardingPage + 1) }
      if value.translation.width > 70 { move(to: state.onboardingPage - 1) }
    })
  }

  private var ambientBackground: some View {
    ZStack {
      Circle().fill(citrus.opacity(0.10)).frame(width: 420, height: 420)
        .blur(radius: 85).offset(x: -430, y: -270)
      Circle().fill(Color.orange.opacity(0.07)).frame(width: 360, height: 360)
        .blur(radius: 80).offset(x: 430, y: 300)
    }.allowsHitTesting(false)
  }

  private var header: some View {
    HStack {
      HStack(spacing: 11) {
        ClementineMark(size: 34)
        Text("Clémentine")
          .font(.system(size: 22, weight: .bold, design: .rounded))
      }
      Spacer()
      Button {
        permissions.cancelRequests()
        permissions.refresh()
        state.completeProductOnboarding()
      } label: {
        Text("Passer")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(Color.secondary.opacity(flow.hoveredControl == "skip" ? 0.10 : 0), in: Capsule())
      }
      .buttonStyle(StableInteractionButtonStyle())
      .onHover { flow.hoveredControl = $0 ? "skip" : nil }
      .animation(.easeInOut(duration: 0.18), value: flow.hoveredControl)
    }
    .frame(maxWidth: 1040)
    .padding(.bottom, 18)
  }

  @ViewBuilder private var slide: some View {
    switch state.onboardingPage {
    case 0: OnboardingConversionSlide(state: state)
    case 1: OnboardingToolsSlide(state: state)
    case 2: OnboardingActionsSlide(state: state)
    case 3: OnboardingWorkspaceSlide()
    default: OnboardingPermissionsSlide(center: permissions)
    }
  }

  private var footer: some View {
    HStack {
      navButton(id: "back", icon: "chevron.left", title: "Retour", visible: state.onboardingPage > 0) {
        move(to: state.onboardingPage - 1)
      }
      Spacer()
      HStack(spacing: 8) {
        ForEach(0..<pageCount, id: \.self) { index in
          Button { move(to: index) } label: {
            Capsule()
              .fill(index == state.onboardingPage ? citrus : Color.secondary.opacity(0.24))
              .frame(width: index == state.onboardingPage ? 24 : 8, height: 8)
              .animation(.easeInOut(duration: 0.24), value: state.onboardingPage)
          }
          .buttonStyle(StableInteractionButtonStyle())
          .accessibilityLabel("Étape \(index + 1)")
        }
      }
      Spacer()
      navButton(id: "next", icon: nextIcon, title: nextTitle, trailingIcon: true) {
        if state.onboardingPage == pageCount - 1 {
          if permissions.allRequiredGranted { state.completeProductOnboarding() }
          else { permissions.requestAll { state.completeProductOnboarding() } }
        } else { move(to: state.onboardingPage + 1) }
      }
      .disabled(permissions.isRequestingAll)

    }
    .frame(maxWidth: 1040)
    .padding(.top, 18)
  }

  private var nextTitle: String {
    guard state.onboardingPage == pageCount - 1 else { return "Continuer" }
    if permissions.isRequestingAll { return "Autorisation en cours…" }
    return permissions.allRequiredGranted ? "Terminer" : "Approuver Clémentine"
  }
  private var nextIcon: String {
    guard state.onboardingPage == pageCount - 1 else { return "chevron.right" }
    return permissions.allRequiredGranted ? "checkmark" : "checkmark.shield"
  }

  private func navButton(id: String, icon: String, title: String, visible: Bool = true,
    trailingIcon: Bool = false, action: @escaping () -> Void) -> some View
  {
    let hovered = flow.hoveredControl == id
    return Button(action: action) {
      HStack(spacing: 8) {
        if !trailingIcon { Image(systemName: icon) }
        Text(title)
        if trailingIcon { Image(systemName: icon) }
      }
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(id == "next" ? Color.white : Color.primary)
      .padding(.horizontal, 17).frame(height: 38)
      .background(id == "next" ? (hovered ? citrus.opacity(0.82) : citrus) :
        (hovered ? citrus.opacity(0.12) : Color.clementineSurface), in: Capsule())
      .overlay(Capsule().stroke(id == "next" ? Color.clear : Color.clementineBorder))
    }
    .buttonStyle(StableInteractionButtonStyle())
    .onHover { flow.hoveredControl = $0 ? id : nil }
    .opacity(visible ? 1 : 0)
    .disabled(!visible)
    .animation(.easeInOut(duration: 0.18), value: hovered)
  }

  private func move(to target: Int) {
    guard target >= 0, target < pageCount, target != state.onboardingPage else { return }
    flow.direction = target > state.onboardingPage ? 1 : -1
    withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) { state.onboardingPage = target }
  }
}

private struct OnboardingSlideShell<Content: View>: View {
  let eyebrow: String
  let title: String
  let detail: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 34) {
      VStack(alignment: .leading, spacing: 18) {
        Text(eyebrow.uppercased())
          .font(.system(size: 11, weight: .bold)).tracking(1.6).foregroundStyle(citrus)
        Text(title)
          .font(.system(size: 35, weight: .bold, design: .rounded))
          .fixedSize(horizontal: false, vertical: true)
        Text(detail)
          .font(.system(size: 16)).foregroundStyle(.secondary)
          .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .frame(width: 270, alignment: .topLeading)
      content.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    .padding(34)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
      .stroke(Color.clementineBorder, lineWidth: 0.9))
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }
}

private struct ShortcutBadge: View {
  let symbol: String
  let title: String
  var body: some View {
    HStack(spacing: 9) {
      Text(symbol).font(.system(size: 16, weight: .semibold))
      Text(title).font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(citrus)
    .padding(.horizontal, 13).frame(height: 38)
    .background(citrus.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
      .stroke(citrus.opacity(0.35)))
  }
}

/// The onboarding reads the production catalogue, including tools for multiple files.
/// A family-specific glyph (e.g. PDF/video split) is kept as a distinct example.
struct OnboardingToolExample: Identifiable {
  let tool: Tool
  let family: Family
  var icon: String { WheelGlyph.key(tool.id, family: family) }
  var id: String { tool.id + ":" + icon }
  var item: WheelItem { WheelItem(title: tool.wheelTitle, icon: icon, action: id) }
  static let all: [Self] = {
    var seen = Set<String>()
    let preferred = ["pdf", "jpg", "mp4", "mp3", "zip"]
    let formats = preferred + Compatibility.conversions.keys.sorted().filter { !preferred.contains($0) }
    return formats.flatMap { format -> [Self] in
      let source = URL(fileURLWithPath: "/Example." + format)
      return Tool.catalogue(for: source).compactMap { tool in
        let example = Self(tool: tool, family: Family.of(source))
        return seen.insert(example.id).inserted ? example : nil
      }
    }
  }()
}

private struct OnboardingConversionSlide: View {
  @ObservedObject var state: AppState
  private var formatCount: Int { Set(Compatibility.conversions.values.flatMap { $0 }).count }
  var body: some View {
    OnboardingSlideShell(eyebrow: "1 · Conversion", title: "Convertissez en un clique",
      detail: "Cliquez sur votre fichier, appuyez sur Maj puis déposez-le sur le format voulu. \(formatCount) formats disponibles.") {
      OnboardingDragDemo(state: state, actions: false)
    }
  }
}

/// Deterministic, cancellable animation: pick up a desktop file, press a key,
/// reveal the wheel at the cursor, choose a petal and release the file.
private final class OnboardingDemoState: ObservableObject {
  @Published var start = Date()
  @Published var selected = 0
}

private struct OnboardingDragDemo: View {
  @ObservedObject var state: AppState
  let actions: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var animation = OnboardingDemoState()
  private let examples = [("Image.jpg", "photo"), ("Document.pdf", "doc.richtext"),
    ("Tableau.xlsx", "tablecells"), ("Document.docx", "doc.text"),
    ("Vidéo.mp4", "play.rectangle"), ("Audio.mp3", "music.note")]

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
        let elapsed = reduceMotion ? 3.8 : max(0, timeline.date.timeIntervalSince(animation.start)) * 1.3
        let cycle = Int(elapsed / 6.8)
        let time = elapsed.truncatingRemainder(dividingBy: 6.8)
        let example = examples[cycle % examples.count]
        let url = URL(fileURLWithPath: "/" + example.0)
        let items = actions ? WheelActionItems.forURLs([url], preview: true) :
          Array(Compatibility.targets([url]).prefix(7)).map {
            WheelItem(title: Compatibility.label($0), icon: "", action: "convert:" + $0)
          }
        let selected = actions ? cycle % max(1, items.count) : 0
        let resultURL = OnboardingConversionResult.url(source: url, item: items.indices.contains(selected) ? items[selected] : nil)
        let completed = !actions && time >= 4.65
        let angle = -WheelGeometry.angle(selected, count: max(1, items.count))
        let center = CGPoint(x: geometry.size.width * 0.55, y: geometry.size.height * 0.54)
        let origin = CGPoint(x: center.x - 42, y: center.y + 18)
        let target = CGPoint(x: center.x + cos(angle) * 84.5, y: center.y + sin(angle) * 84.5)
        let drag = CGFloat(ease((time - 0.6) / 1.3))
        let choose = CGFloat(ease((time - 2.5) / 1.0))
        let point = CGPoint(x: origin.x + (center.x-origin.x)*drag + (target.x-center.x)*choose,
          y: origin.y + (center.y-origin.y)*drag + (target.y-center.y)*choose)
        let visible = time >= 1.9 && time < 4.9
        let hovered = visible ? WheelGeometry.hit(
          CGPoint(x: point.x - center.x, y: center.y - point.y), count: items.count, center: .zero) : nil
        ZStack(alignment: .topLeading) {
          OnboardingDemoPhoto().scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
          Color.black.opacity(0.17)
          HStack(spacing: 7) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.semibold)
            Text("Fichier   Édition   Présentation")
          }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 12).frame(width: geometry.size.width, height: 24, alignment: .leading)
            .background(.black.opacity(0.22))
          desktopFile(completed ? resultURL.lastPathComponent : example.0,
            icon: completed ? Family.of(resultURL).icon : example.1)
            .opacity(time > 0.6 && time < 4.65 ? 0.3 : 1)
            .position(x: origin.x, y: origin.y - 28)
          FeatureWheelPreview(items: items, appearance: state.appearance,
            soundFeedback: false, hapticFeedback: false,
            previewSelection: hovered, drivesSelection: true, allowsPointerInteraction: false,
            animateOpening: visible)
            .frame(width: WheelGeometry.side, height: WheelGeometry.side)
            .opacity(visible ? 1 : 0)
            .position(center)
          if time > 0.6 && time < 4.65 {
            desktopFile(example.0, icon: example.1).scaleEffect(0.42)
              .opacity(0.85 * (1 - ease((time - 4.35) / 0.3)))
              .position(x: point.x - 9, y: point.y - 9)
          }
          Image(nsImage: NSCursor.arrow.image).resizable().scaledToFit()
            .frame(width: NSCursor.arrow.image.size.width, height: NSCursor.arrow.image.size.height)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            .position(x: point.x + NSCursor.arrow.image.size.width / 2 - NSCursor.arrow.hotSpot.x,
              y: point.y + NSCursor.arrow.image.size.height / 2 - NSCursor.arrow.hotSpot.y)
          ShortcutBadge(symbol: actions ? "⌥" : "⇧", title: actions ? "Option" : "Maj")
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(citrus.opacity(visible ? 1 : 0), lineWidth: 2))
            .padding(.leading, 16).padding(.top, 40)
          Text(time < 0.6 ? "Cliquez et maintenez" : time < 1.9 ? "Glissez le fichier" :
            time < 2.5 ? (actions ? "Appuyez sur Option" : "Appuyez sur Maj") :
            time < 4.65 ? "Choisissez puis relâchez" : actions ? "Action lancée !" : "C’est fait !")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.black.opacity(0.38), in: Capsule())
            .position(x: geometry.size.width / 2, y: geometry.size.height - 30)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
    .onAppear { animation.start = Date() }
    .allowsHitTesting(false)
  }
  private func ease(_ value: Double) -> Double {
    let t = min(1, max(0, value)); return t*t*(3-2*t)
  }
  private func desktopFile(_ name: String, icon: String) -> some View {
    VStack(spacing: 5) {
      Image(systemName: icon).font(.system(size: 28, weight: .regular))
        .foregroundStyle(citrus).frame(width: 48, height: 55)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 7))
      Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 2).background(.black.opacity(0.3), in: Capsule())
    }.frame(width: 112)
  }
}

private struct OnboardingToolsSlide: View {
  @ObservedObject var state: AppState
  @StateObject private var animation = OnboardingDemoState()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let examples = OnboardingToolExample.all
  private var first: Int { (animation.selected / 7) * 7 }
  private var items: [WheelItem] { examples[first..<min(first+7, examples.count)].map(\.item) }
  var body: some View {
    OnboardingSlideShell(eyebrow: "2 · Outils", title: "Modifiez sans interrompre ce que vous faites",
      detail: "Tous vos outils à portée de main, pour un fichier ou plusieurs. Chaque module propose ses réglages et son aperçu.") {
      HStack(spacing: 14) {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 21).fill(Color.clementineRaisedSurface.opacity(0.72))
          FeatureWheelPreview(items: items, appearance: state.appearance,
            soundFeedback: false, hapticFeedback: false,
            previewSelection: animation.selected - first, drivesSelection: true,
            allowsPointerInteraction: false, animateOpening: true)
            .frame(width: WheelGeometry.side, height: WheelGeometry.side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          ShortcutBadge(symbol: "⌘", title: "Commande").padding(14)
        }.frame(width: 280)
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 10) {
              ForEach(Array(examples.enumerated()), id: \.element.id) { index, example in
                Button { animation.selected = index } label: {
                  OnboardingToolCard(example: example, active: animation.selected == index)
                }.buttonStyle(StableInteractionButtonStyle()).id(index)
              }
            }.padding(2)
          }
          .scrollIndicators(.hidden)
          .onChange(of: animation.selected) { _, value in
            withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(value, anchor: .center) }
          }
        }
      }
      .task {
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(2.3)) } catch { break }
          guard !reduceMotion, !examples.isEmpty else { continue }
          withAnimation(.easeInOut(duration: 0.28)) { animation.selected = (animation.selected + 1) % examples.count }
        }
      }
    }
  }
}

private struct OnboardingToolCard: View {
  let example: OnboardingToolExample
  let active: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 9) {
        WheelGlyphView(key: example.icon).frame(width: 22, height: 22)
        Text(example.tool.wheelTitle).font(.system(size: 11, weight: .bold))
        Spacer(minLength: 0)
      }
      Text(FeatureToolCopy.forTool(example.tool).summary)
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      illustration.frame(height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(active ? citrus.opacity(0.12) : Color.clementineSurface,
      in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? citrus.opacity(0.5) : Color.clementineBorder))
  }
  private var illustration: some View {
    OnboardingToolIllustration(example: example)
  }

}

private struct OnboardingActionsSlide: View {
  @ObservedObject var state: AppState
  var body: some View {
    OnboardingSlideShell(eyebrow: "3 · Actions", title: "Envoyez vos fichiers là où ils doivent être",
      detail: "Gardez vos fichiers à portée de main : AirDrop, Float, copie, déplacement et envoi vers Finovox.") {
      OnboardingDragDemo(state: state, actions: true)
    }
  }
}

private struct OnboardingWorkspaceSlide: View {
  var body: some View {
    OnboardingSlideShell(eyebrow: "4 · Atelier", title: "Retrouvez tout dans un espace clair",
      detail: "Ajoutez vos fichiers, contrôlez leur aperçu, puis lancez une conversion, un outil ou une action depuis la même fenêtre.") {
      VStack(spacing: 13) {
        HStack {
          Text("Atelier").font(.system(size:16,weight:.bold,design:.rounded))
          Spacer()
          Label("Ajouter des fichiers",systemImage:"plus")
            .font(.system(size:10,weight:.semibold)).foregroundStyle(.white)
            .padding(.horizontal,11).frame(height:28).background(citrus,in:Capsule())
        }
        HStack(spacing:14) {
          VStack(spacing:8) {
            mockFile("Photo-demo.jpg", "2,4 MB · Image")
            mockFile("Contrat.pdf", "840 KB · PDF")
          }
          .frame(maxWidth:.infinity)
          OnboardingDemoPhoto().scaledToFill().frame(width:185,height:132).clipped()
            .clipShape(RoundedRectangle(cornerRadius:11))
        }
        .padding(13)
        .background(citrus.opacity(0.09),in:RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).stroke(citrus.opacity(0.42)))
        HStack(alignment:.top,spacing:10) {
          mockColumn("Conversion", [("JPG", "photo"), ("PDF", "doc.richtext"), ("PNG", "photo")])
          mockColumn("Outils", [("ANNOTATE", "wheel:annotate"), ("COMPRESS", "wheel:compress"), ("CROP", "wheel:crop")])
          mockColumn("Actions", [("AIRDROP", "wheel:airdrop"), ("FLOAT", "wheel:float"), ("COPY", "wheel:copy")])
        }
      }
      .padding(18)
      .background(Color.clementineRaisedSurface.opacity(0.72),in:RoundedRectangle(cornerRadius:21))
    }
  }
  private func mockFile(_ name:String,_ detail:String)->some View {
    HStack(spacing:9) {
      Image(systemName:name.hasSuffix("pdf") ? "doc.richtext" : "photo")
        .foregroundStyle(citrus).frame(width:27,height:27).background(citrus.opacity(0.11),in:RoundedRectangle(cornerRadius:7))
      VStack(alignment:.leading,spacing:2) {Text(name).font(.system(size:10,weight:.semibold));Text(detail).font(.system(size:8)).foregroundStyle(.secondary)}
      Spacer();Image(systemName:"eye.fill").font(.system(size:9)).foregroundStyle(citrus)
    }.padding(9).background(Color.clementineSurface,in:RoundedRectangle(cornerRadius:10))
  }
  private func mockColumn(_ title:String,_ values:[(String, String)])->some View {
    VStack(alignment:.leading,spacing:7) {
      Text(title).font(.system(size:10,weight:.semibold))
      ForEach(values,id:\.0) { value in
        HStack {WheelGlyphView(key:value.1).frame(width:12,height:12);Text(value.0);Spacer();Image(systemName:"chevron.right").foregroundStyle(.secondary)}
          .font(.system(size:9,weight:.medium)).padding(.horizontal,9).frame(height:29)
          .background(Color.clementineSurface,in:RoundedRectangle(cornerRadius:8))
      }
    }.frame(maxWidth:.infinity)
  }
}

private struct OnboardingPermissionsSlide: View {
  @ObservedObject var center: PermissionCenter
  var body: some View {
    OnboardingSlideShell(eyebrow: "5 · Autorisations", title: "Tout est prêt pour configurer Clémentine",
      detail: "Choisissez les accès que vous accordez à Clémentine. Vous pourrez les modifier à tout moment.") {
      VStack(spacing: 11) {
        ForEach(ClementinePermission.allCases) { permission in
          let status = center.status(permission)
          HStack(spacing:12) {
            Image(systemName:permission.icon).font(.system(size:15,weight:.medium))
              .foregroundStyle(status == .unavailable ? Color.secondary : citrus)
              .frame(width:34,height:34).background(citrus.opacity(0.10),in:RoundedRectangle(cornerRadius:9))
            VStack(alignment:.leading,spacing:2) {
              Text(permission.title).font(.system(size:13,weight:.semibold))
              Text(status == .unavailable ? "Application non installée · aucune autorisation nécessaire." : permission.detail)
                .font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: status == .granted ? "checkmark.shield.fill" :
              status == .unavailable ? "minus.circle.fill" : "xmark.shield.fill")
              .foregroundStyle(status == .granted ? Color.green : status == .unavailable ? Color.secondary : Color.red)
              .font(.system(size:17,weight:.semibold))
          }
          .padding(11)
          .background(Color.clementineSurface,in:RoundedRectangle(cornerRadius:13))
          .overlay(RoundedRectangle(cornerRadius:13).stroke(Color.clementineBorder))
        }

      }
      .padding(18)
      .background(Color.clementineRaisedSurface.opacity(0.72),in:RoundedRectangle(cornerRadius:21))
    }
  }
}

struct OnboardingDemoPhoto: View {
  var body: some View {
    if let url = Bundle.main.url(forResource:"clementine-demo",withExtension:"jpg",subdirectory:"Demo"),
      let image = NSImage(contentsOf:url) {
      Image(nsImage:image).resizable()
    } else {
      LinearGradient(colors:[.blue,.pink],startPoint:.top,endPoint:.bottom)
    }
  }
}

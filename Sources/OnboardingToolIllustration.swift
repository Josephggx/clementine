import SwiftUI

/// Compact, read-only examples: each tool shows its own operation, not a second icon card.
struct OnboardingToolIllustration: View {
  let example: OnboardingToolExample
  private let muted = Color.secondary.opacity(0.2)
  var body: some View {
    content.font(.system(size: 9)).frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .ignore).accessibilityLabel(trString(example.tool.name + " : aperçu"))
  }

  @ViewBuilder private var content: some View {
    switch example.tool.id {
    case "compress":
      VStack(alignment: .leading, spacing: 7) {
        HStack { Text(tr("8,4 Mo")).foregroundStyle(.secondary); Image(systemName: "arrow.right"); Text(tr("2,1 Mo")).foregroundStyle(citrus); Spacer(); Text(tr("−75 %")).fontWeight(.bold).foregroundStyle(citrus) }
        GeometryReader { g in
          Capsule().fill(muted).frame(height: 7)
          Capsule().fill(citrus).frame(width: g.size.width * 0.25, height: 7)
        }.frame(height: 7)
      }.padding(.vertical, 8)
    case "strip":
      VStack(spacing: 5) {
        metadata("Auteur", "Camille Martin", removed: false)
        metadata("Localisation", "Paris, France", removed: true)
        metadata("Logiciel", "Aperçu", removed: false)
      }
    case "organize":
      HStack(spacing: 7) {
        page("3", selected: true); page("1"); page("2")
        Image(systemName: "arrow.uturn.backward").foregroundStyle(citrus)
      }
    case "mergepdf":
      HStack(spacing: 7) {
        page("A"); Text(tr("+")).foregroundStyle(.secondary); page("B")
        Image(systemName: "arrow.right").foregroundStyle(citrus)
        VStack(spacing: 3) { page("A · B", selected: true); Text(tr("Réuni.pdf")).font(.system(size: 8)) }
      }
    case "split":
      if example.family == .pdf {
        HStack(spacing: 6) {
          page("1–3", selected: true)
          Image(systemName: "arrow.right").foregroundStyle(citrus)
          ForEach(1...3, id: \.self) { page(String($0)) }
        }
      } else {
        VStack(spacing: 5) {
          HStack(spacing: 3) { ForEach(0..<3) { n in filmSegment("0:\(n * 10)") } }
          HStack { Text(tr("00:00")); Spacer(); Text(tr("3 segments")).foregroundStyle(citrus); Spacer(); Text(tr("00:30")) }.foregroundStyle(.secondary)
        }
      }
    case "archive":
      HStack(spacing: 7) {
        VStack(alignment: .leading, spacing: 4) { file("Image.jpg"); file("Contrat.pdf") }
        Image(systemName: "arrow.right").foregroundStyle(citrus)
        Text(tr("Documents.zip")).fontWeight(.semibold).padding(9)
          .background(citrus.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
      }
    case "extract":
      HStack(spacing: 10) {
        Text(tr("Dossier.zip")).foregroundStyle(.secondary)
        Image(systemName: "arrow.right").foregroundStyle(citrus)
        VStack(alignment: .leading, spacing: 4) { file("Facture.pdf"); file("Photo.jpg"); file("Notes.txt") }
      }
    case "annotate":
      photo.overlay {
        GeometryReader { g in
          Path { p in
            p.move(to: CGPoint(x: g.size.width * 0.18, y: 38))
            p.addQuadCurve(to: CGPoint(x: g.size.width * 0.82, y: 18), control: CGPoint(x: g.size.width * 0.45, y: -8))
          }.stroke(citrus, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          Text(tr("À garder")).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).offset(x: 15, y: 42)
        }
      }
    case "crop":
      photo.overlay {
        ZStack {
          Rectangle().stroke(.white.opacity(0.8), lineWidth: 1)
          HStack { Spacer(); Divider().overlay(.white); Spacer(); Divider().overlay(.white); Spacer() }
          VStack { Spacer(); Divider().overlay(.white); Spacer(); Divider().overlay(.white); Spacer() }
        }.padding(.horizontal, 35).padding(.vertical, 5)
      }
    case "adjust":
      HStack(spacing: 2) {
        photo.saturation(0.1).overlay(alignment: .bottomLeading) { caption("Avant") }
        photo.saturation(1.35).contrast(1.1).overlay(alignment: .bottomTrailing) { caption("Après") }
      }
    case "frame":
      ZStack { RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.88, green: 0.75, blue: 0.60)); photo.padding(.horizontal, 25).padding(.vertical, 7) }
    case "redact":
      photo.overlay(alignment: .center) {
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 2).fill(.black).frame(width: 76, height: 9)
          RoundedRectangle(cornerRadius: 2).fill(.black).frame(width: 50, height: 9)
        }
      }
    case "collage":
      HStack(spacing: 3) { photo; VStack(spacing: 3) { photo; photo } }
    case "snapshot":
      HStack(spacing: 5) {
        ForEach(["00:02", "00:08", "00:15"], id: \.self) { time in
          photo.overlay(alignment: .bottom) { caption(time) }
        }
      }
    case "trim":
      waveform.overlay {
        HStack { Capsule().fill(citrus).frame(width: 3); Spacer(); Capsule().fill(citrus).frame(width: 3) }
          .background(citrus.opacity(0.12)).padding(.horizontal, 35)
      }.overlay(alignment: .bottom) { caption("00:04 — 00:18") }
    case "join":
      VStack(spacing: 6) {
        HStack(spacing: 5) { filmSegment("Intro.mov"); Text(tr("+")); filmSegment("Suite.mov") }
        HStack { Text(tr("00:00")); Capsule().fill(citrus).frame(height: 3); Text(tr("00:42")) }
      }
    case "speed":
      VStack(spacing: 7) {
        HStack(spacing: 3) {
          ForEach(["0,5×", "1×", "1,5×", "2×"], id: \.self) { speed in
            Text(trString(speed)).fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 5)
              .background(speed == "1,5×" ? citrus.opacity(0.25) : muted.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
          }
        }
        HStack { Text(tr("Durée")).foregroundStyle(.secondary); Spacer(); Text(tr("00:30 → 00:20")).foregroundStyle(citrus) }
      }
    case "normalize":
      HStack(spacing: 9) {
        waveform.scaleEffect(x: 1, y: 0.4)
        Image(systemName: "arrow.right").foregroundStyle(citrus)
        waveform.overlay(alignment: .topTrailing) { Text(tr("−16 LUFS")).font(.system(size: 8)).foregroundStyle(.secondary) }
      }
    case "mute":
      HStack(spacing: 10) {
        photo.overlay(alignment: .bottomLeading) { caption("Vidéo.mp4") }
        VStack(alignment: .leading, spacing: 6) {
          Text(tr("Piste audio")).foregroundStyle(.secondary)
          HStack(spacing: 5) { Image(systemName: "speaker.slash"); Text(tr("Retirée")).fontWeight(.semibold) }.foregroundStyle(citrus)
        }
      }
    case "visualize":
      photo.overlay { waveform.padding(.horizontal, 18).padding(.vertical, 8) }
        .overlay(alignment: .bottomTrailing) { caption("Audio → Vidéo") }
    case "channels":
      VStack(spacing: 10) { meter("G", amount: 0.72); meter("D", amount: 0.45) }.padding(.vertical, 8)
    case "bleep":
      waveform.overlay {
        Rectangle().fill(citrus.opacity(0.2)).frame(width: 65)
          .overlay(Text(tr("BIP")).font(.system(size: 10, weight: .bold)).foregroundStyle(citrus))
      }.overlay(alignment: .bottomTrailing) { caption("00:07–00:09") }
    default:
      EmptyView()
    }
  }
  private var photo: some View {
    GeometryReader { g in
      OnboardingDemoPhoto().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
    }.clipShape(RoundedRectangle(cornerRadius: 4))
  }
  private var waveform: some View {
    GeometryReader { g in
      HStack(spacing: 3) {
        ForEach(0..<24) { i in
          Capsule().fill(citrus.opacity(0.55 + Double(i % 3) * 0.2))
            .frame(maxWidth: .infinity).frame(height: g.size.height * (0.2 + Double((i * 7) % 11) / 14))
        }
      }.frame(height: g.size.height)
    }
  }
  private func page(_ text: String, selected: Bool = false) -> some View {
    VStack(spacing: 4) {
      Text(trString(text)).fontWeight(.semibold).foregroundStyle(selected ? citrus : .primary)
      ForEach(0..<3) { _ in Capsule().fill(muted).frame(height: 2) }
    }.padding(7).frame(maxWidth: .infinity)
      .background(selected ? citrus.opacity(0.12) : Color.clementineRaisedSurface, in: RoundedRectangle(cornerRadius: 4))
  }
  private func metadata(_ key: String, _ value: String, removed: Bool) -> some View {
    HStack { Text(trString(key)).foregroundStyle(.secondary); Spacer(); Text(trString(value)).strikethrough(removed).foregroundStyle(removed ? citrus : .primary) }
  }
  private func file(_ name: String) -> some View {
    HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).stroke(citrus, lineWidth: 1).frame(width: 7, height: 9); Text(trString(name)).lineLimit(1) }
  }
  private func caption(_ text: String) -> some View {
    Text(trString(text)).font(.system(size: 8, weight: .medium)).foregroundStyle(.white)
      .padding(.horizontal, 4).padding(.vertical, 2).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
  }
  private func filmSegment(_ text: String) -> some View {
    photo.overlay(alignment: .bottomLeading) { caption(text) }
  }
  private func meter(_ label: String, amount: Double) -> some View {
    HStack(spacing: 7) {
      Text(trString(label)).fontWeight(.bold)
      GeometryReader { g in
        Capsule().fill(muted)
        Capsule().fill(citrus).frame(width: g.size.width * amount)
      }.frame(height: 6)
    }
  }
}

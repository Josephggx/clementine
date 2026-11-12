import SwiftUI

struct WhatsNewView: View {
  @ObservedObject var news: WhatsNewStore
  @ObservedObject private var language = AppLanguage.shared
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        if news.entries.isEmpty {
          Text(tr("Les nouveautés arrivent bientôt."))
            .foregroundStyle(.secondary).padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        ForEach(news.entries) { entry in
          HStack(alignment: .top, spacing: 18) {
            Image(systemName: entry.icon)
              .font(.system(size: 21, weight: .medium))
              .foregroundStyle(citrus)
              .frame(width: 46, height: 46)
              .background(citrus.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
              HStack(alignment: .top, spacing: 12) {
                Text(entry.title.localized(language.code))
                  .font(.system(size: 18, weight: .semibold, design: .rounded))
                  .foregroundStyle(.primary)
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(entry.formattedDate).font(.system(size: 11, weight: .medium))
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8).padding(.vertical, 4)
                  .background(Color.clementineRaisedSurface, in: Capsule())
                  .fixedSize()
                  .help(Text(verbatim: "Version \(entry.version)"))
                  .accessibilityValue(Text(verbatim: "Version \(entry.version)"))
              }
              Text(entry.body.localized(language.code))
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(22)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.clementineGroupedSurface, in: RoundedRectangle(cornerRadius: 17))
          .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.clementineBorder, lineWidth: 0.7))
          .accessibilityElement(children: .combine)
        }
      }.padding(28)
    }
    .scrollIndicators(.hidden)
    .onAppear { news.markAllRead() }
  }
}

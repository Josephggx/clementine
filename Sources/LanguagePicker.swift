import SwiftUI

struct LanguagePicker: View {
  @ObservedObject private var language = AppLanguage.shared
  var compact = false
  var body: some View {
    Picker(selection:$language.code) {
      Text("Français").tag("fr")
      Text("English").tag("en")
    } label: {
      Text(tr("Langue"))
    }
    .pickerStyle(.menu)
    .modifier(LanguageLabelVisibility(hidden:compact))
    .fixedSize(horizontal:compact,vertical:false)
    .help(tr("Langue de l’application"))
  }
}

private struct LanguageLabelVisibility: ViewModifier {
  let hidden: Bool
  @ViewBuilder func body(content: Content) -> some View {
    if hidden { content.labelsHidden() } else { content }
  }
}

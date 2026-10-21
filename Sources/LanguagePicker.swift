import SwiftUI

struct LanguagePicker: View {
  @ObservedObject private var language = AppLanguage.shared
  var compact = false
  var body: some View {
    Picker(selection:$language.code) {
      Text("Français").tag("fr")
      Text("English").tag("en")
    } label: {
      Label(tr("Langue"),systemImage:"globe")
    }
    .pickerStyle(.menu)
    .fixedSize(horizontal:compact,vertical:false)
    .help(tr("Langue de l’application"))
  }
}

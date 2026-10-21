import AppKit
import SwiftUI

@main struct LanguageCheck {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    if CommandLine.arguments.contains("--ui") {
      let state = AppState()
      state.showingOnboarding = true
      state.appearance = "dark"; state.applyAppearance()
      let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1136,height:790),
        styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
      window.isReleasedWhenClosed = false
      window.title = "LanguageCheck"
      window.contentView = NSHostingView(rootView:MainView(state:state))
      NSApp.setActivationPolicy(.regular)
      window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
      withExtendedLifetime((window,state)) { NSApp.run() }
      return
    }
    let resource = Bundle.main.url(forResource:"en",withExtension:"json",subdirectory:"Localization")!
    let translations = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:resource))
    let suite = "io.joseph.clementine.localization-test."+UUID().uuidString
    let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let language = AppLanguage(defaults:defaults,translations:translations)
    precondition(language.code == "fr")
    for key in translations.keys {
      precondition(language.translate(key) == key,"French must remain byte-for-byte unchanged")
      precondition(language.resolve(AppMessage(stringLiteral:key)) == key)
    }
    language.code = "en"
    for (key,value) in translations { precondition(language.translate(key) == value) }
    precondition(AppLanguage(defaults:defaults,translations:translations).code == "en")
    precondition(language.resolve("\(3) fichier\("s")") == "3 files")
    precondition(language.resolve("Clémentine version \("1.0.7")") == "Clémentine version 1.0.7")
    precondition(language.translate("Cliquez sur votre fichier, appuyez sur Maj puis déposez-le sur le format voulu. 39 formats disponibles.") ==
      "Click and hold your file, press Shift, then drop it onto the format you want. 39 formats available.")
    precondition(language.translate("PRÉSENTATIONS") == "PRESENTATIONS")
    precondition(language.translate("/Users/Joseph/Documents/Été.pdf") == "/Users/Joseph/Documents/Été.pdf")
    precondition(language.translate("Été.pdf") == "Été.pdf")
    precondition(language.resolve("Ouvrir \("Réglages {0}.pdf")") == "Open Réglages {0}.pdf")
    precondition(language.translate("Choisissez au moins deux fichiers compatibles avec cet outil.") == "Choose at least two files compatible with this tool.")
    let placeholder = try NSRegularExpression(pattern:#"\{[0-9]+\}"#)
    func slots(_ text:String) -> Set<String> {
      Set(placeholder.matches(in:text,range:NSRange(text.startIndex...,in:text)).map {
        String(text[Range($0.range,in:text)!])
      })
    }
    for (key,value) in translations { precondition(slots(key) == slots(value),"Translation lost placeholders: \(key)") }
    language.code = "fr"
    precondition(language.translate("Réglages") == "Réglages")
    precondition(AppLanguage(defaults:defaults,translations:translations).code == "fr")
    print("PASS: \(translations.count) translations, exact French fallback, live selection, persistence, interpolation, uppercase headings and unchanged filenames/paths")
  }
}

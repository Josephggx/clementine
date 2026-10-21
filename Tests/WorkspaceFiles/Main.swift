import AppKit
import SwiftUI

@main struct WorkspaceFilesCheck {
  @MainActor static func wait(_ condition:()->Bool) {
    let limit = Date().addingTimeInterval(20)
    while !condition(), Date() < limit { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
    precondition(condition(),"File operation did not finish")
  }

  @MainActor static func main() throws {
    _ = NSApplication.shared
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("clementine-files-"+UUID().uuidString)
    try fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer { if !CommandLine.arguments.contains("--ui") { try? fm.removeItem(at:root) } }
    let input = root.appendingPathComponent("Originaux",isDirectory:true)
    try fm.createDirectory(at:input,withIntermediateDirectories:true)
    let a = input.appendingPathComponent("Été et espaces.txt")
    let hidden = input.appendingPathComponent(".env")
    let folder = input.appendingPathComponent("Dossier",isDirectory:true)
    try "Texte à conserver".write(to:a,atomically:true,encoding:.utf8)
    try "test-only".write(to:hidden,atomically:true,encoding:.utf8)
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    try Data([1,2,3]).write(to:folder.appendingPathComponent("Document.bin"))
    var settings = Options(); settings.outputFolder = root.path; settings.archiveFormat = "zip"
    let zip = try Engine().run([a,hidden,folder],action:"archive",options:settings)[0]
    func read(_ url:URL) -> String { try! String(contentsOf:url,encoding:.utf8) }
    precondition(WorkspaceFileOperations.editableName(hidden) == ".env")
    let state = AppState(); state.sound=false; state.reveal=false
    state.showingOnboarding=false; state.page="workspace"; state.files=[zip,a,folder]
    if CommandLine.arguments.contains("--ui") {
      state.appearance="dark"; state.applyAppearance()
      let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1136,height:790),
        styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
      window.title="WorkspaceFilesCheck"; window.isReleasedWhenClosed=false
      window.contentView=NSHostingView(rootView:MainView(state:state))
      NSApp.setActivationPolicy(.regular); window.center(); window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps:true)
      withExtendedLifetime((window,state)) { NSApp.run() }
      return
    }
    let renamed = try state.renamePinnedFile(a,to:"Renommé.txt")
    precondition(renamed.lastPathComponent == "Renommé.txt" && state.files == [zip,renamed,folder])
    precondition(read(renamed) == "Texte à conserver")
    precondition(!fm.fileExists(atPath:a.path))
    let collision = input.appendingPathComponent("Existe.txt")
    try "Ne pas écraser".write(to:collision,atomically:true,encoding:.utf8)
    for invalid in ["Existe","../Sortie","","..","nom:invalide","nom\0invalide"] {
      do { _ = try state.renamePinnedFile(renamed,to:invalid); fatalError("Invalid rename accepted") }
      catch { precondition(state.files.contains(renamed) && fm.fileExists(atPath:renamed.path)) }
    }
    precondition(read(collision) == "Ne pas écraser")
    var replacements: [URL]?
    state.unzipPinnedFile(zip) { replacements=$0 }
    state.unzipPinnedFile(zip) // A second click must not queue a second extraction.
    wait { replacements != nil }
    let contents = replacements!
    precondition(contents.map(\.lastPathComponent).sorted() == [".env","Dossier","Été et espaces.txt"].sorted())
    precondition(Array(state.files.suffix(2)) == [renamed,folder] && !state.files.contains(zip))
    precondition(fm.fileExists(atPath:zip.path) && state.jobs.count == 1 && !state.jobs[0].failed)
    let extractedFile = contents.first { $0.lastPathComponent == a.lastPathComponent }!
    precondition(read(extractedFile) == "Texte à conserver")
    precondition(state.pinnedFileOperations.isEmpty)
    let broken = root.appendingPathComponent("Corrompu.zip")
    try "Not a ZIP".write(to:broken,atomically:true,encoding:.utf8)
    state.files=[broken,renamed]
    state.unzipPinnedFile(broken)
    wait { state.pinnedFileOperations.isEmpty }
    precondition(state.files == [broken,renamed] && state.jobs[0].failed && state.error != nil)

    state.files=[renamed,folder]
    state.trashPinnedFile(renamed,recycle:{ _,finish in finish(ClementineError("Refus simulé")) })
    wait { state.pinnedFileOperations.isEmpty }
    precondition(state.files == [renamed,folder] && fm.fileExists(atPath:renamed.path))
    let trash = root.appendingPathComponent("Corbeille de test",isDirectory:true)
    try fm.createDirectory(at:trash,withIntermediateDirectories:true)
    state.trashPinnedFile(renamed,recycle:{ source,finish in
      do { try fm.moveItem(at:source,to:trash.appendingPathComponent(source.lastPathComponent)); finish(nil) }
      catch { finish(error) }
    })
    wait { state.pinnedFileOperations.isEmpty }
    precondition(state.files == [folder] && !fm.fileExists(atPath:renamed.path))
    precondition(fm.fileExists(atPath:trash.appendingPathComponent(renamed.lastPathComponent).path))
    state.files=[]; state.replacePinnedFile(zip,with:contents)
    precondition(state.files.isEmpty,"A cleared workspace must not be populated by late results")
    for ext in ["zip","tar","gz","rar","7z","bz2","xz"] {
      let tools = Tool.available([root.appendingPathComponent("Archive."+ext)])
      precondition(tools.contains(where:{$0.id == "extract"}))
    }
    precondition(Tool.all.first(where:{$0.id == "extract"})!.name == "Dézip")
    print("PASS: rename/extension/collision/invalid names, real ZIP contents and preserved original, duplicate click, corrupt archive, recycle success/refusal, late results and archive tools")
  }
}

import AppKit
import SwiftUI
import PDFKit

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
    defer { if !CommandLine.arguments.contains("--ui") && Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String != "WorkspaceRevisionPreview" { try? fm.removeItem(at:root) } }
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
    // Finder launches without a UTF-8 locale on some Macs. Accented archive
    // names must still extract, while traversal and links remain forbidden.
    setenv("LC_ALL","C",1)
    defer {unsetenv("LC_ALL")}
    let zip = try Engine().run([a,hidden,folder],action:"archive",options:settings)[0]
    func read(_ url:URL) -> String { try! String(contentsOf:url,encoding:.utf8) }
    precondition(WorkspaceFileOperations.editableName(hidden) == ".env")
    let state = AppState(); state.sound=false; state.reveal=false
    state.showingOnboarding=false; state.page="workspace"; state.files=[zip,a,folder]
    if CommandLine.arguments.contains("--ui") || Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String == "WorkspaceRevisionPreview" {
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
    precondition(contents.allSatisfy {fm.fileExists(atPath:$0.path) && !$0.path.contains("/.clementine-")})
    precondition(contents.allSatisfy {$0.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path+"/")})
    precondition(state.pinnedFileOperations.isEmpty)
    try Engine().process("/usr/bin/python3",["-c", """
import pathlib, sys, zipfile, stat
root = pathlib.Path(sys.argv[1])
for filename, member in [('traversal.zip', '../outside.txt'), ('absolute.zip', '/outside.txt')]:
    with zipfile.ZipFile(root / filename, 'w') as z:
        z.writestr(member, 'must not extract')
with zipfile.ZipFile(root / 'link.zip', 'w') as z:
    info = zipfile.ZipInfo('link')
    info.create_system = 3
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    z.writestr(info, '../outside')
""", root.path])
    for filename in ["traversal.zip","absolute.zip","link.zip"] {
      let staging=root.appendingPathComponent(UUID().uuidString)
      try fm.createDirectory(at:staging,withIntermediateDirectories:true)
      do {
        _ = try Engine().extract(root.appendingPathComponent(filename),stage:staging)
        fatalError("Unsafe archive accepted: \(filename)")
      } catch {
        let remaining=try fm.contentsOfDirectory(atPath:staging.path)
        precondition(remaining.isEmpty)
      }
    }
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
    // Stable identities must follow Finder renames and collapse hard links.
    let tracked = input.appendingPathComponent("Suivi.txt")
    let moved = input.appendingPathComponent("Nom modifié.txt")
    try "stable".write(to:tracked,atomically:true,encoding:.utf8)
    state.files=[tracked]
    try fm.moveItem(at:tracked,to:moved)
    state.refreshPinnedFiles()
    precondition(state.files == [moved],"Bookmark must follow a Finder rename")
    state.add([moved])
    precondition(state.files.count == 1,"Renaming/re-adding cannot pin the same file twice")
    let link = input.appendingPathComponent("Lien.txt")
    try fm.linkItem(at:moved,to:link)
    state.add([link])
    precondition(state.files.count == 1,"Hard-linked aliases must not duplicate pins")
    let revision=state.fileRevision
    try "updated metadata".write(to:moved,atomically:false,encoding:.utf8)
    state.refreshPinnedFiles()
    precondition(state.fileRevision > revision)
    let simulatedTrash=root.appendingPathComponent(".Trash",isDirectory:true)
    try fm.createDirectory(at:simulatedTrash,withIntermediateDirectories:true)
    try fm.moveItem(at:moved,to:simulatedTrash.appendingPathComponent(moved.lastPathComponent))
    state.refreshPinnedFiles()
    precondition(state.files.isEmpty,"Trashed bookmarks must be removed even when the file still exists")
    precondition(TrackedFiles.isInTrash(URL(fileURLWithPath:"/Volumes/Data/.Trashes/501/Doc.pdf")))
    precondition(!TrackedFiles.isInTrash(URL(fileURLWithPath:"/Documents/Trash Notes.txt")))
    state.files=[link]
    try fm.removeItem(at:link)
    state.refreshPinnedFiles()
    precondition(state.files.isEmpty,"Deleted files must be removed")

    let pdfs=(0..<2).map {root.appendingPathComponent("Suivi-\($0).pdf")}
    for pdf in pdfs {
      let doc=PDFDocument();doc.insert(PDFPage(),at:0);doc.insert(PDFPage(),at:1)
      precondition(doc.write(to:pdf))
    }
    let session=ModuleSession(tool:"split",files:pdfs,defaults:Options(),reveal:false)
    wait {!session.loading}
    let tracker=TrackedFiles();tracker.observe(session.files)
    let renamedPDF=root.appendingPathComponent("PDF renommé.pdf")
    try fm.moveItem(at:pdfs[1],to:renamedPDF)
    session.reconcileFiles(tracker.refresh(session.files))
    precondition(session.files == [pdfs[0],renamedPDF] && session.options.pdfSplitGroups[renamedPDF.path] != nil)
    try fm.moveItem(at:pdfs[0],to:simulatedTrash.appendingPathComponent(pdfs[0].lastPathComponent))
    session.reconcileFiles(tracker.refresh(session.files))
    precondition(session.files == [renamedPDF] && session.activeFile == 0 && session.canSave)
    var closed=false;session.close={closed=true}
    try fm.moveItem(at:renamedPDF,to:simulatedTrash.appendingPathComponent(renamedPDF.lastPathComponent))
    session.reconcileFiles(tracker.refresh(session.files))
    precondition(closed,"Editors must close when all inputs are trashed")
    // A Finder change during initial loading must not be overwritten by an older callback.
    let loadingPDFs=(0..<2).map {root.appendingPathComponent("Chargement-\($0).pdf")}
    for pdf in loadingPDFs {let doc=PDFDocument();doc.insert(PDFPage(),at:0);doc.insert(PDFPage(),at:1);precondition(doc.write(to:pdf))}
    let loadingSession=ModuleSession(tool:"split",files:loadingPDFs,defaults:Options(),reveal:false)
    let loadingTracker=TrackedFiles();loadingTracker.observe(loadingSession.files)
    try fm.moveItem(at:loadingPDFs[0],to:simulatedTrash.appendingPathComponent(loadingPDFs[0].lastPathComponent))
    loadingSession.reconcileFiles(loadingTracker.refresh(loadingSession.files))
    wait {!loadingSession.loading}
    precondition(loadingSession.files == [loadingPDFs[1]] && loadingSession.canSave)
    precondition(loadingSession.splitThumbnails[loadingPDFs[0]] == nil)
    print("PASS: rename/extension/collision/invalid names, real ZIP contents and preserved original, duplicate click, corrupt archive, recycle success/refusal, late results and archive tools")
  }
}

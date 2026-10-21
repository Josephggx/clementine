import AppKit

extension WorkspaceFilesCheck {
  @MainActor static func coherence(_ root:URL) throws {
    let fm=FileManager.default
    let base=root.appendingPathComponent("Cohérence")
    try fm.createDirectory(at:base,withIntermediateDirectories:true)
    let state=AppState();state.sound=false;state.reveal=false
    func create(_ relative:String,_ contents:String) throws -> URL {
      let u=base.appendingPathComponent(relative)
      try fm.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true)
      try contents.write(to:u,atomically:true,encoding:.utf8)
      return u
    }
    func checkPins() {
      precondition(TrackedFiles.unique(state.files).count == state.files.count,"Duplicate pins")
      precondition(state.files.allSatisfy {fm.fileExists(atPath:$0.path) && !TrackedFiles.isInTrash($0)},"Missing pin")
    }
    func submit(_ action:String,_ files:[URL]) throws -> [URL] {
      var result:Result<[URL],Error>?
      var settings=Options();settings.outputFolder=base.path
      state.submit(action,files:files,overrideOptions:settings,revealOutputs:false) {result=$0}
      wait {result != nil}
      return try result!.get()
    }
    var naming=try create("Nommage.txt","original")
    for valid in ["Été 🧡 2026", "deux.points", "Question ? * < > | \\", "O’Connor & \"devis\"", "CON", "test", "TEST"] {
      naming=try WorkspaceFileOperations.rename(naming,to:valid)
      precondition(naming.lastPathComponent == valid+".txt")
      let data=try String(contentsOf:naming);precondition(data == "original")
    }
    for invalid in ["", "   ", ".", "..", ".caché", "nom/invalide", "nom:invalide", "nul\0nom", "ligne\nnom", "ligne\rnom",String(repeating:"x",count:300)] {
      do {_ = try WorkspaceFileOperations.rename(naming,to:invalid);fatalError("Invalid name accepted: \(invalid)")}
      catch {precondition(fm.fileExists(atPath:naming.path))}
    }
    let special=try create("Symboles ? * < > | \\.txt","special characters")
    let specialZip=try submit("archive",[special,naming])[0]
    let specialRoot=try submit("extract",[specialZip])[0]
    let specialResult=specialRoot.appendingPathComponent(special.lastPathComponent)
    let specialContents=try String(contentsOf:specialResult)
    precondition(specialContents == "special characters","Mac filename changed during ZIP roundtrip")
    print("PASS: macOS naming, symbols, accents, emoji, case-only changes, invalid/overlong names and special-character ZIP roundtrip")

    let a=try create("A/Été.txt","first")
    let b=try create("B/2-Été.txt","second")
    let c=try create("C/Été.txt","third")
    state.add([a,b,c,a,a.standardizedFileURL]);checkPins()
    precondition(state.files.count == 3)
    // Filename conflicts inside a ZIP must never overwrite or omit an input.
    let zip=try submit("archive",state.files)[0]
    let firstExtract=try submit("extract",[zip])[0]
    let archived=try fm.contentsOfDirectory(at:firstExtract,includingPropertiesForKeys:nil).filter {$0.pathExtension == "txt"}
    let payloads=try archived.map {try String(contentsOf:$0)}
    precondition(payloads.sorted() == ["first","second","third"],"Archive lost a colliding name")
    let zip2=try submit("archive",state.files)[0]
    precondition(zip != zip2 && fm.fileExists(atPath:zip.path),"Existing ZIP overwritten")
    let secondExtract=try submit("extract",[zip])[0]
    precondition(firstExtract != secondExtract,"Existing extracted folder overwritten")
    precondition(!Tool.available([zip]).contains {$0.id == "archive"})
    precondition(Tool.available([zip,zip2]).contains {$0.id == "archive"})
    precondition(Tool.available([zip,a]).contains {$0.id == "archive"})
    let archiveBatch=try submit("archive",[zip,zip2])[0]
    let batchRoot=try submit("extract",[archiveBatch])[0]
    precondition(fm.fileExists(atPath:batchRoot.appendingPathComponent(zip.lastPathComponent).path))
    precondition(fm.fileExists(atPath:batchRoot.appendingPathComponent(zip2.lastPathComponent).path))
    let multiple=try submit("extract",[zip,zip2])
    precondition(multiple.count == 2 && multiple[0] != multiple[1])
    let nested=try submit("archive",[zip,a])[0]
    let nestedRoot=try submit("extract",[nested])[0]
    precondition(fm.fileExists(atPath:nestedRoot.appendingPathComponent(zip.lastPathComponent).path))
    precondition(fm.fileExists(atPath:nestedRoot.appendingPathComponent(a.lastPathComponent).path))
    print("PASS: batch ZIP, colliding filenames, repeated ZIP/extraction, ZIP+ZIP and ZIP+document")

    state.files=[];state.add([zip,zip,a])
    let renamedZIP=try state.renamePinnedFile(zip,to:"Archive renommée")
    state.add([renamedZIP,zip]);checkPins()
    precondition(state.files == [renamedZIP,a])
    var unzipped:[URL]?
    state.unzipPinnedFile(renamedZIP) {unzipped=$0}
    state.unzipPinnedFile(renamedZIP)
    wait {unzipped != nil || state.pinnedFileOperations.isEmpty}
    precondition(unzipped?.count == 3)
    checkPins();precondition(!state.files.contains(renamedZIP))
    precondition(fm.fileExists(atPath:renamedZIP.path),"Unzip removed original ZIP")
    state.add(unzipped!+unzipped!);checkPins();precondition(state.files.count == 4)
    // A pinned original and an extracted copy have distinct identities and both belong here.
    state.add([a]);precondition(state.files.count == 4)
    print("PASS: pinned ZIP rename, deduplication, extraction replacement and preserved original")

    // Finder-style changes, including re-adding before the next periodic refresh.
    let moved=base.appendingPathComponent("Déplacé et renommé.txt")
    try fm.moveItem(at:a,to:moved)
    state.add([moved,moved]);checkPins()
    precondition(!state.files.contains(a) && state.files.contains(where:{TrackedFiles.sameItem($0,moved)}) && state.files.count == 4,"External move pins: \(state.files.map(\.path))")
    let hardlink=base.appendingPathComponent("Même fichier.txt")
    try fm.linkItem(at:moved,to:hardlink)
    state.add([hardlink]);precondition(state.files.count == 4,"Hard-link pins: \(state.files.map(\.path))")
    let copy=base.appendingPathComponent("Copie indépendante.txt")
    try fm.copyItem(at:moved,to:copy)
    state.add([copy]);precondition(state.files.count == 5)
    let other=try create("Autre.txt","do not overwrite")
    let pinnedMoved=state.files.first {TrackedFiles.sameItem($0,moved)}!
    do {_ = try state.renamePinnedFile(pinnedMoved,to:"Autre");fatalError("Collision overwritten")}
    catch {let data=try String(contentsOf:other);precondition(data == "do not overwrite")}
    // Removing a pin leaves the Finder item intact; removing the item removes only that pin.
    state.files.removeAll {$0 == copy};precondition(fm.fileExists(atPath:copy.path))
    state.add([copy]);try fm.removeItem(at:copy);state.refreshPinnedFiles();checkPins()
    precondition(!state.files.contains(copy) && state.files.count == 4)
    let trash=base.appendingPathComponent(".Trash",isDirectory:true)
    try fm.createDirectory(at:trash,withIntermediateDirectories:true)
    try fm.moveItem(at:moved,to:trash.appendingPathComponent(moved.lastPathComponent))
    state.refreshPinnedFiles();checkPins();precondition(state.files.count == 3)
    state.add([trash.appendingPathComponent(moved.lastPathComponent)])
    precondition(state.files.count == 3,"Trash item re-pinned")
    print("PASS: external rename/move, duplicate re-add, hard links versus copies, collision, removal and Trash")

    // Real NSWorkspace recycling of a disposable file, not a mock.
    let disposable=try create("Suppression réelle.txt","disposable fixture")
    state.add([disposable]);state.trashPinnedFile(disposable)
    wait {state.pinnedFileOperations.isEmpty}
    precondition(!fm.fileExists(atPath:disposable.path) && !state.files.contains(disposable))
    checkPins()
    print("PASS: real macOS Trash operation removes only its pinned document")

    // Clearing while unzip runs must not resurrect the source or extracted pins.
    state.files=[renamedZIP]
    state.unzipPinnedFile(renamedZIP)
    do {_ = try state.renamePinnedFile(renamedZIP,to:"Pendant extraction");fatalError("Busy input renamed")}
    catch {precondition(fm.fileExists(atPath:renamedZIP.path))}
    state.trashPinnedFile(renamedZIP)
    precondition(fm.fileExists(atPath:renamedZIP.path),"Busy input trashed")
    state.files=[]
    wait {state.pinnedFileOperations.isEmpty}
    precondition(state.files.isEmpty)
    let remaining=try fm.contentsOfDirectory(atPath:base.path)
    precondition(remaining.allSatisfy {!$0.hasPrefix(".clementine-")},"Staging files leaked")
    print("PASS: clear during extraction and temporary-file cleanup")
  }
}

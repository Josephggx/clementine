import AppKit

extension WorkspaceFilesCheck {
  @MainActor static func refinements(_ root:URL) throws {
    let fm=FileManager.default
    let folder=root.appendingPathComponent("Nouvelles actions")
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let a=folder.appendingPathComponent("Été.txt")
    let hidden=folder.appendingPathComponent(".env")
    let directory=folder.appendingPathComponent("Dossier.photos")
    try Data([0,255,100,10]).write(to:a)
    try "SECRET TEST".write(to:hidden,atomically:true,encoding:.utf8)
    try fm.createDirectory(at:directory,withIntermediateDirectories:true)
    try Data([3,2,1]).write(to:directory.appendingPathComponent("contenu.bin"))
    let copies=try WorkspaceFileOperations.duplicate([a,hidden,directory,a])
    precondition(copies.count == 3 && copies[0].lastPathComponent == "Été copie.txt")
    let copiedBytes=try Data(contentsOf:copies[0]);precondition(copiedBytes == Data([0,255,100,10]))
    precondition(copies[2].lastPathComponent == "Dossier.photos copie")
    precondition(fm.fileExists(atPath:copies[2].appendingPathComponent("contenu.bin").path))
    let again=try WorkspaceFileOperations.duplicate([a]);precondition(again[0].lastPathComponent == "Été copie 2.txt")
    do {
      _=try WorkspaceFileOperations.duplicate([a,folder.appendingPathComponent("absent")])
      fatalError("Missing source must fail")
    } catch {precondition(!fm.fileExists(atPath:folder.appendingPathComponent("Été copie 3.txt").path))}

    let state=AppState();state.files=[hidden];state.page="settings"
    var opened=false;state.showWindow={opened=true}
    state.fileAction("workspace",urls:[a,a,directory])
    precondition(opened && state.page == "workspace" && state.files == [hidden,a,directory])
    state.fileAction("path",urls:[a,directory])
    precondition(NSPasteboard.general.string(forType:.string) == [a.path,directory.path].joined(separator:"\n"))
    state.fileAction("copy",urls:[a,directory])
    let copiedURLs=NSPasteboard.general.readObjects(forClasses:[NSURL.self]) as? [URL]
    precondition(copiedURLs == [a,directory])
    for input in [[a],[a,hidden],[directory],[]] {
      let actions=WheelActionItems.forURLs(input)
      precondition(actions.contains {$0.action == "action:duplicate"})
      precondition(actions.contains {$0.action == "action:workspace"})
      precondition(Set(actions.map(\.action)).count == actions.count)
    }

    for format in ["zip","tar","gz"] {
      var settings=Options();settings.outputFolder=folder.path;settings.archiveFormat=format
      let archive=try Engine().run([a,hidden,directory],action:"archive",options:settings)[0]
      precondition(WorkspaceFileOperations.canExtract(archive))
      let extractState=AppState();extractState.files=[archive,hidden]
      var result:[URL]?
      extractState.unzipPinnedFile(archive) {result=$0}
      wait {extractState.pinnedFileOperations.isEmpty}
      precondition(result?.count == 3,"\(format) must replace archive with real contents")
      precondition(!extractState.files.contains(archive) && fm.fileExists(atPath:archive.path))
      let file=result!.first {$0.lastPathComponent == a.lastPathComponent}!
      let data=try Data(contentsOf:file);precondition(data == Data([0,255,100,10]))
    }
    let raw=folder.appendingPathComponent("binary.gz")
    let output=Process();output.executableURL=URL(fileURLWithPath:"/usr/bin/gzip");output.arguments=["-c",a.path]
    fm.createFile(atPath:raw.path,contents:nil)
    let handle=try FileHandle(forWritingTo:raw);output.standardOutput=handle
    try output.run();output.waitUntilExit();try handle.close();precondition(output.terminationStatus == 0)
    var settings=Options();settings.outputFolder=folder.path
    let extracted=try Engine().run([raw],action:"extract",options:settings)[0]
    let rawBytes=try Data(contentsOf:extracted.appendingPathComponent("binary"))
    precondition(rawBytes == Data([0,255,100,10]),"Plain gzip must preserve binary data")
    precondition(WorkspaceFileOperations.canExtract(folder.appendingPathComponent("sample.tar.gz")))
    precondition(WorkspaceFileOperations.canExtract(folder.appendingPathComponent("sample.tgz")))
    precondition(!WorkspaceFileOperations.canExtract(directory))
    print("PASS: Duplicate files/folders/batches/collisions/rollback, Atelier append/dedupe/open, Copy/Copy Path clipboard, ZIP/TAR/GZIP real pinned extraction and plain binary gzip")
  }
}

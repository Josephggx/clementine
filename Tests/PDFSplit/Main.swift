import AppKit
import SwiftUI
import PDFKit
import CoreText

@main struct PDFSplitCheck {
  static func fixture(_ url: URL, count: Int) throws {
    var bounds = CGRect(x:0,y:0,width:300,height:420)
    let context = CGContext(url as CFURL,mediaBox:&bounds,nil)!
    for index in 0..<count {
      context.beginPDFPage(nil)
      context.textPosition = CGPoint(x:30,y:330)
      let text = NSAttributedString(string:"Source page \(index+1)",attributes:[
        .font:NSFont.systemFont(ofSize:20), .foregroundColor:NSColor.black])
      CTLineDraw(CTLineCreateWithAttributedString(text),context)
      context.endPDFPage()
    }
    context.closePDF()
  }

  @MainActor static func main() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("clementine-split-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    defer { if !CommandLine.arguments.contains("--ui") && Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String != "SplitRevisionPreview" && Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String != "OrganizeRevisionPreview" { try? FileManager.default.removeItem(at:root) } }
    let source = root.appendingPathComponent("Document.pdf")
    let second = root.appendingPathComponent("Autre.pdf")
    try fixture(source,count:4); try fixture(second,count:2)
    if CommandLine.arguments.contains("--ui") || Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String == "SplitRevisionPreview" || Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String == "OrganizeRevisionPreview" {
      NSApp.setActivationPolicy(.regular)
      let organize=Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String == "OrganizeRevisionPreview"
      let module = ModuleWindowController(tool:organize ? "organize" : "split",files:organize ? [source] : [source,second],defaults:Options(),reveal:false)
      module.show(); NSApp.activate(ignoringOtherApps:true)
      module.window.makeKeyAndOrderFront(nil)
      module.onClose={NSApp.terminate(nil)}
      withExtendedLifetime(module) { NSApp.run() }
      return
    }
    let engine = Engine()
    var options = Options()
    options.moduleEditor = true
    func export(_ name:String, _ sources:[URL] = []) throws -> [URL] {
      options.outputFolder = root.appendingPathComponent(name).path
      return try engine.run(sources.isEmpty ? [source] : sources,action:"split",options:options)
    }
    func contents(_ url:URL) -> [String] {
      let doc = PDFDocument(url:url)!
      return (0..<doc.pageCount).map { doc.page(at:$0)!.string!.trimmingCharacters(in:.whitespacesAndNewlines) }
    }
    let individual = try export("individual")
    precondition(individual.count == 4 && individual.allSatisfy { $0.pathExtension == "pdf" })
    for (index,url) in individual.enumerated() { precondition(contents(url) == ["Source page \(index+1)"]) }
    options.pdfSplitMode = "custom"
    options.pdfSplitGroups[source.path] = [[2,0],[],[3,1]]
    let custom = try export("custom")
    precondition(custom.count == 2 && contents(custom[0]) == ["Source page 3","Source page 1"])
    precondition(contents(custom[1]) == ["Source page 4","Source page 2"])
    options.pdfSplitGroups[second.path] = [[1,0]]
    let batch = try export("batch",[source,second])
    precondition(batch.count == 3 && contents(batch[2]) == ["Source page 2","Source page 1"])
    for invalid in [[[0,1],[2]],[[0,1,2,3,3]],[[0,1,2,4]],[]] {
      options.pdfSplitGroups[source.path] = invalid
      do { _ = try export("invalid-"+UUID().uuidString); fatalError("Invalid grouping accepted") }
      catch is ClementineError { }
    }
    // Edited instances can duplicate, rotate and deliberately remove source pages.
    options.pdfSplitGroups[source.path] = [[4,0],[2]]
    options.pdfSplitEdits[source.path] = [0:ModulePage(index:0,rotation:90),
      4:ModulePage(index:0,rotation:180),2:ModulePage(index:2)]
    let edited = try export("edited")
    precondition(edited.count == 2 && contents(edited[0]) == ["Source page 1","Source page 1"])
    precondition(contents(edited[1]) == ["Source page 3"])
    let editedPDF = PDFDocument(url:edited[0])!
    precondition(editedPDF.page(at:0)!.rotation == 180 && editedPDF.page(at:1)!.rotation == 90)
    for malformed in [[[0,0],[2,4]],[[0,4]],[[0,2,4,99]],[]] {
      precondition(!PDFSplitLayout.isValid(malformed,count:4,edits:options.pdfSplitEdits[source.path]))
    }
    options.pdfSplitEdits.removeAll()
    let single = root.appendingPathComponent("Une page.pdf")
    try fixture(single,count:1)
    precondition(!Tool.available([single]).contains(where:{$0.id == "split"}))
    precondition(!Tool.available([source,single]).contains(where:{$0.id == "split"}))
    precondition(Tool.available([source]).contains(where:{$0.id == "split"}))
    precondition(Tool.catalogue(for:single).contains(where:{$0.id == "split"}))
    options.pdfSplitFormat = "png"
    let images = try export("images")
    precondition(images.count == 4)
    for image in images {
      let bitmap = NSBitmapImageRep(data:try Data(contentsOf:image))!
      precondition(image.pathExtension == "png" && bitmap.pixelsWide == 600 && bitmap.pixelsHigh == 840)
    }
    options.pdfSplitFormat = "jpg"
    let jpegs = try export("jpeg")
    precondition(jpegs.count == 4)
    for image in jpegs {
      let data = try Data(contentsOf:image)
      let bitmap = NSBitmapImageRep(data:data)!
      precondition(image.pathExtension == "jpg" && Array(data.prefix(2)) == [0xff,0xd8])
      precondition(bitmap.pixelsWide == 600 && bitmap.pixelsHigh == 840)
    }
    var layout = PDFSplitLayout.individual(count:4)
    layout = PDFSplitLayout.moving(2,in:layout,to:0,before:0)
    precondition(layout == [[2,0],[1],[3]])
    layout = PDFSplitLayout.moving(0,in:layout,to:0,before:2)
    precondition(layout[0] == [0,2])
    for move in 0..<500 {
      layout = PDFSplitLayout.moving(move % 4,in:layout,to:(move / 4) % layout.count)
      precondition(PDFSplitLayout.isComplete(layout,count:4))
    }
    precondition(PDFSplitLayout.inserting(nil,in:[[0],[1]],at:0) == [[],[0],[1]])
    precondition(PDFSplitLayout.inserting(nil,in:[[0],[1]],at:1) == [[0],[],[1]])
    precondition(PDFSplitLayout.inserting(nil,in:[[0],[1]],at:2) == [[0],[1],[]])
    precondition(PDFSplitLayout.inserting(1,in:[[0],[1]],at:0) == [[1],[0]])
    precondition(PDFSplitLayout.inserting(0,in:[[0],[1]],at:2) == [[1],[0]])
    precondition(PDFSplitLayout.moving(99,in:layout,to:0) == layout)
    precondition(PDFSplitLayout.moving(0,in:layout,to:99) == layout)
    for tools in [Tool.available([source,second]),Tool.catalogue(for:source)] {
      let merge = tools.firstIndex(where:{$0.id == "mergepdf"})!
      precondition(tools[merge+1].id == "split" && tools[merge].wheelTitle == "MERGE")
    }
    let session = ModuleSession(tool:"split",files:[source],defaults:Options(),reveal:false,cataloguePreview:true)
    precondition(session.canSave && session.options.pdfSplitFormat == "pdf" && session.options.pdfSplitMode == "pages")
    session.options.pdfSplitMode = "custom"
    precondition(session.canSave)
    session.options.pdfSplitGroups[source.path] = []
    precondition(!session.canSave)
    for format in ["png","jpg"] {
      session.options.pdfSplitFormat = format
      precondition(session.canSave)
    }
    let organizer=ModuleSession(tool:"organize",files:[source],defaults:Options(),reveal:false,cataloguePreview:true)
    let firstID=organizer.options.modulePages[0].id
    let thirdID=organizer.options.modulePages[2].id
    organizer.editOrganizedPage(firstID,action:"rotate")
    organizer.editOrganizedPage(firstID,action:"duplicate")
    let duplicateID=organizer.options.modulePages[1].id
    precondition(duplicateID != firstID && organizer.options.modulePages[1].rotation == 90)
    organizer.moveOrganizedPage(thirdID,before:firstID)
    precondition(organizer.options.modulePages[0].id == thirdID)
    organizer.editOrganizedPage(firstID,action:"remove")
    precondition(!organizer.options.modulePages.contains(where:{$0.id == firstID}))
    organizer.editOrganizedPage(firstID,action:"rotate") // A stale menu cannot mutate another page.
    organizer.moveOrganizedPage(thirdID)
    precondition(organizer.options.modulePages.map(\.index) == [0,1,2])
    var organizedSettings=organizer.options
    organizedSettings.outputFolder=root.appendingPathComponent("organized").path
    let organized=try engine.run([source],action:"organize",options:organizedSettings)[0]
    let organizedPDF=PDFDocument(url:organized)!
    precondition(organizedPDF.pageCount == 3 && organizedPDF.page(at:0)!.rotation == 90)
    precondition(contents(organized) == ["Source page 1","Source page 2","Source page 3"])
    print("PASS: editable PDF pages, custom groups/order, batch sources, PNG/JPEG pages, invalid groups, 500 page moves, wheel adjacency, defaults and Organize commands/export")
  }
}

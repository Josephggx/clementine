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
    defer { if !CommandLine.arguments.contains("--ui") { try? FileManager.default.removeItem(at:root) } }
    let source = root.appendingPathComponent("Document.pdf")
    let second = root.appendingPathComponent("Autre.pdf")
    try fixture(source,count:4); try fixture(second,count:2)
    if CommandLine.arguments.contains("--ui") {
      NSApp.setActivationPolicy(.regular)
      let module = ModuleWindowController(tool:"split",files:[source,second],defaults:Options(),reveal:false)
      module.show(); NSApp.activate(ignoringOtherApps:true)
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
    options.pdfSplitFormat = "png"
    let images = try export("images")
    precondition(images.count == 4)
    for image in images {
      let bitmap = NSBitmapImageRep(data:try Data(contentsOf:image))!
      precondition(image.pathExtension == "png" && bitmap.pixelsWide == 600 && bitmap.pixelsHigh == 840)
    }
    var layout = PDFSplitLayout.individual(count:4)
    layout = PDFSplitLayout.moving(2,in:layout,to:0,before:0)
    precondition(layout == [[2,0],[1],[],[3]])
    layout = PDFSplitLayout.moving(0,in:layout,to:0,before:2)
    precondition(layout[0] == [0,2])
    for move in 0..<500 {
      layout = PDFSplitLayout.moving(move % 4,in:layout,to:(move / 4) % 4)
      precondition(PDFSplitLayout.isComplete(layout,count:4))
    }
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
    print("PASS: editable PDF pages, custom groups/order, batch sources, PNG pages, invalid groups, 500 page moves, wheel adjacency and defaults")
  }
}

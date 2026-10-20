import AppKit
import ApplicationServices
import SwiftUI

let citrus = Color(red:0.96,green:0.43,blue:0.19)

final class ImportCheck: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  var status: NSTextField!
  var scenario: NSPopUpButton!
  var runButton: NSButton!
  var caseName = ""
  var cases: [(String, [String])] = []
  var started = Date()
  let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey:"TestRoot") as! String)
  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--routes") {
      for raw in ["https://app.finovox.com", "https://app.finovox.com/", "https://app.finovox.com/?page=1"] {
        precondition(FinovoxImportPage.route(for:URL(string:raw)) == .documents)
      }
      for raw in ["https://app.finovox.com/abc/preview", "https://app.finovox.com/internal-tools", "https://finovox.com/", "http://app.finovox.com/", "https://app.finovox.com.evil.test/"] {
        precondition(FinovoxImportPage.route(for:URL(string:raw)) == .other)
      }
      for raw in ["https://app.finovox.com/login", "https://app.finovox.com/auth/login", "https://app.finovox.com/signin"] {
        precondition(FinovoxImportPage.route(for:URL(string:raw)) == .signIn)
      }
      print("PASS: document list, preview, internal tools, sign-in and foreign origins")
      NSApp.terminate(nil);return
    }
    guard AXIsProcessTrusted() else {
      try? "accessibility-not-trusted\n".write(to:root.appendingPathComponent("test-result.txt"),atomically:true,encoding:.utf8)
      NSApp.terminate(nil);return
    }
    NSApp.setActivationPolicy(.accessory)
    prepareFixtures()
    window=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:230),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title="Clémentine — Vérification Finovox";window.isReleasedWhenClosed=false
    let view=NSView(frame:NSRect(x:0,y:0,width:520,height:230))
    status=NSTextField(wrappingLabelWithString:"Test avec un fichier de démonstration uniquement.")
    status.frame=NSRect(x:20,y:125,width:480,height:75);view.addSubview(status)
    scenario=NSPopUpButton(frame:NSRect(x:20,y:80,width:480,height:32))
    scenario.addItems(withTitles:cases.map(\.0));view.addSubview(scenario)
    if let flag=CommandLine.arguments.firstIndex(of:"--case"),
      CommandLine.arguments.count>flag+1, let index=Int(CommandLine.arguments[flag+1]),
      cases.indices.contains(index-1) {scenario.selectItem(at:index-1)}
    runButton=NSButton(title:"Tester l’import de démonstration",target:self,action:#selector(start))
    runButton.frame=NSRect(x:95,y:25,width:330,height:32);view.addSubview(runButton)
    window.contentView=view;window.center();window.makeKeyAndOrderFront(nil)
    FinovoxUploader.shared.onStageChange = { [weak self] stage in
      guard let self else{return}
      self.status.stringValue="Étape : "+stage
      self.record(stage)
    }
    FinovoxUploader.shared.onDiagnostic = { [weak self] message in self?.record(message) }
    FinovoxUploader.shared.onCompletion = { [weak self] success,message in
      guard let self else{return}
      self.status.stringValue=message
      self.record((success ? "SUCCESS " : "FAIL ")+message)
      self.runButton.isEnabled=true;self.scenario.isEnabled=true
      DispatchQueue.main.async {
        // Keep the test controls above the uploader's informational result.
        // The next start closes that result through the normal uploader flow.
        self.window.level=NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1)
        NSApp.activate(ignoringOtherApps:true)
        self.window.makeKeyAndOrderFront(nil)
      }
      try? "\(success ? "success" : "failure")\n\(Date().timeIntervalSince(self.started))\n\(message)\n"
        .write(to:self.root.appendingPathComponent("test-result.txt"),atomically:true,encoding:.utf8)
    }
  }
  @objc func start() {
    window.level = .normal
    let selected=cases[scenario.indexOfSelectedItem]
    caseName=selected.0;started=Date();record("START "+caseName)
    runButton.isEnabled=false;scenario.isEnabled=false
    FinovoxUploader.shared.start(selected.1.map {root.appendingPathComponent($0)})
  }
  func prepareFixtures() {
    if CommandLine.arguments.contains("--reuse-fixtures"),
      let data=try? Data(contentsOf:root.appendingPathComponent("cases.json")),
      let rows=try? JSONDecoder().decode([[String]].self,from:data),
      rows.allSatisfy({$0.count>=2}) {
      cases=rows.map {($0[0],Array($0.dropFirst()))};return
    }
    let prefix="Clementine-test-"+String(Int(Date().timeIntervalSince1970))
    let photo=try! Data(contentsOf:root.appendingPathComponent("Clementine-test-import-20261020.jpg"))
    for suffix in ["jpg.jpg","jpeg.jpeg","archive-a.jpg","archive-b.jpg","batch.jpg","accents épreuve.jpg"] {
      try! photo.write(to:root.appendingPathComponent(prefix+"-"+suffix))
    }
    for suffix in ["document.pdf","batch.pdf","mixed.pdf"] {
      let url=root.appendingPathComponent(prefix+"-"+suffix)
      let consumer=CGDataConsumer(url:url as CFURL)!
      var box=CGRect(x:0,y:0,width:400,height:560)
      let context=CGContext(consumer:consumer,mediaBox:&box,nil)!
      context.beginPDFPage(nil);context.setFillColor(NSColor.orange.cgColor)
      context.fill(CGRect(x:80,y:180,width:240,height:200))
      context.endPDFPage();context.closePDF()
    }
    let zip=Process();zip.executableURL=URL(fileURLWithPath:"/usr/bin/zip")
    zip.currentDirectoryURL=root
    zip.arguments=["-q",prefix+"-archive.zip",prefix+"-archive-a.jpg",prefix+"-archive-b.jpg"]
    try! zip.run();zip.waitUntilExit();precondition(zip.terminationStatus==0)
    cases=[("01 JPG",[prefix+"-jpg.jpg"]),
      ("02 JPEG",[prefix+"-jpeg.jpeg"]),
      ("03 PDF",[prefix+"-document.pdf"]),
      ("04 ZIP — deux images",[prefix+"-archive.zip"]),
      ("05 Batch PDF + JPG",[prefix+"-batch.pdf",prefix+"-batch.jpg"]),
      ("06 Nom accentué et espaces",[prefix+"-accents épreuve.jpg"]),
      ("07 Réimport du JPG",[prefix+"-jpg.jpg"]),
      ("08 Lot existant + nouveau",[prefix+"-jpg.jpg",prefix+"-mixed.pdf"])]
    if let data=try? JSONEncoder().encode(cases.map {[$0.0]+$0.1}) {
      try? data.write(to:root.appendingPathComponent("cases.json"))
    }
    try? cases.map {$0.0+": "+$0.1.joined(separator:", ")}.joined(separator:"\n")
      .write(to:root.appendingPathComponent("cases.txt"),atomically:true,encoding:.utf8)
  }
  func record(_ text:String) {
    let row=String(format:"%.3f",Date().timeIntervalSince(started))+" "+text+"\n"
    let url=root.appendingPathComponent("trace.log")
    if let handle=try? FileHandle(forWritingTo:url) {_ = try? handle.seekToEnd();try? handle.write(contentsOf:Data(row.utf8));try? handle.close()}
    else {try? row.write(to:url,atomically:true,encoding:.utf8)}
  }
}
let app=NSApplication.shared
let delegate=ImportCheck();app.delegate=delegate;app.run()

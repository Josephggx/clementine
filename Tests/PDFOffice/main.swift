import AppKit
import CoreText
import PDFKit
import Foundation

func runChecks() throws {
let fm = FileManager.default
let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PDF_OFFICE_TEST_ROOT"]!)
if fm.fileExists(atPath:root.path) {try fm.removeItem(at:root)}
try fm.createDirectory(at:root,withIntermediateDirectories:true)
let engine = Engine()
var options = Options(); options.outputFolder = root.appendingPathComponent("Exports").path
func require(_ value: Bool, _ message: String) throws { if !value { throw ClementineError(message) } }
let phrase = "Native PDF text remains editable 24681357"
let native = root.appendingPathComponent("Native.pdf")
var bounds = CGRect(x:0,y:0,width:420,height:600)
let pdf = CGContext(native as CFURL,mediaBox:&bounds,nil)!
pdf.beginPDFPage(nil); pdf.textPosition = CGPoint(x:32,y:500)
CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:phrase,attributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.black])),pdf)
pdf.setFillColor(NSColor.orange.cgColor);pdf.fillEllipse(in:CGRect(x:50,y:100,width:80,height:80));pdf.endPDFPage();pdf.closePDF()
let image = try engine.renderPage(PDFDocument(url:native)!.page(at:0)!,scale:2)
let scan = root.appendingPathComponent("Scan.pdf")
let scanned=PDFDocument();scanned.insert(PDFPage(image:NSImage(cgImage:image,size:.zero))!,at:0);scanned.write(to:scan)
let mixed = root.appendingPathComponent("Mixed.pdf")
let mixedDoc = PDFDocument(url:native)!;mixedDoc.insert(scanned.page(at:0)!,at:1);mixedDoc.write(to:mixed)
var checks:[[String:Any]]=[]
for (url, editable, imageCount) in [(native,true,0),(scan,false,1),(mixed,true,1)] {
 let original=try Data(contentsOf:url)
 let output=try engine.run([url],action:"convert:docx",options:options)[0]
 let xml=try engine.process("/usr/bin/unzip",["-p",output.path,"word/document.xml"])
 let media=try engine.process("/usr/bin/unzip",["-Z1",output.path]).components(separatedBy:.newlines).filter{$0.hasPrefix("word/media/") && !$0.hasSuffix("/")}
 try require(xml.contains("24681357")==editable,"Wrong text editability: \(url.lastPathComponent)")
 try require(media.count==imageCount,"Wrong page image policy: \(url.lastPathComponent): \(media.count)")
 try require(try Data(contentsOf:url)==original,"Original modified")
 checks.append(["source":url.lastPathComponent,"editableText":editable,"fullPageImages":media.count,"originalUnchanged":true,"passed":true])
 print("PASS \(url.lastPathComponent): editable=\(editable), page images=\(media.count)");fflush(stdout)
}
var preserve=options;preserve.pdfOfficeLayout="preservePages"
let preserved=try engine.run([native],action:"convert:docx",options:preserve)[0]
let xml=try engine.process("/usr/bin/unzip",["-p",preserved.path,"word/document.xml"])
try require(!xml.contains("24681357") && xml.contains("<w:drawing>"),"Explicit page preservation changed")
checks.append(["source":"Native.pdf","explicitPreservePages":true,"passed":true])
try JSONSerialization.data(withJSONObject:["passed":checks.count,"checks":checks],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
print("PASS \(checks.count) PDF Office checks")

}
if let root = Bundle.main.object(forInfoDictionaryKey: "PDFOfficeTestRoot") as? String {
 let app=NSApplication.shared;app.setActivationPolicy(.regular)
 let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 window.title="Clémentine — Vérification PDF éditable"
 let label=NSTextField(wrappingLabelWithString:"Vérification du texte natif, des scans et des PDF mixtes…")
 label.frame=NSRect(x:20,y:50,width:460,height:80);window.contentView?.addSubview(label)
 let button=NSButton(title:"Fermer le test",target:app,action:#selector(NSApplication.terminate(_:)));button.frame=NSRect(x:340,y:15,width:140,height:30);window.contentView?.addSubview(button)
 window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
 setenv("PDF_OFFICE_TEST_ROOT",root,1)
 setenv("CLEMENTINE_OFFICE","/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice",1)
 let source=Bundle.main.object(forInfoDictionaryKey:"ClementineSourceRoot") as! String
 setenv("CLEMENTINE_TOOLS",source+"/Resources/Tools",1);setenv("CLEMENTINE_RESOURCES",source+"/Resources",1)
 DispatchQueue.global(qos:.userInitiated).async {
   do {try runChecks();DispatchQueue.main.async{label.stringValue="4 contrôles réussis : texte éditable, scans, PDF mixte et conservation explicite des pages."}}
   catch {try? error.localizedDescription.write(to:URL(fileURLWithPath:root).appendingPathComponent("failure.txt"),atomically:true,encoding:.utf8);DispatchQueue.main.async{label.stringValue="Échec : \(error.localizedDescription)"}}
 }
 app.run()
} else {
 setenv("PDF_OFFICE_TEST_ROOT",CommandLine.arguments[1],1)
 try runChecks()
}

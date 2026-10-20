import AppKit
import Foundation
import PDFKit
import CoreText
func pagePixels(_ page:PDFPage)->[UInt8] {
 let width=420,height=600;var data=[UInt8](repeating:255,count:width*height*4)
 data.withUnsafeMutableBytes { memory in
  let c=CGContext(data:memory.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height))
  let ref=page.pageRef!;c.concatenate(ref.getDrawingTransform(.mediaBox,rect:CGRect(x:0,y:0,width:width,height:height),rotate:0,preserveAspectRatio:true));c.drawPDFPage(ref)
 };return data
}
func pageError(_ original:PDFDocument,_ converted:PDFDocument)->Double {
 guard original.pageCount==converted.pageCount else{return 255}
 return (0..<original.pageCount).map { i -> Double in
  let a=pagePixels(original.page(at:i)!),b=pagePixels(converted.page(at:i)!)
  return zip(a,b).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(a.count)
 }.max() ?? 255
}
func runDocumentChecks() -> Bool {
do {
let e=Engine(),fm=FileManager.default
let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["DOCUMENT_TEST_ROOT"]!)
try fm.createDirectory(at:root,withIntermediateDirectories:true)
let input=root.appendingPathComponent("Sources"),output=root.appendingPathComponent("Exports")
try fm.createDirectory(at:input,withIntermediateDirectories:true);try fm.createDirectory(at:output,withIntermediateDirectories:true)
var o=Options();o.outputFolder=output.path
var report:[[String:Any]]=[]
func require(_ v:Bool,_ message:String="Assertion invalide") throws {if !v {throw ClementineError(message)}}
func test(_ name:String,_ body:()throws->Void) {do{try body();report.append(["name":name,"passed":true]);print("PASS \(name)")}catch{report.append(["name":name,"passed":false,"error":error.localizedDescription]);print("FAIL \(name): \(error.localizedDescription)")};fflush(stdout)}
func run(_ source:URL,_ ext:String,_ settings:Options?=nil)throws->[URL] {try e.run([source],action:"convert:"+ext,options:settings ?? o)}
func xml(_ url:URL,_ part:String)throws->String {try e.process("/usr/bin/unzip",["-p",url.path,part])}
func entries(_ url:URL)throws->[String] {try e.process("/usr/bin/unzip",["-Z1",url.path]).components(separatedBy:.newlines)}
let art=try e.canvas(width:240,height:160){c in c.setFillColor(NSColor.orange.cgColor);c.fill(CGRect(x:0,y:0,width:240,height:160));c.setFillColor(NSColor.blue.cgColor);c.fillEllipse(in:CGRect(x:50,y:20,width:120,height:120))}
let image=input.appendingPathComponent("Illustration.png");try DocumentFidelity.png(art,to:image)
let pdf=input.appendingPathComponent("Mixed.pdf")
var bounds=CGRect(x:0,y:0,width:420,height:600)
let ctx=CGContext(pdf as CFURL,mediaBox:&bounds,nil)!
for n in 0..<3 {
 ctx.beginPDFPage(nil);ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(bounds)
 if n != 1 {
  ctx.textMatrix = .identity;ctx.textPosition=CGPoint(x:40,y:530)
  let line=CTLineCreateWithAttributedString(NSAttributedString(string:"Joseph — Tableau et illustration \(n+1)",attributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.black]));CTLineDraw(line,ctx)
  ctx.textPosition=CGPoint(x:40,y:490);CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:"Finovox 123,45 €",attributes:[.font:NSFont.systemFont(ofSize:12)])),ctx)
 }
 ctx.draw(art,in:CGRect(x:50,y:180,width:240,height:160))
 ctx.endPDFPage()
};ctx.closePDF()
let original=try Data(contentsOf:pdf)
var preserved:URL?,rich:URL?,book:URL?
test("PDF → DOCX: one 300 DPI image per page; no OCR substituted") {
 var settings=o;settings.pdfOfficeLayout="preservePages";let file=try run(pdf,"docx",settings)[0];preserved=file
 let parts=try entries(file).filter{$0.hasPrefix("word/media/") && $0.hasSuffix(".png")};try require(parts.count==3)
 let content=try xml(file,"word/document.xml");try require(!content.contains("Joseph") && content.components(separatedBy:"<wp:anchor ").count-1==3)
 let extracted=input.appendingPathComponent("extracted");try fm.createDirectory(at:extracted,withIntermediateDirectories:true);_ = try e.process("/usr/bin/unzip",["-o","-q",file.path,"-d",extracted.path])
 let bitmap=try e.loadImage(extracted.appendingPathComponent(parts[0]));try require(bitmap.width==1750 && bitmap.height==2500)
}
test("Preserved DOCX reopens as PDF without blank/extra pages") {
 guard let file=preserved else{throw ClementineError("Fixture manquante")};let back=try run(file,"pdf")[0]
 let doc=PDFDocument(url:back)!;try require(doc.pageCount==3,"\(doc.pageCount) pages au lieu de 3")
 try require(abs(doc.page(at:0)!.bounds(for:.mediaBox).width-420)<2)
 try require(pageError(PDFDocument(url:pdf)!,doc)<2,"Rendu des pages altéré")
}
test("PDF → PPTX: page images and three slides") {
 let file=try run(pdf,"pptx")[0],parts=try entries(file);try require(parts.filter{$0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml")}.count==3)
 try require(parts.filter{$0.hasPrefix("ppt/media/") && $0.hasSuffix(".png")}.count==3)
 let back=try run(file,"pdf")[0];try require(PDFDocument(url:back)?.pageCount==3)
}
test("PDF → EPUB fixed layout: image pages, ordered spine, stored mimetype") {
 var settings=o;settings.epubLayout="preservePages";let file=try run(pdf,"epub",settings)[0];book=file
 let opf=try xml(file,"EPUB/package.opf");try require(opf.contains("pre-paginated") && opf.components(separatedBy:"<itemref ").count==4)
 let data=try Data(contentsOf:file);try require(data[8]==0 && data[9]==0);try require(try entries(file).first=="mimetype")
}
test("PDF → DOCX editable: text plus actual embedded illustration") {
 var settings=o;settings.pdfOfficeLayout="editable";let file=try run(pdf,"docx",settings)[0]
 let content=try xml(file,"word/document.xml");try require(content.contains("Joseph"))
 try require(try entries(file).contains{$0.hasPrefix("word/media/") && !$0.hasSuffix("/")})
}
test("PDF → EPUB adjustable: text and illustrations") {
 let file=try run(pdf,"epub")[0],parts=try entries(file);let html=try parts.filter{$0.hasSuffix(".xhtml")}.map{try xml(file,$0)}.joined()
 try require(html.contains("Joseph") && html.contains("img"))
}
test("PDF → TXT: selected text, without pretending image OCR") {
 let file=try run(pdf,"txt")[0],text=try String(contentsOf:file);try require(text.contains("Joseph"))
}
test("Image-only PDF → TXT: explicit error instead of empty output") {
 let scan=input.appendingPathComponent("Scan.pdf");let doc=PDFDocument();doc.insert(PDFPage(image:NSImage(cgImage:art,size:.zero))!,at:0);doc.write(to:scan)
 do {_ = try run(scan,"txt");throw ClementineError("Un scan ne doit pas être présenté comme un texte extrait")}catch let error as ClementineError {try require(error.message.contains("sélectionnable"))}
}
let md=input.appendingPathComponent("Structured.md")
try "# Titre Joseph\n\nUn **texte en gras** avec [un lien](https://example.com).\n\n| Client | Total |\n| --- | --- |\n| Finovox | 123 |\n\n![Illustration](Illustration.png)\n".write(to:md,atomically:true,encoding:.utf8)
test("Markdown → DOCX retains heading, bold, table and illustration") {
 let file=try run(md,"docx")[0];rich=file;let content=try xml(file,"word/document.xml")
 try require(content.contains("Joseph") && content.contains("<w:tbl>") && content.contains("<w:b"))
 try require(try entries(file).contains{$0.hasPrefix("word/media/") && !$0.hasSuffix("/")})
}
test("Markdown → PDF retains text and image") {let file=try run(md,"pdf")[0];try require(PDFDocument(url:file)?.string?.contains("Joseph")==true)}
test("DOCX → Markdown retains table, bold, hyperlink and image") {
 guard let rich else {throw ClementineError("Fixture DOCX absente")};let file=try run(rich,"md")[0],text=try String(contentsOf:file)
 try require(text.contains("Joseph") && text.contains("**") && text.contains("| ---") && fm.fileExists(atPath:RichDocuments.markdownAssets(for:file).path) && !text.contains("data:image/") && text.contains("https://example.com"))
}
test("DOCX → EPUB retains embedded image and text") {
 guard let rich else {throw ClementineError("Fixture DOCX absente")};let file=try run(rich,"epub")[0],parts=try entries(file)
 let html=try parts.filter{$0.hasSuffix(".xhtml")}.map{try xml(file,$0)}.joined();try require(html.contains("Joseph") && html.contains("img"))
}
test("EPUB fixed image pages → DOCX retains all artwork") {
 guard let book else {throw ClementineError("Fixture EPUB absente")};let file=try run(book,"docx")[0];try require(try entries(file).filter{$0.hasPrefix("word/media/") && !$0.hasSuffix("/")}.count==3)
}
test("EPUB fixed image pages → HTML embeds all images") {
 guard let book else {throw ClementineError("Fixture EPUB absente")};let file=try run(book,"html")[0],html=try String(contentsOf:file);try require(html.components(separatedBy:"data:image/png;base64,").count==4)
}
test("Markdown remote image cannot silently disappear or cause a request") {
 let file=input.appendingPathComponent("Remote.md");try "![remote](https://example.com/test.png)".write(to:file,atomically:true,encoding:.utf8)
 do {_ = try run(file,"docx");throw ClementineError("Ressource distante acceptée")}catch let error as ClementineError{try require(error.message.contains("distante"))}
}
test("PDF → Markdown retains illustrations as local PNG files") {
 let file=try run(pdf,"md")[0],text=try String(contentsOf:file)
 try require(text.contains("Joseph") && !text.contains("data:image/") && fm.fileExists(atPath:RichDocuments.markdownAssets(for:file).path))
}
test("DOCX → HTML is self contained, with embedded artwork") {
 guard let rich else{throw ClementineError("Fixture absente")}
 let file=try run(rich,"html")[0];var directory:ObjCBool=false;fm.fileExists(atPath:file.path,isDirectory:&directory)
 try require(!directory.boolValue);let text=try String(contentsOf:file)
 try require(text.contains("Joseph") && text.contains("data:image/png;base64,"))
}
test("Rotated PDF renders upright at 300 DPI") {
 let doc=PDFDocument(url:pdf)!;doc.page(at:0)!.rotation=90
 let file=input.appendingPathComponent("Rotated.pdf");doc.write(to:file)
 let exported=try run(file,"png");let bitmap=try e.loadImage(exported[0]);try require(bitmap.width==2500 && bitmap.height==1750)
}
test("RTFD → DOCX retains attached artwork and text") {
 let content=NSMutableAttributedString(string:"Joseph — pièce jointe\n",attributes:[.font:NSFont.systemFont(ofSize:14)])
 let attachment=NSTextAttachment();attachment.fileWrapper=FileWrapper(regularFileWithContents:try Data(contentsOf:image));attachment.fileWrapper?.preferredFilename="Illustration.png"
 content.append(NSAttributedString(attachment:attachment))
 let file=input.appendingPathComponent("Attached.rtfd")
 let wrapper=try content.fileWrapper(from:NSRange(location:0,length:content.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtfd]);try wrapper.write(to:file,options:.atomic,originalContentsURL:nil)
 let converted=try run(file,"docx")[0];try require(try xml(converted,"word/document.xml").contains("Joseph"))
 try require(try entries(converted).contains{$0.hasPrefix("word/media/") && !$0.hasSuffix("/")})
}
if Bundle.main.object(forInfoDictionaryKey:"DocumentTestRoot") != nil, ProcessInfo.processInfo.environment["DOCUMENT_TEST_NATIVE"] == "1" {
 test("PDF → native Pages → PDF: all page images retained") {
  var settings=o;settings.pdfOfficeLayout="preservePages";let file=try run(pdf,"pages",settings)[0],back=try run(file,"pdf")[0]
  try require(PDFDocument(url:back)?.pageCount==3)
  try require(pageError(PDFDocument(url:pdf)!,PDFDocument(url:back)!)<2,"Rendu Pages altéré")
 }
 test("Rich DOCX → native Pages → DOCX: text, table and image retained") {
  guard let rich else {throw ClementineError("Fixture DOCX absente")}
  let pages=try run(rich,"pages")[0],back=try run(pages,"docx")[0]
  let content=try xml(back,"word/document.xml");try require(content.contains("Joseph") && content.contains("<w:tbl>"))
  try require(try entries(back).contains{$0.hasPrefix("word/media/") && !$0.hasSuffix("/")})
 }
 test("Native Numbers offers spreadsheet outputs") {
  let source=input.appendingPathComponent("Sales.csv")
  try "Product,Amount\nOrange,42\n".write(to:source,atomically:true,encoding:.utf8)
  let workbook=try run(source,"xlsx")[0],numbers=try run(workbook,"numbers")[0]
  for format in ["xlsx","ods","tsv","pdf","csv"] {
   let files=try run(numbers,format)
   try require(!files.isEmpty && files.allSatisfy{fm.fileExists(atPath:$0.path)},"Numbers → \(format) absent")
   if format == "pdf" {try require((PDFDocument(url:files[0])?.pageCount ?? 0)>0)}
  }
 }
 test("Native Keynote offers presentation outputs") {
  let sourceRoot=URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"ClementineSourceRoot") as? String ?? fm.currentDirectoryPath)
  let fixture=sourceRoot.appendingPathComponent("Tests/DocumentEngine/KeynoteFixture.key")
  let keynote=input.appendingPathComponent("KeynoteFixture.key")
  try fm.copyItem(at:fixture,to:keynote)
  for format in ["pptx","pdf","jpg","png"] {
   let files=try run(keynote,format)
   try require(!files.isEmpty && files.allSatisfy{fm.fileExists(atPath:$0.path)},"Keynote → \(format) absent")
   if format == "pdf" {try require(PDFDocument(url:files[0])?.pageCount==1)}
  }
 }
}
test("Original PDF content is unchanged") {try require(try Data(contentsOf:pdf)==original)}
let passed=report.filter{$0["passed"] as? Bool==true}.count
let result:[String:Any]=["passed":passed,"total":report.count,"checks":report,"exactTangerineParityCertified":false]
try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
print("PASS \(passed) / \(report.count) document checks")
return passed==report.count
} catch { print("FAIL Preparation: \(error)");return false }
}

if CommandLine.arguments.contains("--gui") || Bundle.main.object(forInfoDictionaryKey:"DocumentTestRoot") != nil {
 let app=NSApplication.shared
 let menu=NSMenu(),item=NSMenuItem(),submenu=NSMenu()
 submenu.addItem(withTitle:"Quitter le test",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
 item.submenu=submenu;menu.addItem(item);app.mainMenu=menu
 app.setActivationPolicy(.regular)
 let root=Bundle.main.object(forInfoDictionaryKey:"DocumentTestRoot") as? String ?? NSTemporaryDirectory()+"ClementineDocumentTest"
 setenv("DOCUMENT_TEST_ROOT",root,1)
 setenv("DOCUMENT_TEST_NATIVE","1",1)
 if Bundle.main.object(forInfoDictionaryKey:"DocumentMatrixAffected") as? Bool == true {setenv("DOCUMENT_MATRIX_AFFECTED","1",1)}
 setenv("CLEMENTINE_DIAGNOSTICS",root,1)
 try? JSONSerialization.data(withJSONObject:ProcessInfo.processInfo.environment.filter{["TMPDIR","TMP","TEMP","SAL_USE_VCLPLUGIN","DYLD_LIBRARY_PATH"].contains($0.key)},options:.prettyPrinted).write(to:URL(fileURLWithPath:root).appendingPathComponent("environment.json"))
 let workspace=Bundle.main.object(forInfoDictionaryKey:"ClementineSourceRoot") as! String
 setenv("CLEMENTINE_TOOLS",workspace+"/Resources/Tools",1)
 setenv("CLEMENTINE_RESOURCES",workspace+"/Resources",1)
 setenv("CLEMENTINE_OFFICE","/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice",1)
 try? FileManager.default.createDirectory(atPath:root,withIntermediateDirectories:true)
 freopen(root+"/tests.log","w",stdout);freopen(root+"/errors.log","w",stderr)
 let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 window.title="Clémentine — Vérification des conversions"
 let label=NSTextField(wrappingLabelWithString:"Vérification des documents illustrés, pages, scans et formats bureautiques…")
 label.frame=NSRect(x:24,y:45,width:450,height:95);window.contentView?.addSubview(label)
 window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
 DispatchQueue.global(qos:.userInitiated).async {
  let passed=runDocumentChecks()
  runConversionMatrix(URL(fileURLWithPath:root))
  DispatchQueue.main.async {label.stringValue=passed ? "Tous les contrôles des documents sont réussis." : "Vérification terminée. Des écarts sont consignés dans le rapport."}
 }
 app.run()
} else {exit(runDocumentChecks() ? 0 : 1)}

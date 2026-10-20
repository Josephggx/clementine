import AppKit
import Foundation
import PDFKit
import CoreText
import ImageIO

func runMarkdownChecks() -> Bool {
do {
let fm=FileManager.default,engine=Engine()
let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["MARKDOWN_TEST_ROOT"]!)
if fm.fileExists(atPath:root.path) {try fm.removeItem(at:root)}
try fm.createDirectory(at:root,withIntermediateDirectories:true)
let input=root.appendingPathComponent("input"),output=root.appendingPathComponent("output")
try fm.createDirectory(at:input,withIntermediateDirectories:true)
try fm.createDirectory(at:output,withIntermediateDirectories:true)
var options=Options();options.outputFolder=output.path
var results:[[String:Any]]=[]
func check(_ condition:Bool,_ message:String) throws {if !condition {throw ClementineError(message)}}
func test(_ name:String,_ body:()throws->Void) {
 do {try body();results.append(["name":name,"passed":true]);print("PASS \(name)")}
 catch {results.append(["name":name,"passed":false,"error":error.localizedDescription]);print("FAIL \(name): \(error.localizedDescription)")}
 fflush(stdout)
}
let art=try engine.canvas(width:100,height:80) {c in c.setFillColor(NSColor.orange.cgColor);c.fill(CGRect(x:0,y:0,width:100,height:80))}
func pdf(_ file:URL,text:Bool,image:Bool) throws {
 var box=CGRect(x:0,y:0,width:300,height:400)
 let c=CGContext(file as CFURL,mediaBox:&box,nil)!
 c.beginPDFPage(nil);c.setFillColor(NSColor.white.cgColor);c.fill(box)
 if text {
  c.textMatrix = .identity;c.textPosition=CGPoint(x:20,y:350)
  CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:"Joseph Finovox",attributes:[.font:NSFont.systemFont(ofSize:14)])),c)
 }
 if image {c.draw(art,in:CGRect(x:30,y:100,width:100,height:80))}
 c.endPDFPage();c.closePDF()
}
func run(_ file:URL,_ ext:String="md") throws -> URL {try engine.run([file],action:"convert:"+ext,options:options)[0]}
func images(_ md:URL) throws -> [URL] {
 let html=try run(md,"html")
 let rendered=try RichDocuments.parse(String(contentsOf:html,encoding:.utf8))
 let nodes=try rendered.nodes(forXPath:"//img")
 try check(!nodes.isEmpty,"Images missing after Markdown parsing")
 for node in nodes {
  let src=(node as! XMLElement).attribute(forName:"src")!.stringValue!
  try check(src.hasPrefix("data:image/png;base64,"),"Local image did not resolve")
  let data=Data(base64Encoded:src.components(separatedBy:",")[1])!
  try check(CGImageSourceCreateWithData(data as CFData,nil) != nil,"Invalid image bytes")
 }
 let folder=RichDocuments.markdownAssets(for:md)
 return try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
}
let mixed=input.appendingPathComponent("Démo (édition) #1%.pdf")
try pdf(mixed,text:true,image:true)
var first:URL!
test("PDF text and artwork export to readable Markdown with real PNG files") {
 first=try run(mixed)
 let text=try String(contentsOf:first,encoding:.utf8)
 try check(text.contains("Joseph") && text.contains("![Illustration]("),"Missing editable text/image syntax")
 try check(!text.contains("data:image/") && !text.contains(".clementine-"),"Image encoded as URL or tied to temporary files")
 try check(try !images(first).isEmpty,"No PNG exported")
}
test("Repeated export renames Markdown and its image folder together") {
 let second=try run(mixed)
 try check(second != first,"Existing export overwritten")
 let text=try String(contentsOf:second,encoding:.utf8)
 let encoded=RichDocuments.markdownImagePath(folder:RichDocuments.markdownAssets(for:second).lastPathComponent,file:"image-1.png")
 try check(text.contains(encoded),"Collision renamed the file but broke image references")
 _ = try images(second);_ = try images(first)
}
test("Moving Markdown with its image folder retains rendered images") {
 let moved=root.appendingPathComponent("Moved");try fm.createDirectory(at:moved,withIntermediateDirectories:true)
 let copy=moved.appendingPathComponent(first.lastPathComponent)
 try fm.copyItem(at:first,to:copy)
 try fm.copyItem(at:RichDocuments.markdownAssets(for:first),to:RichDocuments.markdownAssets(for:copy))
 _ = try images(copy)
}
test("Existing unrelated image folder is preserved") {
 let file=input.appendingPathComponent("Occupied.pdf");try pdf(file,text:true,image:true)
 let folder=output.appendingPathComponent("Occupied-images")
 try fm.createDirectory(at:folder,withIntermediateDirectories:true)
 let marker=folder.appendingPathComponent("keep.txt");try "keep".write(to:marker,atomically:true,encoding:.utf8)
 let md=try run(file)
 try check(md.lastPathComponent == "Occupied (1).md","Existing image folder not respected")
 try check(try String(contentsOf:marker)=="keep","Existing assets modified")
 _ = try images(md)
}
test("Image-only PDF keeps its page image") {
 let file=input.appendingPathComponent("Scan.pdf");try pdf(file,text:false,image:true)
 let md=try run(file);_ = try images(md)
 try check(try String(contentsOf:md).contains("![Page 1]("),"Image-only page discarded")
}
test("Text-only PDF does not produce an empty image folder") {
 let file=input.appendingPathComponent("Text.pdf");try pdf(file,text:true,image:false)
 let md=try run(file)
 try check(!fm.fileExists(atPath:RichDocuments.markdownAssets(for:md).path),"Empty assets folder created")
 try check(try String(contentsOf:md).contains("Joseph"),"Native text missing")
}
test("Duplicate artwork is stored once and alternate text is safely escaped") {
 let png=root.appendingPathComponent("art.png");try DocumentFidelity.png(art,to:png)
 let data=try Data(contentsOf:png),src="data:image/png;base64,"+data.base64EncodedString()
 let html=input.appendingPathComponent("Repeated.html")
 try DocumentFidelity.html("<p><img alt=\"[one]\" src=\"\(src)\"><img alt=\"two\" src=\"\(src)\"></p>").write(to:html,atomically:true,encoding:.utf8)
 let md=try run(html),text=try String(contentsOf:md)
 try check(text.contains("![\\[one\\]]("),"Invalid Markdown alternate text")
 try check(try images(md).count == 1,"Duplicate artwork exported twice")
}
test("Batch PDFs with identical names keep separate valid image references") {
 let a=input.appendingPathComponent("A"),b=input.appendingPathComponent("B")
 for dir in [a,b] {try fm.createDirectory(at:dir,withIntermediateDirectories:true);try pdf(dir.appendingPathComponent("Batch.pdf"),text:true,image:true)}
 let files=try engine.run([a.appendingPathComponent("Batch.pdf"),b.appendingPathComponent("Batch.pdf")],action:"convert:md",options:options)
 try check(files.count == 2 && files[0] != files[1],"Batch outputs collided")
 for file in files {_ = try images(file)}
}
test("Temporary conversion folders are removed") {
 try check(try !fm.contentsOfDirectory(atPath:output.path).contains(where:{$0.hasPrefix(".clementine-")}),"Staging files leaked")
}
try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
return results.allSatisfy{$0["passed"] as? Bool == true}
} catch {print("FAIL preparation: \(error)");return false}
}
if let root=Bundle.main.object(forInfoDictionaryKey:"MarkdownTestRoot") as? String,
   let workspace=Bundle.main.object(forInfoDictionaryKey:"ClementineSourceRoot") as? String {
 let app=NSApplication.shared;app.setActivationPolicy(.regular)
 setenv("MARKDOWN_TEST_ROOT",root,1);setenv("CLEMENTINE_RESOURCES",workspace+"/Resources",1);setenv("CLEMENTINE_TOOLS",workspace+"/Resources/Tools",1)
 try? FileManager.default.createDirectory(atPath:root,withIntermediateDirectories:true)
 freopen(root+"/tests.log","w",stdout);freopen(root+"/errors.log","w",stderr)
 let menu=NSMenu(),item=NSMenuItem(),submenu=NSMenu()
 submenu.addItem(withTitle:"Quitter le test",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");item.submenu=submenu;menu.addItem(item);app.mainMenu=menu
 let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 window.title="Clémentine — Vérification Markdown"
 let label=NSTextField(wrappingLabelWithString:"Vérification des images Markdown…");label.frame=NSRect(x:24,y:45,width:450,height:95);window.contentView?.addSubview(label)
 window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
 DispatchQueue.global(qos:.userInitiated).async {
  let passed=runMarkdownChecks()
  DispatchQueue.main.async {label.stringValue=passed ? "Les 9 contrôles Markdown sont réussis." : "Des erreurs sont consignées dans le rapport."}
 }
 app.run()
} else {exit(runMarkdownChecks() ? 0 : 1)}

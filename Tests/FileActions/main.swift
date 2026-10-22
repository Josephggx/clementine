import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String) {precondition(value(),message);checks += 1}
func urls(_ extensions:[String])->[URL] {extensions.map {URL(fileURLWithPath:"/sample."+$0)}}
for ext in ["pdf","docx","doc","pages","rtf","txt","md","html","xlsx","xls","csv","tsv","ods","numbers","jpg","png","heic","pptx","ppt","odp","key"] {
 check(WheelActionItems.forURLs(urls([ext]),preview:true).contains {$0.action=="action:print"},"Print missing for \(ext)")
}
for ext in ["zip","tar","gz","mp4","mp3","epub","srt","unknown"] {
 check(!WheelActionItems.forURLs(urls([ext]),preview:true).contains {$0.action=="action:print"},"Unsupported Print for \(ext)")
}
check(!PrintEligibility.supports([]),"Empty selection cannot print")
check(PrintEligibility.supports(urls(["pdf","docx","xlsx","jpg","key"])),"Mixed printable batch")
check(!PrintEligibility.supports(urls(["pdf","mp4"])),"Mixed unsupported batch cannot silently omit a file")
for ext in ["pdf","jpg","png","zip"] {
 check(!WheelActionItems.forURLs(urls([ext]),preview:true).contains {$0.action=="action:finovox"},"Finovox must default to hidden")
 check(WheelActionItems.forURLs(urls([ext]),preview:true,finovoxEnabled:true).contains {$0.action=="action:finovox"},"Opted-in Finovox missing")
}
for ext in ["docx","xlsx","key","mp4"] {
 check(!WheelActionItems.forURLs(urls([ext]),preview:true,finovoxEnabled:true).contains {$0.action=="action:finovox"},"Opt-in does not override unsupported formats")
}
let root=FileManager.default.temporaryDirectory.appendingPathComponent("clementine-print-check-"+UUID().uuidString)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:root)}
let folder=root.appendingPathComponent("folder",isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
check(!PrintEligibility.supports([folder]),"Folders cannot print")
let pdf=root.appendingPathComponent("Document.pdf"),image=root.appendingPathComponent("Image.png")
let source=PDFDocument();source.insert(PDFPage(),at:0);source.insert(PDFPage(),at:1)
check(source.write(to:pdf),"PDF fixture written")
let context=CGContext(data:nil,width:64,height:32,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red:1,green:0.5,blue:0,alpha:1));context.fill(CGRect(x:0,y:0,width:64,height:32))
let writer=CGImageDestinationCreateWithURL(image as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(writer,context.makeImage()!,nil);check(CGImageDestinationFinalize(writer),"PNG fixture written")
let originalPDF=try Data(contentsOf:pdf),originalImage=try Data(contentsOf:image)
let prepared=try PrintAction.prepare([pdf,image],in:root.appendingPathComponent("job"),options:Options())
check(prepared.pageCount==3,"One print job contains every PDF page and image")
check(prepared.page(at:0)?.bounds(for:.mediaBox)==source.page(at:0)?.bounds(for:.mediaBox),"PDF page size preserved")
let finalPDF=try Data(contentsOf:pdf),finalImage=try Data(contentsOf:image)
check(finalPDF==originalPDF,"Source PDF remains unchanged")
check(finalImage==originalImage,"Source image remains unchanged")
do {_ = try PrintAction.prepare([pdf,root.appendingPathComponent("missing.pdf")],in:root.appendingPathComponent("missing-job"),options:Options());fatalError("Missing file accepted")}
catch {checks += 1}
let csv=root.appendingPathComponent("Tableau.csv");try "Nom,Montant\nTest,42\n".write(to:csv,atomically:true,encoding:.utf8)
let sheet=try PrintAction.prepare([csv],in:root.appendingPathComponent("sheet-job"),options:Options())
check(sheet.pageCount>0 && (sheet.string ?? "").contains("42"),"Spreadsheet print preparation contains cell values")
print("PASS: \(checks) file action and print preparation checks; no print dialog or app window opened")

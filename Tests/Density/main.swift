import AppKit
import CoreText
import Foundation
import ImageIO
let e=Engine(),root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["DENSITY_TEST_ROOT"]!)
if FileManager.default.fileExists(atPath:root.path) {try FileManager.default.removeItem(at:root)}
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
let input=root.appendingPathComponent("Three-pages.pdf")
var media=CGRect(x:0,y:0,width:420,height:600)
let pdf=CGContext(input as CFURL,mediaBox:&media,nil)!
for page in 1...3 {
 pdf.beginPDFPage(nil);pdf.setFillColor(NSColor.white.cgColor);pdf.fill(media)
 pdf.textPosition=CGPoint(x:40,y:520)
 CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:"Clémentine — page \(page)",attributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.black])),pdf)
 pdf.setFillColor(NSColor.systemOrange.cgColor);pdf.fillEllipse(in:CGRect(x:40,y:350,width:90,height:90));pdf.endPDFPage()
}
pdf.closePDF()
var options=Options();options.outputFolder=root.path
var checks:[[String:Any]]=[]
for ext in ["png","jpg"] {
 do {
  let files=try e.run([input],action:"convert:"+ext,options:options)
  guard files.count==3 else{throw ClementineError("Toutes les pages attendues")}
  for file in files {
   let source=CGImageSourceCreateWithURL(file as CFURL,nil)!,properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as! [CFString:Any]
   let x=properties[kCGImagePropertyDPIWidth] as? Double ?? 0,y=properties[kCGImagePropertyDPIHeight] as? Double ?? 0
   guard abs(x-300)<0.1,abs(y-300)<0.1 else{throw ClementineError("DPI incorrect : \(x) × \(y)")}
  }
  checks.append(["name":"PDF → \(ext.uppercased()): three pages and 300 DPI metadata","passed":true])
 } catch {checks.append(["name":ext,"passed":false,"error":error.localizedDescription])}
}
try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
for check in checks {print(check)}
exit(checks.allSatisfy{$0["passed"] as? Bool == true} ? 0 : 1)

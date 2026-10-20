import AppKit
import PDFKit
import CoreText
import Foundation

func runLayoutChecks() throws {
 guard let rootPath=ProcessInfo.processInfo.environment["PDF_LAYOUT_ROOT"], !rootPath.isEmpty else {
  throw ClementineError("PDF_LAYOUT_ROOT manquant")
 }
 let root=URL(fileURLWithPath:rootPath),engine=Engine(),fm=FileManager.default
 if fm.fileExists(atPath:root.path) {try fm.removeItem(at:root)}
 try fm.createDirectory(at:root,withIntermediateDirectories:true)
 let pdf=root.appendingPathComponent("Native-layout.pdf")
 var bounds=CGRect(x:0,y:0,width:420,height:600)
 guard let c=CGContext(pdf as CFURL,mediaBox:&bounds,nil) else { throw ClementineError("Création du PDF de test impossible") }
 func text(_ value:String,x:CGFloat,y:CGFloat,font:NSFont,color:NSColor = .black) {
  c.textMatrix = .identity;c.textPosition=CGPoint(x:x,y:y)
  CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:[.font:font,.foregroundColor:color])),c)
 }
 for page in 0..<2 {
  c.beginPDFPage(nil);c.setFillColor(NSColor.white.cgColor);c.fill(bounds)
  c.setFillColor(NSColor.orange.cgColor);c.fill(CGRect(x:28,y:540,width:364,height:26))
  text("FACTURE CLÉMENTINE \(page+1)",x:36,y:548,font:NSFont(name:"Helvetica-Bold",size:15)!,color:.white)
  text("Joseph — Document original",x:32,y:510,font:NSFont(name:"Times-Roman",size:13)!)
  text("Référence 24681357",x:240,y:510,font:NSFont(name:"Helvetica",size:10)!,color:.darkGray)
  for line in 0..<5 {
   text("Colonne gauche ligne \(line+1)",x:32,y:470-CGFloat(line)*18,font:NSFont(name:"Helvetica",size:10)!)
   text("Colonne droite ligne \(line+1)",x:230,y:470-CGFloat(line)*18,font:NSFont(name:"Helvetica-Oblique",size:10)!)
  }
  c.setStrokeColor(NSColor.gray.cgColor);c.setLineWidth(0.7)
  for y:CGFloat in [280,306,332,358] {c.move(to:CGPoint(x:32,y:y));c.addLine(to:CGPoint(x:388,y:y));c.strokePath()}
  for x:CGFloat in [32,240,320,388] {c.move(to:CGPoint(x:x,y:280));c.addLine(to:CGPoint(x:x,y:358));c.strokePath()}
  text("Description",x:40,y:340,font:NSFont(name:"Helvetica-Bold",size:10)!)
  text("Montant",x:330,y:340,font:NSFont(name:"Helvetica-Bold",size:10)!)
  text("Prestation",x:40,y:314,font:NSFont(name:"Helvetica",size:10)!)
  text("123,45 €",x:330,y:314,font:NSFont(name:"Helvetica",size:10)!)
  c.setFillColor(NSColor.systemBlue.cgColor);c.fillEllipse(in:CGRect(x:40,y:170,width:70,height:70))
  text("Page \(page+1) / 2",x:180,y:30,font:NSFont(name:"Helvetica",size:9)!)
  c.endPDFPage()
 };c.closePDF()
 let original=try Data(contentsOf:pdf)
 let options=Options()
 let candidate=try Documents.office(pdf,to:root.appendingPathComponent("Positioned.docx"),engine:engine,options:options,nativePDFLayout:true)
 let back=try Documents.office(candidate,to:root.appendingPathComponent("Positioned.pdf"),engine:engine,options:options)
 var reflow=options;reflow.pdfOfficeLayout="editable"
 let baseline=try DocumentFidelity.pdf(pdf,to:root.appendingPathComponent("Reflow.docx"),options:reflow,engine:engine)
 let baselinePDF=try Documents.office(baseline,to:root.appendingPathComponent("Reflow.pdf"),engine:engine,options:options)
 let xml=try engine.process("/usr/bin/unzip",["-p",candidate.path,"word/document.xml"])
 guard let a=PDFDocument(url:pdf), let b=PDFDocument(url:back), let old=PDFDocument(url:baselinePDF) else {
  throw ClementineError("Réouverture d’un PDF de contrôle impossible")
 }
 func difference(_ converted:PDFDocument)throws->Double {
  guard a.pageCount == converted.pageCount else{return 255}
  var total=0.0
  for page in 0..<a.pageCount {
   guard let originalPage=a.page(at:page), let convertedPage=converted.page(at:page) else { return 255 }
   let first=try engine.renderPage(originalPage,scale:1),second=try engine.renderPage(convertedPage,scale:1)
   guard first.width==second.width,first.height==second.height else{return 255}
   func pixels(_ image:CGImage)->[UInt8] {
    var data=[UInt8](repeating:255,count:image.width*image.height*4)
    data.withUnsafeMutableBytes {buffer in
      guard let ctx=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
      ctx.setFillColor(NSColor.white.cgColor);ctx.fill(CGRect(x:0,y:0,width:image.width,height:image.height));ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    };return data
   }
   let p=pixels(first),q=pixels(second)
   total += zip(p,q).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(p.count)
   try? DocumentFidelity.png(second,to:root.appendingPathComponent("candidate-\(page+1).png"))
   try? DocumentFidelity.png(first,to:root.appendingPathComponent("original-\(page+1).png"))
  };return total/Double(a.pageCount)
 }
 let mae=try difference(b),prior=try difference(old)
 func ink(_ image:CGImage)->Int {
   var bytes=[UInt8](repeating:255,count:image.width*image.height*4)
   bytes.withUnsafeMutableBytes {buffer in let c=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))}
   return stride(from:0,to:bytes.count,by:4).filter{min(bytes[$0],bytes[$0+1],bytes[$0+2])<200}.count
 }
 let originalInk=ink(try engine.renderPage(a.page(at:0)!,scale:1)),convertedInk=ink(try engine.renderPage(b.page(at:0)!,scale:1))
 let checks:[String:Bool]=["visibleContentRetained":convertedInk>originalInk*8/10,"nativeTextEditable":xml.contains("24681357") && xml.contains("<w:t"),"pageCountPreserved":a.pageCount==b.pageCount,"textSurvivesReopen":b.string?.contains("24681357")==true,"stylesRetained":xml.contains("w:sz") && xml.contains("w:rFonts"),"originalUnchanged":try Data(contentsOf:pdf)==original,"improvesVisualFidelity":mae<prior,"lowVisualError":mae<10]
 let report:[String:Any]=["checks":checks,"passed":checks.values.filter{$0}.count,"total":checks.count,"meanPixelError":mae,"previousMeanPixelError":prior,"pageCount":b.pageCount]
 try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
 let passed=checks.values.filter{$0}.count
 guard passed == checks.count else { throw ClementineError("Fidélité PDF : \(passed)/\(checks.count) contrôles réussis") }
 print("PASS \(passed)/\(checks.count) contrôles de fidélité PDF")
}
if let root=Bundle.main.object(forInfoDictionaryKey:"PDFLayoutRoot") as? String {
 let app=NSApplication.shared;app.setActivationPolicy(.regular)
 let window=NSWindow(contentRect:CGRect(x:0,y:0,width:500,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 window.title="Clémentine — Fidélité PDF"
 let label=NSTextField(wrappingLabelWithString:"Comparaison des polices, positions et pages PDF…");label.frame=CGRect(x:20,y:45,width:460,height:95);window.contentView?.addSubview(label)
 let quit=NSButton(title:"Fermer le test",target:app,action:#selector(NSApplication.terminate(_:)));quit.frame=CGRect(x:340,y:10,width:140,height:30);window.contentView?.addSubview(quit)
 window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
 let source=Bundle.main.object(forInfoDictionaryKey:"ClementineSourceRoot") as! String
 setenv("PDF_LAYOUT_ROOT",root,1);setenv("CLEMENTINE_RESOURCES",source+"/Resources",1);setenv("CLEMENTINE_TOOLS",source+"/Resources/Tools",1);setenv("CLEMENTINE_OFFICE","/Applications/Clémentine.app/Contents/Helpers/LibreOffice.app/Contents/MacOS/soffice",1)
 DispatchQueue.global(qos:.userInitiated).async {
  do {try runLayoutChecks();DispatchQueue.main.async{label.stringValue="Comparaison terminée. Rapport disponible."}}
  catch {try? FileManager.default.createDirectory(atPath:root,withIntermediateDirectories:true);try? error.localizedDescription.write(toFile:root+"/failure.txt",atomically:true,encoding:.utf8);DispatchQueue.main.async{label.stringValue="Échec : \(error.localizedDescription)"}}
 };app.run()
} else {try runLayoutChecks()}

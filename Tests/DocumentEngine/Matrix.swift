import AppKit
import PDFKit
import Foundation

/// Exercises every directed catalogue edge; this is engine coverage, not a claim of pixel parity.
func runConversionMatrix(_ root:URL) {
 let e=Engine(),fm=FileManager.default
 var report:[[String:Any]]=[],sources:[String:URL]=[:]
 func need(_ ext:String)throws->URL {guard let file=sources[ext] else{throw ClementineError("Fixture absente: \(ext)")};return file}
 func seed(_ ext:String,_ body:()throws->URL) {do {sources[ext]=try body()} catch{print("FAIL Fixture \(ext): \(error.localizedDescription)");fflush(stdout)}}
 let affected=ProcessInfo.processInfo.environment["DOCUMENT_MATRIX_AFFECTED"] == "1"
 let inputs=root.appendingPathComponent("Matrix Sources"),outputs=root.appendingPathComponent(affected ? "Matrix Affected Exports" : "Matrix Exports")
 func convert(_ file:URL,_ target:String,_ folder:URL)throws->URL {var o=Options();o.outputFolder=folder.path;return try e.run([file],action:"convert:"+target,options:o)[0]}
 do {
  try fm.createDirectory(at:inputs,withIntermediateDirectories:true);try fm.createDirectory(at:outputs,withIntermediateDirectories:true)
  if affected {
   for file in try fm.contentsOfDirectory(at:inputs,includingPropertiesForKeys:nil) {sources[file.pathExtension.lowercased()]=file}
   for (ext,name) in [("pdf","Sources/Mixed.pdf"),("md","Sources/Structured.md"),("rtfd","Sources/Attached.rtfd")] {sources[ext]=root.appendingPathComponent(name)}
  } else {
  let image=try e.canvas(width:160,height:120){c in c.setFillColor(NSColor.orange.cgColor);c.fill(CGRect(x:0,y:0,width:160,height:120));c.setFillColor(NSColor.blue.cgColor);c.fillEllipse(in:CGRect(x:30,y:20,width:80,height:80))}
  let png=inputs.appendingPathComponent("Picture.png");try DocumentFidelity.png(image,to:png);sources["png"]=png
  for ext in ["jpg","webp","heic","tiff","avif","bmp"] {seed(ext){try convert(png,ext,inputs)}}
  let svg=inputs.appendingPathComponent("Drawing.svg");try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"160\" height=\"120\"><rect width=\"160\" height=\"120\" fill=\"orange\"/><circle cx=\"80\" cy=\"60\" r=\"40\" fill=\"blue\"/></svg>".write(to:svg,atomically:true,encoding:.utf8);sources["svg"]=svg
  let wav=inputs.appendingPathComponent("Sound.wav");try e.ff(["-f","lavfi","-i","sine=frequency=440:sample_rate=44100:duration=0.8",wav.path]);sources["wav"]=wav
  for ext in ["mp3","m4a","flac","ogg","opus","aiff","wma"] {seed(ext){try convert(wav,ext,inputs)}}
  let mp4=inputs.appendingPathComponent("Clip.mp4");try e.ff(["-loop","1","-i",png.path,"-i",wav.path,"-t","0.8","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac",mp4.path]);sources["mp4"]=mp4
  for ext in ["mov","mkv","webm","avi","wmv","gif"] {seed(ext){try convert(mp4,ext,inputs)}}
  for (ext,name) in [("pdf","Sources/Mixed.pdf"),("md","Sources/Structured.md"),("rtfd","Sources/Attached.rtfd")] {let u=root.appendingPathComponent(name);if fm.fileExists(atPath:u.path){sources[ext]=u}}
  let text=inputs.appendingPathComponent("Text.txt");try "Joseph — matrice de conversion\nFinovox 123,45 €\n".write(to:text,atomically:true,encoding:.utf8);sources["txt"]=text
  let rtf=inputs.appendingPathComponent("Text.rtf");try e.process("/usr/bin/textutil",["-convert","rtf","-output",rtf.path,text.path]);sources["rtf"]=rtf
  let clipping=inputs.appendingPathComponent("Text.textclipping");try Data().write(to:clipping)
  let value="Joseph — texte extrait".data(using:.utf16BigEndian)!
  func bytes(_ value:Int,_ count:Int)->Data {Data((0..<count).reversed().map{UInt8((value >> ($0*8))&255)})}
  let dataStart=256,mapStart=256+4+value.count
  var fork=bytes(dataStart,4)+bytes(mapStart,4)+bytes(value.count+4,4)+bytes(50,4)
  fork.append(Data(repeating:0,count:256-fork.count));fork.append(bytes(value.count,4));fork.append(value)
  let header=fork.prefix(16);fork.append(header);fork.append(Data(repeating:0,count:8));fork.append(bytes(28,2));fork.append(bytes(50,2))
  fork.append(bytes(0,2));fork.append("utxt".data(using:.ascii)!);fork.append(bytes(0,2));fork.append(bytes(10,2));fork.append(bytes(128,2));fork.append(bytes(65535,2));fork.append(Data(repeating:0,count:8))
  try fork.write(to:URL(fileURLWithPath:clipping.path+"/..namedfork/rsrc"));sources["textclipping"]=clipping
  seed("docx") {try convert(need("md"),"docx",inputs)}
  seed("epub") {try convert(need("docx"),"epub",inputs)}
  seed("pages") {try convert(need("docx"),"pages",inputs)}
  seed("pptx") {try convert(need("pdf"),"pptx",inputs)}
  seed("ppt") {try convert(need("pptx"),"ppt",inputs)}
  let csv=inputs.appendingPathComponent("Table.csv");try "Client,Total\nFinovox,123\nJoseph,456\n".write(to:csv,atomically:true,encoding:.utf8);sources["csv"]=csv
  for ext in ["xlsx","ods","tsv"] {seed(ext){try convert(csv,ext,inputs)}}
  seed("xls") {try convert(need("xlsx"),"xls",inputs)}
  let srt=inputs.appendingPathComponent("Captions.srt");try "1\n00:00:00,000 --> 00:00:00,600\nJoseph — conversion\n".write(to:srt,atomically:true,encoding:.utf8);sources["srt"]=srt;sources["vtt"]=try convert(srt,"vtt",inputs)
  for ext in ["zip","tar","gz","rar"] {seed(ext){try e.archive([text],stage:inputs,format:ext)}}
  }
 } catch {report.append(["name":"Fixture preparation","passed":false,"error":error.localizedDescription]);print("FAIL Matrix fixture preparation: \(error.localizedDescription)");fflush(stdout)}
 // The Numbers → CSV extension has its own native Numbers fixture and test suite.
 for source in Compatibility.conversions.keys.sorted() where source != "numbers" {
  for target in Compatibility.conversions[source] ?? [] {
   if affected && !(target == "html" || (source == "pdf" && target == "md")) {continue}
   let name=source+" → "+target
   autoreleasepool {
    do {
     guard let file=sources[source] else{throw ClementineError("Fixture \(source) absente")}
     let folder=outputs.appendingPathComponent(source+"-"+target);try fm.createDirectory(at:folder,withIntermediateDirectories:true)
     var o=Options();o.outputFolder=folder.path
     let files=try e.run([file],action:"convert:"+target,options:o)
     guard !files.isEmpty else{throw ClementineError("Aucune sortie")}
     for u in files {
      switch target {
      case "jpg","png","webp","heic","tiff","avif","bmp":let bitmap=try e.loadImage(u);guard bitmap.width>0,bitmap.height>0 else{throw ClementineError("Image vide")}
      case "mp4","mov","mkv","webm","avi","wmv","gif","mp3","m4a","wav","flac","ogg","opus","aiff","wma":guard try e.mediaDuration(u)>0.2 else{throw ClementineError("Durée perdue")}
      case "pdf":guard let doc=PDFDocument(url:u),doc.pageCount>0 else{throw ClementineError("PDF vide")}
      case "docx","pptx","xlsx","epub":let listing=try e.process("/usr/bin/unzip",["-t",u.path]);guard listing.contains("No errors detected") else{throw ClementineError("Paquet invalide")}
      case "pages":if e.bytes(u)==0 {guard (try fm.contentsOfDirectory(atPath:u.path)).count>0 else{throw ClementineError("Pages vide")}}
      case "zip","tar","gz":let dir=folder.appendingPathComponent("verification");try fm.createDirectory(at:dir,withIntermediateDirectories:true);let unpacked=try e.extract(u,stage:dir);guard !(try fm.contentsOfDirectory(atPath:unpacked.path)).isEmpty else{throw ClementineError("Archive vide")}
      case "html":var d:ObjCBool=false;fm.fileExists(atPath:u.path,isDirectory:&d);if affected && d.boolValue {throw ClementineError("HTML doit être autonome")};if !d.boolValue {guard e.bytes(u)>0 else{throw ClementineError("HTML vide")}}
      default:guard e.bytes(u)>0 else{throw ClementineError("Sortie vide")}
      }
     }
     report.append(["name":name,"passed":true]);print("PASS Matrix \(name)")
    } catch {report.append(["name":name,"passed":false,"error":error.localizedDescription]);print("FAIL Matrix \(name): \(error.localizedDescription)")}
    fflush(stdout)
   }
  }
 }
 let passed=report.filter{$0["passed"] as? Bool==true}.count
 let result:[String:Any]=["passed":passed,"total":report.count,"checks":report,"comparisonAgainstTangerineOutputs":false]
 try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(affected ? "matrix-affected-validation.json" : "matrix-validation.json"))
 print("PASS Matrix \(passed) / \(report.count)");fflush(stdout)
}

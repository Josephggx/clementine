import AppKit
import PDFKit
import Foundation
final class ModuleEngineCheck {
  var root:URL
  var files:[String:URL]=[:]
  init() {root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["MODULE_TEST_ROOT"]!)}
  func makeFixtures() throws {
    let e=Engine();var o=Options()
    let image=try e.canvas(width:640,height:480) {c in
      c.setFillColor(NSColor.systemTeal.cgColor);c.fill(CGRect(x:0,y:0,width:640,height:480))
      c.setFillColor(NSColor.systemOrange.cgColor);c.fillEllipse(in:CGRect(x:150,y:100,width:300,height:300))
      c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:10,y:10,width:80,height:80))
    }
    let png=root.appendingPathComponent("Module Test.png");try e.saveImage(image,to:png,o:o)
    let audio=root.appendingPathComponent("Module Test.wav")
    try e.ff(["-f","lavfi","-i","sine=frequency=440:sample_rate=48000:duration=3","-af","pan=stereo|c0=c0|c1=0.25*c0",audio.path])
    let video=root.appendingPathComponent("Module Test.mp4")
    try e.ff(["-loop","1","-i",png.path,"-i",audio.path,"-t","3","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac",video.path])
    let doc=PDFDocument();for _ in 0..<3 {doc.insert(PDFPage(image:NSImage(cgImage:image,size:.zero))!,at:doc.pageCount)}
    let pdf=root.appendingPathComponent("Module Test.pdf");doc.write(to:pdf)
    files=["image":png,"audio":audio,"video":video,"pdf":pdf]
    o.outputFolder=root.path
  }

  func run() {
      var rows:[[String:Any]]=[]
      func test(_ name:String,_ body:() throws -> Void) {
        do {try body();rows.append(["name":name,"passed":true])}
        catch {rows.append(["name":name,"passed":false,"error":error.localizedDescription])}
      }
      func require(_ condition:Bool) throws {if !condition {throw ClementineError("Assertion invalide")}}
      let e=Engine();let png=self.files["image"]!,audio=self.files["audio"]!,video=self.files["video"]!,pdf=self.files["pdf"]!
      let originals = [png,audio,video,pdf].map { try! Data(contentsOf:$0) }
      var o=Options();o.moduleEditor=true;o.outputFolder=self.root.appendingPathComponent("exports").path
      func run(_ files:[URL],_ action:String,_ options:Options) throws -> [URL] {try e.run(files,action:action,options:options)}
      test("Photo adjustments: all controls and output dimensions") {
        var settings=o;settings.photoAdjustments=["Exposure":0.2,"Brightness":10,"Contrast":10,"Highlights":10,"Shadows":10,"Whites":10,"Blacks":10,"Gamma":10,"Temperature":10,"Tint":10,"Saturation":10,"Vibrance":10,"Hue":10,"Clarity":10,"Texture":10,"Fade":10,"Blur":5,"Dehaze":10,"Sharpness":10,"Noise Reduction":10,"Grain":10,"Vignette":10]
        let output=try run([png],"adjust",settings)[0],image=try e.loadImage(output);try require(image.width==640 && image.height==480)
      }
      for control in ["Exposure","Brightness","Contrast","Highlights","Shadows","Whites","Blacks","Gamma","Temperature","Tint","Saturation","Vibrance","Hue","Clarity","Texture","Dehaze","Fade","Sharpness","Noise Reduction","Grain","Vignette","Blur"] {
        test("Photo control \(control)") {var settings=o;settings.photoAdjustments=[control:control == "Exposure" ? 0.2 : 10];_=try run([png],"adjust",settings)}
      }
      for kind in ["arrow","draw","text","rectangle","ellipse","highlight","number","magnifier","image"] {
        test("Annotation \(kind)") {
          var settings=o;settings.marks=[ModuleMark(kind:kind,text:kind == "image" ? png.path : "1",points:[ModulePoint(x:0.1,y:0.1),ModulePoint(x:0.4,y:0.3)])]
          _=try run([png],"annotate",settings)
        }
      }
      test("Solid and blurred multiple redactions") {
        var settings=o;settings.marks=[ModuleMark(),ModuleMark(x:0.5,y:0.5,blur:true)]
        let output=try run([png],"redact",settings)[0];try require(e.bytes(output)>0)
      }
      for ratio in ["Auto","1:1","16:9","4:5"] {
        test("Frame \(ratio), corners and shadow") {var settings=o;settings.canvasRatio=ratio;settings.padding=40;_=try run([png],"frame",settings)}
      }
      for style in ["Grid","Row","Column","Featured"] {
        test("Collage \(style)") {var settings=o;settings.collageStyle=style;settings.width=640;settings.height=480;settings.padding=8;let output=try run([png,png,png],"collage",settings)[0];let image=try e.loadImage(output);try require(image.width==640 && image.height==480)}
      }
      test("Metadata inspect/edit/remove uses copied file") {
        var settings=o;settings.metadataChanges=["XMP:Title":"Module test"];let edited=try run([png],"strip",settings)[0]
        let exif=Engine.exiftool!;let result=try e.process("/usr/bin/perl",[exif,"-s","-s","-s","-XMP:Title",edited.path]);try require(result.contains("Module test"))
        settings.metadataRemoveAll=true;settings.metadataChanges=[:];let stripped=try run([edited],"strip",settings)[0];let blank=try e.process("/usr/bin/perl",[exif,"-s","-s","-s","-XMP:Title",stripped.path]);try require(blank.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
      }
      test("PDF reorder / duplicate / rotate preserves page geometry") {
        var settings=o;settings.modulePages=[ModulePage(index:2,rotation:90),ModulePage(index:0),ModulePage(index:0)]
        let output=try run([pdf],"organize",settings)[0];let doc=PDFDocument(url:output)!;try require(doc.pageCount==3)
        try require(doc.page(at:0)!.rotation == 90 && doc.page(at:1)!.rotation == 0 && doc.page(at:2)!.rotation == 0)
        try require(doc.page(at:1)!.bounds(for:.mediaBox) == doc.page(at:2)!.bounds(for:.mediaBox))
      }
      test("Normalize loudness range and peak") {var settings=o;settings.volume = -18;settings.loudnessRange=8;settings.truePeak = -2;_=try run([audio],"normalize",settings)}
      for output in [1,2] {test("Audio channels \(output)") {var settings=o;settings.channels=output;settings.left=0.5;settings.right=0.2;_=try run([audio],"channels",settings)}}
      test("Multiple bleep intervals") {var settings=o;settings.marks=[ModuleMark(kind:"bleep",start:0.3,end:0.7),ModuleMark(kind:"bleep",start:1.5,end:2.2)];_=try run([audio],"bleep",settings)}
      test("Trim exact interval and silent ends") {var settings=o;settings.start=0.2;settings.duration=1.3;settings.trimSilence=true;let file=try run([audio],"trim",settings)[0];try require(abs(try e.mediaDuration(file)-1.3)<0.1)}
      test("Video speed preserves audio and duration") {var settings=o;settings.speed=2;let output=try run([video],"speed",settings)[0];try require(abs(try e.mediaDuration(output)-1.5)<0.2)}
      test("Timed solid and blur video redactions") {var settings=o;settings.marks=[ModuleMark(start:0.2,end:1),ModuleMark(x:0.5,y:0.4,blur:true,start:1,end:2.5)];_=try run([video],"redact",settings)}
      for shape in ["Landscape · 16:9","Portrait · 9:16","Square · 1:1"] {test("Audio visualization \(shape)") {var settings=o;settings.visualizerShape=shape;_=try run([audio],"visualize",settings)}}
      test("Still image audio visualizer") {var settings=o;settings.visualizerStyle="Still Image";settings.backgroundImage=png.path;_=try run([audio],"visualize",settings)}
      test("Join uses the first clip canvas") {let output=try run([video,video],"join",o)[0];let info=try e.probe(output),streams=info["streams"] as! [[String:Any]];try require(streams.first {$0["codec_type"] as? String == "video"}?["width"] as? Int == 640)}
      test("Audio batch joins two files") {let output=try run([audio,audio],"join",o)[0];try require(abs(try e.mediaDuration(output)-6)<0.2)}
      test("PDF batch accepts a PDF and an image") {let output=try run([pdf,png],"mergepdf",o)[0];try require(PDFDocument(url:output)?.pageCount==4)}
      test("Mixed files create one archive") {var settings=o;settings.archiveFormat="zip";let output=try run([pdf,png],"archive",settings)[0];try require(output.pathExtension=="zip" && e.bytes(output)>0)}
      test("One file creates a ZIP") {var settings=o;settings.archiveFormat="zip";let output=try run([png],"archive",settings)[0];try require(output.pathExtension=="zip" && e.bytes(output)>0)}
      test("Video split folders and removed clips") {var settings=o;settings.times="1,2";settings.splitRemoved=[1];let output=try run([video],"split",settings)[0];let clips=try FileManager.default.contentsOfDirectory(at:output,includingPropertiesForKeys:nil);try require(clips.count==2)}
      test("Video split merged export") {var settings=o;settings.times="1,2";settings.splitRemoved=[1];settings.splitExportMode="Merged";let output=try run([video],"split",settings)[0];try require(abs(try e.mediaDuration(output)-2)<0.2)}
      test("Invalid module coordinates rejected") {var settings=o;settings.marks=[ModuleMark(x:Double.nan)];do {_=try run([png],"redact",settings);throw ClementineError("Invalid values accepted")} catch let error as ClementineError {try require(error.message != "Invalid values accepted")}}
      test("Image target compression keeps the input format") {var settings=o;settings.targetMB=0.01;let output=try run([png],"target",settings)[0];try require(output.pathExtension=="png");try require(e.bytes(output)<=10000)}
      test("Per-file batch crop selections") {
        let other=self.root.appendingPathComponent("Other.png");try FileManager.default.copyItem(at:png,to:other)
        defer {try? FileManager.default.removeItem(at:other)}
        var settings=o;settings.moduleCrops=[png.path:ModuleCrop(x:10,y:10,width:200,height:150),other.path:ModuleCrop(x:0,y:0,width:100,height:300)]
        let outputs=try run([png,other],"crop",settings);let a=try e.loadImage(outputs[0]),b=try e.loadImage(outputs[1]);try require(a.width==200 && a.height==150 && b.width==100 && b.height==300)
      }
      test("Portrait video metadata uses upright dimensions") {
        let rotated=self.root.appendingPathComponent("Rotated.mp4")
        // FFmpeg 9 writes display rotation through the input display matrix option.
        // This matches the metadata produced by current phones and cameras.
        try e.ff(["-display_rotation","90","-i",video.path,"-c","copy",rotated.path])
        let size=Engine.videoDisplaySize(try e.probe(rotated));try require(size.width==480 && size.height==640)
        var settings=o;settings.width=300;settings.height=400
        let output=try run([rotated],"crop",settings)[0];let actual=Engine.videoDisplaySize(try e.probe(output));try require(actual.width==300 && actual.height==400)
      }
      for background in ModuleBackgrounds.names {
        test("Background preset \(background)") {var settings=o;settings.background=background;settings.padding=40;_=try run([png],"frame",settings)}
      }
      test("PDF metadata removal rewrites the document") {
        let marked=self.root.appendingPathComponent("Marked.pdf"),document=PDFDocument(url:pdf)!
        document.documentAttributes=[PDFDocumentAttribute.titleAttribute:"Secret module title",PDFDocumentAttribute.authorAttribute:"Module author"]
        try require(document.write(to:marked));var settings=o;settings.metadataRemoveAll=true
        let output=try run([marked],"strip",settings)[0],data=try Data(contentsOf:output)
        try require(PDFDocument(url:output)?.pageCount==3)
        try require(!String(decoding:data,as:UTF8.self).contains("Secret module title"))
      }
      test("Photo preview keeps the full export separate") {
        let large=try e.canvas(width:2400,height:1600) {$0.setFillColor(NSColor.systemTeal.cgColor);$0.fill(CGRect(x:0,y:0,width:2400,height:1600))}
        var settings=o;settings.photoAdjustments=["Exposure":0.2]
        let preview=try e.moduleImage(large,action:"adjust",options:settings,preview:true),full=try e.moduleImage(large,action:"adjust",options:settings)
        try require(preview.width==1200 && preview.height==800 && full.width==2400 && full.height==1600)
      }
      test("Input file untouched") {for (index,url) in [png,audio,video,pdf].enumerated() {try require(try Data(contentsOf:url)==originals[index])}}
      let report:[String:Any]=["tests":rows,"passed":rows.filter {$0["passed"] as? Bool == true}.count,"total":rows.count]
      try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:self.root.appendingPathComponent("validation.json"))

    print("PASS \(report["passed"]!) / \(rows.count) module export checks")
    for row in rows where row["passed"] as? Bool == false { print(row) }
    exit(rows.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
  }
}
let check=ModuleEngineCheck()
try FileManager.default.createDirectory(at:check.root,withIntermediateDirectories:true)
try check.makeFixtures()
check.run()

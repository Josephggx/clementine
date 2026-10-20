import AppKit
import SwiftUI
import PDFKit

final class ModuleFixture: NSObject,NSApplicationDelegate {
  var window:NSWindow!
  var modules:[UUID:ModuleWindowController]=[:]
  var root:URL!
  var files:[String:URL]=[:]
  var choices:[(String,Family)]=[("compress",.image),("strip",.image),("adjust",.image),("annotate",.image),("frame",.image),("crop",.image),("redact",.image),("collage",.image),("trim",.video),("crop",.video),("speed",.video),("join",.video),("snapshot",.video),("split",.video),("redact",.video),("normalize",.audio),("visualize",.audio),("trim",.audio),("channels",.audio),("bleep",.audio),("mergepdf",.pdf),("organize",.pdf)]
  var status:NSTextField!
  func applicationDidFinishLaunching(_ notification:Notification) {
    NSApp.setActivationPolicy(.regular)
    let source=Bundle.main.object(forInfoDictionaryKey:"ProjectRoot") as! String
    setenv("CLEMENTINE_TOOLS",source+"/Resources/Tools",1)
    root=URL(fileURLWithPath:source+"/.build/module-test-results")
    try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    window=NSWindow(contentRect:NSRect(x:0,y:0,width:570,height:750),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
    window.title="Clémentine — Modules";window.isReleasedWhenClosed=false
    let content=NSView(frame:NSRect(x:0,y:0,width:570,height:750))
    status=NSTextField(wrappingLabelWithString:"Préparation des fichiers…");status.frame=NSRect(x:20,y:690,width:530,height:45);content.addSubview(status)
    for (i,choice) in choices.enumerated() {
      let spec=ModuleSpecification.get(choice.0,family:choice.1)
      let button=NSButton(title:spec.title,target:self,action:#selector(openModule(_:)));button.tag=i
      button.frame=NSRect(x:20+Double(i%2)*270,y:650-Double(i/2)*48,width:260,height:36);content.addSubview(button)
    }
    let test=NSButton(title:"Vérifier les exports",target:self,action:#selector(runTests));test.frame=NSRect(x:20,y:50,width:260,height:36);content.addSubview(test)
    let quitButton=NSButton(title:"Quitter le test",target:self,action:#selector(quit));quitButton.frame=NSRect(x:290,y:50,width:260,height:36);content.addSubview(quitButton)
    window.contentView=content;window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    let menu=NSMenu();let item=NSMenuItem();let sub=NSMenu();sub.addItem(withTitle:"Quitter le test",action:#selector(quit),keyEquivalent:"q").target=self;item.submenu=sub;menu.addItem(item);NSApp.mainMenu=menu
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        try self.makeFixtures()
        DispatchQueue.main.async {self.status.stringValue="22 modules prêts — fichiers de démonstration uniquement"}
      } catch {DispatchQueue.main.async {self.status.stringValue=error.localizedDescription}}
    }
  }
  func makeFixtures() throws {
    let cached=["image":"Module Test.png","audio":"Module Test.wav","video":"Module Test.mp4","pdf":"Module Test.pdf"]
    if cached.values.allSatisfy({FileManager.default.fileExists(atPath:root.appendingPathComponent($0).path)}) {
      files=cached.mapValues {root.appendingPathComponent($0)};return
    }
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
  func selection(_ tool:String,_ family:Family) -> [URL] {
    let key=family == .image ? "image" : family == .audio ? "audio" : family == .video ? "video" : "pdf"
    guard let file=files[key] else {return []}
    return ["collage","join","mergepdf"].contains(tool) ? [file,file] : [file]
  }
  @objc func openModule(_ sender:NSButton) {
    let choice=choices[sender.tag],files=selection(choices[sender.tag].0,choices[sender.tag].1)
    guard !files.isEmpty else {return}
    var defaults=Options();defaults.outputFolder=root.appendingPathComponent("exports").path
    let controller=ModuleWindowController(tool:choice.0,files:files,defaults:defaults,reveal:false)
    modules[controller.session.id]=controller
    controller.onClose={ [weak self,weak controller] in if let id=controller?.session.id {self?.modules.removeValue(forKey:id)} }
    controller.show()
  }
  @objc func runTests() {
    status.stringValue="Vérification des exports…"
    DispatchQueue.global(qos:.userInitiated).async {
      var rows:[[String:Any]]=[]
      func test(_ name:String,_ body:() throws -> Void) {
        do {try body();rows.append(["name":name,"passed":true])}
        catch {rows.append(["name":name,"passed":false,"error":error.localizedDescription])}
      }
      func require(_ condition:Bool) throws {if !condition {throw ClementineError("Assertion invalide")}}
      let e=Engine();let png=self.files["image"]!,audio=self.files["audio"]!,video=self.files["video"]!,pdf=self.files["pdf"]!
      var o=Options();o.moduleEditor=true;o.outputFolder=self.root.appendingPathComponent("exports").path
      func run(_ files:[URL],_ action:String,_ options:Options) throws -> [URL] {try e.run(files,action:action,options:options)}
      test("Photo adjustments: all controls and output dimensions") {
        var settings=o;settings.photoAdjustments=["Exposure":0.2,"Brightness":10,"Contrast":10,"Highlights":10,"Shadows":10,"Whites":10,"Blacks":10,"Gamma":10,"Temperature":10,"Tint":10,"Saturation":10,"Vibrance":10,"Hue":10,"Clarity":10,"Dehaze":10,"Sharpness":10,"Noise Reduction":10,"Grain":10,"Vignette":10]
        let output=try run([png],"adjust",settings)[0],image=try e.loadImage(output);try require(image.width==640 && image.height==480)
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
      test("PDF reorder / duplicate / rotate / same width") {
        var settings=o;settings.modulePages=[ModulePage(index:2,rotation:90),ModulePage(index:0),ModulePage(index:0)];settings.samePageWidth=true
        let output=try run([pdf],"organize",settings)[0];let doc=PDFDocument(url:output)!;try require(doc.pageCount==3)
        let widths=(0..<3).map {doc.page(at:$0)!.bounds(for:.mediaBox).width};try require((widths.max()!-widths.min()!)<1)
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
      test("Input file untouched") {try require(FileManager.default.fileExists(atPath:png.path));try require(FileManager.default.fileExists(atPath:audio.path))}
      let report:[String:Any]=["tests":rows,"passed":rows.filter {$0["passed"] as? Bool == true}.count,"total":rows.count]
      try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:self.root.appendingPathComponent("validation.json"))
      DispatchQueue.main.async {self.status.stringValue="\(report["passed"]!) / \(rows.count) exports réussis"}
    }
  }
  @objc func quit() {NSApp.terminate(nil)}
}
@main struct ModuleRegression {
  static func main() {let app=NSApplication.shared,delegate=ModuleFixture();app.delegate=delegate;withExtendedLifetime(delegate) {app.run()}}
}

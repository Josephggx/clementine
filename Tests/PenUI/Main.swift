import AppKit
import SwiftUI
import Combine

final class PenFixture:NSObject,NSApplicationDelegate {
  var controller:ModuleWindowController!
  var subscription:AnyCancellable?
  var root:URL!
  var results:[[String:Any]]=[]
  func applicationDidFinishLaunching(_ note:Notification) {
    NSApp.setActivationPolicy(.regular)
    root=URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"PenTestRoot") as! String)
    try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let engine=Engine(),file=root.appendingPathComponent("Stylo-demo.png")
    let image=try! engine.canvas(width:800,height:600){c in c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:800,height:600))}
    try! DocumentFidelity.png(image,to:file)
    var options=Options();options.outputFolder=root.path
    controller=ModuleWindowController(tool:"annotate",files:[file],defaults:options,reveal:false)
    let menu=NSMenu(),item=NSMenuItem(),sub=NSMenu()
    sub.addItem(withTitle:"Quitter le test",action:#selector(quit),keyEquivalent:"q").target=self;item.submenu=sub;menu.addItem(item);NSApp.mainMenu=menu
    controller.show();NSApp.activate(ignoringOtherApps:true)
    subscription=controller.session.$loading.filter{!$0}.first().sink{[weak self] _ in DispatchQueue.main.async{self?.checks()}}
  }
  func check(_ value:Bool,_ name:String) {results.append(["name":name,"passed":value])}
  func checks() {
    let session=controller.session,engine=Engine()
    let canvas=ModuleCanvasView(frame:CGRect(x:0,y:0,width:400,height:300));canvas.session=session
    let testWindow=NSWindow(contentRect:canvas.frame,styleMask:.borderless,backing:.buffered,defer:false);testWindow.contentView=canvas
    var serial=0
    func event(_ kind:NSEvent.EventType,_ point:CGPoint)->NSEvent {
      serial += 1
      return NSEvent.mouseEvent(with:kind,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:testWindow.windowNumber,context:nil,eventNumber:serial,clickCount:1,pressure:0.5)!
    }
    func stroke(_ points:[CGPoint]) {
      canvas.mouseDown(with:event(.leftMouseDown,points[0]))
      for p in points.dropFirst(){canvas.mouseDragged(with:event(.leftMouseDragged,p))}
      canvas.mouseUp(with:event(.leftMouseUp,points.last!))
    }
    session.options.marks=[];session.undoStack=[];session.drawingTool="draw"
    let rectangle=ModuleMark(kind:"rectangle",x:0.1,y:0.1,width:0.8,height:0.8,color:"#999999")
    session.options.marks=[rectangle];session.selectedMark=rectangle.id
    check(!canvas.showsSelection,"Pen mode hides the selected rectangle and resize handles")
    let first=[CGPoint(x:80,y:100),CGPoint(x:100,y:70),CGPoint(x:140,y:120),CGPoint(x:170,y:70),CGPoint(x:200,y:100)]
    stroke(first)
    check(session.options.marks.count==2,"Drawing inside a rectangle creates a stroke instead of moving it")
    check(session.options.marks[0].x==rectangle.x && session.options.marks[0].width==rectangle.width,"Existing annotation stays unchanged")
    check(session.selectedMark==nil,"Finished stroke has no bounding box selection")
    let previous=session.options.marks.last!
    check(previous.points.count>=first.count,"Freehand keeps the sampled pointer path")
    check(session.undoStack.count==1,"One undo step per stroke")
    stroke([CGPoint(x:120,y:90),CGPoint(x:140,y:60),CGPoint(x:160,y:130)])
    check(session.options.marks.count==3,"Crossing an existing stroke starts an independent stroke")
    check(session.options.marks[1].points.count==previous.points.count,"Crossing does not reshape the previous stroke")
    session.undo()
    check(session.options.marks.count==2,"Undo removes the entire last stroke")
    stroke([CGPoint(x:399,y:299),CGPoint(x:440,y:330)])
    do {try engine.validateModuleOptions(session.options);check(true,"Edge-clamped strokes remain valid for export")}catch{check(false,"Edge-clamped strokes remain valid for export")}
    let edge=session.options.marks.last!
    check(edge.x+edge.width<=1 && edge.y+edge.height<=1,"Stroke bounds do not extend beyond the image")
    stroke([CGPoint(x:280,y:190)])
    let dot=session.options.marks.last!
    check(dot.points.count==1,"Click without dragging creates a one-point stroke")
    var dotOptions=session.options;dotOptions.marks=[dot]
    do {
      let result=try engine.moduleImage(session.sourceImage!,action:"annotate",options:dotOptions,preview:false)
      let base=session.sourceImage!
      func bytes(_ image:CGImage)->[UInt8] {
        var data=[UInt8](repeating:0,count:image.width*image.height*4)
        data.withUnsafeMutableBytes {b in let c=CGContext(data:b.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))};return data
      }
      check(bytes(result) != bytes(base),"A single pen click produces a visible exported dot")
      try DocumentFidelity.png(result,to:root.appendingPathComponent("dot-export.png"))
    }catch{check(false,"A single pen click produces a visible exported dot")}
    session.drawingTool="highlight";session.selectedMark=previous.id
    check(!canvas.showsSelection,"Highlighter also remains freehand without resize handles")
    stroke([CGPoint(x:80,y:230),CGPoint(x:170,y:210),CGPoint(x:240,y:240)])
    check(session.options.marks.last?.kind=="highlight" && session.selectedMark==nil,"Highlighter adds an independent deselected stroke")
    session.drawingTool="select"
    check(canvas.showsSelection,"Explicit Select mode enables editing frames")
    session.options.marks=[];session.undoStack=[]
    stroke([CGPoint(x:80,y:60)])
    check(session.options.marks.isEmpty && session.undoStack.isEmpty,"Clicking empty space in Select mode does not draw or add undo history")
    session.drawingTool="draw";session.strokeWidth=9
    stroke(first)
    check(session.options.marks.last?.size==9,"New strokes use the chosen pen width")
    stroke([CGPoint(x:220,y:80),CGPoint(x:230,y:60),CGPoint(x:250,y:120),CGPoint(x:270,y:70),CGPoint(x:300,y:100)])
    session.renderPreview()
    let failures=results.filter{$0["passed"] as? Bool != true}.count
    try! JSONSerialization.data(withJSONObject:["passed":results.count-failures,"total":results.count,"checks":results],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
    withExtendedLifetime(testWindow){}
  }
  @objc func quit() {controller.window.close();NSApp.terminate(nil)}
}
@main struct PenCheck {
 static func main() {let app=NSApplication.shared,delegate=PenFixture();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}

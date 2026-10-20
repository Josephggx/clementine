import AppKit
import PDFKit
import CoreText

final class FloatFixture:NSObject,NSApplicationDelegate {
  var controller:FloatController!
  let state=AppState()
  var root:URL!
  var files:[URL]=[]
  var rows:[[String:Any]]=[]
  func applicationDidFinishLaunching(_ note:Notification) {
    NSApp.setActivationPolicy(.regular)
    root=URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"FloatTestRoot") as! String)
    try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    for n in 1...3 {
      let url=root.appendingPathComponent("Document de démonstration \(n).pdf")
      var box=CGRect(x:0,y:0,width:420,height:600)
      let c=CGContext(url as CFURL,mediaBox:&box,nil)!
      c.beginPDFPage(nil);c.setFillColor(NSColor.white.cgColor);c.fill(box)
      for line in 0..<25 {
        c.textMatrix = .identity;c.textPosition=CGPoint(x:40,y:550-CGFloat(line)*18)
        let text=line == 0 ? "CLÉMENTINE — DOCUMENT DE DÉMONSTRATION" : "Texte de démonstration pour vérifier la miniature du Float."
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:line == 0 ? 11 : 9),.foregroundColor:NSColor.darkGray])),c)
      }
      c.endPDFPage();c.closePDF();files.append(url)
    }
    let menu=NSMenu(),item=NSMenuItem(),sub=NSMenu()
    for (title,selector,key) in [("Déployer",#selector(expand),"e"),("Replier",#selector(collapse),"r"),("Un fichier",#selector(single),"1"),("Plusieurs fichiers",#selector(multiple),"3"),("Noter la position",#selector(capturePosition),"p"),("Vérifier",#selector(checks),"t"),("Quitter le test",#selector(quit),"q")] {
      sub.addItem(withTitle:title,action:selector,keyEquivalent:key).target=self
    }
    item.submenu=sub;menu.addItem(item);NSApp.mainMenu=menu
    checks();single();controller.show();NSApp.activate(ignoringOtherApps:true)
  }
  func require(_ value:Bool,_ name:String) {rows.append(["name":name,"passed":value])}
  @objc func checks() {
    rows=[]
    for count in [1,2,3,4,8,20,100] {
      require(FloatLayout.size(count:count,expanded:false)==CGSize(width:100,height:115),"Compact size stays 100 × 115 for \(count) files")
      let size=FloatLayout.size(count:count,expanded:true)
      require(size.width<=288 && size.height<=451,"Expanded shelf remains bounded for \(count) files")
      let screen=CGRect(x:-1200,y:-500,width:1200,height:900)
      let frame=FloatLayout.frame(size:size,anchoredTo:CGRect(x:-50,y:200,width:100,height:115),in:screen)
      require(screen.contains(frame),"Shelf stays on an external screen with negative coordinates, count \(count)")
    }
    require(FloatLayout.size(count:1,expanded:true)==CGSize(width:112,height:267),"Single-file expanded reference size 112 × 267")
    var move=FloatMoveTracker()
    let bounds=CGRect(x:-1200,y:-500,width:1200,height:900)
    move.begin(pointer:CGPoint(x:-900,y:100),origin:CGPoint(x:-950,y:50))
    require(move.update(pointer:CGPoint(x:-898,y:101),size:FloatLayout.compact,in:bounds)==nil,"Small pointer motion remains a click")
    require(move.update(pointer:CGPoint(x:-860,y:125),size:FloatLayout.compact,in:bounds)==CGPoint(x:-910,y:75),"Dragging the thumbnail moves the island with the pointer")
    require(move.end(),"A completed move does not expand the island on mouse-up")
    move.begin(pointer:CGPoint(x:-900,y:100),origin:CGPoint(x:-950,y:50))
    require(!move.end(),"A click remains available to expand the island")
    move.begin(pointer:CGPoint(x:-900,y:100),origin:CGPoint(x:-950,y:50))
    require(move.update(pointer:CGPoint(x:200,y:800),size:FloatLayout.compact,in:bounds)==CGPoint(x:-100,y:285),"Dragging stays inside an external display")
    _ = move.end()
    require(FloatLayout.pinnedOrigin(CGPoint(x:-1185,y:40),size:FloatLayout.compact,in:bounds)==CGPoint(x:-1200,y:40),"Releasing near the left edge pins the island")
    require(FloatLayout.pinnedOrigin(CGPoint(x:-115,y:40),size:FloatLayout.compact,in:bounds)==CGPoint(x:-100,y:40),"Releasing near the right edge pins the island")
    require(FloatLayout.pinnedOrigin(CGPoint(x:-650,y:40),size:FloatLayout.compact,in:bounds)==CGPoint(x:-650,y:40),"Releasing away from an edge keeps free placement")
    let rightPinned=CGRect(x:-100,y:40,width:100,height:115)
    require(FloatLayout.frame(size:CGSize(width:288,height:267),anchoredTo:rightPinned,in:bounds).maxX==bounds.maxX,"Expanding a pinned island keeps it on the right edge")
    let model=FloatModel([files[0],files[0]])
    require(model.files.count == 1,"Duplicate URL appears once")
    model.add([files[1]]);model.select(files[0],modifiers:[]);model.select(files[1],modifiers:.command)
    require(model.carried(files[0])==Array(files.prefix(2)),"Selected files are carried in shelf order")
    model.remove([files[0]])
    require(!model.selected.contains(files[0]) && FileManager.default.fileExists(atPath:files[0].path),"Removing a file clears selection without deleting the original")
    let panel=FloatController(files:[files[0]],state:state)
    require(!panel.panel.styleMask.contains(.titled) && !panel.panel.isOpaque && panel.panel.backgroundColor == .clear,"Island has no titlebar or opaque window background")
    require(!panel.panel.hasShadow && panel.panel.level == .floating,"Floating level, no rectangular system window shadow")
    require(panel.panel.frame.size==FloatLayout.compact,"Native panel starts at compact dimensions")
    panel.model.expanded=true;panel.resize()
    require(panel.panel.frame.size==FloatLayout.size(count:1,expanded:true),"Native panel expands to reference dimensions")
    panel.model.expanded=false;panel.resize()
    require(panel.panel.frame.size==FloatLayout.compact,"Native panel collapses to compact dimensions")
    try! JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("validation.json"))
  }
  @objc func single() {
    controller?.panel.close();controller=FloatController(files:[files[0]],state:state);controller.show()
  }
  @objc func capturePosition() {
    let frame=controller.panel.frame
    let report:[String:Double]=["x":Double(frame.minX),"y":Double(frame.minY),"width":Double(frame.width),"height":Double(frame.height)]
    try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
      .write(to:root.appendingPathComponent("position.json"))
  }
  @objc func multiple() {controller.add(Array(files.dropFirst()));controller.model.expanded=true;controller.resize()}
  @objc func expand() {controller.model.expanded=true;controller.resize()}
  @objc func collapse() {controller.model.expanded=false;controller.resize()}
  @objc func quit() {controller.panel.close();NSApp.terminate(nil)}
}
@main struct FloatCheck {
  static func main() {
    let app=NSApplication.shared,delegate=FloatFixture();app.delegate=delegate
    withExtendedLifetime(delegate){app.run()}
  }
}

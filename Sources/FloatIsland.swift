import AppKit
import SwiftUI
import PDFKit
import QuickLookThumbnailing

/// Transparent, borderless file island. Opening its shelf keeps the thumbnail's top anchor.
final class FloatPanel:NSPanel {
  override var canBecomeKey:Bool {true}
  override var canBecomeMain:Bool {false}
}
final class FloatController:NSObject,NSWindowDelegate {
  let panel:FloatPanel
  let model:FloatModel
  private let state:AppState
  var onClose:(()->Void)?
  init(files:[URL],state:AppState) {
    self.state=state;model=FloatModel(files)
    panel=FloatPanel(contentRect:CGRect(origin:.zero,size:FloatLayout.compact),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    super.init()
    panel.isMovableByWindowBackground=true
    panel.title="Float";panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=false
    panel.level = .floating;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
    panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.delegate=self
    panel.contentView=NSHostingView(rootView:FloatView(state:state,model:model,onResize:{[weak self] in self?.resize()},onClose:{[weak self] in self?.panel.close()}))
    let screen=NSScreen.screens.first{$0.frame.contains(NSEvent.mouseLocation)} ?? NSScreen.main!
    let point=NSEvent.mouseLocation
    let anchor=CGRect(x:point.x+18,y:point.y-FloatLayout.compact.height/2,width:100,height:115)
    panel.setFrame(FloatLayout.frame(size:FloatLayout.compact,anchoredTo:anchor,in:screen.visibleFrame),display:true)
  }
  func show() {panel.orderFrontRegardless()}
  func add(_ files:[URL]) {model.add(files);resize();show()}
  func resize() {
    guard !model.files.isEmpty else{panel.close();return}
    let area=panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let next=FloatLayout.frame(size:FloatLayout.size(count:model.files.count,expanded:model.expanded),anchoredTo:panel.frame,in:area)
    panel.setFrame(next,display:true)
  }
  func windowWillClose(_ notification:Notification) {onClose?()}
}
final class FloatModel:ObservableObject {
  @Published private(set) var files:[URL]=[]
  @Published var expanded=false
  @Published var hovering=false
  @Published var dropping=false
  @Published var selected=Set<URL>()
  @Published var thumbnails:[URL:NSImage]=[:]
  private var requests:[URL:QLThumbnailGenerator.Request]=[:]
  init(_ urls:[URL]) {add(urls)}
  func add(_ urls:[URL]) {
    for url in urls where url.isFileURL && !files.contains(url) {
      files.append(url);thumbnails[url]=NSWorkspace.shared.icon(forFile:url.path)
      let request=QLThumbnailGenerator.Request(fileAt:url,size:CGSize(width:180,height:220),scale:2,representationTypes:.all)
      requests[url]=request
      QLThumbnailGenerator.shared.generateBestRepresentation(for:request) {[weak self] representation,_ in
        DispatchQueue.main.async {
          guard let self,self.files.contains(url) else{return}
          if let representation {self.thumbnails[url]=representation.nsImage}
          self.requests.removeValue(forKey:url)
        }
      }
    }
  }
  func remove(_ urls:[URL]) {
    let removed=Set(urls);files.removeAll{removed.contains($0)};selected.subtract(removed)
    for url in urls {if let request=requests.removeValue(forKey:url){QLThumbnailGenerator.shared.cancel(request)};thumbnails.removeValue(forKey:url)}
  }
  func select(_ url:URL,modifiers:NSEvent.ModifierFlags) {
    if modifiers.contains(.command) {if selected.contains(url){selected.remove(url)}else{selected.insert(url)}}
    else if modifiers.contains(.shift),let first=files.firstIndex(where:{selected.contains($0)}),let last=files.firstIndex(of:url) {selected.formUnion(files[min(first,last)...max(first,last)])}
    else {selected=[url]}
  }
  func carried(_ url:URL?) -> [URL] {
    guard let url else{return files}
    return selected.contains(url) ? files.filter{selected.contains($0)} : [url]
  }
  deinit {for request in requests.values {QLThumbnailGenerator.shared.cancel(request)}}
}

/// Original vector paperclip: layered metal highlights, independent of Tangerine's assets.
struct FloatPaperclip:View {
  let expanded:Bool
  var body:some View {
    Canvas {context,size in
      context.translateBy(x:size.width/2+(expanded ? 24 : -7),y:expanded ? 54 : 46)
      context.rotate(by:.degrees(expanded ? -18 : 26))
      context.scaleBy(x:0.86,y:0.92)
      context.translateBy(x:-16,y:-42)
      var wire=Path()
      wire.move(to:CGPoint(x:9,y:28));wire.addLine(to:CGPoint(x:9,y:67))
      wire.addCurve(to:CGPoint(x:24,y:67),control1:CGPoint(x:9,y:78),control2:CGPoint(x:24,y:78))
      wire.addLine(to:CGPoint(x:24,y:12))
      wire.addCurve(to:CGPoint(x:0,y:12),control1:CGPoint(x:24,y:-5),control2:CGPoint(x:0,y:-5))
      wire.addLine(to:CGPoint(x:0,y:69))
      wire.addCurve(to:CGPoint(x:32,y:69),control1:CGPoint(x:0,y:91),control2:CGPoint(x:32,y:91))
      wire.addLine(to:CGPoint(x:32,y:18))
      var shadow=context;shadow.addFilter(.shadow(color:.black.opacity(0.23),radius:0.9,x:0.6,y:1))
      shadow.stroke(wire,with:.color(.black.opacity(0.48)),style:StrokeStyle(lineWidth:2.4,lineCap:.round,lineJoin:.round))
      context.stroke(wire,with:.linearGradient(Gradient(colors:[.white,Color(white:0.46),.white,Color(white:0.60)]),startPoint:CGPoint(x:0,y:0),endPoint:CGPoint(x:32,y:0)),style:StrokeStyle(lineWidth:1.65,lineCap:.round,lineJoin:.round))
      var highlight=context;highlight.translateBy(x:-0.32,y:0)
      highlight.stroke(wire,with:.color(.white.opacity(0.82)),style:StrokeStyle(lineWidth:0.5,lineCap:.round,lineJoin:.round))
    }.allowsHitTesting(false)
  }
}
struct FloatGlass:View {
  @Environment(\.colorScheme) private var colorScheme
  var body:some View {
    let shape=RoundedRectangle(cornerRadius:32,style:.continuous)
    let dark = colorScheme == .dark
    if #available(macOS 26.0,*) {
      shape
        .fill(dark ? Color(red:0.10,green:0.095,blue:0.085).opacity(0.82) : .white.opacity(0.72))
        .glassEffect(.clear,in:shape)
        .overlay(shape.strokeBorder(.white.opacity(dark ? 0.14 : 0.34),lineWidth:0.5))
    } else {
      shape
        .fill(.ultraThinMaterial)
        .overlay(shape.fill(dark ? Color.black.opacity(0.24) : Color.white.opacity(0.10)))
        .overlay(shape.strokeBorder(.white.opacity(dark ? 0.13 : 0.42),lineWidth:0.5))
    }
  }
}
struct FloatView:View {
  @ObservedObject private var language = AppLanguage.shared
  @ObservedObject var state:AppState
  @ObservedObject var model:FloatModel
  let onResize:()->Void
  let onClose:()->Void
  private var size:CGSize {FloatLayout.size(count:model.files.count,expanded:model.expanded)}
  var body:some View {
    let _ = language.code

    ZStack(alignment:.topLeading) {
      if model.expanded {FloatGlass()}
      VStack(spacing:0) {
        preview.frame(height:model.expanded ? 127 : 115)
        if model.expanded {
          HStack(spacing:5) {
            Button {model.expanded=false} label:{Image(systemName:"chevron.up").font(.system(size:8,weight:.semibold))}
              .buttonStyle(.plain).help(tr("Replier le Float")).accessibilityLabel(tr("Replier le Float"))
            Text(trString(model.dropping ? "Drop to add" : "\(model.files.count) \(model.files.count == 1 ? "Item" : "Items")"))
              .font(.system(size:11,weight:.medium))
              .overlay(FloatMoveRegion().accessibilityLabel(tr("Déplacer le Float")))
          }.frame(maxWidth:.infinity).frame(height:35)
          Divider().padding(.horizontal,12)
          ScrollView {
            LazyVGrid(columns:Array(repeating:GridItem(.fixed(80),spacing:8),count:FloatLayout.columns(model.files.count)),spacing:0) {
              ForEach(model.files,id:\.self) {file in cell(file)}
            }.padding(.top,13).padding(.horizontal,12).padding(.bottom,8)
          }.scrollIndicators(.hidden)
        }
      }
      if model.hovering {
        Button(action:onClose) {Image(systemName:"xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white,Color(white:0.16)).font(.system(size:16))}
          .buttonStyle(.plain).help(tr("Fermer le Float sans supprimer les fichiers"))
          .accessibilityLabel(tr("Fermer le Float sans supprimer les fichiers"))
          .padding(.leading,model.expanded ? 18 : 8).padding(.top,13)
      }
    }.frame(width:size.width,height:size.height)
      .preferredColorScheme(ClementineAppearance(rawValue:state.appearance)?.colorScheme)
      .overlay {if model.dropping {RoundedRectangle(cornerRadius:32).stroke(Color.orange.opacity(0.7),lineWidth:1.5).allowsHitTesting(false)}}
      .onHover {model.hovering=$0}
      .onChange(of:model.expanded) { _, _ in onResize() }
      .onChange(of:model.files.count) { _, _ in onResize() }
      .onDrop(of:["public.file-url"],isTargeted:$model.dropping) {providers in
        let accepted=providers.filter{$0.hasItemConformingToTypeIdentifier("public.file-url")}
        for provider in accepted {
          provider.loadItem(forTypeIdentifier:"public.file-url",options:nil) {item,_ in
            let url=(item as? URL) ?? (item as? Data).flatMap{URL(dataRepresentation:$0,relativeTo:nil)}
            if let url {DispatchQueue.main.async{model.add([url])}}
          }
        };return !accepted.isEmpty
      }
  }
  private var preview:some View {
    ZStack {
      ForEach(Array(model.files.prefix(3).reversed()),id:\.self) {file in
        let index=model.files.firstIndex(of:file) ?? 0
        Image(nsImage:model.thumbnails[file] ?? NSImage()).resizable().aspectRatio(contentMode:.fit)
          .frame(width:58,height:80).clipShape(RoundedRectangle(cornerRadius:4))
          .shadow(color:.black.opacity(0.20),radius:2.5,x:0,y:1.5)
          .rotationEffect(.degrees(index == 0 ? 0 : index == 1 ? -6 : 5))
          .offset(x:CGFloat(index)*2,y:CGFloat(index)*2)
      }.offset(y:model.expanded ? 10.5 : -1)
      FloatPaperclip(expanded:model.expanded)
      FloatDragRegion(model:model,file:nil,onClick:{if !model.expanded {model.expanded=true}},context:{menuActions(model.files)})
        .accessibilityLabel(trString(model.expanded ? "Float — glisser pour déplacer l’îlot, Option-glisser pour emporter les fichiers." : "Float — cliquer pour déployer, glisser pour déplacer l’îlot."))
    }.frame(maxWidth:.infinity).contentShape(Rectangle())
  }
  private func cell(_ file:URL)->some View {
    VStack(spacing:7) {
      Image(nsImage:model.thumbnails[file] ?? NSImage()).resizable().aspectRatio(contentMode:.fit)
        .frame(width:44,height:44).shadow(color:.black.opacity(0.13),radius:1.5,x:0,y:1)
      Text(file.lastPathComponent).font(.system(size:11)).multilineTextAlignment(.center).lineLimit(2)
        .frame(width:86,height:30,alignment:.top)
    }.frame(width:80,height:92,alignment:.top)
      .background(model.selected.contains(file) ? Color.accentColor.opacity(0.16) : .clear,in:RoundedRectangle(cornerRadius:7))
      .overlay(FloatDragRegion(model:model,file:file,onClick:{model.select(file,modifiers:NSEvent.modifierFlags)},context:{menuActions(model.carried(file))}))
  }
  private func menuActions(_ files:[URL])->[(String,()->Void)] {
    [("Ouvrir",{files.forEach{NSWorkspace.shared.open($0)}}),
     ("Afficher dans le Finder",{state.fileAction("reveal",urls:files)}),
     ("Copier",{state.fileAction("copy",urls:files)}),
     ("Copier le chemin",{state.fileAction("path",urls:files)}),
     ("Ouvrir dans l’atelier",{state.add(files,replace:true);state.showWindow?()}),
     ("Retirer du Float",{model.remove(files)})]
  }
}

struct FloatDragRegion:NSViewRepresentable {
  let model:FloatModel
  let file:URL?
  let onClick:()->Void
  let context:()->[(String,()->Void)]
  func makeNSView(context:Context)->FloatDragSource {FloatDragSource()}
  func updateNSView(_ view:FloatDragSource,context:Context) {
    view.model=model;view.file=file;view.onClick=onClick;view.actions=self.context
    view.setAccessibilityElement(true);view.setAccessibilityRole(.button)
    view.setAccessibilityLabel(file?.lastPathComponent ?? (model.expanded ? "Déplacer le Float" : "Déployer ou déplacer le Float"))
  }
}
struct FloatMoveTracker {
  private(set) var startPointer:NSPoint?
  private(set) var startOrigin:NSPoint = .zero
  private(set) var moved=false
  mutating func begin(pointer:NSPoint,origin:NSPoint) {
    startPointer=pointer;startOrigin=origin;moved=false
  }
  mutating func update(pointer:NSPoint,size:CGSize,in screen:CGRect)->NSPoint? {
    guard let startPointer else{return nil}
    let delta=CGSize(width:pointer.x-startPointer.x,height:pointer.y-startPointer.y)
    if !moved && hypot(delta.width,delta.height)<4{return nil}
    moved=true
    return FloatLayout.draggedOrigin(startOrigin,delta:delta,size:size,in:screen)
  }
  mutating func end()->Bool {
    let wasMoved=moved;startPointer=nil;moved=false;return wasMoved
  }
}
final class FloatDragSource:NSView,NSDraggingSource {
  weak var model:FloatModel?
  var file:URL?
  var onClick:(()->Void)?
  var actions:(()->[(String,()->Void)])?
  private var press:NSPoint?
  private var dragging=false
  private var moving=FloatMoveTracker()
  private var menuCallbacks:[()->Void]=[]
  override var acceptsFirstResponder:Bool {true}
  override func accessibilityPerformPress()->Bool {onClick?();return true}
  override func mouseDown(with event:NSEvent) {
    press=event.locationInWindow;dragging=false
    if file == nil,let window {moving.begin(pointer:window.convertPoint(toScreen:event.locationInWindow),origin:window.frame.origin)}
  }
  override func mouseUp(with event:NSEvent) {
    defer {press=nil}
    let moved=moving.end()
    if moved,file == nil,let window,let screen=window.screen {
      window.setFrameOrigin(FloatLayout.pinnedOrigin(window.frame.origin,size:window.frame.size,in:screen.visibleFrame))
    }
    guard !dragging,!moved,let start=press,hypot(start.x-event.locationInWindow.x,start.y-event.locationInWindow.y)<4 else{return}
    if event.clickCount == 2,let file {NSWorkspace.shared.open(file)}else{onClick?()}
  }
  override func mouseDragged(with event:NSEvent) {
    guard let window,let model else{return}
    if file == nil && (!model.expanded || !event.modifierFlags.contains(.option)) {
      let pointer=window.convertPoint(toScreen:event.locationInWindow)
      let screen=NSScreen.screens.first{$0.frame.contains(pointer)} ?? window.screen ?? NSScreen.main
      if let screen,let origin=moving.update(pointer:pointer,size:window.frame.size,in:screen.visibleFrame) {
        window.setFrameOrigin(origin)
      }
      return
    }
    guard !dragging,let start=press,hypot(start.x-event.locationInWindow.x,start.y-event.locationInWindow.y)>=4 else{return}
    dragging=true
    let urls=model.carried(file)
    let items=urls.enumerated().map {index,url -> NSDraggingItem in
      let item=NSDraggingItem(pasteboardWriter:url as NSURL)
      item.setDraggingFrame(CGRect(x:CGFloat(index)*3,y:CGFloat(index)*3,width:48,height:64),contents:model.thumbnails[url] ?? NSWorkspace.shared.icon(forFile:url.path))
      return item
    }
    guard !items.isEmpty else{return}
    beginDraggingSession(with:items,event:event,source:self)
  }
  func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {[.copy,.generic]}
  override func menu(for event:NSEvent)->NSMenu? {
    let menu=NSMenu();let choices=actions?() ?? [];menuCallbacks=choices.map{$0.1}
    for (index,choice) in choices.enumerated() {let item=NSMenuItem(title:trString(choice.0),action:#selector(menuAction(_:)),keyEquivalent:"");item.tag=index;item.target=self;menu.addItem(item)}
    return menu
  }
  @objc private func menuAction(_ sender:NSMenuItem) {if menuCallbacks.indices.contains(sender.tag){menuCallbacks[sender.tag]()}}
}

struct FloatMoveRegion:NSViewRepresentable {
  func makeNSView(context:Context)->FloatMoveSource {FloatMoveSource()}
  func updateNSView(_ view:FloatMoveSource,context:Context) {}
}
final class FloatMoveSource:NSView {
  private var moving=FloatMoveTracker()
  override func mouseDown(with event:NSEvent) {
    if let window {moving.begin(pointer:window.convertPoint(toScreen:event.locationInWindow),origin:window.frame.origin)}
  }
  override func mouseDragged(with event:NSEvent) {
    guard let window else{return}
    let pointer=window.convertPoint(toScreen:event.locationInWindow)
    let screen=NSScreen.screens.first{$0.frame.contains(pointer)} ?? window.screen ?? NSScreen.main
    if let screen,let origin=moving.update(pointer:pointer,size:window.frame.size,in:screen.visibleFrame) {
      window.setFrameOrigin(origin)
    }
  }
  override func mouseUp(with event:NSEvent) {
    if moving.end(),let window,let screen=window.screen {
      window.setFrameOrigin(FloatLayout.pinnedOrigin(window.frame.origin,size:window.frame.size,in:screen.visibleFrame))
    }
  }
}

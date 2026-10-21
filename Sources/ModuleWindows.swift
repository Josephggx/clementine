import AppKit
import SwiftUI
import AVKit
import PDFKit
import Combine

final class ModulePanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { false } }

final class ModuleWindowController: NSObject, NSWindowDelegate {
  let session: ModuleSession
  let window: NSPanel
  var onClose: (() -> Void)?
  var subscriptions = Set<AnyCancellable>()
  init(tool: String, files: [URL], defaults: Options, reveal: Bool) {
    session = ModuleSession(tool:tool,files:files,defaults:defaults,reveal:reveal)
    let spec = session.specification
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
    window = ModulePanel(contentRect:NSRect(x:0,y:0,width:spec.width,height:min(spec.height,visible.height-50)),styleMask:[.borderless,.fullSizeContentView,.nonactivatingPanel],backing:.buffered,defer:false)
    super.init()
    window.title = trString(spec.title); window.isOpaque = false; window.backgroundColor = .clear
    window.hasShadow = true; window.isMovableByWindowBackground = false; window.isReleasedWhenClosed = false
    window.hidesOnDeactivate = false; window.level = .floating; window.delegate = self
    window.collectionBehavior = [.fullScreenAuxiliary,.moveToActiveSpace]
    window.contentView = NSHostingView(rootView:ModuleRoot(session:session, movableHeader:true))
    session.close = { [weak self] in self?.window.close() }
    window.center()
    session.$targetEnabled.dropFirst().sink { [weak self] enabled in
      guard let self else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        let extra: CGFloat = enabled ? 110 : 0
        let frame = self.window.frame
        let height = min(spec.height+extra,visible.height-50)
        self.window.setFrame(NSRect(x:frame.minX,y:frame.maxY-height,width:spec.width,height:height),display:true,animate:true)
      }
    }.store(in:&subscriptions)
  }
  func show() {
    window.orderFrontRegardless()
    // Taking key focus from an inactive app can switch to its main window’s
    // Space even for a nonactivating panel. A user click can focus the module.
    if NSApp.isActive { window.makeKey() }
  }
  func windowWillClose(_ notification: Notification) { session.pause(); DispatchQueue.main.async { [self] in onClose?() } }
}
struct ModuleGlass: ViewModifier {
  static let cornerRadius: CGFloat = 21
  @ViewBuilder func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius:Self.cornerRadius,style:.continuous)
    if #available(macOS 26.0,*) {
      content.glassEffect(.regular.tint(.white.opacity(0.20)),in:shape)
        .overlay(shape.stroke(.white.opacity(0.58), lineWidth: 0.8))
    } else {
      content.background(.regularMaterial,in:shape)
        .overlay(shape.stroke(.white.opacity(0.58), lineWidth: 0.8))
    }
  }
}
private final class ModuleRootHover: ObservableObject { @Published var close = false }
struct ModuleRoot: View {
  @ObservedObject private var language = AppLanguage.shared
  @ObservedObject var session: ModuleSession
  var movableHeader = false
  @StateObject private var hover = ModuleRootHover()
  var body: some View {
    VStack(spacing:0) {
      ZStack {
        Text(trString(session.specification.title)).font(.system(size:14,weight:.semibold))
        HStack {
          Button { session.cancel() } label: {
            Image(systemName:"xmark").font(.system(size:11,weight:.medium))
              .frame(width:26,height:26)
              .background(hover.close ? citrus.opacity(0.16) : Color.gray.opacity(0.09),in:Circle())
              .foregroundStyle(hover.close ? citrus : Color.secondary)
          }
          .buttonStyle(.plain).help(tr("Close"))
          .onHover {hover.close=$0}
          .animation(.easeOut(duration:0.16),value:hover.close)
          Spacer()
        }
      }.padding(.horizontal,12).frame(height:40)
        .overlay {
          if movableHeader { ModuleHeaderDragArea() }
        }
      Divider().opacity(0.5)
      ScrollView {
        ModuleContent(session:session).padding(12)
      }.scrollIndicators(.automatic)
      if let error = session.error {
        HStack(alignment:.top) { Text(trString(error)).font(.caption).foregroundStyle(.red).textSelection(.enabled); Spacer(); Button { session.error = nil } label:{Image(systemName:"xmark")} }.padding(12)
      }
      Divider().opacity(0.5)
      HStack {
        if ["crop","adjust","annotate","frame","redact"].contains(session.tool) { Button(tr("Reset")) { session.reset() } }
        if session.loading { ProgressView().controlSize(.small).tint(citrus) }
        if session.busy { ProgressView(value:session.progress).tint(citrus).frame(width:90); Button(tr("Cancel")) { session.cancel() }.buttonStyle(.borderless) }
        Spacer()
        if session.tool == "strip" && session.metadataCanEdit { Button(tr("Remove All")) { session.options.metadataRemoveAll = true; for i in session.metadata.indices { session.metadata[i].removed = true } } }
        Button(trString(session.tool == "strip" && !session.metadataCanEdit ? "Exporter JSON" : session.tool == "snapshot" ? "Save \(session.frames.count) Frame\(session.frames.count == 1 ? "" : "s")" : session.specification.button)) { session.export() }
          .buttonStyle(.borderedProminent).tint(citrus)
          .disabled(!session.canSave).keyboardShortcut(.defaultAction)
      }.controlSize(.small).padding(.horizontal,16).frame(height:52)
    }
    .id(language.code).environment(\.locale,language.locale)
    .font(.system(size:12)).foregroundStyle(.primary)
    .tint(citrus)
    .background(Color.clementineSurface.opacity(0.62))
    .modifier(ModuleGlass()).clipShape(RoundedRectangle(cornerRadius:ModuleGlass.cornerRadius,style:.continuous))
    .onExitCommand { session.cancel() }
  }
}
struct ModuleContent: View {
  @ObservedObject var session: ModuleSession
  var o: Binding<Options> { $session.options }
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      switch session.tool {
      case "compress": compression
      case "strip": metadata
      case "adjust": imageCanvas; adjustments
      case "annotate": imageCanvas; annotations
      case "frame": imageCanvas; backgroundControls
      case "crop": mediaCanvas; cropControls
      case "redact": mediaCanvas; redactControls
      case "collage": imageCanvas; collageControls
      case "trim": if session.family == .video { mediaCanvas }; trimControls
      case "speed": mediaCanvas; speedControls; playback
      case "snapshot": mediaCanvas; snapshotControls
      case "split":
        if session.family == .pdf { PDFSplitControls(session:session) }
        else { mediaCanvas; splitControls }
      case "normalize": audioOverview; normalizeControls
      case "channels": channelControls
      case "bleep": bleepControls
      case "visualize": visualizerPreview; visualizerControls
      case "join", "mergepdf": ordering
      case "archive": archiveControls
      case "organize": pdfPages
      default: EmptyView()
      }
    }.frame(maxWidth:.infinity,alignment:.leading)
    .onChange(of:session.options.photoAdjustments) { _, _ in session.renderPreview() }
  }
  var imageCanvas: some View {
    ZStack(alignment:.top) {
      ModuleCanvas(session:session)
      if session.tool == "adjust" {
        HStack(spacing:8) {
          Button {session.previewScale=max(1,session.previewScale-0.25)} label:{Image(systemName:"minus.magnifyingglass")}
          Text(tr("\(Int(session.previewScale*100)) %")).font(.caption).monospacedDigit()
          Button {session.previewScale=min(8,session.previewScale+0.25)} label:{Image(systemName:"plus.magnifyingglass")}
          Spacer();Button(tr("Reset")) {session.previewScale=1;session.previewOffset = .zero};Button(tr("Original")) {session.showsOriginal.toggle()}
        }.buttonStyle(.plain).foregroundStyle(.white).padding(8).background(.black.opacity(0.25))
      }
    }.frame(height:canvasHeight).background(Color.black.opacity(session.tool == "frame" || session.tool == "collage" || session.tool == "crop" ? 0.035 : 0.9),in:RoundedRectangle(cornerRadius:10)).clipShape(RoundedRectangle(cornerRadius:10))
  }
  var canvasHeight: CGFloat {
    switch session.tool { case "adjust":return 290; case "frame":return 335; case "collage":return 310; case "crop":return 420; default:return 470 }
  }
  @ViewBuilder var mediaCanvas: some View {
    if session.family == .video {
      if session.cataloguePreview {
        ModuleCanvas(session:session, video:true)
          .frame(height:session.tool == "redact" ? 410 : 390)
          .background(.black.opacity(0.16), in:RoundedRectangle(cornerRadius:10))
          .clipShape(RoundedRectangle(cornerRadius:10))
      } else if session.tool == "crop" || session.tool == "redact" {
        ZStack {
          ModuleVideoView(player:session.player).allowsHitTesting(false)
          if session.tool == "redact",session.options.marks.contains(where:{$0.blur}) {
            GeometryReader { geo in
              let scale=min(geo.size.width/max(1,session.sourceSize.width),geo.size.height/max(1,session.sourceSize.height))
              let w=session.sourceSize.width*scale,h=session.sourceSize.height*scale
              ModuleVideoView(player:session.player).blur(radius:12).mask {
                ZStack(alignment:.topLeading) {
                  Color.clear
                  ForEach(session.options.marks.filter {$0.blur && session.position >= $0.start && session.position <= $0.end}) { mark in
                    Rectangle().frame(width:mark.width*w,height:mark.height*h).position(x:(geo.size.width-w)/2+(mark.x+mark.width/2)*w,y:(geo.size.height-h)/2+(mark.y+mark.height/2)*h)
                  }
                }
              }.allowsHitTesting(false)
            }
          }
          ModuleCanvas(session:session,video:true)
        }.frame(height:session.tool == "redact" ? 410 : 400).background(.black,in:RoundedRectangle(cornerRadius:10)).clipShape(RoundedRectangle(cornerRadius:10))
      } else { ModuleVideoView(player:session.player).frame(height:390).clipShape(RoundedRectangle(cornerRadius:10)) }
    } else { imageCanvas }
  }
  var compression: some View {
    VStack(alignment:.leading,spacing:18) {
      Text(session.files.count == 1 ? session.files[0].lastPathComponent : "\(session.files.count) files").foregroundStyle(.secondary).font(.caption)
      Text(tr("Original size: \(ByteCountFormatter.string(fromByteCount:session.cataloguePreview ? 4_800_000 : session.files.reduce(0) { $0 + Engine().bytes($1) },countStyle:.file))"))
      Text(tr("Compression preset")).fontWeight(.semibold)
      Picker("",selection:o.strong) { Text(tr("Balanced")).tag(false); Text(tr("Strong")).tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width:150)
      Text(trString(session.options.strong ? "Smaller files with more compression." : "Smaller files with less quality loss.")).font(.caption).foregroundStyle(.secondary)
      if session.family == .image {
        Picker(tr("Image size"),selection:$session.imageSize) { ForEach(["Keep original dimensions","2560 px","1920 px","1600 px","1280 px","1024 px","800 px"],id:\.self) { Text(trString($0)).tag($0) } }
      }
      Divider()
      Toggle(tr("Compress to target file size"),isOn:$session.targetEnabled)
      if session.targetEnabled {
        Picker(tr("Target"),selection:$session.targetMode) { Text(tr("File size")).tag("File size"); Text(tr("Reduction")).tag("Reduction") }.pickerStyle(.segmented)
        if session.targetMode == "File size" {
          HStack { TextField(tr("Size"),value:$session.targetValue,format:.number).textFieldStyle(.roundedBorder); Picker(tr("Unit"),selection:$session.targetUnit) { Text(tr("MB")).tag("MB");Text(tr("KB")).tag("KB") }.labelsHidden().frame(width:70) }
        } else { slider("Reduction",binding:$session.reduction,range:1...99,suffix:"%") }
        if session.family == .video { Picker(tr("Encoding"),selection:o.targetEncoding) {Text(tr("Accurate")).tag("Accurate");Text(tr("Fast")).tag("Fast")} }
      }
      if session.family == .pdf { Text(tr("PDF compression flattens pages. Selectable text, links and forms will be removed.")).font(.caption).foregroundStyle(.secondary) }
    }.frame(minHeight:230,alignment:.top)
  }
  var metadata: some View {
    VStack(alignment:.leading,spacing:12) {
      HStack { Text(session.files[0].lastPathComponent).font(.caption).foregroundStyle(.secondary); Spacer(); TextField(tr("Search metadata"),text:$session.search).textFieldStyle(.roundedBorder).frame(width:170) }
      ForEach(Array(Set(session.metadata.map(\.group))).sorted(),id:\.self) { group in
        let indices = session.metadata.indices.filter { session.metadata[$0].group == group && (session.search.isEmpty || session.metadata[$0].key.localizedCaseInsensitiveContains(session.search) || session.metadata[$0].value.localizedCaseInsensitiveContains(session.search)) }
        if !indices.isEmpty {
          Text(trString(group)).font(.caption).foregroundStyle(.secondary)
          ForEach(indices,id:\.self) { index in
            HStack {
              Text(session.metadata[index].label).frame(maxWidth:155,alignment:.trailing).lineLimit(2)
              TextField(tr("Value"),text:$session.metadata[index].value).textFieldStyle(.roundedBorder).disabled(session.metadata[index].removed || !session.metadata[index].editable)
              Button { session.metadata[index].removed.toggle() } label:{Image(systemName:session.metadata[index].removed ? "arrow.uturn.backward.circle" : "minus.circle")}.buttonStyle(.plain).disabled(!session.metadata[index].editable)
            }.opacity(session.metadata[index].removed ? 0.4 : 1)
          }
          Divider()
        }
      }
      Text(trString(session.metadataCanEdit ? "For photos, Remove All also clears hidden camera and processing data. HDR and portrait effects may change." : "Lecture seule pour ce format. Les métadonnées peuvent être exportées en JSON.")).font(.caption).foregroundStyle(.secondary)
    }
  }
  var adjustments: some View {
    VStack(alignment:.leading,spacing:14) {
      ForEach([("Light",["Exposure","Brightness","Contrast","Highlights","Shadows","Whites","Blacks","Gamma"]),("Color",["Temperature","Tint","Saturation","Vibrance","Hue"]),("Detail",["Clarity","Texture","Sharpness","Dehaze","Fade","Vignette","Grain","Noise Reduction","Blur"])],id:\.0) { section in
        Text(trString(section.0)).font(.caption).foregroundStyle(.secondary)
        ForEach(section.1,id:\.self) { key in
          HStack(spacing:6) {
            Text(trString(key)).font(.system(size:10)).frame(width:85,alignment:.leading)
            Slider(value:Binding(get:{session.options.photoAdjustments[key] ?? 0},set:{session.options.photoAdjustments[key] = $0}),in:key == "Exposure" ? -4...4 : key == "Hue" ? -180...180 : ["Grain","Sharpness","Noise Reduction","Blur","Fade"].contains(key) ? 0...100 : -100...100).tint(citrus)
            Text(trString(String(format:key == "Exposure" ? "%.2f EV" : "%+.0f",session.options.photoAdjustments[key] ?? 0))).font(.system(size:10)).monospacedDigit().frame(width:43,alignment:.trailing)
            Button { session.options.photoAdjustments[key] = 0 } label:{Image(systemName:"arrow.counterclockwise")}.buttonStyle(.plain).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
  var cropControls: some View {
    VStack(spacing:14) {
      if session.files.count>1 {
        ScrollView(.horizontal) {HStack {ForEach(Array(session.files.enumerated()),id:\.offset) {index,url in
          Button {session.selectCropFile(index)} label:{VStack {if let image=session.fileThumbnails[url] {Image(nsImage:image).resizable().scaledToFit().frame(width:55,height:40)};Text(url.lastPathComponent).lineLimit(1).font(.caption2)}.padding(4).overlay(RoundedRectangle(cornerRadius:6).stroke(index==session.activeFile ? .orange : .clear))}.buttonStyle(.plain)
        }}}
      }
      HStack { Text(tr("Aspect ratio")).foregroundStyle(.secondary); Picker(tr("Aspect ratio"),selection:$session.aspect) { ForEach(["Free","1:1","16:9","9:16","4:3","3:4"],id:\.self) { Text(trString($0)).tag($0) } }.labelsHidden().pickerStyle(.segmented).onChange(of:session.aspect) { _, value in
        if let ratio = Engine.ratio(value) {
          let maxW = session.sourceImage?.width ?? Int(session.sourceSize.width), maxH = session.sourceImage?.height ?? Int(session.sourceSize.height)
          session.options.width = min(maxW,Int(Double(maxH)*ratio)); session.options.height = Int(Double(session.options.width)/ratio)
          session.options.x = max(0,(maxW-session.options.width)/2); session.options.y = max(0,(maxH-session.options.height)/2)
        }
      } }
      HStack { Text(tr("W")).foregroundStyle(.secondary); number(o.width); Text(tr("H")).foregroundStyle(.secondary); number(o.height); Text(tr("px")).foregroundStyle(.secondary); Spacer() }
      if session.family == .video { Slider(value:Binding(get:{session.position},set:session.seek),in:0...max(0.001,session.duration)).tint(citrus); playback }
    }
  }
  var annotations: some View {
    VStack(alignment:.leading,spacing:10) {
      HStack(spacing:5) {
        ForEach([("select","cursorarrow"),("arrow","arrow.up.left"),("draw","pencil.tip"),("text","textformat"),("rectangle","rectangle"),("ellipse","circle"),("highlight","highlighter"),("number","1.circle"),("magnifier","plus.magnifyingglass"),("image","photo.on.rectangle")],id:\.0) { item in
          Button { session.drawingTool = item.0;session.selectedMark=nil; if item.0 == "image" { chooseAnnotationImage() } } label:{Image(systemName:item.1).foregroundStyle(session.drawingTool == item.0 ? .white : .secondary).frame(width:25,height:25).background(session.drawingTool == item.0 ? citrus : Color.black.opacity(0.055),in:RoundedRectangle(cornerRadius:5))}.buttonStyle(.plain).help(trString(item.0 == "draw" ? "Stylo libre" : item.0 == "select" ? "Sélectionner et déplacer" : item.0)).accessibilityLabel(trString(item.0 == "draw" ? "Stylo libre" : item.0 == "select" ? "Sélectionner et déplacer" : item.0))
        }
      }
      HStack {
        ColorPicker(tr("Color"),selection:$session.color,supportsOpacity:false).labelsHidden().onChange(of:session.color) { _, color in
          let hex = NSColor(color).hexString
          session.options.color = hex
          if let index = session.options.marks.firstIndex(where:{$0.id == session.selectedMark}) { session.options.marks[index].color = hex; session.renderPreview() }
        }
        if session.drawingTool == "text" { TextField(tr("Text"),text:o.text).textFieldStyle(.roundedBorder) }
        Spacer(); Button { session.undo() } label:{Image(systemName:"arrow.uturn.backward")}.disabled(session.undoStack.isEmpty)
        Button { session.deleteMark() } label:{Image(systemName:"trash")}.disabled(session.selectedMark == nil)
      }
      if ["text","number"].contains(session.drawingTool) {
        HStack {
          Picker(tr("Font"),selection:o.annotationFont) {ForEach(["System","Rounded","Serif","Monospaced"],id:\.self) {Text(trString($0)).tag($0)}}
          TextField(tr("Size"),value:o.fontSize,format:.number).textFieldStyle(.roundedBorder).frame(width:50)
        }.onChange(of:session.options.annotationFont) { _, value in if let i=session.options.marks.firstIndex(where:{$0.id==session.selectedMark}) {session.options.marks[i].font=value;session.renderPreview()} }
        .onChange(of:session.options.fontSize) { _, value in if value>0,let i=session.options.marks.firstIndex(where:{$0.id==session.selectedMark}) {session.options.marks[i].size=value/6;session.renderPreview()} }
        .onChange(of:session.options.text) { _, value in if let i=session.options.marks.firstIndex(where:{$0.id==session.selectedMark}),session.options.marks[i].kind == "text" {session.options.marks[i].text=value;session.renderPreview()} }
      }
      if session.drawingTool == "magnifier" {slider("Magnification",binding:o.annotationMagnification,range:1...5,suffix:"×").onChange(of:session.options.annotationMagnification) { _, value in if let i=session.options.marks.firstIndex(where:{$0.id==session.selectedMark}) {session.options.marks[i].magnification=value;session.renderPreview()} }}
      if ["draw","highlight","arrow","rectangle","ellipse"].contains(session.drawingTool) {
        HStack {Text(tr("Épaisseur")).font(.caption);Slider(value:$session.strokeWidth,in:1...20).tint(citrus).frame(maxWidth:180);Text(tr("\(Int(session.strokeWidth))")).font(.caption).monospacedDigit()}
      }
      Text(trString(["draw","highlight"].contains(session.drawingTool) ? "Dessinez librement sur l’image. Chaque geste ajoute un trait indépendant." : session.drawingTool == "select" ? "Cliquez sur une annotation pour la déplacer ou la redimensionner." : "Drag from the tail toward the arrowhead. Drag an annotation to move it.")).font(.caption).foregroundStyle(.secondary)
    }
  }
  func chooseAnnotationImage() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; if panel.runModal() == .OK,let url = panel.url { session.options.text = url.path }
  }
  var redactControls: some View {
    VStack(alignment:.leading,spacing:12) {
      HStack { Text(tr("Style")).foregroundStyle(.secondary); Spacer(); Picker(tr("Style"),selection:o.blur) { Text(tr("Solid")).tag(false); Text(tr("Blur")).tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width:90) }
      HStack { Text(tr("Color")).foregroundStyle(.secondary); Spacer(); ColorPicker(tr("Color"),selection:$session.color,supportsOpacity:false).labelsHidden() }
      if let id = session.selectedMark,let index = session.options.marks.firstIndex(where:{$0.id == id}) {
        HStack { Text(tr("Selected area")).foregroundStyle(.secondary); Spacer(); Button(tr("Delete")) { session.deleteMark() } }
        .onChange(of:session.options.blur) { _, value in session.options.marks[index].blur = value; session.renderPreview() }
        .onChange(of:session.color) { _, value in session.options.color = NSColor(value).hexString; session.options.marks[index].color = session.options.color; session.renderPreview() }
      }
      if session.family == .image { HStack { Text(tr("Detect")).foregroundStyle(.secondary); Spacer(); Button(tr("Faces")) { session.detect("Faces") }; Button(tr("Text")) { session.detect("Text") } } }
      else {
        Text(tr("Redactions")).fontWeight(.medium)
        ForEach($session.options.marks) { $mark in
          ModuleRangeLane(start:$mark.start,end:$mark.end,duration:session.duration,label:"Box \((session.options.marks.firstIndex(where:{$0.id == mark.id}) ?? 0)+1)",onSeek:session.seek).frame(height:25)
        }
        ModuleTimeline(session:session).frame(height:48); playback
      }
    }
  }
  var backgroundControls: some View {
    VStack(spacing:14) {
      HStack(alignment:.top) {
        Text(tr("Background")).foregroundStyle(.secondary).frame(width:75,alignment:.leading)
        VStack(alignment:.leading,spacing:6) {
          ScrollView(.horizontal) { HStack(spacing:5) { ForEach(ModuleBackgrounds.names,id:\.self) { name in
            Button { session.options.background = name; session.options.backgroundImage = ""; session.renderPreview() } label:{Canvas {context,size in context.withCGContext {cg in cg.translateBy(x:0,y:size.height);cg.scaleBy(x:1,y:-1);ModuleBackgrounds.draw(cg,rect:CGRect(origin:.zero,size:size),name:name)}}.frame(width:25,height:25).clipShape(RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(session.options.background == name ? .orange : .clear,lineWidth:2))}.buttonStyle(.plain)
          }; Button { chooseBackground() } label:{Image(systemName:"photo.badge.plus").frame(width:25,height:25)} } }.scrollIndicators(.hidden)
          ScrollView(.horizontal) { HStack(spacing:5) { ForEach(ModuleBackgrounds.solids,id:\.self) { hex in
            Button { session.options.background = hex; session.options.backgroundImage = ""; session.renderPreview() } label:{RoundedRectangle(cornerRadius:5).fill(Color(nsColor:NSColor(hex:hex))).frame(width:25,height:25)}.buttonStyle(.plain)
          }; ColorPicker(tr("Custom"),selection:$session.color,supportsOpacity:false).labelsHidden().onChange(of:session.color) { _, value in session.options.background=NSColor(value).hexString;session.options.backgroundImage="";session.renderPreview()} } }.scrollIndicators(.hidden)
        }
      }
      slider("Padding",binding:o.padding,range:0...400,suffix:"px",render:true)
      slider("Corners",binding:o.corners,range:0...100,suffix:"px",render:true)
      slider("Shadow",binding:o.shadow,range:0...100,suffix:"px",render:true)
      if !session.options.backgroundImage.isEmpty { slider("Blur",binding:o.backgroundBlur,range:0...100,suffix:"",render:true) }
      Picker(tr("Ratio"),selection:o.canvasRatio) { ForEach(["Auto","1:1","16:9","4:5"],id:\.self) { Text(trString($0)).tag($0) } }.pickerStyle(.segmented).onChange(of:session.options.canvasRatio) { _, _ in session.renderPreview() }
    }
  }
  func palette(_ name: String) -> [Color] {(ModuleBackgrounds.colors[name] ?? ModuleBackgrounds.colors["Citrus"]!).map {Color(nsColor:NSColor(hex:$0))}}

  func chooseBackground() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; if panel.runModal() == .OK,let url = panel.url { session.options.backgroundImage = url.path; session.renderPreview() } }
  var collageControls: some View {
    VStack(spacing:12) {
      Picker(tr("Style"),selection:o.collageStyle) { ForEach(["Grid","Row","Column","Featured"],id:\.self) { Text(trString($0)).tag($0) } }.onChange(of:session.options.collageStyle) { _, _ in session.renderPreview() }
      Stepper("Columns                         \(session.options.columns)",value:o.columns,in:1...10).onChange(of:session.options.columns) { _, _ in session.renderPreview() }
      Picker(tr("Canvas"),selection:o.canvasRatio) { ForEach(["Square · 1:1","Landscape · 16:9","Portrait · 4:5","Portrait · 9:16"],id:\.self) { Text(trString($0)).tag($0) } }.onChange(of:session.options.canvasRatio) { _, value in session.options.height = Int(Double(session.options.width)/(Engine.ratio(value) ?? 1)); session.renderPreview() }
      Picker(tr("Width"),selection:o.width) { ForEach([1024,1600,2048,2560,3840,4096],id:\.self) { Text(tr("\($0.formatted()) px")).tag($0) } }.onChange(of:session.options.width) { _, width in session.options.height = Int(Double(width)/(Engine.ratio(session.options.canvasRatio) ?? 1));session.renderPreview() }
      Picker(tr("Image fit"),selection:o.imageFit) { Text(tr("Fill cells (crop edges)")).tag("Fill cells (crop edges)");Text(tr("Fit images (show all)")).tag("Fit images (show all)") }.onChange(of:session.options.imageFit) { _, _ in session.renderPreview() }
      Divider()
      DisclosureGroup("Spacing & background") {
        slider("Spacing",binding:o.collageSpacing,range:0...100,suffix:"px",render:true)
        slider("Padding",binding:o.collagePadding,range:0...200,suffix:"px",render:true)
        slider("Corners",binding:o.corners,range:0...100,suffix:"px",render:true)
        Picker(tr("Background"),selection:o.background) {Text(tr("White")).tag("#FFFFFF");Text(tr("Black")).tag("#000000");Text(tr("Transparent")).tag("Transparent")}.onChange(of:session.options.background) { _, _ in session.renderPreview()}
      }
      DisclosureGroup("Image order") { ordering }
      HStack { Spacer(); Button(tr("Reset Layout")) { session.options.collageStyle = "Grid";session.options.columns = 2;session.options.width = 2048;session.options.height = 2048;session.options.padding = 8;session.options.corners = 0;session.renderPreview() } }
    }
  }
  var playback: some View {
    HStack {
      Button { session.stepFrame(-1) } label:{Image(systemName:"backward.end")}.help(tr("Previous frame"))
      Button { session.togglePlay() } label:{Image(systemName:session.playing ? "pause.fill" : "play.fill")}
      Button { session.stepFrame(1) } label:{Image(systemName:"forward.end")}.help(tr("Next frame"))
      Spacer(); Text(tr("\(Self.time(session.position)) / \(Self.time(session.duration))")).monospacedDigit().foregroundStyle(.secondary)
    }.buttonStyle(.plain)
  }
  var trimControls: some View {
    VStack(spacing:10) {
      HStack { Text(tr("Drag the ends to trim")).foregroundStyle(.secondary); Spacer(); Text(tr("\(Self.time(session.options.duration)) selected")).foregroundStyle(.secondary) }
      ModuleTimeline(session:session,trim:true).frame(height:session.family == .video ? 80 : 100)
      HStack {
        Text(tr("Start")).foregroundStyle(.secondary); timeField(Binding(get:{session.options.start},set:{value in let end=session.options.start+session.options.duration;session.options.start=min(max(0,value),end-0.001);session.options.duration=end-session.options.start;session.seek(session.options.start)}))
        Spacer(); Text(tr("End")).foregroundStyle(.secondary); timeField(Binding(get:{session.options.start+session.options.duration},set:{session.options.duration=max(0.001,min(session.duration,$0)-session.options.start)}))
      }
      if session.family == .audio { Toggle(tr("Trim silent ends automatically"),isOn:o.trimSilence).onChange(of:session.options.trimSilence) { _, _ in session.detectSilentEnds()}; if session.options.trimSilence { slider("Silence threshold",binding:o.silenceThreshold,range:-60 ... -20,suffix:"dB").onChange(of:session.options.silenceThreshold) { _, _ in session.detectSilentEnds()} }; HStack { Spacer(); Button(trString(session.playing ? "Pause" : "▶  Play Selected Range")) { session.seek(session.options.start);session.togglePlay() } } }
      else { playback }
    }
  }
  var speedControls: some View {
    VStack(spacing:8) {
      HStack {Text(tr("Playback speed")).foregroundStyle(.secondary);Spacer();Text(trString(String(format:"%g×",session.options.speed))).foregroundStyle(.secondary)}
      Slider(value:Binding(get:{
        let values=[0.25,0.5,1.0,1.5,2.0,4.0]
        for i in 1..<values.count where session.options.speed<=values[i] {return Double(i-1)+(session.options.speed-values[i-1])/(values[i]-values[i-1])}
        return 5
      },set:{position in
        let values=[0.25,0.5,1.0,1.5,2.0,4.0],index=min(4,max(0,Int(position)))
        session.options.speed=values[index]+(values[index+1]-values[index])*(position-Double(index))
      }),in:0...5).tint(citrus)
      HStack { ForEach([0.25,0.5,1,1.5,2,4],id:\.self) { speed in Button(trString(String(format:"%g×",speed))) { session.options.speed=speed;if session.playing { session.player.rate=Float(speed) } }.buttonStyle(.plain);if speed != 4 { Spacer() } } }.font(.caption).foregroundStyle(.secondary)
    }.onChange(of:session.options.speed) { _, value in if session.playing { session.player.rate = Float(value) } }
  }
  var snapshotControls: some View {
    VStack(spacing:12) {
      Slider(value:Binding(get:{session.position},set:session.seek),in:0...max(0.001,session.duration)).tint(citrus); playback; Divider()
      HStack { Text(tr("\(session.frames.count) selected")).foregroundStyle(.secondary);Spacer();Button(tr("Add Frame")) {session.addPoint()} }
      ScrollView(.horizontal) { HStack { ForEach(session.frames,id:\.self) { time in
        ZStack(alignment:.topTrailing) {
          VStack { if let image = session.frameThumbnails[time] { Image(nsImage:image).resizable().scaledToFit().frame(width:65,height:45) };Text(trString(Self.time(time))).font(.caption) }.onTapGesture {session.seek(time)}
          Button {session.frames.removeAll {$0 == time}} label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain)
        }
      } } }.frame(minHeight:65)
    }
  }
  var splitControls: some View {
    VStack(spacing:14) {
      HStack { Text(tr("\(session.splitPoints.count) split points")).foregroundStyle(.secondary);Spacer();Button(tr("✂  Add Split")) {session.addPoint()} }
      ModuleTimeline(session:session).frame(height:48); playback
      ForEach(session.splitPoints,id:\.self) { time in HStack {Button(trString(Self.time(time))) {session.seek(time)};Spacer();Button {session.splitPoints.removeAll {$0 == time}} label:{Image(systemName:"minus.circle")}} }
      if !session.splitPoints.isEmpty {
        let boundaries=[0]+session.splitPoints+[session.duration]
        ScrollView(.horizontal) {HStack {ForEach(0..<boundaries.count-1,id:\.self) {index in
          VStack {Text(tr("Clip \(index+1)"));Text(trString(Self.time(boundaries[index+1]-boundaries[index]))).font(.caption);Button(trString(session.options.splitRemoved.contains(index) ? "Restore" : "Remove")) {if session.options.splitRemoved.contains(index) {session.options.splitRemoved.removeAll {$0==index}} else {session.options.splitRemoved.append(index)}}}.padding(6).background(.gray.opacity(0.06),in:RoundedRectangle(cornerRadius:6)).opacity(session.options.splitRemoved.contains(index) ? 0.4 : 1)
        }}}
        Picker(tr("Export"),selection:o.splitExportMode) {Text(tr("Separate clips")).tag("Clips");Text(tr("Merged video")).tag("Merged")}
      }
      Divider(); HStack { Text(tr("Equal clips")).foregroundStyle(.secondary);Spacer();Stepper("\(session.equalClips)",value:$session.equalClips,in:2...100);Button(tr("Set")) {session.splitPoints=(1..<session.equalClips).map {session.duration*Double($0)/Double(session.equalClips)}} }
    }.onChange(of:session.splitPoints) { _, _ in session.options.splitRemoved=[]}
  }
  var audioOverview: some View {
    VStack(spacing:10) {
      HStack { Text(session.files[0].lastPathComponent);Spacer();Text(trString(Self.time(session.duration))) }.font(.caption).foregroundStyle(.secondary)
      ModuleTimeline(session:session).frame(height:240);playback
    }
  }
  var normalizeControls: some View {
    VStack(spacing:18) {
      slider("Target loudness",binding:o.volume,range:-30 ... -5,suffix:"LUFS")
      slider("Loudness range",binding:o.loudnessRange,range:1...20,suffix:"LU")
      slider("True peak limit",binding:o.truePeak,range:-6...0,suffix:"dBTP")
      Text(tr("−16 LUFS is a balanced default for spoken audio and music. The true peak limit helps prevent clipping after encoding.")).font(.caption).foregroundStyle(.secondary)
      HStack { Button(tr("Original")) { session.playOriginal() };Spacer();Button(tr("▶  Preview Output")) {session.export(previewOnly:true)} }
    }
  }
  var channelControls: some View {
    VStack(spacing:18) {
      Text(tr("Output channel preview")).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
      ForEach(["L","R"],id:\.self) { channel in HStack {Text(trString(channel)).frame(width:24,height:24).background(.orange.opacity(0.1),in:Circle());ModuleWaveform(samples:(channel == "L" ? session.leftWaveform : session.rightWaveform).map {$0*Float(channel == "L" ? session.options.left : session.options.right)},tint:.gray).frame(height:45);Button {session.export(previewOnly:true,channel:channel)} label:{Image(systemName:"play.fill")}.buttonStyle(.plain)} }
      Divider()
      Picker(tr("Output"),selection:o.channels) {Text(tr("Mono")).tag(1);Text(tr("Stereo")).tag(2)}.pickerStyle(.segmented)
      slider("Left volume",binding:o.left,range:0...1,suffix:"%",multiplier:100)
      slider("Right volume",binding:o.right,range:0...1,suffix:"%",multiplier:100)
      HStack {Text(tr("Preview")).foregroundStyle(.secondary);Spacer();Button(tr("▶  Play Output")) {session.export(previewOnly:true)} }
    }
  }
  var bleepControls: some View {
    VStack(alignment:.leading,spacing:16) {
      HStack {Text(tr("Bleeps")).fontWeight(.medium);Text(tr("\(session.options.marks.count)")).foregroundStyle(.secondary)}
      ModuleBleepLane(session:session).frame(height:45)
      ModuleTimeline(session:session).frame(height:85)
      HStack {Text(trString(Self.time(0)));Spacer();Text(trString(Self.time(session.duration)))}.font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
      Text(tr("Drag across the Bleep layer to add a section, then drag a clip or either edge to adjust it.")).font(.caption).foregroundStyle(.secondary)
      Divider();HStack {Text(tr("Preview")).foregroundStyle(.secondary);Spacer();Button(tr("Original")) {session.playOriginal()};Button(tr("▶  With Bleeps")) {session.export(previewOnly:true)} }
    }
  }
  var visualizerPreview: some View {
    ZStack {
      if session.options.visualizerStyle == "Still Image", !session.options.backgroundImage.isEmpty,let image=NSImage(contentsOfFile:session.options.backgroundImage) {Image(nsImage:image).resizable().scaledToFit()}
      else {ModuleWaveform(samples:session.waveform).foregroundStyle(.orange).padding(15)}
    }.frame(height:390).frame(maxWidth:.infinity).background(.black,in:RoundedRectangle(cornerRadius:10))
  }
  var visualizerControls: some View {
    VStack(spacing:14) {
      Picker(tr("Style"),selection:o.visualizerStyle) {Text(tr("Waveform")).tag("Waveform");Text(tr("Still Image")).tag("Still Image")}
      if session.options.visualizerStyle == "Still Image" {Button(tr("Choose Image…")) {chooseBackground()} }
      Picker(tr("Shape"),selection:o.visualizerShape) {ForEach(["Landscape · 16:9","Portrait · 9:16","Square · 1:1"],id:\.self) {Text(trString($0)).tag($0)}}
    }
  }
  var ordering: some View {
    VStack(alignment:.leading,spacing:10) {
      Text(trString(session.tool == "join" ? "Ordre de lecture" : "Ordre des documents")).foregroundStyle(.secondary)
      ForEach(Array(session.files.enumerated()),id:\.offset) { index,url in
        HStack {Text(tr("\(index+1)")).foregroundStyle(.secondary);Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:30,height:30);Text(url.lastPathComponent).lineLimit(1);Spacer();VStack(spacing:2) {Button {session.moveFile(index,by:-1)} label:{Image(systemName:"chevron.up")}.disabled(index==0);Button {session.moveFile(index,by:1)} label:{Image(systemName:"chevron.down")}.disabled(index==session.files.count-1)} }.padding(8).background(.gray.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
      }
    }.frame(minHeight:150,alignment:.top)
  }
  var archiveControls: some View {
    VStack(alignment:.leading,spacing:14) {
      Text(tr("\(session.files.count) fichier\(session.files.count > 1 ? "s" : "") dans l’archive"))
        .foregroundStyle(.secondary)
      Picker(tr("Format"),selection:o.archiveFormat) {
        Text(tr("ZIP")).tag("zip")
        Text(tr("TAR")).tag("tar")
        Text(tr("TAR + GZIP")).tag("gz")
        Text(tr("RAR")).tag("rar")
      }
    }.frame(maxWidth:.infinity,alignment:.leading)
  }
  var pdfPages: some View {
    VStack(alignment:.leading,spacing:0) {
      HStack {
        Text(tr("\(session.options.modulePages.count) page\(session.options.modulePages.count == 1 ? "" : "s")"))
          .font(.system(size:11)).foregroundStyle(.secondary)
        Spacer()
        Button(tr("Reset Order")) { resetPDFPages() }
          .buttonStyle(.plain).font(.system(size:11))
          .foregroundStyle(pdfPagesAreOriginal ? Color.secondary.opacity(0.48) : citrus)
          .disabled(pdfPagesAreOriginal)
      }
      .padding(.horizontal,2).padding(.bottom,12)

      LazyVGrid(columns:[GridItem(.adaptive(minimum:112,maximum:132),spacing:12,alignment:.top)],alignment:.leading,spacing:14) {
        ForEach(Array(session.options.modulePages.enumerated()),id:\.element.id) { offset,page in
          PDFPageCard(session:session,page:page,offset:offset)
            .onDrag {session.draggedPage=page;return NSItemProvider(object:page.id.uuidString as NSString)}
            .onDrop(of:["public.text"],delegate:PDFPageDropDelegate(target:page,session:session))
        }
      }
      .frame(maxWidth:.infinity,minHeight:338,alignment:.topLeading)
    }
  }
  var pdfPagesAreOriginal: Bool {
    session.options.modulePages.count == session.pageThumbnails.count &&
    session.options.modulePages.enumerated().allSatisfy { $0.element.index == $0.offset && $0.element.rotation == 0 }
  }
  func resetPDFPages() { session.options.modulePages=session.pageThumbnails.keys.sorted().map {ModulePage(index:$0)} }
  func slider(_ title:String,binding:Binding<Double>,range:ClosedRange<Double>,suffix:String,multiplier:Double=1,render:Bool=false) -> some View {
    VStack(spacing:5) {HStack {Text(trString(title)).foregroundStyle(.secondary);Spacer();Text(trString(String(format:suffix == "dBTP" || suffix == "×" ? "%.1f %@" : "%.0f %@",binding.wrappedValue*multiplier,suffix))).monospacedDigit().foregroundStyle(.secondary)};Slider(value:binding,in:range).tint(citrus).onChange(of:binding.wrappedValue) { _, _ in if render {session.renderPreview()}} }
  }
  func number(_ binding:Binding<Int>) -> some View {TextField("",value:binding,format:.number).textFieldStyle(.roundedBorder).frame(width:65)}
  func timeField(_ binding:Binding<Double>) -> some View {ModuleTimeField(value:binding).frame(width:70,height:20)}
  static func time(_ time:Double) -> String {let safe=time.isFinite ? max(0,time) : 0;return String(format:"%d:%05.2f",Int(safe)/60,safe.truncatingRemainder(dividingBy:60))}
}

private struct PDFPageCard: View {
  @ObservedObject var session: ModuleSession
  let page: ModulePage
  let offset: Int
  var hovered: Bool {session.hoveredPage == page.id}
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius:7,style:.continuous).fill(Color.clementineRaisedSurface)
      if let image=session.pageThumbnails[page.index] {
        GeometryReader { geometry in
          let sideways = abs(page.rotation % 180) == 90
          Image(nsImage:image)
            .resizable()
            .scaledToFit()
            .frame(
              width: sideways ? geometry.size.height : geometry.size.width,
              height: sideways ? geometry.size.width : geometry.size.height)
            .rotationEffect(.degrees(Double(page.rotation)))
            .frame(width:geometry.size.width,height:geometry.size.height)
        }
        .padding(9)
        .clipped()
      }
      VStack {
        HStack(alignment:.top) {
          Text(trString(String(offset+1))).font(.system(size:11,weight:.semibold)).foregroundStyle(.white)
            .frame(width:23,height:23).background(citrus,in:Circle())
          Spacer()
          if hovered {
            HStack(spacing:3) {
              action("rotate.right") {session.options.modulePages[offset].rotation=(page.rotation+90)%360}
              action("plus.square.on.square") {session.options.modulePages.insert(ModulePage(index:page.index,rotation:page.rotation),at:offset+1)}
              action("trash") {session.options.modulePages.remove(at:offset)}
            }.transition(.opacity.combined(with:.scale(scale:0.92,anchor:.topTrailing)))
          } else {
            Image(systemName:"ellipsis").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary)
              .frame(width:23,height:23).background(.ultraThinMaterial,in:Circle())
          }
        }
        Spacer()
      }.padding(7)
    }
    .frame(height:164)
    .overlay(RoundedRectangle(cornerRadius:7,style:.continuous).stroke(hovered ? citrus.opacity(0.8) : Color.clementineBorder,lineWidth:hovered ? 1.25 : 0.7))
    .shadow(color:.black.opacity(hovered ? 0.14 : 0.08),radius:hovered ? 7 : 3,y:2)
    .scaleEffect(hovered ? 1.015 : 1)
    .animation(.easeOut(duration:0.14),value:hovered)
    .onHover {inside in session.hoveredPage=inside ? page.id : (session.hoveredPage == page.id ? nil : session.hoveredPage)}
  }
  func action(_ icon:String,perform:@escaping ()->Void)->some View {
    Button(action:perform) {Image(systemName:icon).font(.system(size:10,weight:.medium)).frame(width:23,height:23).background(.ultraThinMaterial,in:Circle())}.buttonStyle(.plain)
  }
}

private struct PDFPageDropDelegate: DropDelegate {
  let target: ModulePage
  let session: ModuleSession
  func dropEntered(info:DropInfo) {
    guard let dragged=session.draggedPage,dragged.id != target.id,
          let source=session.options.modulePages.firstIndex(where:{$0.id == dragged.id}),
          let destination=session.options.modulePages.firstIndex(where:{$0.id == target.id}) else {return}
    withAnimation(.easeInOut(duration:0.16)) {
      session.options.modulePages.move(fromOffsets:IndexSet(integer:source),toOffset:destination > source ? destination+1 : destination)
    }
  }
  func dropUpdated(info:DropInfo)->DropProposal? {DropProposal(operation:.move)}
  func performDrop(info:DropInfo)->Bool {session.draggedPage=nil;return true}
}
extension NSColor {
  var hexString:String {let color=usingColorSpace(.deviceRGB) ?? .black;return String(format:"#%02X%02X%02X",Int(color.redComponent*255),Int(color.greenComponent*255),Int(color.blueComponent*255))}
}

import AppKit
import SwiftUI
import AVKit

final class ModuleDragMemory: ObservableObject {
  var originalStart: Double?
  var originalEnd: Double?
  var original: (Double,Double)?
  var start: Double?
  var active: UUID?
}
struct ModuleCanvas: NSViewRepresentable {
  @ObservedObject var session: ModuleSession
  var video = false
  func makeNSView(context:Context) -> ModuleCanvasView {let view=ModuleCanvasView();view.session=session;view.video=video;return view}
  func updateNSView(_ view:ModuleCanvasView,context:Context) {view.session=session;view.video=video;view.needsDisplay=true}
}
final class ModuleCanvasView: NSView {
  weak var session: ModuleSession?
  var video=false
  var start=CGPoint.zero, previous=CGPoint.zero
  var original:ModuleMark?
  var handle:Int?
  var drawing=false
  var gestureStarted=false
  var cropStart=CGRect.zero
  var freehandMode:Bool {session?.tool == "annotate" && ["draw","highlight"].contains(session?.drawingTool ?? "")}
  var showsSelection:Bool { !freehandMode && session?.showsOriginal != true }
  override var isFlipped:Bool {true}
  override var acceptsFirstResponder:Bool {true}
  override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
  var contentRect:CGRect {
    let source=session?.sourceImage
    let width=Double(source?.width ?? Int(session?.sourceSize.width ?? 1)),height=Double(source?.height ?? Int(session?.sourceSize.height ?? 1))
    let size:CGSize
    if !["crop","redact","annotate"].contains(session?.tool ?? ""),let image=session?.preview {size=image.size}
    else {size=CGSize(width:max(1,width),height:max(1,height))}
    let fillsCatalogueFrame = session?.cataloguePreview == true && session?.tool != "frame"
    let scale = fillsCatalogueFrame
      ? max(bounds.width/max(1,size.width),bounds.height/max(1,size.height))
      : min(bounds.width/max(1,size.width),bounds.height/max(1,size.height))
    let zoom = session?.previewScale ?? 1,offset = session?.previewOffset ?? .zero
    return CGRect(x:(bounds.width-size.width*scale*zoom)/2+offset.width,y:(bounds.height-size.height*scale*zoom)/2+offset.height,width:size.width*scale*zoom,height:size.height*scale*zoom)
  }
  func normalized(_ point:CGPoint) -> CGPoint {let rect=contentRect;return CGPoint(x:min(1,max(0,(point.x-rect.minX)/max(1,rect.width))),y:min(1,max(0,(point.y-rect.minY)/max(1,rect.height))))}
  func mappedRect(_ rect:CGRect) -> CGRect {let box=contentRect;return CGRect(x:box.minX+rect.minX*box.width,y:box.minY+rect.minY*box.height,width:rect.width*box.width,height:rect.height*box.height)}
  override func draw(_ dirtyRect:NSRect) {
    guard let session,let context=NSGraphicsContext.current?.cgContext else {return}
    let rect=contentRect
    let directAnnotations=session.tool == "annotate" && session.sourceImage != nil
    let shown = session.showsOriginal || directAnnotations ? session.sourceImage.map { NSImage(cgImage:$0,size:.zero) } : session.preview
    if (!video || session.cataloguePreview),let image=shown {
      image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    if directAnnotations,!session.showsOriginal,let image=session.sourceImage {
      context.saveGState()
      context.translateBy(x:rect.minX,y:rect.maxY)
      context.scaleBy(x:rect.width/CGFloat(image.width),y:-rect.height/CGFloat(image.height))
      context.clip(to:CGRect(x:0,y:0,width:image.width,height:image.height))
      let engine=Engine()
      for mark in session.options.marks {
        let box=CGRect(x:mark.x*Double(image.width),y:(1-mark.y-mark.height)*Double(image.height),width:mark.width*Double(image.width),height:mark.height*Double(image.height))
        engine.drawAnnotation(mark,in:context,image:image,rect:box)
      }
      context.restoreGState()
    }
    if session.tool == "crop" {
      let width=Double(session.sourceImage?.width ?? max(1,Int(session.sourceSize.width))),height=Double(session.sourceImage?.height ?? max(1,Int(session.sourceSize.height)))
      let crop=mappedRect(CGRect(x:Double(session.options.x)/width,y:Double(session.options.y)/height,width:Double(session.options.width)/width,height:Double(session.options.height)/height))
      let mask=CGMutablePath();mask.addRect(rect);mask.addRect(crop);context.addPath(mask);context.setFillColor(CGColor(gray:0,alpha:0.35));context.fillPath(using:.evenOdd)
      selection(crop,context:context)
    } else if ["redact","annotate"].contains(session.tool) {
      if video {
        for mark in session.options.marks where !mark.blur && session.position>=mark.start && session.position<=mark.end {
          let box=mappedRect(mark.rect);context.setFillColor(NSColor(hex:mark.color).cgColor);context.fill(box)
        }
      }
      if showsSelection,let mark=session.options.marks.first(where:{$0.id==session.selectedMark}) {selection(mappedRect(mark.rect),context:context)}
    }
  }
  func selection(_ rect:CGRect,context:CGContext) {
    context.setStrokeColor(NSColor.systemOrange.cgColor);context.setLineWidth(1.5);context.stroke(rect)
    context.setFillColor(NSColor.systemOrange.cgColor)
    for p in handles(rect) {context.fill(CGRect(x:p.x-3,y:p.y-3,width:6,height:6))}
  }
  func handles(_ r:CGRect) -> [CGPoint] {[CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.midX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.midY),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.midX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.minX,y:r.midY)]}
  override func mouseDown(with event:NSEvent) {
    guard let session,["crop","redact","annotate"].contains(session.tool),!session.busy else {return}
    window?.makeFirstResponder(self)
    let point=convert(event.locationInWindow,from:nil);gestureStarted=false;guard contentRect.insetBy(dx:-8,dy:-8).contains(point) else {return};gestureStarted=true
    start=normalized(point);previous=start;handle=nil;original=nil;drawing=false
    if session.tool == "crop" {
      session.remember()
      let width=Double(session.sourceImage?.width ?? max(1,Int(session.sourceSize.width))),height=Double(session.sourceImage?.height ?? max(1,Int(session.sourceSize.height)))
      cropStart=CGRect(x:Double(session.options.x)/width,y:Double(session.options.y)/height,width:Double(session.options.width)/width,height:Double(session.options.height)/height)
      handle=handles(mappedRect(cropStart)).firstIndex {hypot($0.x-point.x,$0.y-point.y)<9}
      if handle==nil,!cropStart.contains(start) {drawing=true}
      return
    }
    if !freehandMode,let selected=session.options.marks.first(where:{$0.id==session.selectedMark}) {
      handle=handles(mappedRect(selected.rect)).firstIndex {hypot($0.x-point.x,$0.y-point.y)<9}
      if handle != nil {session.remember();original=selected;return}
    }
    if !freehandMode,let mark=session.options.marks.reversed().first(where:{$0.rect.insetBy(dx:-0.01,dy:-0.01).contains(start)}) {session.remember();session.selectedMark=mark.id;original=mark;return}
    if session.tool == "annotate",session.drawingTool == "select" {session.selectedMark=nil;gestureStarted=false;needsDisplay=true;return}
    session.remember()
    var mark=ModuleMark(kind:session.tool == "redact" ? "rectangle" : session.drawingTool,x:start.x,y:start.y,width:0,height:0,color:session.tool == "redact" ? session.options.color : NSColor(session.color).hexString,text:session.options.text,blur:session.options.blur,end:session.duration,points:[ModulePoint(x:start.x,y:start.y)])
    mark.size=session.strokeWidth
    mark.font = session.options.annotationFont; mark.magnification = session.options.annotationMagnification
    if mark.kind == "text" || mark.kind == "number" {mark.size = session.options.fontSize/6}
    if mark.kind == "number" {mark.text=String(session.options.marks.filter {$0.kind=="number"}.count+1)}
    if mark.kind == "text",mark.text.isEmpty {mark.text="Text"}
    session.options.marks.append(mark);session.selectedMark=mark.id;drawing=true
  }
  override func mouseDragged(with event:NSEvent) {
    guard gestureStarted,let session,!session.busy else {return}
    let point=normalized(convert(event.locationInWindow,from:nil))
    if session.tool == "crop" {
      var rect=changed(cropStart,end:point)
      if let ratio = Engine.ratio(session.aspect), drawing || handle != nil {
        let normalizedRatio = ratio*session.sourceSize.height/max(1,session.sourceSize.width)
        rect.size.height = rect.width/max(0.001,normalizedRatio)
        if rect.maxY>1 { rect.size.height = 1-rect.minY; rect.size.width = rect.height*normalizedRatio }
        if rect.maxX>1 { rect.size.width = 1-rect.minX;rect.size.height=rect.width/normalizedRatio }
      }
      let width=Double(session.sourceImage?.width ?? max(1,Int(session.sourceSize.width))),height=Double(session.sourceImage?.height ?? max(1,Int(session.sourceSize.height)))
      session.options.x=Int(rect.minX*width);session.options.y=Int(rect.minY*height)
      session.options.width=max(1,Int(rect.width*width));session.options.height=max(1,Int(rect.height*height))
    } else if let index=session.options.marks.firstIndex(where:{$0.id==session.selectedMark}) {
      var mark=session.options.marks[index]
      let previousRect=mark.rect
      let rect=changed(original?.rect ?? CGRect(origin:start,size:.zero),end:point)
      mark.x=rect.minX;mark.y=rect.minY;mark.width=rect.width;mark.height=rect.height
      if drawing {
        if ["draw","highlight"].contains(mark.kind) {mark.points.append(ModulePoint(x:point.x,y:point.y))}
        else {mark.points=[ModulePoint(x:start.x,y:start.y),ModulePoint(x:point.x,y:point.y)]}
      } else if let original {
        mark.points=original.points.map {p in
          let base=original.rect
          return ModulePoint(x:rect.minX+(p.x-base.minX)/max(0.0001,base.width)*rect.width,y:rect.minY+(p.y-base.minY)/max(0.0001,base.height)*rect.height)
        }
      }
      if ["draw","highlight"].contains(mark.kind),!mark.points.isEmpty {
        let xs=mark.points.map(\.x),ys=mark.points.map(\.y)
        mark.x=xs.min()!;mark.y=ys.min()!;mark.width=max(0,xs.max()!-mark.x);mark.height=max(0,ys.max()!-mark.y)
      }
      if previousRect != mark.rect || drawing {session.options.marks[index]=mark;if session.tool != "annotate" {session.renderPreview()}}
    }
    previous=point;needsDisplay=true
  }
  func changed(_ base:CGRect,end:CGPoint) -> CGRect {
    if drawing {return CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x-start.x),height:abs(end.y-start.y))}
    if let handle {
      var x1=base.minX,y1=base.minY,x2=base.maxX,y2=base.maxY
      if [0,6,7].contains(handle) {x1=min(end.x,x2-0.005)}
      if [2,3,4].contains(handle) {x2=max(end.x,x1+0.005)}
      if [0,1,2].contains(handle) {y1=min(end.y,y2-0.005)}
      if [4,5,6].contains(handle) {y2=max(end.y,y1+0.005)}
      return CGRect(x:max(0,x1),y:max(0,y1),width:min(1,x2)-max(0,x1),height:min(1,y2)-max(0,y1))
    }
    return CGRect(x:min(1-base.width,max(0,base.minX+end.x-start.x)),y:min(1-base.height,max(0,base.minY+end.y-start.y)),width:base.width,height:base.height)
  }
  override func mouseUp(with event:NSEvent) {
    guard gestureStarted,let session else {return}
    defer {gestureStarted=false}
    if session.tool != "crop",let index=session.options.marks.firstIndex(where:{$0.id==session.selectedMark}) {
      if drawing,["draw","highlight"].contains(session.options.marks[index].kind) {
        let point=normalized(convert(event.locationInWindow,from:nil))
        if let last=session.options.marks[index].points.last,last.x != point.x || last.y != point.y {
          session.options.marks[index].points.append(ModulePoint(x:point.x,y:point.y))
        }
        let points=session.options.marks[index].points
        let xs=points.map(\.x),ys=points.map(\.y)
        session.options.marks[index].x=xs.min() ?? point.x;session.options.marks[index].y=ys.min() ?? point.y
        session.options.marks[index].width=(xs.max() ?? point.x)-session.options.marks[index].x
        session.options.marks[index].height=(ys.max() ?? point.y)-session.options.marks[index].y
        session.selectedMark=nil
      } else if session.options.marks[index].width<0.005 || session.options.marks[index].height<0.005 {
        if ["text","number"].contains(session.options.marks[index].kind) {session.options.marks[index].width=min(0.2,1-session.options.marks[index].x);session.options.marks[index].height=min(0.08,1-session.options.marks[index].y)}
        else if ["arrow","draw","highlight"].contains(session.options.marks[index].kind),!session.options.marks[index].points.isEmpty {
          session.options.marks[index].width=max(0.002,session.options.marks[index].width);session.options.marks[index].height=max(0.002,session.options.marks[index].height)
        } else {session.options.marks.remove(at:index);session.selectedMark=nil}
      }
      session.renderPreview()
    }
    original=nil;handle=nil;drawing=false;needsDisplay=true
  }
  override func magnify(with event:NSEvent) {guard let session else {return};session.previewScale=min(8,max(1,session.previewScale*(1+event.magnification)));needsDisplay=true}
  override func scrollWheel(with event:NSEvent) {
    guard let session,session.previewScale>1 else {super.scrollWheel(with:event);return}
    session.previewOffset.width += event.scrollingDeltaX;session.previewOffset.height += event.scrollingDeltaY;needsDisplay=true
  }
  override func keyDown(with event:NSEvent) {
    if event.keyCode==51 || event.keyCode==117 {session?.deleteMark()}
    else if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers=="z" {session?.undo()}
    else {super.keyDown(with:event)}
  }
}
struct ModuleWaveform: View {
  let samples:[Float]
  var tint:Color = .orange
  var body:some View {
    Canvas {context,size in
      var path=Path();let count=max(1,samples.count)
      for (index,value) in samples.enumerated() {let x=Double(index)/Double(count)*size.width;let h=max(1,Double(value)*size.height*0.85);path.move(to:CGPoint(x:x,y:(size.height-h)/2));path.addLine(to:CGPoint(x:x,y:(size.height+h)/2))}
      context.stroke(path,with:.color(tint.opacity(0.8)),lineWidth:max(0.7,min(2,size.width/Double(count)*0.65)))
    }.background(.gray.opacity(0.045),in:RoundedRectangle(cornerRadius:8))
  }
}
struct ModuleTimeline: View {
  @ObservedObject var session:ModuleSession
  var trim=false
  @StateObject private var memory = ModuleDragMemory()
  var body:some View {
    GeometryReader {geo in
      ZStack(alignment:.leading) {
        if session.family == .video,!session.thumbnails.isEmpty {HStack(spacing:0) {ForEach(session.thumbnails.indices,id:\.self) {index in Image(nsImage:session.thumbnails[index]).resizable().scaledToFill().frame(width:geo.size.width/Double(session.thumbnails.count),height:geo.size.height).clipped()}}}
        else {ModuleWaveform(samples:session.waveform)}
        if trim {
          let x=session.options.start/session.duration*geo.size.width
          let end=(session.options.start+session.options.duration)/session.duration*geo.size.width
          Rectangle().fill(.black.opacity(0.3)).frame(width:max(0,x))
          Rectangle().fill(.black.opacity(0.3)).frame(width:max(0,geo.size.width-end)).offset(x:end)
          Rectangle().stroke(.orange,lineWidth:2).frame(width:max(1,end-x)).offset(x:x)
          ForEach([false,true],id:\.self) {isEnd in
            RoundedRectangle(cornerRadius:2).fill(.orange).frame(width:10).overlay(Capsule().fill(.white).frame(width:2,height:18)).offset(x:(isEnd ? end : x)-5)
              .gesture(DragGesture(minimumDistance:0).onChanged {value in
                if memory.originalStart==nil {memory.originalStart=session.options.start;memory.originalEnd=session.options.start+session.options.duration}
                let delta=value.translation.width/geo.size.width*session.duration
                let a=memory.originalStart ?? 0,b=memory.originalEnd ?? session.duration
                if isEnd {session.options.duration=max(0.001,min(session.duration,b+delta)-session.options.start)}
                else {session.options.start=min(b-0.001,max(0,a+delta));session.options.duration=b-session.options.start;session.seek(session.options.start)}
              }.onEnded {_ in memory.originalStart=nil;memory.originalEnd=nil})
          }
        }
        ForEach(session.splitPoints,id:\.self) {time in Rectangle().fill(.orange).frame(width:2).offset(x:time/session.duration*geo.size.width)}
        Rectangle().fill(.white).frame(width:1).shadow(color:.black.opacity(0.7),radius:1).offset(x:session.position/session.duration*geo.size.width)
      }.clipShape(RoundedRectangle(cornerRadius:6)).contentShape(Rectangle())
      .simultaneousGesture(DragGesture(minimumDistance:0).onEnded {value in if !trim {session.seek(value.location.x/geo.size.width*session.duration)}})
    }
  }
}
struct ModuleRangeLane: View {
  @Binding var start:Double
  @Binding var end:Double
  let duration:Double
  let label:String
  var onSeek:((Double)->Void)?
  @StateObject private var memory = ModuleDragMemory()
  var body:some View {
    GeometryReader {geo in
      let x=start/duration*geo.size.width,width=max(12,(end-start)/duration*geo.size.width)
      ZStack(alignment:.leading) {
        RoundedRectangle(cornerRadius:4).fill(.gray.opacity(0.05)).allowsHitTesting(false)
        ZStack {
          RoundedRectangle(cornerRadius:4).fill(.orange.opacity(0.5))
          Text(label).font(.caption2).lineLimit(1).foregroundStyle(.white)
          HStack {Capsule().fill(.white).frame(width:2,height:14);Spacer();Capsule().fill(.white).frame(width:2,height:14)}.padding(.horizontal,5)
        }.frame(width:width).offset(x:x)
        .gesture(DragGesture(minimumDistance:0).onChanged {value in
          if memory.original==nil {memory.original=(start,end)}
          guard let original=memory.original else {return}
          let local=value.startLocation.x,delta=value.translation.width/geo.size.width*duration
          if local<9 {start=max(0,min(original.1-0.001,original.0+delta))}
          else if local>width-9 {end=min(duration,max(original.0+0.001,original.1+delta))}
          else {let length=original.1-original.0;start=max(0,min(duration-length,original.0+delta));end=start+length}
          onSeek?(start)
        }.onEnded {_ in memory.original=nil})
      }
    }
  }
}
struct ModuleBleepLane:View {
  @ObservedObject var session:ModuleSession
  @StateObject private var memory = ModuleDragMemory()
  var body:some View {
    GeometryReader {geo in
      ZStack {
        RoundedRectangle(cornerRadius:5).fill(.gray.opacity(0.04)).contentShape(Rectangle())
          .gesture(DragGesture(minimumDistance:2).onChanged {value in
            let a=max(0,min(session.duration,value.startLocation.x/geo.size.width*session.duration)),b=max(0,min(session.duration,value.location.x/geo.size.width*session.duration))
            if memory.start==nil {session.remember();memory.start=a;var mark=ModuleMark(kind:"bleep",start:a,end:a+0.001);mark.color="#ED7444";memory.active=mark.id;session.options.marks.append(mark)}
            if let i=session.options.marks.firstIndex(where:{$0.id==memory.active}) {session.options.marks[i].start=min(a,b);session.options.marks[i].end=max(a+0.001,b)}
          }.onEnded {_ in memory.start=nil;memory.active=nil})
        ForEach($session.options.marks) {$mark in
          ModuleRangeLane(start:$mark.start,end:$mark.end,duration:session.duration,label:"Bleep",onSeek:session.seek)
            .contextMenu {Button("Delete") {session.options.marks.removeAll {$0.id==mark.id}}}
        }
      }
    }
  }
}

struct ModuleTimeField: NSViewRepresentable {
  @Binding var value:Double
  func makeCoordinator()->Coordinator {Coordinator(value:$value)}
  func makeNSView(context:Context)->NSTextField {
    let field=NSTextField();field.isBordered=false;field.drawsBackground=false
    field.font=NSFont.monospacedSystemFont(ofSize:11,weight:.regular)
    field.stringValue=ModuleContent.time(value);field.delegate=context.coordinator
    field.target=context.coordinator;field.action=#selector(Coordinator.commit(_:))
    field.setAccessibilityLabel("Timecode");return field
  }
  func updateNSView(_ view:NSTextField,context:Context) {context.coordinator.value=$value;if view.currentEditor()==nil {view.stringValue=ModuleContent.time(value)}}
  final class Coordinator:NSObject,NSTextFieldDelegate {
    var value:Binding<Double>
    init(value:Binding<Double>) {self.value=value}
    @objc func commit(_ field:NSTextField) {
      let parts=field.stringValue.replacingOccurrences(of:",",with:".").split(separator:":").compactMap {Double($0)}
      if !parts.isEmpty,parts.count<=3,parts.allSatisfy({$0.isFinite && $0>=0}) {
        let seconds=parts.reduce(0) {$0*60+$1};value.wrappedValue=seconds
      }
      field.stringValue=ModuleContent.time(value.wrappedValue)
    }
    func controlTextDidEndEditing(_ notification:Notification) {if let field=notification.object as? NSTextField {commit(field)}}
  }
}

struct ModuleVideoView:NSViewRepresentable {
  let player:AVPlayer
  func makeNSView(context:Context)->AVPlayerView {
    let view=AVPlayerView();view.controlsStyle = .none;view.videoGravity = .resizeAspect
    view.player=player;view.wantsLayer=true;view.layer?.backgroundColor=NSColor.black.cgColor
    return view
  }
  func updateNSView(_ view:AVPlayerView,context:Context) {if view.player !== player {view.player=player}}
}

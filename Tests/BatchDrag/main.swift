import AppKit
import Foundation

// Exercise the real NSDraggingDestination methods without opening a test app or
// touching Finder's drag pasteboard, the clipboard, or the installed application.
final class DragInfo: NSObject, NSDraggingInfo {
  let draggingPasteboard: NSPasteboard
  var draggingLocation: NSPoint
  var draggingSequenceNumber = 1
  var draggingSourceOperationMask: NSDragOperation = [.copy, .generic]
  var draggingDestinationWindow: NSWindow? { nil }
  var draggingSource: Any? { nil }
  var draggedImage: NSImage? { nil }
  var draggedImageLocation: NSPoint { draggingLocation }
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 0
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }
  init(_ pb: NSPasteboard, point: NSPoint) { draggingPasteboard=pb; draggingLocation=point }
  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func resetSpringLoading() {}
  func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
var checks=0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !condition() { fputs("FAIL: \(message)\n",stderr); exit(1) }
}
let root=FileManager.default.temporaryDirectory.appendingPathComponent("clementine-batch-drag-"+UUID().uuidString)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:root) }
let engine=Engine()
let image=try engine.canvas(width:16,height:12) { c in c.setFillColor(NSColor.orange.cgColor); c.fill(CGRect(x:0,y:0,width:16,height:12)) }
let files=try (1...100).map { i -> URL in
  let u=root.appendingPathComponent("Image été \(i).png")
  try engine.saveImage(image,to:u,o:Options()); return u
}
for count in [1,10,11,25,100] {
  for changesAtRelease in [false,true] {
    let pb=NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }
    var session=WheelDragSession(pasteboardGeneration:pb.changeCount)
    let preview=Array(files.prefix(min(count,10)))
    pb.clearContents(); check(pb.writeObjects(preview as [NSURL]),"publish initial selection")
    _=session.sample(down:true,flags:.shift,generation:pb.changeCount,containsFiles:true,resolve:{ _ in "formats" })
    let id=session.id, oldGeneration=pb.changeCount
    let choices=Compatibility.targets(preview).map { WheelItem(title:$0,icon:"",action:"convert:"+$0) }
    let wheel=WheelView(frame:CGRect(x:0,y:0,width:272,height:272),urls:preview,items:choices,preview:false)
    let jpg=choices.firstIndex { $0.action == "convert:jpg" }!
    let info=DragInfo(pb,point:WheelGeometry.point(84,WheelGeometry.angle(jpg,count:choices.count),center:wheel.center))
    var down=true, commits=0, delivered:[URL]=[], chosen=""
    wheel.onRefresh={
      _=session.sample(down:down,flags:[],generation:pb.changeCount,containsFiles:true,resolve:{ _ in nil })
    }
    wheel.onValidate={ session.acceptsDrop(id:id,generation:$0.draggingPasteboard.changeCount) }
    wheel.onChoose={ item, urls, generation in
      guard let generation, session.commit(id:id,generation:generation) else { return false }
      commits += 1;delivered=urls;chosen=item.action;return true
    }
    check(!wheel.draggingEntered(info).isEmpty,"native entry accepts selection of \(count)")
    // Finder completes/reorders its selection after the preview was created.
    let final=Array(files.prefix(count).reversed())
    pb.clearContents(); check(pb.writeObjects(final as [NSURL]),"publish complete selection")
    if changesAtRelease { down=false }
    check(wheel.prepareForDragOperation(info),"prepare follows final generation even at release")
    check(!session.acceptsDrop(id:id,generation:oldGeneration),"obsolete generation is rejected")
    check(wheel.performDragOperation(info),"native drop succeeds for \(count) files")
    check(delivered==final && chosen=="convert:jpg","drop delivers every file, in final order")
    check(!wheel.performDragOperation(info) && commits==1,"drop can only commit once")
    var options=Options();options.outputFolder=root.appendingPathComponent("output-\(count)-\(changesAtRelease)").path
    try FileManager.default.createDirectory(atPath:options.outputFolder,withIntermediateDirectories:true)
    let outputs=try engine.run(delivered,action:chosen,options:options)
    check(outputs.count==count,"one JPEG generated per input")
    check(outputs.allSatisfy { NSImage(contentsOf:$0) != nil && $0.pathExtension=="jpg" },"all converted files are readable")
    check(final.allSatisfy { FileManager.default.fileExists(atPath:$0.path) },"originals remain intact")
  }
}
// Incomplete promised data cannot silently produce only part of a batch.
let incomplete=NSPasteboard.withUniqueName()
defer { incomplete.releaseGlobally() }
final class MissingURLProvider: NSObject, NSPasteboardItemDataProvider {
  func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {}
}
let provider=MissingURLProvider()
let ready=NSPasteboardItem();ready.setString(files[0].absoluteString,forType:.fileURL)
let missing=NSPasteboardItem();missing.setDataProvider(provider,forTypes:[.fileURL])
incomplete.writeObjects([ready,missing])
check(WheelDropPayload(pasteboard:incomplete)==nil,"reject incomplete file payload")
// A different native gesture, cancelled gesture, or centre drop cannot execute.
let pb=NSPasteboard.withUniqueName();defer {pb.releaseGlobally()};pb.writeObjects(files.prefix(25).map {$0 as NSURL})
let wheel=WheelView(frame:CGRect(x:0,y:0,width:272,height:272),urls:files,items:[WheelItem(title:"JPG",icon:"",action:"convert:jpg")],preview:false)
var commits=0;wheel.onChoose={ _,_,_ in commits += 1;return true }
let info=DragInfo(pb,point:WheelGeometry.point(84,WheelGeometry.angle(0,count:1),center:wheel.center))
check(!wheel.draggingEntered(info).isEmpty,"first native sequence enters")
info.draggingSequenceNumber=2
check(!wheel.performDragOperation(info) && commits==0,"different native sequence is rejected")
info.draggingSequenceNumber=1;info.draggingLocation=wheel.center
check(!wheel.performDragOperation(info) && commits==0,"centre is never a drop button")
wheel.onValidate={_ in false};info.draggingLocation=WheelGeometry.point(84,WheelGeometry.angle(0,count:1),center:wheel.center)
check(!wheel.performDragOperation(info) && commits==0,"cancelled drag is rejected")
// Finder enters at the empty centre because the wheel opens under the pointer.
// Keep negotiating the file drag there, but never execute a centre/gutter drop.
for count in [1, 10, 14, 31, 100] {
  let board = NSPasteboard.withUniqueName()
  defer { board.releaseGlobally() }
  board.writeObjects(files.prefix(count).map { $0 as NSURL })
  let destination = WheelView(frame: CGRect(x: 0, y: 0, width: 272, height: 272),
    urls: Array(files.prefix(count)), items: [WheelItem(title: "PNG", icon: "", action: "convert:png"),
      WheelItem(title: "PDF", icon: "", action: "convert:pdf")], preview: false)
  let dragInfo = DragInfo(board, point: destination.center)
  var executions = 0
  destination.onChoose = { _, input, _ in executions += 1; return input.count == count }
  check(!destination.draggingEntered(dragInfo).isEmpty, "centre entry keeps Finder's \(count)-file gesture")
  check(destination.selected == nil, "centre is not highlighted")
  check(!destination.prepareForDragOperation(dragInfo), "centre cannot prepare a drop")
  check(!destination.performDragOperation(dragInfo) && executions == 0, "centre never executes")
  dragInfo.draggingLocation = WheelGeometry.point(84, WheelGeometry.angle(0, count: 2), center: destination.center)
  check(!destination.draggingUpdated(dragInfo).isEmpty && destination.selected == 0, "native hover selects the accepted petal")
  let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
  destination.mouseExited(with: exit)
  check(destination.selected == 0, "unrelated mouse tracking cannot clear native drag selection")
  destination.draggingExited(dragInfo)
  check(destination.selected == nil, "native drag exit clears hover")
  check(!destination.draggingEntered(dragInfo).isEmpty && destination.selected == 0, "native reentry restores hover")
  check(destination.prepareForDragOperation(dragInfo), "same highlighted petal accepts drop")
  check(destination.performDragOperation(dragInfo) && executions == 1, "centre-to-petal batch executes once")
}
print("PASS \(checks) batch drag checks; 1/10/11/14/25/31/100 files, centre entry, native hover ownership, late payloads, reordered URLs and 294 real image conversions")

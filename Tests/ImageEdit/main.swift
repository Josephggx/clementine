import AppKit
import SwiftUI
import Foundation

let root=FileManager.default.temporaryDirectory.appendingPathComponent("clementine-image-edit-"+UUID().uuidString)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:root)}
let engine=Engine()
var checks=0
func check(_ condition: @autoclosure () -> Bool,_ message:String) {
  checks += 1
  if !condition() {fputs("FAIL: \(message)\n",stderr);exit(1)}
}
func waitUntil(_ predicate:()->Bool) {
  let end=Date().addingTimeInterval(15)
  while !predicate(),Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
  check(predicate(),"asynchronous operation finishes")
}
func pixels(_ image:CGImage)->Data {
  let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,
    bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
  return Data(bytes:context.data!,count:image.width*image.height*4)
}
let source=try engine.canvas(width:400,height:300) {c in
  c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:0,y:0,width:400,height:300))
  c.setFillColor(NSColor.blue.cgColor);c.fill(CGRect(x:0,y:0,width:40,height:300))
}
let input=root.appendingPathComponent("Photo.png"), second=root.appendingPathComponent("Second.png")
try engine.saveImage(source,to:input,o:Options())
try engine.saveImage(source,to:second,o:Options())
let original=try Data(contentsOf:input)
let crop=ModuleCrop(x:100,y:50,width:200,height:150)
let mark=ModuleMark(kind:"draw",x:0.375,y:0.333333333,width:0.25,height:0,color:"#FF0000",size:6,
  points:[ModulePoint(x:0.375,y:1.0/3),ModulePoint(x:0.625,y:1.0/3)])
func session(_ files:[URL]=[input])->ModuleSession {
  let s=ModuleSession(tool:"annotate",files:files,defaults:Options(),reveal:false,cataloguePreview:true)
  s.sourceImage=source;s.sourceSize=CGSize(width:400,height:300)
  s.preview=NSImage(cgImage:source,size:.zero)
  s.options.marks=[];s.options.x=0;s.options.y=0;s.options.width=400;s.options.height=300
  s.options.outputFolder=root.appendingPathComponent(UUID().uuidString).path
  return s
}
func setCrop(_ s:ModuleSession) {
  s.setImageEditMode("crop");s.remember()
  s.options.x=crop.x;s.options.y=crop.y;s.options.width=crop.width;s.options.height=crop.height
}
func addMark(_ s:ModuleSession) {s.setImageEditMode("annotate");s.remember();s.options.marks.append(mark)}
let cropFirst=session();setCrop(cropFirst);addMark(cropFirst)
let annotateFirst=session();addMark(annotateFirst);setCrop(annotateFirst)
let a=try engine.moduleImage(source,action:"annotate",options:cropFirst.options)
let b=try engine.moduleImage(source,action:"annotate",options:annotateFirst.options)
check(a.width==200 && a.height==150,"combined export has crop dimensions")
check(pixels(a)==pixels(b),"crop → annotate and annotate → crop produce identical pixels")
let ref=NSBitmapImageRep(cgImage:a)
check(ref.colorAt(x:100,y:50)!.redComponent>0.9 && ref.colorAt(x:100,y:50)!.greenComponent<0.2,"annotation remains at its source position after crop")
check(ref.colorAt(x:100,y:90)!.greenComponent>0.9,"uncorrupted image away from annotation")
let snapshot=cropFirst.currentImageEdit
for _ in 0..<15 {cropFirst.setImageEditMode("crop");cropFirst.setImageEditMode("annotate")}
check(cropFirst.currentImageEdit==snapshot,"repeated tab switches do not transform or flatten marks")
let canvas=ModuleCanvasView(frame:CGRect(x:0,y:0,width:400,height:300));canvas.session=cropFirst
check(canvas.contentRect==CGRect(x:-200,y:-100,width:800,height:600),"cropped canvas maps original coordinates")
let p=canvas.normalized(CGPoint(x:200,y:100))
check(abs(p.x-0.5)<0.0001 && abs(p.y-1.0/3)<0.0001,"pointer maps to same source coordinates in cropped view")
check(canvas.visibleImageRect==canvas.bounds,"cropped preview fills expected frame without leaking margins")
cropFirst.setImageEditMode("crop")
check(canvas.contentRect==CGRect(x:0,y:0,width:400,height:300),"Crop returns to original image for reversible framing")
check(cropFirst.options.marks==snapshot.marks,"marks survive expanding crop")
cropFirst.setImageEditMode("annotate")

// Drive actual canvas mouse handlers offscreen: no NSWindow or test app is created.
func event(_ type:NSEvent.EventType,_ p:CGPoint)->NSEvent {
  NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
let drawn=session();setCrop(drawn);drawn.setImageEditMode("annotate");drawn.drawingTool="draw"
canvas.session=drawn
canvas.mouseDown(with:event(.leftMouseDown,CGPoint(x:100,y:100)))
canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:200,y:140)))
canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:300,y:180)))
check(drawn.options.marks.count==1,"freehand gesture creates one annotation on cropped image")
check(abs(drawn.options.marks[0].points[0].x-0.375)<0.0001,"freehand points saved in source coordinates")
check(drawn.selectedMark==nil,"freehand ends without selection rectangle")
let drawnState=drawn.currentImageEdit
drawn.setImageEditMode("crop")
canvas.mouseDown(with:event(.leftMouseDown,CGPoint(x:100,y:50)))
canvas.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:120,y:60)))
canvas.mouseUp(with:event(.leftMouseUp,CGPoint(x:120,y:60)))
check(drawn.options.x==120 && drawn.options.y==60,"crop handles move while preserving annotations")
check(drawn.options.marks==drawnState.marks,"crop mouse gesture leaves marks unchanged")
drawn.undo();check(drawn.currentImageEdit==drawnState,"undo restores crop and annotations together")
drawn.reset();check(drawn.options.marks.isEmpty && drawn.options.width==400 && drawn.options.height==300,"reset restores full original")
drawn.undo();check(drawn.currentImageEdit==drawnState,"reset can be undone")
let onlyCrop=session();setCrop(onlyCrop);check(onlyCrop.canSave,"crop-only editing can save with no annotations")
let full=session();check(full.canSave,"unmodified full image can save")
let unmodified=try engine.moduleImage(source,action:"annotate",options:full.options)
check(pixels(unmodified)==pixels(source),"no edits preserves image pixels")
let undo=session();addMark(undo);setCrop(undo);undo.undo()
check(undo.options.width==400 && undo.options.marks==[mark],"undo crop keeps earlier annotations")
undo.undo();check(undo.options.marks.isEmpty,"undo earlier annotation")

// Export using the same asynchronous Save path as the module, in either mode.
for s in [cropFirst,annotateFirst,onlyCrop] {
  var closed=false;s.close={closed=true};s.export()
  waitUntil { !s.busy }
  check(s.error==nil && closed,"Save completes and closes module without Finder activation")
  let out=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:s.options.outputFolder),includingPropertiesForKeys:nil).first!
  let exported=try engine.loadImage(out)
  check(exported.width==200 && exported.height==150,"saved file uses current crop in either tab")
  if !s.options.marks.isEmpty {check(pixels(exported)==pixels(a),"saved image contains annotations and crop")}
}

let batch=session([input,second]);setCrop(batch);addMark(batch);batch.selectCropFile(1)
waitUntil { !batch.busy }
check(batch.options.marks.isEmpty && batch.options.width==400,"next file starts with its own edits")
batch.setImageEditMode("crop");batch.options.x=0;batch.options.y=0;batch.options.width=80;batch.options.height=70
batch.selectCropFile(0);waitUntil { !batch.busy }
check(batch.currentImageEdit==snapshot,"return to first file restores its crop and marks")
check(!batch.undoStack.isEmpty,"undo history stays with its file")
batch.persistImageEdit()
let outputs=try engine.run(batch.files,action:"annotate",options:batch.options)
let firstResult=try engine.loadImage(outputs[0]),secondResult=try engine.loadImage(outputs[1])
check(firstResult.width==200 && firstResult.height==150,"batch first crop")
check(secondResult.width==80 && secondResult.height==70,"batch second crop")
check(pixels(firstResult)==pixels(a),"batch annotation only belongs to first file")
let secondRef=NSBitmapImageRep(cgImage:secondResult)
check(secondRef.colorAt(x:60,y:40)!.greenComponent>0.9,"second file has no leaked annotation")

for invalid in [ModuleCrop(x:-1,y:0,width:100,height:100),ModuleCrop(x:399,y:0,width:20,height:20),ModuleCrop(x:0,y:0,width:0,height:100)] {
  var o=Options();o.x=invalid.x;o.y=invalid.y;o.width=invalid.width;o.height=invalid.height
  do {_=try engine.moduleImage(source,action:"annotate",options:o);check(false,"invalid crop rejected")} catch {check(true,"invalid crop rejected")}
}
full.options.x=399;full.options.width=500;full.options.y = -2;full.options.height = -10;full.clampImageCrop()
check(full.options.x==399 && full.options.width==1 && full.options.y==0 && full.options.height==1,"numeric crop bounds are clamped safely")
let large=try engine.resize(source,width:2400,height:1800)
var largeOptions=cropFirst.options;largeOptions.x*=6;largeOptions.y*=6;largeOptions.width*=6;largeOptions.height*=6
let largePreview=try engine.moduleImage(large,action:"annotate",options:largeOptions,preview:true)
check(largePreview.width==600 && largePreview.height==450,"large preview scales crop as well as original")
let after=try Data(contentsOf:input)
check(after==original,"all operations leave original file unchanged")
check(Tool.available([input]).contains {$0.id=="annotate" && $0.wheelTitle=="EDIT" && $0.icon=="pencil.tip"},"Edit keeps annotation icon")
check(!Tool.available([input]).contains {$0.id=="crop"},"no separate image Crop action")
check(!Tool.catalogue(for:input).contains {$0.id=="crop"},"no separate image Crop in catalogue")
check(Tool.available([input,second]).contains {$0.id=="annotate"},"batch crop remains available through Edit")
// Real loading and Finder lifecycle, using only temporary fixtures.
let tracked=ModuleSession(tool:"annotate",files:[input,second],defaults:Options(),reveal:false)
waitUntil { !tracked.loading }
check(tracked.options.width==400 && tracked.options.height==300,"real load initializes full crop")
setCrop(tracked);addMark(tracked)
let renamed=root.appendingPathComponent("Renamed.png")
try FileManager.default.moveItem(at:input,to:renamed)
tracked.reconcileFiles(.init(urls:[renamed,second],renamed:[input:renamed],removed:[],metadataChanged:true))
check(tracked.options.moduleImageEdits?[input.path]==nil && tracked.options.moduleImageEdits?[renamed.path]==snapshot,"Finder rename preserves edits under new path")
tracked.selectCropFile(1);waitUntil { !tracked.busy }
tracked.options.width=80;tracked.options.height=70
tracked.selectCropFile(0);waitUntil { !tracked.busy }
check(tracked.currentImageEdit==snapshot,"renamed file still restores its own edits")
tracked.reconcileFiles(.init(urls:[second],renamed:[:],removed:[renamed],metadataChanged:false))
waitUntil { !tracked.loading }
check(tracked.options.width==80 && tracked.options.height==70 && tracked.options.marks.isEmpty,"removing active file restores survivor without stale annotations")
var cancelled=false;tracked.close={cancelled=true}
tracked.reconcileFiles(.init(urls:[],renamed:[:],removed:[second],metadataChanged:false))
check(cancelled,"removing last file closes editor")
try FileManager.default.moveItem(at:renamed,to:input)
let invalidFile=root.appendingPathComponent("Unreadable.png")
try Data("not an image".utf8).write(to:invalidFile)
let failed=session([input,invalidFile]);addMark(failed);failed.selectCropFile(1)
waitUntil { !failed.busy }
check(failed.error != nil && !failed.canSave,"failed image load never saves previous image edits onto wrong file")
failed.selectCropFile(0);waitUntil { !failed.busy }
check(failed.options.marks==[mark],"return from unreadable image preserves previous edits")
let untouched=session();var closedWithoutSave=false;untouched.close={closedWithoutSave=true};untouched.cancel()
check(closedWithoutSave && !FileManager.default.fileExists(atPath:untouched.options.outputFolder),"Cancel produces no output")
for kind in ["arrow","draw","highlight","rectangle","ellipse","text","number","magnifier","image"] {
  var o=cropFirst.options
  o.marks=[ModuleMark(kind:kind,x:0.3,y:0.3,width:0.2,height:0.2,color:"#FF0000",text:kind == "image" ? input.path : "A",points:[ModulePoint(x:0.3,y:0.3),ModulePoint(x:0.5,y:0.5)])]
  let output=try engine.moduleImage(source,action:"annotate",options:o)
  check(output.width==200 && output.height==150,"\(kind) works with crop")
}
let encoded=try JSONEncoder().encode(batch.options)
let decoded=try JSONDecoder().decode(Options.self,from:encoded)
check(decoded.moduleImageEdits==batch.options.moduleImageEdits,"per-file edits survive option encoding")
// Offscreen canvas image for inspecting crop clipping and annotations. No window is created.
canvas.session=cropFirst
canvas.frame=CGRect(x:0,y:0,width:400,height:420)
let context=CGContext(data:nil,width:400,height:420,bitsPerComponent:8,bytesPerRow:1600,
  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(NSColor.darkGray.cgColor);context.fill(CGRect(x:0,y:0,width:400,height:420))
context.translateBy(x:0,y:420);context.scaleBy(x:1,y:-1)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
canvas.draw(canvas.bounds)
NSGraphicsContext.restoreGraphicsState()
if let path=ProcessInfo.processInfo.environment["EDIT_CANVAS_SNAPSHOT"] {
  try engine.saveImage(context.makeImage()!,to:URL(fileURLWithPath:path),o:Options())
}
print("PASS: \(checks) image editing checks; no app window opened")

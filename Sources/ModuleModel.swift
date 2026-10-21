import AppKit
import SwiftUI
import AVFoundation
import PDFKit
import Vision
import ImageIO

struct MetadataRow: Identifiable {
  var id: String { key }
  let key: String
  let group: String
  let name: String
  var value: String
  var original: String
  var removed = false
  var editable = true
  var label: String { name.replacingOccurrences(of:"([a-z0-9])([A-Z])",with:"$1 $2",options:.regularExpression) }
}
struct ModuleSpecification {
  let title: String, button: String
  let width: CGFloat, height: CGFloat
  static func get(_ tool: String, family: Family) -> ModuleSpecification {
    if tool == "split", family == .pdf { return .init(title:"Split PDF",button:"Split",width:640,height:660) }
    let video = family == .video
    let values: [String: (String,String,CGFloat,CGFloat)] = [
      "compress": ("Compress","Compress",380,375), "strip": ("Metadata","Save",480,540),
      "adjust": ("Edit Photo","Save Edited Copy",480,787),
      "annotate": ("Annotate Photo","Save Annotated Copy",440,728),
      "frame": ("Add BG","Save with Background",440,650),
      "crop": (video ? "Crop Video" : "Crop Image","Apply",400,video ? 663 : 605),
      "redact": (video ? "Redact Video" : "Redact Photo","Save Redacted Copy",400,video ? 850 : 741),
      "collage": ("Create Collage","Create Collage",400,696),
      "trim": (video ? "Trim Video" : "Trim Audio","Apply",400,video ? 682 : 336),
      "speed": ("Change Video Speed","Apply",400,670),
      "join": (video ? "Assembler les vidéos" : "Assembler les audios", "Assembler",320,298),
      "snapshot": ("Video Snapshots","Save Frames",400,676),
      "split": ("Split Video","Split Video",400,650),
      "normalize": ("Normalize Volume","Normalize Audio",400,611),
      "visualize": ("Audio Visualizer","Create Visualization",400,631),
      "channels": ("Convert Audio Channels","Apply",400,400),
      "bleep": ("Bleep Audio","Save Bleeped Copy",400,400),
      "mergepdf": ("Merge","Créer le PDF",320,298),
      "archive": ("ZIP","Créer le ZIP",360,230),
      "organize": ("Organize PDF","Save Organized PDF",560,600)
    ]
    let v = values[tool] ?? (tool, "Apply",400,400)
    return .init(title:v.0,button:v.1,width:v.2,height:v.3)
  }
}

final class ModuleSession: ObservableObject, Identifiable, @unchecked Sendable {
  let id = UUID()
  let tool: String
  let family: Family
  let cataloguePreview: Bool
  @Published var files: [URL]
  @Published var options: Options
  @Published var preview: NSImage?
  @Published var sourceImage: CGImage?
  @Published var activeFile = 0
  @Published var fileThumbnails: [URL:NSImage] = [:]
  @Published var sourceSize = CGSize(width:1,height:1)
  @Published var waveform: [Float] = []
  @Published var leftWaveform: [Float] = []
  @Published var rightWaveform: [Float] = []
  @Published var thumbnails: [NSImage] = []
  @Published var duration = 1.0
  @Published var frameDuration = 1.0/30.0
  @Published var position = 0.0
  @Published var previewScale = 1.0
  @Published var previewOffset = CGSize.zero
  @Published var showsOriginal = false
  @Published var playing = false
  @Published var busy = false
  @Published var loading = true
  @Published var progress = 0.0
  @Published var error: String?
  @Published var metadata: [MetadataRow] = []
  @Published var metadataCanEdit = false
  @Published var search = ""
  @Published var selectedMark: UUID?
  @Published var drawingTool = "arrow"
  @Published var strokeWidth = 4.0
  @Published var color: Color = .red
  @Published var aspect = "Free"
  @Published var targetEnabled = false
  @Published var targetMode = "File size"
  @Published var targetUnit = "MB"
  @Published var targetValue = 1.0
  @Published var reduction = 50.0
  @Published var imageSize = "Keep original dimensions"
  @Published var splitPoints: [Double] = []
  @Published var equalClips = 2
  @Published var frames: [Double] = []
  @Published var frameThumbnails: [Double:NSImage] = [:]
  var autoTrimOriginal: (Double,Double)?
  var silenceGeneration = UUID()
  @Published var splitThumbnails: [URL: [Int:NSImage]] = [:]
  @Published var pageThumbnails: [Int:NSImage] = [:]
  @Published var hoveredPage: UUID?
  @Published var draggedPage: ModulePage?
  @Published var undoStack: [[ModuleMark]] = []
  let player = AVPlayer()
  var close: (() -> Void)?
  var reveal = true
  private var playerObserver: Any?
  private var previewTask: DispatchWorkItem?
  private var previewGeneration = UUID()
  private var token: CancellationToken?
  private var previewToken: CancellationToken?
  private var scratch = FileManager.default.temporaryDirectory.appendingPathComponent("clementine-module-" + UUID().uuidString)
  init(tool: String, files: [URL], defaults: Options, reveal: Bool,
       cataloguePreview: Bool = false) {
    self.tool = tool; self.files = files; self.family = Family.of(files[0])
    self.cataloguePreview = cataloguePreview; self.reveal = reveal
    var o = Options(); o.moduleEditor = true; o.outputFolder = defaults.outputFolder
    o.quality = defaults.quality; o.strip = defaults.strip
    o.archiveFormat = defaults.archiveFormat
    o.padding = tool == "frame" ? 160 : 8
    if tool == "collage" { o.corners = 0; o.background = "#FFFFFF"; o.canvasRatio = "Square · 1:1" }
    o.color = tool == "redact" ? "#000000" : "#ED7444"
    self.options = o
    self.color = Color(nsColor:NSColor(hex:o.color))
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    if !cataloguePreview && tool != "strip" && (family == .video || family == .audio) {
      player.replaceCurrentItem(with: AVPlayerItem(url: files[0]))
      playerObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds:0.03,preferredTimescale:600),queue:.main) { [weak self] time in
        guard let self else { return }
        self.position = max(0,time.seconds.isFinite ? time.seconds : 0)
        if self.tool == "trim", self.position >= self.options.start + self.options.duration { self.pause() }
        if self.position >= self.duration { self.pause() }
      }
    }
    if cataloguePreview { prepareCataloguePreview() } else { load() }
  }
  deinit {
    if let playerObserver { player.removeTimeObserver(playerObserver) }
    player.pause(); token?.cancel(); previewToken?.cancel(); previewTask?.cancel()
    let path = scratch
    DispatchQueue.global().async { try? FileManager.default.removeItem(at:path) }
  }
  var specification: ModuleSpecification { .get(tool,family:family) }
  var canSave: Bool {
    if busy || loading { return false }
    switch tool {
    case "annotate", "redact", "bleep": return !options.marks.isEmpty
    case "snapshot": return !frames.isEmpty
    case "split":
      if family == .pdf {
        return files.allSatisfy { file in
          guard let thumbs = splitThumbnails[file], !thumbs.isEmpty else { return false }
          return ["png","jpg"].contains(options.pdfSplitFormat) || options.pdfSplitMode == "pages" ||
            PDFSplitLayout.isComplete(options.pdfSplitGroups[file.path] ?? [], count: thumbs.count)
        }
      }
      return !splitPoints.isEmpty
    case "organize": return !options.modulePages.isEmpty
    default: return true
    }
  }
  private func prepareCataloguePreview() {
    loading = false
    duration = 32
    position = 8
    options.duration = 24
    options.start = 4
    sourceSize = CGSize(width: 1200, height: 800)
    options.width = 1200
    options.height = 800
    waveform = (0..<120).map { index in
      let wave = abs(sin(Double(index) * 0.31))
      return Float(0.18 + wave * (0.38 + 0.34 * abs(sin(Double(index) * 0.071))))
    }
    leftWaveform = waveform
    rightWaveform = waveform.enumerated().map { index, value in
      min(1, value * Float(0.72 + 0.24 * abs(sin(Double(index) * 0.17))))
    }

    if family == .image || family == .video {
      let image = Self.catalogueImage()
      sourceSize = CGSize(width: image.width, height: image.height)
      options.width = image.width
      options.height = image.height
      sourceImage = image
      let displayedImage = tool == "collage" ? Self.catalogueCollage(image) : image
      preview = NSImage(cgImage: displayedImage, size: .zero)
    }
    if tool == "strip" {
      metadataCanEdit = family == .image
      metadata = [
        MetadataRow(key:"File.Name",group:"File",name:"Name",value:files[0].lastPathComponent,original:files[0].lastPathComponent,editable:false),
        MetadataRow(key:"File.Size",group:"File",name:"Size",value:"2.5 MB",original:"2.5 MB",editable:false),
        MetadataRow(key:"Exif.DateTimeOriginal",group:"ExifIFD",name:"DateTimeOriginal",value:"2026:10:19 14:32:08",original:"2026:10:19 14:32:08"),
        MetadataRow(key:"Exif.Make",group:"ExifIFD",name:"Make",value:"Apple",original:"Apple"),
      ]
    }
    if tool == "organize" {
      options.modulePages = (0..<3).map { ModulePage(index:$0) }
      let image = NSImage(cgImage:Self.cataloguePage(),size:.zero)
      pageThumbnails = Dictionary(uniqueKeysWithValues:(0..<3).map {($0,image)})
    }
    if tool == "split" {
      if family == .pdf {
        let image = NSImage(cgImage:Self.cataloguePage(),size:.zero)
        for file in files {
          splitThumbnails[file] = Dictionary(uniqueKeysWithValues:(0..<4).map { ($0,image) })
          options.pdfSplitGroups[file.path] = PDFSplitLayout.individual(count:4)
        }
      } else { splitPoints = [10, 21] }
    }
    if tool == "snapshot" { frames = [8, 18] }
    if tool == "annotate" {
      drawingTool = "draw"
      options.marks = [ModuleMark(kind:"draw",x:0.18,y:0.25,width:0.42,height:0.25,
        color:"#ED7444",size:4,points:[ModulePoint(x:0,y:0.5),ModulePoint(x:0.25,y:0.1),ModulePoint(x:0.55,y:0.75),ModulePoint(x:1,y:0.3)])]
    }
    if tool == "redact" {
      options.marks = [ModuleMark(kind:"rectangle",x:0.2,y:0.3,width:0.42,height:0.17,
        color:"#000000",size:4)]
    }
    if tool == "bleep" {
      options.marks = [ModuleMark(kind:"rectangle",x:0,y:0,width:0,height:0,
        color:"#ED7444",size:4,start:8,end:14)]
    }
    if family == .image, ["adjust", "frame", "redact"].contains(tool) { renderPreview() }
  }
  private static func catalogueImage() -> CGImage {
    if let url = Bundle.main.url(forResource: "clementine-demo", withExtension: "jpg",
      subdirectory: "Demo"), let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      return cgImage
    }
    let width = 1200, height = 800
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
      bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(colorsSpace:space,colors:[
      NSColor(calibratedRed:0.98,green:0.47,blue:0.20,alpha:1).cgColor,
      NSColor(calibratedRed:0.55,green:0.17,blue:0.30,alpha:1).cgColor,
      NSColor(calibratedRed:0.10,green:0.12,blue:0.23,alpha:1).cgColor,
    ] as CFArray,locations:[0,0.56,1])!
    context.drawLinearGradient(gradient,start:CGPoint(x:80,y:760),end:CGPoint(x:1120,y:40),options:[])
    context.setFillColor(NSColor.white.withAlphaComponent(0.20).cgColor)
    context.fillEllipse(in:CGRect(x:155,y:155,width:300,height:300))
    context.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    context.fill(CGRect(x:610,y:155,width:390,height:440))
    return context.makeImage()!
  }
  private static func catalogueCollage(_ image: CGImage) -> CGImage {
    let width = 1200, height = 1200
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
      bytesPerRow:width*4,space:space,
      bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x:0,y:0,width:width,height:height))
    let gap: CGFloat = 16
    let cells = [
      CGRect(x:0,y:0,width:(CGFloat(width)-gap)/2,height:CGFloat(height)),
      CGRect(x:(CGFloat(width)+gap)/2,y:0,width:(CGFloat(width)-gap)/2,height:CGFloat(height)),
    ]
    for cell in cells {
      context.saveGState()
      context.clip(to:cell)
      let scale = max(cell.width/CGFloat(image.width),cell.height/CGFloat(image.height))
      let size = CGSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
      context.draw(image,in:CGRect(x:cell.midX-size.width/2,y:cell.midY-size.height/2,
        width:size.width,height:size.height))
      context.restoreGState()
    }
    return context.makeImage()!
  }
  private static func cataloguePage() -> CGImage {
    let width = 700, height = 980
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
      bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:width,height:height))
    context.setFillColor(NSColor(calibratedWhite:0.18,alpha:1).cgColor)
    context.fill(CGRect(x:75,y:830,width:310,height:24))
    context.setFillColor(NSColor(calibratedWhite:0.72,alpha:1).cgColor)
    for row in 0..<10 {context.fill(CGRect(x:75,y:760-row*54,width:550-(row%3)*55,height:11))}
    context.setFillColor(NSColor(calibratedRed:0.96,green:0.39,blue:0.17,alpha:0.82).cgColor)
    context.fill(CGRect(x:75,y:120,width:550,height:210))
    return context.makeImage()!
  }
  func load() {
    let url = files[0], tool = tool, family = family
    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      do {
        if tool != "strip" && tool != "archive" && family == .image {
          if tool == "crop",self.files.count>1 {
            var crops:[String:ModuleCrop]=[:],thumbnails:[URL:NSImage]=[:]
            for file in self.files {
              if let source=CGImageSourceCreateWithURL(file as CFURL,nil),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] {
                var w=properties[kCGImagePropertyPixelWidth] as? Int ?? 1,h=properties[kCGImagePropertyPixelHeight] as? Int ?? 1
                if [5,6,7,8].contains(properties[kCGImagePropertyOrientation] as? Int ?? 1) {swap(&w,&h)}
                crops[file.path]=ModuleCrop(x:0,y:0,width:w,height:h)
                if let thumb=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:120] as CFDictionary) {thumbnails[file]=NSImage(cgImage:thumb,size:.zero)}
              }
            }
            DispatchQueue.main.async {self.options.moduleCrops=crops;self.fileThumbnails=thumbnails}
          }
          let image = try Engine().loadImage(url)
          DispatchQueue.main.async {
            self.sourceImage = image; self.sourceSize = CGSize(width:image.width,height:image.height); self.preview = NSImage(cgImage:image,size:.zero)
            if tool == "crop" { self.options.width = image.width; self.options.height = image.height }
            if tool == "collage" { self.options.width = 2048; self.options.height = 2048; self.renderPreview() }
          }
        }
        if tool != "strip" && tool != "archive" && (family == .video || family == .audio) {
          let engine = Engine()
          let probe = try engine.probe(url)
          let duration = ((probe["format"] as? [String:Any])?["duration"] as? String).flatMap(Double.init) ?? 1
          let streams = probe["streams"] as? [[String:Any]] ?? []
          let video = streams.first { ($0["codec_type"] as? String) == "video" }
          var thumbs: [NSImage] = []
          if family == .video {
            let generator = AVAssetImageGenerator(asset:AVURLAsset(url:url)); generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width:320,height:180)
            for i in 0..<8 {
              if let img = try? generator.copyCGImage(at:CMTime(seconds:duration*Double(i)/8,preferredTimescale:600),actualTime:nil) { thumbs.append(NSImage(cgImage:img,size:.zero)) }
            }
          }
          let samples = await Self.waveforms(url,duration:duration)
          DispatchQueue.main.async {
            self.duration = max(0.001,duration); self.options.duration = max(0.001,duration)
            self.waveform = samples.mix; self.leftWaveform = samples.left; self.rightWaveform = samples.right; self.thumbnails = thumbs
            if let video {
              let rate=(video["avg_frame_rate"] as? String ?? video["r_frame_rate"] as? String ?? "30/1").split(separator:"/").compactMap {Double($0)}
              if rate.count==2,rate[0]>0,rate[1]>0 {self.frameDuration=rate[1]/rate[0]}
              let size=Engine.videoDisplaySize(probe)
              self.options.width = Int(size.width)
              self.options.height = Int(size.height)
              self.sourceSize = CGSize(width:self.options.width,height:self.options.height)
            }
          }
        }
        if tool == "strip" { try self.loadMetadata() }
        if tool == "split", family == .pdf {
          var thumbnails: [URL: [Int:NSImage]] = [:]
          var groups: [String: [[Int]]] = [:]
          for file in self.files {
            guard let doc = PDFDocument(url:file), !doc.isLocked, doc.pageCount > 0 else {
              throw ClementineError(tr("PDF illisible, vide ou verrouillé : \(file.lastPathComponent)"))
            }
            var pages: [Int:NSImage] = [:]
            for i in 0..<doc.pageCount {
              pages[i] = doc.page(at:i)?.thumbnail(of:CGSize(width:150,height:180),for:.mediaBox)
            }
            guard pages.count == doc.pageCount else { throw ClementineError(tr("Aperçu des pages impossible")) }
            thumbnails[file] = pages
            groups[file.path] = PDFSplitLayout.individual(count:doc.pageCount)
          }
          DispatchQueue.main.async { self.splitThumbnails = thumbnails; self.options.pdfSplitGroups = groups }
        }
        if tool == "organize", let doc = PDFDocument(url:url) {
          var thumbs: [Int:NSImage] = [:]
          for i in 0..<doc.pageCount { thumbs[i] = doc.page(at:i)?.thumbnail(of:CGSize(width:180,height:240),for:.mediaBox) }
          let pages = (0..<doc.pageCount).map { ModulePage(index:$0) }
          DispatchQueue.main.async { self.options.modulePages = pages; self.pageThumbnails = thumbs }
        }
      } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
      DispatchQueue.main.async { self.loading = false }
    }
  }
  static func waveforms(_ url:URL,duration:Double) async ->(mix:[Float],left:[Float],right:[Float]) {
    let asset=AVURLAsset(url:url)
    guard let track=try? await asset.loadTracks(withMediaType:.audio).first,
      let reader=try? AVAssetReader(asset:asset) else {return ([],[],[])}
    let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
    reader.add(output);guard reader.startReading() else {return ([],[],[])}
    var left=[Float](repeating:0,count:500),right=left
    while let buffer=output.copyNextSampleBuffer() {
      guard let block=CMSampleBufferGetDataBuffer(buffer),let format=CMSampleBufferGetFormatDescription(buffer),let description=CMAudioFormatDescriptionGetStreamBasicDescription(format) else {continue}
      let channels=max(1,Int(description.pointee.mChannelsPerFrame))
      let timestamp=CMSampleBufferGetPresentationTimeStamp(buffer).seconds
      var length=0;var pointer:UnsafeMutablePointer<Int8>?
      guard timestamp.isFinite,CMBlockBufferGetDataPointer(block,atOffset:0,lengthAtOffsetOut:nil,totalLengthOut:&length,dataPointerOut:&pointer)==noErr,let pointer else {continue}
      let count=length/4,frames=count/channels,rate=max(1,description.pointee.mSampleRate)
      pointer.withMemoryRebound(to:Float.self,capacity:count) {values in
        for frame in stride(from:0,to:frames,by:max(1,frames/256)) {
          let time=timestamp+Double(frame)/rate,index=min(499,max(0,Int(time/max(0.001,duration)*500)))
          let l=values[frame*channels],r=values[frame*channels+min(1,channels-1)]
          if l.isFinite {left[index]=max(left[index],abs(l))};if r.isFinite {right[index]=max(right[index],abs(r))}
        }
      }
    }
    let peak=max(0.01,max(left.max() ?? 0,right.max() ?? 0))
    left=left.map {$0/peak};right=right.map {$0/peak}
    return (zip(left,right).map {max($0,$1)},left,right)
  }
  func loadMetadata() throws {
    guard let exif = Engine.exiftool else { throw ClementineError(tr("ExifTool est absent")) }
    let json = try Engine().process("/usr/bin/perl",[exif,"-j","-G1","-s",files[0].path])
    let dict = (try JSONSerialization.jsonObject(with:Data(json.utf8)) as? [[String:Any]])?.first ?? [:]
    let writableOutput = try Engine().process("/usr/bin/perl",[exif,"-listw","-s"])
    let writable = Set(writableOutput.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    let writableFormats = try Engine().process("/usr/bin/perl",[exif,"-listwf"])
    let writableExtensions = Set(writableFormats.split(whereSeparator: { $0.isWhitespace }).dropFirst(3).map { String($0).lowercased() })
    let canEdit = files.allSatisfy { writableExtensions.contains($0.pathExtension.lowercased()) }
    let rows = dict.keys.sorted().filter { !$0.hasPrefix("ExifTool:") && $0 != "SourceFile" }.map { key -> MetadataRow in
      let parts = key.split(separator:":",maxSplits:1).map(String.init)
      let value = dict[key].map { String(describing:$0) } ?? ""
      return MetadataRow(key:key,group:parts.count>1 ? parts[0] : "File",name:parts.last ?? key,value:value,original:value,editable:canEdit && writable.contains(parts.last ?? key) && parts.first != "System")
    }
    DispatchQueue.main.async { self.metadataCanEdit = canEdit; self.metadata = rows }
  }
  func pause() { player.pause(); playing = false }
  func seek(_ seconds: Double) {
    position = min(duration,max(0,seconds))
    player.seek(to:CMTime(seconds:position,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
  }
  func togglePlay() {
    if playing { pause(); return }
    if tool == "trim", position < options.start || position >= options.start+options.duration { seek(options.start) }
    if position >= duration { seek(0) }
    playing = true; player.playImmediately(atRate:tool == "speed" ? Float(options.speed) : 1)
  }
  func stepFrame(_ direction: Double) {pause();seek((round(position/frameDuration)+direction)*frameDuration)}
  func step(_ amount: Double) { pause(); seek(position+amount) }
  func reset() {
    pause(); options.marks = []; undoStack = []; selectedMark = nil
    options.photoAdjustments = [:]; options.brightness = 0; options.contrast = 1; options.saturation = 1
    options.x = 0; options.y = 0
    if let image = sourceImage { options.width = image.width; options.height = image.height }
    renderPreview()
  }
  func remember() { undoStack.append(options.marks); if undoStack.count>80 { undoStack.removeFirst() } }
  func undo() { if let previous = undoStack.popLast() { options.marks = previous; renderPreview() } }
  func deleteMark() { remember(); options.marks.removeAll { $0.id == selectedMark }; selectedMark = nil; renderPreview() }
  func moveFile(_ index: Int, by delta: Int) {
    let other = index+delta
    guard files.indices.contains(other) else { return }
    files.swapAt(index,other); if tool == "collage" { renderPreview() }
  }
  func addPoint() {
    if tool == "snapshot" { if !frames.contains(where:{abs($0-position)<0.001}) {
      let time = position,url = files[0];frames.append(time);frames.sort()
      DispatchQueue.global(qos:.userInitiated).async {
        let generator = AVAssetImageGenerator(asset:AVURLAsset(url:url));generator.appliesPreferredTrackTransform = true;generator.maximumSize = CGSize(width:160,height:100);generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        if let frame = try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:nil) { DispatchQueue.main.async { self.frameThumbnails[time] = NSImage(cgImage:frame,size:.zero) } }
      }
    } }
    else if position>0 && position<duration && !splitPoints.contains(where:{abs($0-position)<0.001}) { splitPoints.append(position); splitPoints.sort() }
  }
  func detect(_ kind: String) {
    guard let image = sourceImage else { return }
    busy = true
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        let request: VNImageBasedRequest = kind == "Faces" ? VNDetectFaceRectanglesRequest() : VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage:image).perform([request])
        let boxes = (request.results ?? []).compactMap { ($0 as? VNDetectedObjectObservation)?.boundingBox ?? ($0 as? VNRecognizedTextObservation)?.boundingBox }
        DispatchQueue.main.async {
          self.remember()
          for box in boxes { self.options.marks.append(ModuleMark(x:box.minX,y:1-box.maxY,width:box.width,height:box.height,color:self.options.color,blur:self.options.blur,end:self.duration)) }
          self.busy = false; self.renderPreview()
        }
      } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false } }
    }
  }
  func renderPreview() {
    guard sourceImage != nil else { return }
    previewTask?.cancel()
    let generation = UUID(); previewGeneration = generation
    let settings = options, image = sourceImage!, tool = tool, files = files
    let task = DispatchWorkItem { [weak self] in
      do {
        let engine = Engine()
        let result: CGImage
        if tool == "collage" { result = try engine.moduleCollage(files,options:settings,maximum:1000) }
        else { result = try engine.moduleImage(image,action:tool,options:settings,preview:true) }
        DispatchQueue.main.async { guard let self,self.previewGeneration == generation else { return }; self.preview = NSImage(cgImage:result,size:.zero) }
      } catch { DispatchQueue.main.async { guard let self,self.previewGeneration == generation else { return }; self.error = error.localizedDescription } }
    }
    previewTask = task
    DispatchQueue.global(qos:.userInitiated).asyncAfter(deadline:.now()+0.05,execute:task)
  }
  func export(previewOnly: Bool = false, channel: String? = nil) {
    guard !busy else { return }
    pause(); error = nil; busy = true; progress = 0
    var settings = options
    settings.times = (tool == "snapshot" ? frames : splitPoints).map { String($0) }.joined(separator:",")
    if tool == "compress", targetEnabled {
      if targetMode == "Reduction" { settings.compressionReduction = reduction }
      let bytes = files.reduce(Int64(0)) { $0 + Engine().bytes($1) }
      settings.targetMB = targetMode == "Reduction" ? Double(bytes)*(1-reduction/100)/1_000_000 : targetValue*(targetUnit == "KB" ? 0.001 : 1)
    }
    if tool == "compress" {
      if let width = Int(imageSize.components(separatedBy:" ").first ?? "") { settings.width = width; settings.height = 0 }
      else { settings.width = 0; settings.height = 0 }
    }
    if tool == "crop",files.count>1 {
      settings.moduleCrops[files[activeFile].path] = ModuleCrop(x:options.x,y:options.y,width:options.width,height:options.height)
    }
    if tool == "strip" {
      settings.metadataChanges = Dictionary(uniqueKeysWithValues: metadata.filter { options.metadataRemoveAll ? (!$0.removed && $0.editable) : ($0.editable && ($0.removed || $0.value != $0.original)) }.map { ($0.key,$0.removed ? "" : $0.value) })
    }
    let action = tool == "compress" && targetEnabled ? "target" : tool == "strip" && !metadataCanEdit ? "metadata" : tool
    let files = files, token = CancellationToken()
    if previewOnly {
      settings.outputFolder = scratch.path
      self.previewToken?.cancel(); self.previewToken = token
      settings.previewChannel = channel ?? ""
    } else { self.token = token }
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        let engine = Engine(token:token) { fraction,_ in DispatchQueue.main.async { self.progress = fraction } }
        let outputs = try engine.run(files,action:action,options:settings)
        DispatchQueue.main.async {
          self.busy = false; self.token = nil
          if previewOnly, let file = outputs.first {
            self.player.replaceCurrentItem(with:AVPlayerItem(url:file)); self.seek(self.tool == "trim" ? 0 : self.position)
            self.playing = true; self.player.play()
          } else { if self.reveal { NSWorkspace.shared.activateFileViewerSelecting(outputs) }; self.close?() }
        }
      } catch { DispatchQueue.main.async { self.busy = false; self.token = nil; self.error = error.localizedDescription } }
    }
  }
  func selectCropFile(_ index:Int) {
    guard files.indices.contains(index),index != activeFile,!busy else {return}
    options.moduleCrops[files[activeFile].path]=ModuleCrop(x:options.x,y:options.y,width:options.width,height:options.height)
    activeFile=index;busy=true
    let url=files[index]
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        let image=try Engine().loadImage(url)
        DispatchQueue.main.async {
          self.sourceImage=image;self.sourceSize=CGSize(width:image.width,height:image.height);self.preview=NSImage(cgImage:image,size:.zero)
          let crop=self.options.moduleCrops[url.path] ?? ModuleCrop(x:0,y:0,width:image.width,height:image.height)
          self.options.x=crop.x;self.options.y=crop.y;self.options.width=crop.width;self.options.height=crop.height
          self.aspect="Free";self.busy=false
        }
      } catch {DispatchQueue.main.async {self.error=error.localizedDescription;self.busy=false}}
    }
  }
  func detectSilentEnds() {
    let generation = UUID();silenceGeneration = generation
    if !options.trimSilence {
      if let base=autoTrimOriginal { options.start=base.0;options.duration=base.1 }
      autoTrimOriginal=nil;return
    }
    if autoTrimOriginal==nil {autoTrimOriginal=(options.start,options.duration)}
    let base=autoTrimOriginal!,threshold=options.silenceThreshold,url=files[0]
    DispatchQueue.global(qos:.userInitiated).async {
      do {
        let engine=Engine()
        let log=try engine.process(Engine.executable("ffmpeg"),["-hide_banner","-nostdin","-ss",String(base.0),"-i",url.path,"-t",String(base.1),"-af","silencedetect=noise=\(threshold)dB:d=0.1","-f","null","-"])
        func matches(_ pattern:String)->[Double] {
          let regex=try! NSRegularExpression(pattern:pattern)
          return regex.matches(in:log,range:NSRange(log.startIndex...,in:log)).compactMap {match in Range(match.range(at:1),in:log).flatMap {Double(log[$0])}}
        }
        let starts=matches("silence_start: ([0-9.]+)"),ends=matches("silence_end: ([0-9.]+)")
        let start=(starts.first ?? 1)<0.05 ? (ends.first ?? 0) : 0
        let end=(ends.last ?? 0)>=base.1-0.05 ? (starts.last ?? base.1) : base.1
        DispatchQueue.main.async {
          guard self.silenceGeneration==generation else {return}
          if end>start {self.options.start=base.0+start;self.options.duration=end-start;self.seek(self.options.start)}
          else {self.error="The selection contains only silence."}
        }
      } catch {DispatchQueue.main.async {if self.silenceGeneration==generation {self.error=error.localizedDescription}}}
    }
  }
  func playOriginal() { pause(); player.replaceCurrentItem(with:AVPlayerItem(url:files[0])); seek(0); togglePlay() }
  func cancel() { token?.cancel(); previewToken?.cancel(); pause(); close?() }
}

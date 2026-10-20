import AppKit
import CoreImage
import PDFKit
import AVFoundation

extension Engine {
  func validateModuleOptions(_ o:Options) throws {
    let values = [o.loudnessRange,o.truePeak,o.corners,o.shadow,o.backgroundBlur,o.silenceThreshold] + Array(o.photoAdjustments.values)
    guard values.allSatisfy({$0.isFinite}),o.loudnessRange>=1,o.loudnessRange<=50,o.truePeak<=0,o.truePeak>=(-20),o.corners>=0,o.corners<=2000,o.shadow>=0,o.shadow<=1000,o.backgroundBlur>=0,o.backgroundBlur<=200,o.columns>=1,o.columns<=100 else {throw ClementineError("Paramètres du module invalides")}
    for mark in o.marks {
      guard [mark.x,mark.y,mark.width,mark.height,mark.size,mark.start,mark.end].allSatisfy({$0.isFinite}),mark.x>=0,mark.y>=0,mark.width>=0,mark.height>=0,mark.x+mark.width<=1.0001,mark.y+mark.height<=1.0001,mark.size>0,mark.size<=1000,mark.start>=0,mark.end>mark.start,mark.points.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.x>=0 && $0.y>=0 && $0.x<=1 && $0.y<=1}) else {throw ClementineError("Zone ou annotation invalide")}
      if mark.kind == "image" {_=try loadImage(URL(fileURLWithPath:mark.text))}
    }
    if !o.backgroundImage.isEmpty {_=try loadImage(URL(fileURLWithPath:o.backgroundImage))}
  }

  func moduleImage(_ original: CGImage, action: String, options o: Options, preview: Bool = false, pixelScale: Double = 1) throws -> CGImage {
    if preview,max(original.width,original.height)>1200 {
      let scale=1200.0/Double(max(original.width,original.height))
      let smaller=try resize(original,width:max(1,Int(Double(original.width)*scale)),height:max(1,Int(Double(original.height)*scale)))
      var settings=o;settings.padding*=scale;settings.corners*=scale;settings.shadow*=scale;settings.backgroundBlur*=scale
      if let blur=settings.photoAdjustments["Blur"] {settings.photoAdjustments["Blur"]=blur*scale}
      return try moduleImage(smaller,action:action,options:settings,pixelScale:scale)
    }
    var image = original
    if action == "adjust" {
      var input = CIImage(cgImage:image)
      let bounds = input.extent
      func value(_ name: String) -> Double { o.photoAdjustments[name] ?? 0 }
      func filter(_ name: String, _ parameters: [String:Any]) {
        input = input.applyingFilter(name,parameters:parameters).cropped(to:bounds)
      }
      filter("CIExposureAdjust",["inputEV":value("Exposure")])
      filter("CIColorControls",["inputBrightness":value("Brightness")/100,"inputContrast":1+value("Contrast")/100,"inputSaturation":1+value("Saturation")/100])
      filter("CIHighlightShadowAdjust",["inputHighlightAmount":1-value("Highlights")/100,"inputShadowAmount":value("Shadows")/100])
      if value("Whites") != 0 || value("Blacks") != 0 {
        let black = value("Blacks")/500, white = value("Whites")/500
        filter("CIColorMatrix",["inputBiasVector":CIVector(x:black,y:black,z:black,w:0),"inputRVector":CIVector(x:1+white,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:1+white,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:1+white,w:0)])
      }
      filter("CIGammaAdjust",["inputPower":pow(2,-value("Gamma")/100)])
      filter("CITemperatureAndTint",["inputNeutral":CIVector(x:6500+value("Temperature")*30,y:value("Tint")),"inputTargetNeutral":CIVector(x:6500,y:0)])
      filter("CIVibrance",["inputAmount":value("Vibrance")/100])
      filter("CIHueAdjust",["inputAngle":value("Hue") * .pi / 180])
      if value("Texture") != 0 { filter("CIUnsharpMask",["inputRadius":1,"inputIntensity":value("Texture")/100]) }
      if value("Fade") > 0 { filter("CIColorControls",["inputBrightness":value("Fade")/1000,"inputContrast":1-value("Fade")/250,"inputSaturation":1-value("Fade")/500]) }
      if value("Blur") > 0 { input = input.clampedToExtent(); filter("CIGaussianBlur",["inputRadius":value("Blur")/4]) }
      if value("Clarity") != 0 { filter("CIUnsharpMask",["inputRadius":2.5,"inputIntensity":value("Clarity")/100]) }
      if value("Dehaze") != 0 { filter("CIColorControls",["inputContrast":1+value("Dehaze")/200,"inputBrightness":-value("Dehaze")/1000,"inputSaturation":1]) }
      if value("Sharpness") > 0 { filter("CISharpenLuminance",["inputSharpness":value("Sharpness")/100]) }
      if value("Noise Reduction") > 0 { filter("CINoiseReduction",["inputNoiseLevel":value("Noise Reduction")/1000,"inputSharpness":0.4]) }
      if value("Vignette") != 0 { filter("CIVignette",["inputIntensity":value("Vignette")/50,"inputRadius":Double(min(image.width,image.height))/2]) }
      if value("Grain") > 0, let noise = CIFilter(name:"CIRandomGenerator")?.outputImage {
        let mono = noise.cropped(to:bounds).applyingFilter("CIColorControls",parameters:["inputSaturation":0]).applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:value("Grain")/350)])
        input = mono.applyingFilter("CISoftLightBlendMode",parameters:[kCIInputBackgroundImageKey:input]).cropped(to:bounds)
      }
      if let result = CIContext(options:[.useSoftwareRenderer:true]).createCGImage(input,from:bounds) { image = result }
      else { image = try moduleCPUPixels(image,adjustments:o.photoAdjustments) }
    }
    if action == "redact" || action == "annotate" {
      let marks = o.marks
      let fallbackBlur = marks.contains { $0.blur } ? try moduleCPUPixels(image,blurRadius:20*pixelScale) : nil
      image = try draw(image) { context in
        for mark in marks {
          let rect = CGRect(x:mark.x*Double(image.width),y:(1-mark.y-mark.height)*Double(image.height),width:mark.width*Double(image.width),height:mark.height*Double(image.height))
          if action == "redact" {
            if mark.blur {
              let base = CIImage(cgImage:image)
              let blurred = base.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:20]).cropped(to:rect)
              if let result = CIContext(options:[.useSoftwareRenderer:true]).createCGImage(blurred,from:rect) { context.draw(result,in:rect) }
              else if let result = fallbackBlur?.cropping(to:CGRect(x:mark.x*Double(image.width),y:mark.y*Double(image.height),width:mark.width*Double(image.width),height:mark.height*Double(image.height))) { context.draw(result,in:rect) }
            } else { context.setFillColor(NSColor(hex:mark.color).cgColor); context.fill(rect) }
          } else { drawAnnotation(mark,in:context,image:image,rect:rect) }
        }
      }
    }
    if action == "frame" {
      let padding = Int(o.padding)
      var w = image.width+padding*2, h = image.height+padding*2
      if let ratio = Self.ratio(o.canvasRatio) {
        if Double(w)/Double(h)<ratio { w = Int(Double(h)*ratio) } else { h = Int(Double(w)/ratio) }
      }
      let content = image
      image = try canvas(width:w,height:h) { context in
        drawModuleBackground(context,rect:CGRect(x:0,y:0,width:w,height:h),options:o,image:content)
        let rect = CGRect(x:(w-content.width)/2,y:(h-content.height)/2,width:content.width,height:content.height)
        context.saveGState()
        if o.shadow>0 { context.setShadow(offset:CGSize(width:0,height:-o.shadow/3),blur:o.shadow,color:CGColor(gray:0,alpha:0.35)) }
        context.setFillColor(NSColor.white.cgColor)
        let path = CGPath(roundedRect:rect,cornerWidth:o.corners,cornerHeight:o.corners,transform:nil)
        context.addPath(path); context.fillPath(); context.restoreGState()
        context.saveGState(); context.addPath(path); context.clip(); context.draw(content,in:rect); context.restoreGState()
      }
    }
    return image
  }
  static func ratio(_ value: String) -> Double? {
    if value.contains("16:9") { return 16/9 }
    if value.contains("9:16") { return 9/16 }
    if value.contains("4:5") { return 4/5 }
    if value.contains("4:3") { return 4/3 }
    if value.contains("3:4") { return 3/4 }
    if value.contains("1:1") { return 1 }
    return nil
  }
  func drawAnnotation(_ mark: ModuleMark, in c: CGContext, image: CGImage, rect: CGRect) {
    c.saveGState(); defer { c.restoreGState() }
    let color = NSColor(hex:mark.color)
    c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor)
    let line = max(1,mark.size*Double(image.width)/440)
    c.setLineWidth(line); c.setLineCap(.round); c.setLineJoin(.round)
    func point(_ p: ModulePoint) -> CGPoint { CGPoint(x:p.x*Double(image.width),y:(1-p.y)*Double(image.height)) }
    switch mark.kind {
    case "rectangle": c.stroke(rect)
    case "ellipse": c.strokeEllipse(in:rect)
    case "arrow":
      let a = mark.points.first.map(point) ?? CGPoint(x:rect.minX,y:rect.maxY)
      let b = mark.points.last.map(point) ?? CGPoint(x:rect.maxX,y:rect.minY)
      c.move(to:a); c.addLine(to:b); c.strokePath()
      let angle = atan2(b.y-a.y,b.x-a.x), length = line*4
      c.move(to:b); c.addLine(to:CGPoint(x:b.x-length*cos(angle - .pi/6),y:b.y-length*sin(angle - .pi/6)))
      c.move(to:b); c.addLine(to:CGPoint(x:b.x-length*cos(angle + .pi/6),y:b.y-length*sin(angle + .pi/6))); c.strokePath()
    case "draw", "highlight":
      if mark.kind == "highlight" { c.setAlpha(0.35); c.setLineWidth(line*5) }
      if mark.points.count == 1,let first=mark.points.first {
        let p=point(first),diameter=line*(mark.kind == "highlight" ? 5 : 1)
        c.fillEllipse(in:CGRect(x:p.x-diameter/2,y:p.y-diameter/2,width:diameter,height:diameter))
      } else if let first=mark.points.first {
        c.move(to:point(first))
        if mark.points.count == 2 {c.addLine(to:point(mark.points[1]))}
        else {
          for index in 1..<(mark.points.count-1) {
            let current=point(mark.points[index]),next=point(mark.points[index+1])
            c.addQuadCurve(to:CGPoint(x:(current.x+next.x)/2,y:(current.y+next.y)/2),control:current)
          }
          c.addLine(to:point(mark.points.last!))
        };c.strokePath()
      }
    case "magnifier":
      c.addEllipse(in:rect); c.clip()
      let crop = CGRect(x:mark.x*Double(image.width),y:mark.y*Double(image.height),width:mark.width*Double(image.width),height:mark.height*Double(image.height)).insetBy(dx:rect.width/2*(1-1/max(1,mark.magnification)),dy:rect.height/2*(1-1/max(1,mark.magnification)))
      if let magnified = image.cropping(to:crop) { c.draw(magnified,in:rect) }
      c.resetClip(); c.strokeEllipse(in:rect)
    case "image":
      if let overlay = try? loadImage(URL(fileURLWithPath:mark.text)) { c.draw(overlay,in:rect) }
    default:
      NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:false)
      if mark.kind == "number" { c.fillEllipse(in:rect); NSColor.white.setFill() }
      let text = mark.kind == "number" ? mark.text : mark.text
      let size=max(12,mark.size*Double(image.width)/440*6)
      let font:NSFont
      switch mark.font {
      case "Monospaced":font=NSFont.monospacedSystemFont(ofSize:size,weight:.medium)
      case "Serif":font=NSFont(name:"Georgia",size:size) ?? NSFont.systemFont(ofSize:size)
      case "Rounded":let base=NSFont.systemFont(ofSize:size,weight:.medium);font=base.fontDescriptor.withDesign(.rounded).flatMap {NSFont(descriptor:$0,size:size)} ?? base
      default:font=NSFont.systemFont(ofSize:size,weight:.medium)
      }
      let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:mark.kind == "number" ? NSColor.white : color]
      (text as NSString).draw(in:rect,withAttributes:attributes); NSGraphicsContext.restoreGraphicsState()
    }
  }
  func drawModuleBackground(_ c: CGContext, rect: CGRect, options o: Options, image: CGImage? = nil) {
    if !o.backgroundImage.isEmpty,let background = try? loadImage(URL(fileURLWithPath:o.backgroundImage)) {
      var output = background
      if o.backgroundBlur>0 {
        let input = CIImage(cgImage:background).clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:o.backgroundBlur]).cropped(to:CGRect(x:0,y:0,width:background.width,height:background.height))
        output = CIContext(options:[.useSoftwareRenderer:true]).createCGImage(input,from:input.extent) ?? background
      }
      c.draw(output,in:rect); return
    }
    if o.background == "Transparent" { return }
    if o.background.hasPrefix("#") { c.setFillColor(NSColor(hex:o.background).cgColor); c.fill(rect); return }
    ModuleBackgrounds.draw(c,rect:rect,name:o.background)
  }
  func moduleCollage(_ urls: [URL], options o: Options, maximum: Int? = nil) throws -> CGImage {
    let width = max(64,o.width>0 ? o.width : 2048)
    let ratio = Self.ratio(o.canvasRatio) ?? 1
    let height = o.height>0 ? o.height : Int(Double(width)/ratio)
    let factor = maximum.map { min(1,Double($0)/Double(max(width,height))) } ?? 1
    let w = Int(Double(width)*factor), h = Int(Double(height)*factor)
    let columns = o.collageStyle == "Row" ? urls.count : o.collageStyle == "Column" ? 1 : max(1,o.columns)
    let rows = Int(ceil(Double(urls.count)/Double(columns)))
    guard Double(w)>2*o.collagePadding*factor+o.collageSpacing*factor*Double(columns-1),Double(h)>2*o.collagePadding*factor+o.collageSpacing*factor*Double(rows-1) else {throw ClementineError("L’espacement dépasse la taille du collage")}
    let images = try urls.map {try loadImage($0)}
    let spacing = o.collageSpacing*factor, padding = o.collagePadding*factor
    return try canvas(width:w,height:h) { c in
      drawModuleBackground(c,rect:CGRect(x:0,y:0,width:w,height:h),options:o)
      let cw = (Double(w)-2*padding-spacing*Double(columns-1))/Double(columns), ch = (Double(h)-2*padding-spacing*Double(rows-1))/Double(rows)
      for (i,image) in images.enumerated() {
        var rect = CGRect(x:padding+Double(i%columns)*(cw+spacing),y:Double(h)-padding-Double(i/columns+1)*ch-Double(i/columns)*spacing,width:cw,height:ch)
        if o.collageStyle == "Featured",i == 0,urls.count>1 { rect = CGRect(x:padding,y:padding,width:(Double(w)-2*padding-spacing)*0.6,height:Double(h)-2*padding) }
        else if o.collageStyle == "Featured",urls.count>1 {
          let bh = (Double(h)-2*padding-Double(urls.count-2)*spacing)/Double(urls.count-1)
          rect = CGRect(x:padding+(Double(w)-2*padding-spacing)*0.6+spacing,y:Double(h)-padding-Double(i)*bh-Double(i-1)*spacing,width:(Double(w)-2*padding-spacing)*0.4,height:bh)
        }
        c.saveGState(); c.addPath(CGPath(roundedRect:rect,cornerWidth:o.corners*factor,cornerHeight:o.corners*factor,transform:nil)); c.clip()
        let scale = o.imageFit.hasPrefix("Fill") ? max(rect.width/Double(image.width),rect.height/Double(image.height)) : min(rect.width/Double(image.width),rect.height/Double(image.height))
        let size = CGSize(width:Double(image.width)*scale,height:Double(image.height)*scale)
        c.draw(image,in:CGRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height)); c.restoreGState()
      }
    }
  }
  func moduleMetadata(_ source: URL, stage: URL, options o: Options) throws -> URL {
    guard let exif = Self.exiftool else { throw ClementineError("ExifTool est absent") }
    let destination = output(source,source.pathExtension,stage,suffix:"-metadata")
    if Family.of(source) == .pdf,o.metadataRemoveAll {
      guard let original=PDFDocument(url:source),!original.isLocked else {throw ClementineError("PDF illisible ou verrouillé")}
      let clean=PDFDocument()
      for index in 0..<original.pageCount {if let page=original.page(at:index)?.copy() as? PDFPage {clean.insert(page,at:clean.pageCount)}}
      clean.documentAttributes=[:]
      guard clean.write(to:destination) else {throw ClementineError("Écriture du PDF impossible")}
    } else {try fm.copyItem(at:source,to:destination)}
    var args = [exif,"-overwrite_original"]
    if o.metadataRemoveAll { args.append("-all=") }
    for key in o.metadataChanges.keys.sorted() {
      guard key.range(of:"^[A-Za-z0-9_:.-]+$",options:.regularExpression) != nil else { throw ClementineError("Champ de métadonnées invalide") }
      args.append("-\(key)=\(o.metadataChanges[key]!)")
    }
    if args.count>2 {
      let output = try process("/usr/bin/perl",args+[destination.path])
      if output.localizedCaseInsensitiveContains("not writable") || output.localizedCaseInsensitiveContains("isn't writable") { throw ClementineError(output) }
    }
    return destination
  }
  func moduleOrganize(_ url: URL, stage: URL, options o: Options) throws -> URL {
    guard let doc = PDFDocument(url:url),!doc.isLocked,!o.modulePages.isEmpty else { throw ClementineError("Aucune page à enregistrer") }
    let arranged = PDFDocument()
    for entry in o.modulePages {
      guard let page = doc.page(at:entry.index)?.copy() as? PDFPage else { throw ClementineError("Page introuvable") }
      page.rotation = (page.rotation+entry.rotation)%360
      arranged.insert(page,at:arranged.pageCount)
    }
    let destination = output(url,"pdf",stage,suffix:"-organized")
    if !arranged.write(to:destination) { throw ClementineError("Écriture du PDF impossible") }
    return destination
  }
}

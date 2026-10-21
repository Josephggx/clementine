import AppKit
import Foundation
import PDFKit
import JavaScriptCore
import ImageIO

/// Content policies shared by Finder conversion and the workshop.
/// Page-preserving outputs never substitute OCR text for the original artwork.
enum DocumentFidelity {
  static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
  static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
  static let officeNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  static func pdf(_ source: URL, to dest: URL, options: Options, engine: Engine) throws -> URL {
    guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else {
      throw ClementineError(tr("PDF vide, illisible ou verrouillé"))
    }
    guard document.allowsCopying else { throw ClementineError(tr("Ce PDF n’autorise pas la copie de son contenu.")) }
    let ext = dest.pathExtension.lowercased()
    if ext == "pages" { try NativeOffice.convert(source, to: dest, engine: engine, options: options); return dest }
    if ext == "xlsx" { try PDFText.spreadsheet(document, destination: dest, engine: engine); return dest }
    if ext == "txt" {
      // Plain-text exports in Tangerine do not run OCR on a scan.
      let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ClementineError(tr("Ce PDF ne contient pas de texte sélectionnable. Choisissez DOCX/Pages avec paragraphes modifiables pour utiliser l’OCR."))
      }
      try text.write(to: dest, atomically: true, encoding: .utf8); return dest
    }
    let root = dest.deletingLastPathComponent().appendingPathComponent("document-" + UUID().uuidString)
    try engine.fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? engine.fm.removeItem(at: root) }
    if ext == "md" {
      let html = root.appendingPathComponent("Content.html")
      try reflow(document,root:root,engine:engine).write(to:html,atomically:true,encoding:.utf8)
      return try RichDocuments.convert(html,to:dest,options:options,engine:engine)
    }
    if ext == "docx", options.pdfOfficeLayout == "automatic" {
      let native=(0..<document.pageCount).contains { !(document.page(at:$0)?.string ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
      if native {
        return try Documents.office(source,to:dest,engine:engine,options:options,nativePDFLayout:true)
      }
      try pageDocument(document,root:root,destination:dest,engine:engine)
    } else if ext == "docx", options.pdfOfficeLayout == "preservePages" {
      try pageDocument(document, root: root, destination: dest, engine: engine)
    } else if ext == "pptx" {
      try pageSlides(document, root: root, destination: dest, engine: engine)
    } else if ext == "epub", options.epubLayout == "preservePages" {
      try pageBook(document, root: root, destination: dest, engine: engine)
    } else if ["docx", "epub"].contains(ext) {
      let html = root.appendingPathComponent("Editable.html")
      try reflow(document, root: root, engine: engine, allowOCR: ext != "docx" || options.pdfOfficeLayout == "editable").write(to: html, atomically: true, encoding: .utf8)
      return try Documents.office(html, to: dest, engine: engine, options: options)
    } else { throw ClementineError(tr("Export PDF non disponible")) }
    return dest
  }
  static func png(_ image: CGImage, to url: URL, dpi: Double? = nil) throws {
    guard let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw ClementineError(tr("Création de l’illustration impossible")) }
    let properties: [CFString: Any]? = dpi.map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] }
    CGImageDestinationAddImage(writer, image, properties as CFDictionary?)
    guard CGImageDestinationFinalize(writer) else { throw ClementineError(tr("Enregistrement de l’illustration impossible")) }
  }
  static func write(_ text: String, _ path: String, root: URL) throws {
    let u = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: u, atomically: true, encoding: .utf8)
  }
  static func zip(_ root: URL, to dest: URL, epub: Bool = false, engine: Engine) throws {
    if epub { try engine.process("/usr/bin/zip", ["-q", "-X", "-0", dest.path, "mimetype"], at: root) }
    try engine.process("/usr/bin/zip", ["-q", "-X", "-r", dest.path, ".", "-x", "mimetype"], at: root)
  }
  static func pageSize(_ page: PDFPage) throws -> CGSize {
    let b = page.bounds(for: .mediaBox)
    let rotated = abs(page.rotation % 180) == 90
    let size = CGSize(width: rotated ? b.height : b.width, height: rotated ? b.width : b.height)
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, max(size.width,size.height) <= 14400 else { throw ClementineError(tr("Dimensions de page PDF invalides")) }
    return size
  }
  static func drawingTransform(_ page: PDFPage, canvas: CGSize) throws -> CGAffineTransform {
    let size = try pageSize(page)
    guard let ref = page.pageRef else { throw ClementineError(tr("Page PDF illisible")) }
    // CGPDFPageGetDrawingTransform only shrinks pages; upscale explicitly for 300 DPI.
    let points = CGRect(origin: .zero, size: size)
    return ref.getDrawingTransform(.mediaBox, rect: points, rotate: 0, preserveAspectRatio: true)
      .concatenating(CGAffineTransform(scaleX: canvas.width / size.width, y: canvas.height / size.height))
  }
  static func pageDocument(_ pdf: PDFDocument, root: URL, destination: URL, engine: Engine) throws {
    let media = root.appendingPathComponent("word/media"); try engine.fm.createDirectory(at: media, withIntermediateDirectories: true)
    var body = "", relations = ""
    for index in 0..<pdf.pageCount {
      try engine.token.check(); let page = pdf.page(at: index)!, size = try pageSize(page)
      guard max(size.width,size.height) <= 1584 else { throw ClementineError(tr("Une page dépasse la limite de 22 pouces du format Word.")) }
      try png(engine.renderPage(page, scale: 300/72), to: media.appendingPathComponent("page-\(index+1).png"), dpi:300)
      let id = index+1, cx = Int((size.width*12700).rounded()), cy = Int((size.height*12700).rounded())
      relations += "<Relationship Id=\"p\(id)\" Type=\"\(officeNS)/image\" Target=\"media/page-\(id).png\"/>"
      // Anchoring to the page avoids a line-height creating a spurious blank page.
      body += """
      <w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="1" w:lineRule="exact"/></w:pPr><w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="0" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionH><wp:positionV relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx="\(cx)" cy="\(cy)"/><wp:wrapNone/><wp:docPr id="\(id)" name="Page \(id)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(id)" name="Page \(id)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="p\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>
      """
      let section = "<w:sectPr><w:type w:val=\"nextPage\"/><w:pgSz w:w=\"\(Int((size.width*20).rounded()))\" w:h=\"\(Int((size.height*20).rounded()))\"\(size.width > size.height ? " w:orient=\"landscape\"" : "")/><w:pgMar w:top=\"0\" w:right=\"0\" w:bottom=\"0\" w:left=\"0\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>"
      if index < pdf.pageCount-1 { body += "</w:p><w:p><w:pPr>\(section)</w:pPr></w:p>" } else { body += "</w:p>\(section)" }
    }
    try write(xmlHeader + "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"\(officeNS)\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>\(body)</w:body></w:document>", "word/document.xml", root: root)
    try write(xmlHeader + "<Relationships xmlns=\"\(relNS)\">\(relations)</Relationships>", "word/_rels/document.xml.rels", root: root)
    try write(xmlHeader + "<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"main\" Type=\"\(officeNS)/officeDocument\" Target=\"word/document.xml\"/></Relationships>", "_rels/.rels", root: root)
    try write(xmlHeader + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>", "[Content_Types].xml", root: root)
    try zip(root, to: destination, engine: engine)
  }
  static func pageSlides(_ pdf: PDFDocument, root: URL, destination: URL, engine: Engine) throws {
    let size = try pageSize(pdf.page(at:0)!), w = Int(size.width*12700), h = Int(size.height*12700)
    let media=root.appendingPathComponent("ppt/media");try engine.fm.createDirectory(at:media,withIntermediateDirectories:true)
    var ids="", relationships="", overrides=""
    for i in 0..<pdf.pageCount {
      try engine.token.check();let n=i+1, page=pdf.page(at:i)!, pageSize=try pageSize(page)
      try png(engine.renderPage(page,scale:300/72),to:media.appendingPathComponent("page-\(n).png"),dpi:300)
      let scale=min(size.width/pageSize.width,size.height/pageSize.height)
      let iw=Int(pageSize.width*scale*12700),ih=Int(pageSize.height*scale*12700)
      ids += "<p:sldId id=\"\(255+n)\" r:id=\"s\(n)\"/>"
      relationships += "<Relationship Id=\"s\(n)\" Type=\"\(officeNS)/slide\" Target=\"slides/slide\(n).xml\"/>"
      overrides += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
      let tree="<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
      let picture="<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page \(n)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"image\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\((w-iw)/2)\" y=\"\((h-ih)/2)\"/><a:ext cx=\"\(iw)\" cy=\"\(ih)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
      try write(xmlHeader+"<p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"\(officeNS)\"><p:cSld><p:spTree>\(tree)\(picture)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>","ppt/slides/slide\(n).xml",root:root)
      try write(xmlHeader+"<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"image\" Type=\"\(officeNS)/image\" Target=\"../media/page-\(n).png\"/></Relationships>","ppt/slides/_rels/slide\(n).xml.rels",root:root)
    }
    try write(xmlHeader+"<p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"\(officeNS)\"><p:sldIdLst>\(ids)</p:sldIdLst><p:sldSz cx=\"\(w)\" cy=\"\(h)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>","ppt/presentation.xml",root:root)
    try write(xmlHeader+"<Relationships xmlns=\"\(relNS)\">\(relationships)</Relationships>","ppt/_rels/presentation.xml.rels",root:root)
    try write(xmlHeader+"<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"main\" Type=\"\(officeNS)/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>","_rels/.rels",root:root)
    try write(xmlHeader+"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>\(overrides)</Types>","[Content_Types].xml",root:root)
    try zip(root,to:destination,engine:engine)
  }
  static func pageBook(_ pdf: PDFDocument, root: URL, destination: URL, engine: Engine) throws {
    try write("application/epub+zip","mimetype",root:root)
    try write("<?xml version=\"1.0\"?><container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\" version=\"1.0\"><rootfiles><rootfile full-path=\"EPUB/package.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>","META-INF/container.xml",root:root)
    let media=root.appendingPathComponent("EPUB/images");try engine.fm.createDirectory(at:media,withIntermediateDirectories:true)
    var manifest="",spine="",nav=""
    for i in 0..<pdf.pageCount {
      try engine.token.check();let n=i+1,page=pdf.page(at:i)!,s=try pageSize(page)
      try png(engine.renderPage(page,scale:300/72),to:media.appendingPathComponent("page-\(n).png"),dpi:300)
      manifest += "<item id=\"p\(n)\" href=\"page-\(n).xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"i\(n)\" href=\"images/page-\(n).png\" media-type=\"image/png\"/>"
      spine += "<itemref idref=\"p\(n)\"/>";nav += "<li><a href=\"page-\(n).xhtml\">Page \(n)</a></li>"
      try write("<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Page \(n)</title><meta name=\"viewport\" content=\"width=\(Int(s.width)),height=\(Int(s.height))\"/><style>html,body{margin:0;width:100%;height:100%;}img{width:100%;height:100%;object-fit:contain;}</style></head><body><img src=\"images/page-\(n).png\" alt=\"Page \(n)\"/></body></html>","EPUB/page-\(n).xhtml",root:root)
    }
    let modified=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:"\\.\\d+Z",with:"Z",options:.regularExpression)
    try write("<?xml version=\"1.0\"?><package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"id\"><metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:identifier id=\"id\">urn:uuid:\(UUID().uuidString)</dc:identifier><dc:title>\(Documents.escape(destination.deletingPathExtension().lastPathComponent))</dc:title><dc:language>und</dc:language><meta property=\"dcterms:modified\">\(modified)</meta><meta property=\"rendition:layout\">pre-paginated</meta><meta property=\"rendition:spread\">none</meta></metadata><manifest><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\(manifest)</manifest><spine>\(spine)</spine></package>","EPUB/package.opf",root:root)
    try write("<?xml version=\"1.0\"?><html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\"><head><title>Contents</title></head><body><nav epub:type=\"toc\"><ol>\(nav)</ol></nav></body></html>","EPUB/nav.xhtml",root:root)
    try zip(root,to:destination,epub:true,engine:engine)
  }
  static func html(_ body:String) -> String {
    "<!doctype html><html><head><meta charset=\"utf-8\"><style>body{font:12pt Arial;line-height:1.35}img{max-width:100%;height:auto}table{border-collapse:collapse}td,th{border:1px solid #999;padding:4pt}pre{white-space:pre-wrap}</style></head><body>\(body)</body></html>"
  }
  static func reflow(_ pdf: PDFDocument, root: URL, engine: Engine, allowOCR: Bool = true) throws -> String {
    var body=""
    for i in 0..<pdf.pageCount {
      try engine.token.check();let page=pdf.page(at:i)!, lines=try PDFText.lines(page,engine:engine,allowOCR:allowOCR)
      body += "<section>"
      if lines.isEmpty {
        let path=root.appendingPathComponent("page-\(i+1).png");try png(engine.renderPage(page,scale:300/72),to:path)
        body += "<p><img src=\"\("data:image/png;base64,"+(try Data(contentsOf:path)).base64EncodedString())\" alt=\"Page \(i+1)\"></p>"
      } else {
        var rows:[[PDFText.Line]]=[]
        for line in lines.sorted(by:{$0.box.midY > $1.box.midY}) {
          if let last=rows.indices.last,let first=rows[last].first,abs(first.box.midY-line.box.midY)<max(3,min(first.box.height,line.box.height)*0.4) { rows[last].append(line) } else { rows.append([line]) }
        }
        var inTable=false
        for row in rows {
          let cells=row.sorted{$0.box.minX < $1.box.minX}
          if cells.count>1 {
            if !inTable {body += "<table>";inTable=true}
            body += "<tr>"+cells.map{"<td>\(Documents.escape($0.text))</td>"}.joined()+"</tr>"
          } else {
            if inTable {body += "</table>";inTable=false}
            body += "<p>\(Documents.escape(cells.first?.text ?? ""))</p>"
          }
        }
        if inTable {body += "</table>"}
        // Preserve raster illustrations without duplicating the full scanned text page.
        for (j,box) in PDFArtwork.rectangles(page).enumerated() {
          let bounds=page.bounds(for:.mediaBox)
          if box.width*box.height > bounds.width*bounds.height*0.85 {continue}
          let rendered=try engine.renderPage(page,scale:2)
          let display=CGRect(x:0,y:0,width:rendered.width,height:rendered.height)
          let transform=try drawingTransform(page,canvas:display.size)
          let rect=box.applying(transform);let crop=CGRect(x:rect.minX,y:display.height-rect.maxY,width:rect.width,height:rect.height).intersection(display).integral
          guard crop.width>=2,crop.height>=2,let art=rendered.cropping(to:crop) else {continue}
          let path=root.appendingPathComponent("art-\(i)-\(j).png");try png(art,to:path)
          body += "<p><img src=\"\("data:image/png;base64,"+(try Data(contentsOf:path)).base64EncodedString())\" alt=\"Illustration\"></p>"
        }
      }
      body += "</section>"
    }
    return html(body)
  }
}

private final class PDFArtwork {
  var ctm=CGAffineTransform.identity,stack:[CGAffineTransform]=[],boxes:[CGRect]=[],depth=0
  static func rectangles(_ page:PDFPage) -> [CGRect] {
    guard let ref=page.pageRef else {return []}
    let state=PDFArtwork();state.scan(CGPDFContentStreamCreateWithPage(ref));return state.boxes
  }
  func scan(_ content:CGPDFContentStreamRef) {
    guard depth<16,let table=CGPDFOperatorTableCreate() else {return};depth += 1;defer{depth -= 1}
    CGPDFOperatorTableSetCallback(table,"q") {_,info in guard let info else{return};let s=Unmanaged<PDFArtwork>.fromOpaque(info).takeUnretainedValue();s.stack.append(s.ctm)}
    CGPDFOperatorTableSetCallback(table,"Q") {_,info in guard let info else{return};let s=Unmanaged<PDFArtwork>.fromOpaque(info).takeUnretainedValue();if let t=s.stack.popLast(){s.ctm=t}}
    CGPDFOperatorTableSetCallback(table,"cm") {scanner,info in
      guard let info else{return};let s=Unmanaged<PDFArtwork>.fromOpaque(info).takeUnretainedValue();var values=[CGPDFReal](repeating:0,count:6)
      for i in (0..<6).reversed() {guard CGPDFScannerPopNumber(scanner,&values[i]) else{return}}
      let t=CGAffineTransform(a:values[0],b:values[1],c:values[2],d:values[3],tx:values[4],ty:values[5]);s.ctm=t.concatenating(s.ctm)
    }
    CGPDFOperatorTableSetCallback(table,"Do") {scanner,info in
      guard let info else{return};let s=Unmanaged<PDFArtwork>.fromOpaque(info).takeUnretainedValue();var name:UnsafePointer<CChar>?
      guard CGPDFScannerPopName(scanner,&name),let name else{return}
      let stream=CGPDFScannerGetContentStream(scanner)
      guard let object=CGPDFContentStreamGetResource(stream,"XObject",name) else{return}
      var x:CGPDFStreamRef?;guard CGPDFObjectGetValue(object,.stream,&x),let x else{return}
      guard let dictionary=CGPDFStreamGetDictionary(x) else{return};var subtype:UnsafePointer<CChar>?
      guard CGPDFDictionaryGetName(dictionary,"Subtype",&subtype),let subtype else{return}
      if String(cString:subtype)=="Image" {s.boxes.append(CGRect(x:0,y:0,width:1,height:1).applying(s.ctm))}
      else if String(cString:subtype)=="Form" {
        let saved=s.ctm,stack=s.stack;var matrix:CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary,"Matrix",&matrix),let matrix,CGPDFArrayGetCount(matrix)==6 {
          var v=[CGPDFReal](repeating:0,count:6);for i in 0..<6 {CGPDFArrayGetNumber(matrix,i,&v[i])}
          s.ctm=CGAffineTransform(a:v[0],b:v[1],c:v[2],d:v[3],tx:v[4],ty:v[5]).concatenating(s.ctm)
        }
        var resources:CGPDFDictionaryRef?;CGPDFDictionaryGetDictionary(dictionary,"Resources",&resources)
        s.scan(CGPDFContentStreamCreateWithStream(x,resources ?? dictionary,stream));s.ctm=saved;s.stack=stack
      }
    }
    let scanner=CGPDFScannerCreate(content,table,Unmanaged.passUnretained(self).toOpaque());CGPDFScannerScan(scanner)
  }
}

import AppKit
import Foundation
import JavaScriptCore
import ImageIO

/// Normalizes rich sources to HTML, retaining local images, tables and links.
/// No remote resource is fetched by the importer.
enum RichDocuments {
  static func convert(_ source:URL,to destination:URL,options:Options,engine:Engine) throws -> URL {
    let root=destination.deletingLastPathComponent().appendingPathComponent("rich-"+UUID().uuidString)
    try engine.fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer{try? engine.fm.removeItem(at:root)}
    let input=source.pathExtension.lowercased(),output=destination.pathExtension.lowercased()
    var document:XMLDocument
    if input == "epub" {document=try epub(source,root:root,engine:engine)}
    else if input == "md" {
      let resources=ProcessInfo.processInfo.environment["CLEMENTINE_RESOURCES"].map{URL(fileURLWithPath:$0)} ?? Bundle.main.resourceURL!
      guard let context=JSContext(),let js=try? String(contentsOf:resources.appendingPathComponent("marked.umd.js"),encoding:.utf8) else {throw ClementineError("Le moteur Markdown local est absent")}
      context.evaluateScript(js)
      let text=try Documents.read(source,engine:engine)
      let rendered=context.objectForKeyedSubscript("marked")?.objectForKeyedSubscript("parse")?.call(withArguments:[text])
      guard context.exception == nil,let html=rendered?.toString() else {throw ClementineError("Markdown illisible")}
      document=try parse(DocumentFidelity.html(html));try localize(document,base:source.deletingLastPathComponent(),root:root)
    } else if input == "rtfd" {
      let file=root.appendingPathComponent("Imported.html")
      try engine.process("/usr/bin/textutil",["-convert","html","-output",file.path,source.path])
      document=try parse(String(contentsOf:file,encoding:.utf8))
      try localize(document,base:source,root:root)
    } else if input == "textclipping" {
      // A clipping can contain rich RTFD, RTF or plain text. Prefer the richest representation.
      let attr: NSAttributedString
      if let rich=try clipping(source) {attr=rich}
      else {throw ClementineError("Ce texte extrait n’a pas de contenu riche lisible. Enregistrez-le en RTFD depuis son application.")}
      let data=try attr.data(from:NSRange(location:0,length:attr.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.html])
      document=try parse(String(data:data,encoding:.utf8) ?? "")
      try localize(document,base:source.deletingLastPathComponent(),root:root)
    } else if input == "html" {document=try parse(String(contentsOf:source,encoding:.utf8));try localize(document,base:source.deletingLastPathComponent(),root:root)}
    else {
      let html=root.appendingPathComponent("Imported.html")
      let exported=try Documents.office(source,to:html,engine:engine,options:options,rawHTML:true)
      var isDirectory:ObjCBool=false
      engine.fm.fileExists(atPath:exported.path,isDirectory:&isDirectory)
      let actual=isDirectory.boolValue ? exported.appendingPathComponent(source.deletingPathExtension().lastPathComponent+".html") : exported
      document=try parse(String(contentsOf:actual,encoding:.utf8))
      try localize(document,base:actual.deletingLastPathComponent(),root:root)
    }
    if output == "txt" {
      let body=(try? document.nodes(forXPath:"//body").first) ?? document.rootElement()
      let plain=body.map{plainText($0)} ?? ""
      try plain.write(to:destination,atomically:true,encoding:.utf8);return destination
    }
    if output == "md" {
      try markdownImages(document,to:destination,engine:engine)
      let body=(try? document.nodes(forXPath:"//body").first) ?? document.rootElement()
      let markdown=body.map{md($0)} ?? ""
      try markdown.trimmingCharacters(in:.whitespacesAndNewlines).appending("\n").write(to:destination,atomically:true,encoding:.utf8);return destination
    }
    let html=root.appendingPathComponent("Content.html")
    try document.xmlData(options:.nodeCompactEmptyElement).write(to:html)
    if output == "html" {
      try engine.fm.copyItem(at:html,to:destination);return destination
    }
    return try Documents.office(html,to:destination,engine:engine,options:options)
  }
  /// Standard Markdown readers resolve local image files; many reject data URLs.
  static func markdownAssets(for document: URL) -> URL {
    document.deletingLastPathComponent().appendingPathComponent(document.deletingPathExtension().lastPathComponent+"-images",isDirectory:true)
  }
  static func markdownImagePath(folder: String, file: String) -> String {
    let allowed=CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn:"()#?%[]"))
    return (folder+"/"+file).addingPercentEncoding(withAllowedCharacters:allowed)!
  }
  static func markdownImages(_ document: XMLDocument,to destination:URL,engine:Engine) throws {
    let images=try document.nodes(forXPath:"//img")
    guard !images.isEmpty else {return}
    let assets=markdownAssets(for:destination)
    try engine.fm.createDirectory(at:assets,withIntermediateDirectories:true)
    var exported:[Data:String]=[:]
    do {
      for node in images {
        try engine.token.check()
        guard let image=node as? XMLElement,let src=image.attribute(forName:"src")?.stringValue,
          let comma=src.firstIndex(of:","),src[..<comma].lowercased().hasPrefix("data:image/"),
          src[..<comma].lowercased().hasSuffix(";base64"),
          let data=Data(base64Encoded:String(src[src.index(after:comma)...]),options:.ignoreUnknownCharacters),
          data.count <= 128*1024*1024,
          let source=CGImageSourceCreateWithData(data as CFData,nil),
          let pixels=CGImageSourceCreateImageAtIndex(source,0,nil) else {
          throw ClementineError("Une illustration du document ne peut pas être exportée en Markdown.")
        }
        let filename:String
        if let previous=exported[data] {filename=previous}
        else {
          filename="image-\(exported.count+1).png"
          try DocumentFidelity.png(pixels,to:assets.appendingPathComponent(filename))
          exported[data]=filename
        }
        image.removeAttribute(forName:"src")
        image.addAttribute(XMLNode.attribute(withName:"src",stringValue:markdownImagePath(folder:assets.lastPathComponent,file:filename)) as! XMLNode)
      }
    } catch { try? engine.fm.removeItem(at:assets);throw error }
  }
  static func clipping(_ source:URL) throws -> NSAttributedString? {
    if let data=try? Data(contentsOf:source),!data.isEmpty,let attr=try? NSAttributedString(data:data,options:[:],documentAttributes:nil) {return attr}
    guard let data=try? Data(contentsOf:URL(fileURLWithPath:source.path+"/..namedfork/rsrc")),data.count>=30 else{return nil}
    func u16(_ o:Int)->Int {guard o>=0,o+2<=data.count else{return -1};return Int(data[o])<<8|Int(data[o+1])}
    func u32(_ o:Int)->Int {guard o>=0,o+4<=data.count else{return -1};return (0..<4).reduce(0){($0<<8)|Int(data[o+$1])}}
    let start=u32(0),map=u32(4),types=map+u16(map+24)
    guard start>=0,map>=0,types>=0,types+2<data.count else{return nil}
    let count=u16(types)+1;guard count>0,count<4096 else{return nil}
    var resources:[String:Data]=[:]
    for i in 0..<count {
      let entry=types+2+i*8;guard entry+8<=data.count else{continue}
      let type=String(data:data[entry..<entry+4],encoding:.macOSRoman) ?? ""
      let n=u16(entry+4)+1,refs=types+u16(entry+6);guard n>0,n<4096 else{continue}
      for j in 0..<n {
        let ref=refs+j*12;guard ref>=0,ref+12<=data.count else{continue}
        let offset=start+(Int(data[ref+5])<<16|Int(data[ref+6])<<8|Int(data[ref+7])),length=u32(offset)
        guard offset>=0,length>=0,length<=128*1024*1024,offset+4+length<=data.count else{continue}
        resources[type]=data.subdata(in:offset+4..<offset+4+length)
      }
    }
    for type in ["RTF ","rtf ","RTFD"] {if let d=resources[type],let value=try? NSAttributedString(data:d,options:[:],documentAttributes:nil){return value}}
    if let d=resources["utxt"],let text=String(data:d,encoding:.utf16BigEndian){return NSAttributedString(string:text)}
    if let d=resources["TEXT"],let text=String(data:d,encoding:.macOSRoman){return NSAttributedString(string:text)}
    return nil
  }
  static func parse(_ html:String) throws -> XMLDocument {
    guard html.utf8.count<=128*1024*1024,!html.localizedCaseInsensitiveContains("<!ENTITY") else {throw ClementineError("Document HTML trop volumineux ou illisible")}
    return try XMLDocument(xmlString:html,options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever])
  }
  static func localize(_ doc:XMLDocument,base:URL,root:URL) throws {
    // Remove active content and stylesheet references before giving HTML to the office engine.
    for node in (try? doc.nodes(forXPath:"//script|//iframe|//object|//embed|//link|//base")) ?? [] {node.detach()}
    for style in (try? doc.nodes(forXPath:"//style")) ?? [] {
      if (style.stringValue ?? "").localizedCaseInsensitiveContains("url(") || (style.stringValue ?? "").localizedCaseInsensitiveContains("@import") {style.detach()}
    }
    for element in (try? doc.nodes(forXPath:"//*")) ?? [] {
      guard let e=element as? XMLElement else{continue}
      for attr in e.attributes ?? [] {
        let key=(attr.name ?? "").lowercased(),value=attr.stringValue ?? ""
        if key.hasPrefix("on") || (key == "style" && (value.localizedCaseInsensitiveContains("url(") || value.localizedCaseInsensitiveContains("@import"))) {e.removeAttribute(forName:attr.name!)}
      }
    }
    for node in (try? doc.nodes(forXPath:"//img")) ?? [] {
      guard let e=node as? XMLElement,let src=e.attribute(forName:"src")?.stringValue else{continue}
      if src.hasPrefix("data:image/") {continue}
      let u=URL(string:src,relativeTo:URL(fileURLWithPath:base.path,isDirectory:true)).map{$0.absoluteURL}
      guard let u,u.isFileURL else {throw ClementineError("Une illustration distante ne peut pas être intégrée hors ligne. Enregistrez-la à côté du document.")}
      var resolved=u
      if !FileManager.default.fileExists(atPath:resolved.path) {
        let attachment=base.appendingPathComponent(u.lastPathComponent)
        if FileManager.default.fileExists(atPath:attachment.path) {resolved=attachment}
      }
      let data:Data
      do {data=try Data(contentsOf:resolved)} catch {throw ClementineError("Illustration locale introuvable : \(resolved.path)")}
      guard data.count <= 128*1024*1024, let image=NSImage(data:data),let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else {throw ClementineError("Illustration locale illisible : \(u.lastPathComponent)")}
      let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!
      e.removeAttribute(forName:"src");e.addAttribute(XMLNode.attribute(withName:"src",stringValue:"data:image/png;base64,"+png.base64EncodedString()) as! XMLNode)
    }
  }
  static func epub(_ source:URL,root:URL,engine:Engine) throws -> XMLDocument {
    let expanded=try engine.extract(source,stage:root)
    let container=try XMLDocument(contentsOf:expanded.appendingPathComponent("META-INF/container.xml"),options:.nodeLoadExternalEntitiesNever)
    guard let opf=(try container.nodes(forXPath:"//*[local-name()='rootfile']/@full-path").first)?.stringValue else{throw ClementineError("EPUB sans manifeste")}
    func safe(_ path:String,base:URL) throws -> URL {
      guard let u=URL(string:path,relativeTo:URL(fileURLWithPath:base.path,isDirectory:true))?.absoluteURL,u.isFileURL else {throw ClementineError("Référence EPUB invalide")}
      let result=u.standardizedFileURL.resolvingSymlinksInPath(),prefix=expanded.standardizedFileURL.resolvingSymlinksInPath().path+"/"
      guard result.path.hasPrefix(prefix) else{throw ClementineError("Une ressource EPUB sort du livre")};return result
    }
    let package=try safe(opf,base:expanded),manifest=try XMLDocument(contentsOf:package,options:.nodeLoadExternalEntitiesNever)
    var items:[String:String]=[:]
    for node in try manifest.nodes(forXPath:"//*[local-name()='manifest']/*[local-name()='item']") {if let e=node as? XMLElement,let id=e.attribute(forName:"id")?.stringValue,let href=e.attribute(forName:"href")?.stringValue {items[id]=href}}
    var content=""
    for node in try manifest.nodes(forXPath:"//*[local-name()='spine']/*[local-name()='itemref']") {
      try engine.token.check()
      guard let e=node as? XMLElement,let id=e.attribute(forName:"idref")?.stringValue,let href=items[id] else{throw ClementineError("Chapitre EPUB manquant")}
      let u=try safe(href,base:package.deletingLastPathComponent()),chapter=try parse(String(contentsOf:u,encoding:.utf8))
      try localize(chapter,base:u.deletingLastPathComponent(),root:root)
      guard let body=(try chapter.nodes(forXPath:"//*[local-name()='body']").first) else{throw ClementineError("Chapitre EPUB sans contenu")}
      content += "<section>"+(body.children ?? []).map{$0.xmlString}.joined()+"</section>"
    }
    guard !content.isEmpty else{throw ClementineError("EPUB vide")};return try parse(DocumentFidelity.html(content))
  }
  static func plainText(_ node:XMLNode)->String {
    if node.kind == .text {return node.stringValue ?? ""}
    let name=(node.name ?? "").lowercased();if ["script","style","head"].contains(name){return ""}
    let text=(node.children ?? []).map{plainText($0)}.joined()
    return text+(["p","div","section","h1","h2","h3","li","tr","br"].contains(name) ? "\n" : "")
  }
  static func md(_ node:XMLNode)->String {
    if node.kind == .text {return (node.stringValue ?? "").replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"*",with:"\\*").replacingOccurrences(of:"_",with:"\\_")}
    let tag=(node.name ?? "").lowercased(),e=node as? XMLElement
    func attr(_ name:String)->String {e?.attribute(forName:name)?.stringValue ?? ""}
    let children=(node.children ?? []).map{md($0)}.joined()
    switch tag {
    case "head","script","style":return ""
    case "h1","h2","h3","h4","h5","h6":return "\n\n"+String(repeating:"#",count:Int(tag.dropFirst())!)+" "+children+"\n\n"
    case "p","div","section":return "\n\n"+children+"\n\n"
    case "strong","b":return "**"+children+"**"
    case "em","i":return "*"+children+"*"
    case "pre":return "\n\n```\n"+plainText(node)+"\n```\n\n"
    case "code":return "`"+plainText(node)+"`"
    case "a":return "["+children+"]("+attr("href")+")"
    case "img":
      let alt=attr("alt").replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"[",with:"\\[").replacingOccurrences(of:"]",with:"\\]").replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ")
      return "!["+alt+"]("+attr("src")+")"
    case "br":return "  \n"
    case "li":return "\n- "+children.trimmingCharacters(in:.whitespacesAndNewlines)
    case "table":
      let rows=(try? node.nodes(forXPath:".//*[local-name()='tr']")) ?? []
      return "\n\n"+rows.enumerated().map{index,row in
        let cells=(row.children ?? []).filter{["td","th"].contains(($0.name ?? "").lowercased())}
        let line="| "+cells.map{md($0).replacingOccurrences(of:"|",with:"\\|").replacingOccurrences(of:"\n",with:" ")}.joined(separator:" | ")+" |"
        return line+(index == 0 ? "\n| "+cells.map{_ in "---"}.joined(separator:" | ")+" |" : "")
      }.joined(separator:"\n")+"\n\n"
    default:return children
    }
  }
}

import Foundation
import PDFKit
import CoreGraphics
func pixels(_ page:PDFPage) -> [UInt8] {
 let width=420,height=600
 var bytes=[UInt8](repeating:255,count:width*height*4)
 bytes.withUnsafeMutableBytes { memory in
  let c=CGContext(data:memory.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height))
  let ref=page.pageRef!;c.concatenate(ref.getDrawingTransform(.mediaBox,rect:CGRect(x:0,y:0,width:width,height:height),rotate:0,preserveAspectRatio:true));c.drawPDFPage(ref)
 }
 return bytes
}
let args=CommandLine.arguments
let original=PDFDocument(url:URL(fileURLWithPath:args[1]))!,expected=(0..<original.pageCount).map{pixels(original.page(at:$0)!)}
var report:[[String:Any]]=[]
for path in args.dropFirst(2) {
 guard let doc=PDFDocument(url:URL(fileURLWithPath:path)),doc.pageCount==original.pageCount else {report.append(["file":path,"passed":false,"reason":"page count"]);continue}
 let errors=(0..<doc.pageCount).map{index -> Double in let actual=pixels(doc.page(at:index)!);return zip(expected[index],actual).map{abs(Int($0.0)-Int($0.1))}.reduce(0.0){$0+Double($1)}/Double(actual.count)}
 let maxError=errors.max() ?? 255
 report.append(["file":path,"pageMeanAbsoluteErrors":errors,"passed":maxError<8])
}
let output=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(data:output,encoding:.utf8)!)

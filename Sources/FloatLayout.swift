import AppKit

enum FloatLayout {
  static let compact = CGSize(width:100,height:115)
  static let headerHeight:CGFloat = 163
  static func columns(_ count:Int) -> Int { min(3,max(1,Int(ceil(sqrt(Double(max(1,count))))))) }
  static func size(count:Int,expanded:Bool) -> CGSize {
    guard expanded else{return compact}
    let columns=columns(count),rows=max(1,Int(ceil(Double(count)/Double(columns))))
    return CGSize(width:CGFloat(columns)*88+24,height:headerHeight+CGFloat(min(3,rows))*92+12)
  }
  static func frame(size:CGSize,anchoredTo frame:CGRect,in screen:CGRect) -> CGRect {
    let pinnedLeft=abs(frame.minX-screen.minX)<1
    let pinnedRight=abs(frame.maxX-screen.maxX)<1
    let preferredX=pinnedLeft ? screen.minX : pinnedRight ? screen.maxX-size.width : frame.midX-size.width/2
    let x=min(max(preferredX,screen.minX),max(screen.minX,screen.maxX-size.width))
    let y=min(max(frame.maxY-size.height,screen.minY),max(screen.minY,screen.maxY-size.height))
    return CGRect(origin:CGPoint(x:x,y:y),size:size)
  }
  static func draggedOrigin(_ origin:CGPoint,delta:CGSize,size:CGSize,in screen:CGRect)->CGPoint {
    CGPoint(
      x:min(max(origin.x+delta.width,screen.minX),max(screen.minX,screen.maxX-size.width)),
      y:min(max(origin.y+delta.height,screen.minY),max(screen.minY,screen.maxY-size.height))
    )
  }
  static func pinnedOrigin(_ origin:CGPoint,size:CGSize,in screen:CGRect,threshold:CGFloat=20)->CGPoint {
    let left=abs(origin.x-screen.minX)
    let right=abs(origin.x+size.width-screen.maxX)
    let x:CGFloat
    if left<=threshold || right<=threshold {
      x=left<=right ? screen.minX : screen.maxX-size.width
    } else {x=origin.x}
    return draggedOrigin(CGPoint(x:x,y:origin.y),delta:.zero,size:size,in:screen)
  }
}

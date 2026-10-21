import AppKit
import CoreImage

extension Engine {
  // Core Image may not create a context while the login screen owns the display.
  // This path also lets exports continue in that state; it never returns an unedited image.
  func moduleCPUPixels(_ image:CGImage,adjustments:[String:Double] = [:],blurRadius:Double = 0) throws -> CGImage {
    let width=image.width,height=image.height,count=width*height
    var bytes=[UInt8](repeating:0,count:count*4)
    let rendered=bytes.withUnsafeMutableBytes {buffer -> Bool in
      guard let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return false}
      context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
    }
    guard rendered else {throw ClementineError(tr("Mémoire insuffisante pour le rendu"))}
    func v(_ name:String)->Double {adjustments[name] ?? 0}
    let exposure=pow(2,v("Exposure")),contrast=1+v("Contrast")/100+v("Dehaze")/200-v("Fade")/250
    let brightness=v("Brightness")/100-v("Dehaze")/1000+v("Fade")/1000,gamma=pow(2,v("Gamma")/100)
    let saturation=1+v("Saturation")/100-v("Fade")/500
    let temperature=v("Temperature")/500,tint=v("Tint")/500
    var seed:UInt64=0x6f72616e6765
    for index in 0..<count {
      if index%max(1,width*64)==0 {try token.check()}
      let offset=index*4,alpha=Double(bytes[offset+3])/255
      guard alpha>0 else {continue}
      var r=Double(bytes[offset])/255/alpha,g=Double(bytes[offset+1])/255/alpha,b=Double(bytes[offset+2])/255/alpha
      let luminance=0.2126*r+0.7152*g+0.0722*b
      let shadows=v("Shadows")/100*pow(1-luminance,2)*0.35
      let highlights=v("Highlights")/100*pow(luminance,2)*0.35
      let tone=shadows+highlights+v("Whites")/500*luminance+v("Blacks")/500*(1-luminance)
      r=(r*exposure+tone+brightness-0.5)*contrast+0.5+temperature-tint/2
      g=(g*exposure+tone+brightness-0.5)*contrast+0.5+tint
      b=(b*exposure+tone+brightness-0.5)*contrast+0.5-temperature-tint/2
      r=pow(max(0,r),gamma);g=pow(max(0,g),gamma);b=pow(max(0,b),gamma)
      let gray=0.2126*r+0.7152*g+0.0722*b
      let chroma=max(r,max(g,b))-min(r,min(g,b))
      let color=saturation+v("Vibrance")/100*(1-min(1,chroma))
      r=gray+(r-gray)*color;g=gray+(g-gray)*color;b=gray+(b-gray)*color
      if v("Hue") != 0 {
        let angle=v("Hue") * .pi/180,cosine=cos(angle),sine=sin(angle)
        let nr=(0.213+cosine*0.787-sine*0.213)*r+(0.715-cosine*0.715-sine*0.715)*g+(0.072-cosine*0.072+sine*0.928)*b
        let ng=(0.213-cosine*0.213+sine*0.143)*r+(0.715+cosine*0.285+sine*0.140)*g+(0.072-cosine*0.072-sine*0.283)*b
        let nb=(0.213-cosine*0.213-sine*0.787)*r+(0.715-cosine*0.715+sine*0.715)*g+(0.072+cosine*0.928+sine*0.072)*b
        r=nr;g=ng;b=nb
      }
      let x=(Double(index%width)/Double(width)-0.5)*2,y=(Double(index/width)/Double(height)-0.5)*2
      let vignette=max(0,1-v("Vignette")/100*min(1,(x*x+y*y)/2))
      seed=seed &* 6364136223846793005 &+ 1
      let grain=(Double((seed>>32)&0xffff)/65535-0.5)*v("Grain")/400
      for (channel,value) in [r,g,b].enumerated() {bytes[offset+channel]=UInt8(min(255,max(0,(value*vignette+grain)*alpha*255)))}
    }
    let blur=max(blurRadius,v("Blur")/4)
    if blur>0 {bytes=Self.moduleBoxBlur(bytes,width:width,height:height,radius:max(1,Int(blur)))}
    let detail=(v("Sharpness")+v("Clarity")+v("Texture"))/150
    let noise=v("Noise Reduction")/100
    if detail != 0 || noise>0 {
      let smooth=Self.moduleBoxBlur(bytes,width:width,height:height,radius:1)
      for i in bytes.indices where i%4 != 3 {
        let original=Double(bytes[i]),base=Double(smooth[i])
        bytes[i]=UInt8(min(255,max(0,original+(original-base)*detail+(base-original)*noise)))
      }
    }
    guard let provider=CGDataProvider(data:Data(bytes) as CFData),let result=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw ClementineError(tr("Rendu de l’image impossible"))}
    return result
  }
  static func moduleBoxBlur(_ pixels:[UInt8],width:Int,height:Int,radius:Int)->[UInt8] {
    let r=min(radius,max(width,height)),diameter=2*r+1
    var horizontal=[UInt8](repeating:0,count:pixels.count),output=horizontal
    for y in 0..<height {for channel in 0..<4 {
      var sum=0
      for x in -r...r {sum+=Int(pixels[(y*width+min(width-1,max(0,x)))*4+channel])}
      for x in 0..<width {
        horizontal[(y*width+x)*4+channel]=UInt8(sum/diameter)
        sum-=Int(pixels[(y*width+min(width-1,max(0,x-r)))*4+channel]);sum+=Int(pixels[(y*width+min(width-1,max(0,x+r+1)))*4+channel])
      }
    }}
    for x in 0..<width {for channel in 0..<4 {
      var sum=0
      for y in -r...r {sum+=Int(horizontal[(min(height-1,max(0,y))*width+x)*4+channel])}
      for y in 0..<height {
        output[(y*width+x)*4+channel]=UInt8(sum/diameter)
        sum-=Int(horizontal[(min(height-1,max(0,y-r))*width+x)*4+channel]);sum+=Int(horizontal[(min(height-1,max(0,y+r+1))*width+x)*4+channel])
      }
    }}
    return output
  }
}

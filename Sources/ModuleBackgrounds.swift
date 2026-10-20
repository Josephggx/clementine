import AppKit

enum ModuleBackgrounds {
  static let names = ["Citrus","Mesh","Meadow","Whisper","Orchid","Oasis","Lagoon","Aqua","Dream","Sorbet","Frost","Emerald","Sunset","Sky","Mint","Violet","Graphite"]
  static let solids = ["#FFFFFF","#E7D56D","#B4CE67","#72A17B","#639B97","#87C4D4","#526BC9","#293748","#7554AF","#B3A1CF","#D996AE","#C85C59","#DC9983","#EBA660","#967365","#909292","#111315"]
  static let colors:[String:[String]] = [
    "Citrus":["#EC92A5","#F4D45C","#DFA076","#8963B1"],
    "Mesh":["#B5A4D7","#E3ECF3","#EFD68B","#98BFDB"],
    "Meadow":["#CFEA9B","#F2E9A0","#A8CC87","#CEE9BE"],
    "Whisper":["#DFC2DC","#F6E7DD","#B6C6DD","#EEE0E9"],
    "Orchid":["#B9A2DB","#DAD4F0","#E7BDDF","#EACAAC"],
    "Oasis":["#326D65","#93C7AF","#D7928E","#3A7B6D"],
    "Lagoon":["#288C9F","#8AD0E3","#4664A7","#52B5B6"],
    "Aqua":["#9AD5E7","#E4F4F5","#7FBFD5","#AACEE8"],
    "Dream":["#E6BEDF","#C9E7E9","#B8ACE0","#ECCBDF"],
    "Sorbet":["#F2B098","#F5D099","#D897B6","#DFBCE3"],
    "Frost":["#D4E5F3","#F4FAFD","#B8CBDF","#E6DFF1"],
    "Emerald":["#4D8E77","#BADCB6","#2B6B64","#6EAB8B"],
    "Sunset":["#E89391","#F7BB77","#C57997","#8572BC"],
    "Sky":["#89B8EA","#D6EBFA","#AAC9EC","#B7DDE7"],
    "Mint":["#A3D2BE","#DBEFE0","#8FBFC1","#B4DACE"],
    "Violet":["#9978C0","#C7B2E8","#8A9AD4","#C9A4D4"],
    "Graphite":["#424B54","#7B858B","#252D36","#596473"]
  ]
  static func draw(_ context:CGContext,rect:CGRect,name:String) {
    let colors=(colors[name] ?? colors["Citrus"]!).map {NSColor(hex:$0)}
    context.setFillColor(colors[0].cgColor);context.fill(rect)
    let points=[CGPoint(x:rect.maxX,y:rect.maxY),CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY)]
    for (i,point) in points.enumerated() {
      let color=colors[i+1]
      let stops=[color.cgColor,color.withAlphaComponent(0).cgColor]
      if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:stops as CFArray,locations:[0,1]) {
        context.drawRadialGradient(gradient,startCenter:point,startRadius:0,endCenter:point,endRadius:max(rect.width,rect.height)*0.92,options:.drawsBeforeStartLocation)
      }
    }
  }
}

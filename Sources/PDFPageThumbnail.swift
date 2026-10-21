import AppKit
import SwiftUI

private final class PDFPageThumbnailState: ObservableObject {
  @Published var menu=false
  @Published var control:String?
}

/// Shared by Organize and custom Split, including page sizing and the expanding glass menu.
struct PDFPageThumbnailCard: View {
  var image:NSImage?
  var rotation:Int
  var title:String
  var editable=false
  var rotate:()->Void = {}
  var duplicate:()->Void = {}
  var remove:()->Void = {}
  @StateObject private var hover=PDFPageThumbnailState()
  var body: some View {
    VStack(spacing:6) {
      ZStack(alignment:.topTrailing) {
        if let image {
          let turns=rotation%180 != 0
          Image(nsImage:image).resizable().scaledToFit()
            .frame(width:turns ? 116 : 82,height:turns ? 82 : 116)
            .rotationEffect(.degrees(Double(rotation)))
            .frame(maxWidth:.infinity).frame(height:116).clipped()
            .shadow(color:.black.opacity(0.12),radius:3,y:1)
        }
        if editable {
          HStack(spacing:2) {
            if hover.menu {
              control("trash",title:"Supprimer",action:remove)
              control("arrow.clockwise",title:"Pivoter",action:rotate)
              control("plus.square.on.square",title:"Dupliquer",action:duplicate)
            } else {
              Button {hover.menu=true} label:{Image(systemName:"ellipsis").frame(width:22,height:24)}
                .buttonStyle(.plain).help(tr("Options de la page"))
            }
          }.padding(2).background(.regularMaterial,in:Capsule())
            .onHover {inside in hover.menu=inside;if !inside {hover.control=nil}}
            .animation(.easeOut(duration:0.14),value:hover.menu)
        }
      }.frame(height:116)
      Text(title).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
    }.padding(8).frame(maxWidth:.infinity).frame(height:152)
      .background(Color.clementineRaisedSurface,in:RoundedRectangle(cornerRadius:9))
  }
  private func control(_ icon:String,title:String,action:@escaping()->Void) -> some View {
    let hovered=hover.control == icon
    return Button(action:action) {
      Image(systemName:icon).font(.system(size:10)).foregroundStyle(.primary)
        .frame(width:24,height:24)
        .background(hovered ? citrus.opacity(0.16) : .clear,in:Circle())
    }
    .buttonStyle(.plain).help(trString(title)).accessibilityLabel(trString(title))
    .onHover {inside in
      hover.control=inside ? icon : (hover.control == icon ? nil : hover.control)
    }
    .animation(.easeInOut(duration:0.14),value:hovered)
  }
}

struct PDFPageInsertionHighlight: ViewModifier {
  var active:Bool
  func body(content:Content) -> some View {
    content.offset(x:active ? 7 : 0)
      .overlay(alignment:.leading) {
        Capsule().fill(citrus).frame(width:3).padding(.vertical,4)
          .opacity(active ? 1 : 0).offset(x:-5)
      }
      .animation(.easeOut(duration:0.16),value:active)
  }
}

import AppKit
import SwiftUI

/// A single nonactivating toast: rapid repeated copies replace the previous one.
final class PointerToast {
  static let shared = PointerToast()
  private var panel:NSPanel?
  private var dismissal:DispatchWorkItem?
  private var generation=0

  func show() {
    dismissal?.cancel()
    generation += 1
    let token=generation
    let panel=self.panel ?? NSPanel(contentRect:.zero,
      styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    self.panel=panel
    panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true
    panel.ignoresMouseEvents=true;panel.hidesOnDeactivate=false
    panel.level = .statusBar;panel.collectionBehavior=FloatingWindowPresentation.wheel
    panel.contentView=NSHostingView(rootView:
      Text(tr("Copié !")).font(.system(size:12,weight:.medium))
        .padding(.horizontal,14).padding(.vertical,8)
        .background(.regularMaterial,in:Capsule()))
    let point=NSEvent.mouseLocation
    let screen=NSScreen.screens.first {$0.frame.contains(point)} ?? NSScreen.main
    let area=screen?.visibleFrame ?? CGRect(x:0,y:0,width:1000,height:800)
    let size=CGSize(width:102,height:38)
    let origin=CGPoint(x:min(max(point.x-size.width/2,area.minX+4),area.maxX-size.width-4),
      y:min(max(point.y+22,area.minY+4),area.maxY-size.height-4))
    panel.setFrame(CGRect(origin:origin,size:size),display:true)
    panel.alphaValue=0;panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration=0.12;panel.animator().alphaValue=1
    }
    let work=DispatchWorkItem { [weak self,weak panel] in
      guard let self,let panel,self.generation == token else {return}
      NSAnimationContext.runAnimationGroup({ context in
        context.duration=0.18;panel.animator().alphaValue=0
      },completionHandler:{ [weak self,weak panel] in
        guard self?.generation == token else {return};panel?.orderOut(nil)
      })
    }
    dismissal=work
    DispatchQueue.main.asyncAfter(deadline:.now()+0.95,execute:work)
  }
}

import SwiftUI

extension ModuleSession {
  func editOrganizedPage(_ id:UUID,action:String) {
    guard tool == "organize", !busy, !loading,
      let offset=options.modulePages.firstIndex(where:{$0.id == id}) else {return}
    withAnimation(.snappy(duration:0.24)) {
      let page=options.modulePages[offset]
      switch action {
      case "rotate": options.modulePages[offset].rotation=(page.rotation+90)%360
      case "duplicate": options.modulePages.insert(ModulePage(index:page.index,rotation:page.rotation),at:offset+1)
      case "remove": options.modulePages.remove(at:offset)
      default: break
      }
    }
  }

  func moveOrganizedPage(_ id:UUID,before target:UUID? = nil) {
    guard tool == "organize", !busy, !loading, id != target,
      let source=options.modulePages.firstIndex(where:{$0.id == id}),
      target == nil || options.modulePages.contains(where:{$0.id == target}) else {return}
    withAnimation(.snappy(duration:0.24)) {
      let page=options.modulePages.remove(at:source)
      let destination=target.flatMap {target in options.modulePages.firstIndex(where:{$0.id == target})} ?? options.modulePages.count
      options.modulePages.insert(page,at:destination)
    }
  }
}

import AppKit

extension ModuleSession {
  var currentImageEdit: ModuleImageEdit {
    .init(crop:.init(x:options.x,y:options.y,width:options.width,height:options.height), marks:options.marks)
  }

  func restoreImageEdit(_ edit: ModuleImageEdit) {
    options.x=edit.crop.x; options.y=edit.crop.y
    options.width=edit.crop.width; options.height=edit.crop.height; options.marks=edit.marks
  }

  func persistImageEdit() {
    guard tool == "annotate", sourceImage != nil, !loading, files.indices.contains(activeFile) else { return }
    var edits = options.moduleImageEdits ?? [:]
    edits[files[activeFile].path] = currentImageEdit
    options.moduleImageEdits = edits
    imageEditHistories[files[activeFile].path] = undoStack
  }

  func restoreImageEdit(for file: URL, image: CGImage) {
    restoreImageEdit(options.moduleImageEdits?[file.path] ?? .init(
      crop:.init(x:0,y:0,width:image.width,height:image.height),marks:[]))
    undoStack = imageEditHistories[file.path] ?? []
    selectedMark = nil
  }

  /// The same source-space marks survive both narrowing and expanding the crop.
  func setImageEditMode(_ mode: String) {
    guard ["annotate","crop"].contains(mode), mode != imageEditMode else { return }
    clampImageCrop()
    selectedMark=nil; previewScale=1; previewOffset = .zero; imageEditMode=mode
  }

  func clampImageCrop() {
    guard let image = sourceImage else { return }
    options.x=min(max(0,options.x),image.width-1)
    options.y=min(max(0,options.y),image.height-1)
    options.width=min(max(1,options.width),image.width-options.x)
    options.height=min(max(1,options.height),image.height-options.y)
  }

  var imageCropRect: CGRect {
    guard let image = sourceImage else { return CGRect(x:0,y:0,width:1,height:1) }
    return CGRect(x:Double(options.x)/Double(image.width),y:Double(options.y)/Double(image.height),
      width:Double(max(1,options.width))/Double(image.width),height:Double(max(1,options.height))/Double(image.height))
  }
}

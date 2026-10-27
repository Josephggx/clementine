import AppKit
import AVFoundation

/// Bookmarks follow Finder renames/moves; file IDs collapse aliases to the same item.
/// No directory traversal, filesystem polling outside the explicitly tracked items, or Trash access is required.
final class TrackedFiles {
  struct Record {
    var bookmark:Data?
    var signature:String
  }
  struct Change {
    var urls:[URL]
    var renamed:[URL:URL]
    var removed:[URL]
    var metadataChanged:Bool
  }
  private var records:[URL:Record] = [:]
  static func isInTrash(_ url:URL) -> Bool {
    url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
  }
  static func sameItem(_ lhs:URL,_ rhs:URL) -> Bool {
    if lhs.standardizedFileURL == rhs.standardizedFileURL { return true }
    let keys:Set<URLResourceKey>=[.fileResourceIdentifierKey,.volumeIdentifierKey]
    guard let a=try? fresh(lhs).resourceValues(forKeys:keys),
      let b=try? fresh(rhs).resourceValues(forKeys:keys),
      let aid=a.fileResourceIdentifier as? NSObject, let bid=b.fileResourceIdentifier as? NSObject,
      let av=a.volumeIdentifier as? NSObject, let bv=b.volumeIdentifier as? NSObject else { return false }
    return aid.isEqual(bid) && av.isEqual(bv)
  }
  static func unique(_ urls:[URL]) -> [URL] {
    urls.reduce(into:[]) { result,url in if !result.contains(where:{sameItem($0,url)}) {result.append(url)} }
  }
  private static func fresh(_ url:URL) -> URL {
    // URL caches resource values. Construct a new URL so metadata updates are observed.
    URL(fileURLWithPath:url.path,isDirectory:url.hasDirectoryPath)
  }
  private static func signature(_ url:URL) -> String {
    let value=try? fresh(url).resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.fileResourceIdentifierKey])
    return "\(value?.fileSize ?? 0):\(value?.contentModificationDate?.timeIntervalSince1970 ?? 0):\((value?.fileResourceIdentifier as? NSObject)?.hash ?? 0)"
  }
  func observe(_ urls:[URL]) {
    records=Dictionary(uniqueKeysWithValues:urls.map { url in
      (url,records[url] ?? Record(bookmark:try? url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil),signature:Self.signature(url)))
    })
  }
  func refresh(_ urls:[URL]) -> Change {
    var result=Change(urls:[],renamed:[:],removed:[],metadataChanged:false)
    for original in urls {
      var resolved=original
      if let data=records[original]?.bookmark {
        var stale=false
        if let found=try? URL(resolvingBookmarkData:data,options:[.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale) {
          if original.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == found.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL {
            resolved=original.deletingLastPathComponent().appendingPathComponent(found.lastPathComponent,isDirectory:found.hasDirectoryPath)
          } else {resolved=Self.fresh(found)}
        }
      }
      if Self.isInTrash(resolved) { result.removed.append(original); continue }
      do {
        guard try resolved.checkResourceIsReachable() else {result.removed.append(original); continue}
      } catch {
        let error=error as NSError
        if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(error.code) {
          result.removed.append(original); continue
        }
        // A transient permission or volume failure must not discard the user's selection.
        resolved=original
      }
      if original.standardizedFileURL != resolved.standardizedFileURL {result.renamed[original]=resolved}
      if let old=records[original],old.signature != Self.signature(resolved) {result.metadataChanged=true}
      if !result.urls.contains(where:{Self.sameItem($0,resolved)}) {result.urls.append(resolved)}
    }
    records=Dictionary(uniqueKeysWithValues:result.urls.map { url in
      (url,Record(bookmark:records[url]?.bookmark ?? (try? url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)),signature:Self.signature(url)))
    })
    return result
  }
}

extension AppState {
  func refreshPinnedFiles() {
    let change=pinnedTracker.refresh(files)
    fileRelocations=change.renamed
    if files != change.urls { files=change.urls }
    if change.metadataChanged || !change.renamed.isEmpty { fileRevision &+= 1 }
    for url in change.removed {
      pinnedFileOperations.removeValue(forKey:url)
      for job in jobs where !job.done && job.files.contains(url) {cancel(job.id)}
    }
  }
}

extension ModuleSession {
  /// Keep editors attached to the actual Finder items while retaining edits on survivors.
  func reconcileFiles(_ change:TrackedFiles.Change) {
    guard !cataloguePreview else {return}
    if change.urls.isEmpty {cancel(); return}
    guard files != change.urls else {return}
    if tool == "annotate", !loading {persistImageEdit()}
    let wasLoading=loading
    let selected=files.indices.contains(activeFile) ? files[activeFile] : files.first
    pause()
    if busy {interruptForFileChange()}
    for (old,new) in change.renamed {
      if let value=options.moduleImageEdits?.removeValue(forKey:old.path) {options.moduleImageEdits?[new.path]=value}
      if let value=imageEditHistories.removeValue(forKey:old.path) {imageEditHistories[new.path]=value}
      if let value=splitThumbnails.removeValue(forKey:old) {splitThumbnails[new]=value}
      if let value=fileThumbnails.removeValue(forKey:old) {fileThumbnails[new]=value}
      if let value=options.pdfSplitGroups.removeValue(forKey:old.path) {options.pdfSplitGroups[new.path]=value}
      if let value=options.pdfSplitEdits.removeValue(forKey:old.path) {options.pdfSplitEdits[new.path]=value}
      if let value=options.moduleCrops.removeValue(forKey:old.path) {options.moduleCrops[new.path]=value}
    }
    for removed in change.removed {
      options.moduleImageEdits?.removeValue(forKey:removed.path);imageEditHistories.removeValue(forKey:removed.path)
      splitThumbnails.removeValue(forKey:removed);fileThumbnails.removeValue(forKey:removed)
      options.pdfSplitGroups.removeValue(forKey:removed.path);options.pdfSplitEdits.removeValue(forKey:removed.path)
      options.moduleCrops.removeValue(forKey:removed.path)
    }
    files=change.urls
    activeFile=selected.flatMap {files.firstIndex(of:change.renamed[$0] ?? $0)} ?? 0
    if family == .video || family == .audio {player.replaceCurrentItem(with:AVPlayerItem(url:files[activeFile]))}
    if wasLoading {load();return}
    if family == .image, let selected, change.removed.contains(selected) {
      refreshImageAfterFileChange()
    } else if tool == "collage" {renderPreview()}
  }
}

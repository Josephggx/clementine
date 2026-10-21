import AppKit
import SwiftUI

enum WorkspaceFileOperations {
  static func canExtract(_ url:URL) -> Bool {
    !Family.isFolder(url) && ["zip","tar","gz","gzip","tgz"].contains(url.pathExtension.lowercased())
  }

  /// Finder-style independent copies, beside each original, without overwriting.
  static func duplicate(_ urls:[URL]) throws -> [URL] {
    let fm=FileManager.default
    var outputs:[URL]=[]
    do {
      for source in TrackedFiles.unique(urls) {
        let folder=source.deletingLastPathComponent()
        let ext=Family.isFolder(source) ? "" : source.pathExtension
        let stem=ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        var count=1
        var destination:URL
        repeat {
          let suffix=count == 1 ? " copie" : " copie \(count)"
          destination=folder.appendingPathComponent(stem+suffix+(ext.isEmpty ? "" : "."+ext))
          count += 1
        } while fm.fileExists(atPath:destination.path) || (try? fm.destinationOfSymbolicLink(atPath:destination.path)) != nil
        try fm.copyItem(at:source,to:destination)
        outputs.append(destination)
      }
      return outputs
    } catch {
      for output in outputs {try? fm.removeItem(at:output)}
      throw error
    }
  }

  static func editableName(_ source:URL) -> String {
    Family.isFolder(source) || source.pathExtension.isEmpty
      ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
  }

  static func rename(_ source:URL, to input:String) throws -> URL {
    var name = input.trimmingCharacters(in:.whitespacesAndNewlines)
    let suffix = Family.isFolder(source) || source.pathExtension.isEmpty ? "" : "."+source.pathExtension
    if !suffix.isEmpty, name.lowercased().hasSuffix(suffix.lowercased()) { name = String(name.dropLast(suffix.count)) }
    guard !name.isEmpty, !name.hasPrefix("."),
      !name.contains("/"), !name.contains(":"), !name.contains("\0"),
      !name.contains("\n"), !name.contains("\r") else {
      throw ClementineError(tr("Choisissez un nom sans / ni : et ne commençant pas par un point."))
    }
    let destination = source.deletingLastPathComponent().appendingPathComponent(name+suffix)
    if destination == source { return source }
    let fm = FileManager.default
    if fm.fileExists(atPath:destination.path) || (try? fm.destinationOfSymbolicLink(atPath:destination.path)) != nil {
      let oldID = try? source.resourceValues(forKeys:[.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
      let newID = try? destination.resourceValues(forKeys:[.fileResourceIdentifierKey]).fileResourceIdentifier as? NSObject
      let caseOnly = source.lastPathComponent.lowercased() == destination.lastPathComponent.lowercased()
      guard caseOnly, let oldID, let newID, oldID.isEqual(newID) else {
        throw ClementineError(tr("Un élément porte déjà ce nom. Choisissez un autre nom."))
      }
    }
    try fm.moveItem(at:source,to:destination)
    return destination
  }

  static func extractedContents(_ folders:[URL]) throws -> [URL] {
    try folders.flatMap { folder in
      guard FileManager.default.fileExists(atPath:folder.path),
        !folder.pathComponents.contains(where:{$0.hasPrefix(".clementine-")}) else {
        throw ClementineError(tr("Les fichiers extraits ne sont pas disponibles sur le disque."))
      }
      return try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
        .filter { !["__MACOSX", ".DS_Store"].contains($0.lastPathComponent) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
  }
}

extension AppState {
  func isPinnedFileBusy(_ url:URL) -> Bool {
    pinnedFileOperations[url] != nil || jobs.contains { !$0.done && $0.files.contains(url) }
  }

  /// Replace only an item that is still pinned. Results must not reappear after
  /// the user clears the workspace while a disk operation is finishing.
  func replacePinnedFile(_ source:URL, with replacements:[URL]) {
    guard let offset = files.firstIndex(of:source) else { return }
    var updated = files
    updated.remove(at:offset)
    let unique = TrackedFiles.unique(replacements).filter { candidate in !updated.contains(where:{TrackedFiles.sameItem($0,candidate)}) }
    updated.insert(contentsOf:unique,at:min(offset,updated.count))
    files = updated
    if !Tool.available(files).contains(where:{$0.id == selectedTool}) { selectedTool = nil }
    if !formats.contains(format) { format = formats.first ?? "png" }
  }

  func renamePinnedFile(_ source:URL, to name:String) throws -> URL {
    guard files.contains(source), !isPinnedFileBusy(source) else {
      throw ClementineError(tr("Ce document est en cours d’utilisation. Réessayez après l’opération."))
    }
    let destination = try WorkspaceFileOperations.rename(source,to:name)
    replacePinnedFile(source,with:[destination])
    return destination
  }

  func trashPinnedFile(_ source:URL,
    recycle: ((URL,@escaping(Error?)->Void)->Void)? = nil) {
    guard files.contains(source), !isPinnedFileBusy(source) else { return }
    pinnedFileOperations[source] = "delete"
    let completed: (Error?)->Void = { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.pinnedFileOperations.removeValue(forKey:source)
        if let error { self.error = error.localizedDescription }
        else { self.replacePinnedFile(source,with:[]) }
      }
    }
    if let recycle { recycle(source,completed) }
    else { NSWorkspace.shared.recycle([source]) { _,error in completed(error) } }
  }

  func unzipPinnedFile(_ source:URL, completion: (([URL])->Void)? = nil) {
    guard files.contains(source), !isPinnedFileBusy(source),
      WorkspaceFileOperations.canExtract(source) else { return }
    pinnedFileOperations[source] = "unzip"
    var settings = options
    settings.outputFolder = source.deletingLastPathComponent().path
    submit("extract",files:[source],overrideOptions:settings,revealOutputs:false) { [weak self] result in
      guard let self else { return }
      self.pinnedFileOperations.removeValue(forKey:source)
      switch result {
      case .success(let folders):
        do {
          let contents = try WorkspaceFileOperations.extractedContents(folders)
          self.replacePinnedFile(source,with:contents)
          completion?(contents)
        } catch { self.error = error.localizedDescription }
      case .failure(let error): self.error = error.localizedDescription
      }
    }
  }
}

struct WorkspaceRenameRequest: Identifiable {
  let id = UUID()
  let url: URL
}

private final class WorkspaceInlineDraft: ObservableObject {
  @Published var name=""
  @Published var error:String?
  @Published var hovered:String?
}

struct WorkspaceInlineName: View {
  let url:URL
  @Binding var editing:Bool
  let save:(String)throws->Void
  @StateObject private var draft=WorkspaceInlineDraft()
  @FocusState private var focused:Bool
  private var suffix:String {
    Family.isFolder(url) || url.pathExtension.isEmpty ? "" : "."+url.pathExtension
  }
  var body: some View {
    Group {
      if editing {
        HStack(alignment:.center,spacing:5) {
          // Text supplies the intrinsic width; the field can still compress in
          // a narrow workspace without pushing its controls out of the row.
          Text(draft.name.isEmpty ? " " : draft.name).lineLimit(1).hidden()
            .frame(minWidth:100)
            .overlay {
              TextField("",text:$draft.name)
                .accessibilityLabel(tr("Nouveau nom"))
                .textFieldStyle(.plain).focused($focused)
                .onSubmit(commit).onExitCommand(perform:cancel)
            }
            .padding(.vertical,4)
            .overlay(alignment:.bottom) {
              Rectangle().fill(draft.error == nil ? Color.secondary.opacity(0.35) : .red).frame(height:1)
            }
          if !suffix.isEmpty { Text(suffix).fixedSize() }
          if let error=draft.error {
            Image(systemName:"exclamationmark.circle").foregroundStyle(.red).help(error)
          }
          editButton("checkmark",title:tr("Valider"),action:commit)
          editButton("xmark",title:tr("Annuler"),action:cancel)
        }
        .font(.system(size:13))
        .background(WorkspaceRenameDismissArea(cancel:cancel))
      } else {
        Text(url.lastPathComponent).lineLimit(1)
          .onTapGesture(count:2) { editing=true }
      }
    }
    .onChange(of:editing) { _,value in
      if value {draft.name=WorkspaceFileOperations.editableName(url);draft.error=nil;focused=true}
    }
  }
  private func editButton(_ icon:String,title:String,action:@escaping()->Void)->some View {
    Button(action:action) {
      Image(systemName:icon).font(.system(size:11,weight:.medium))
        .foregroundStyle(.secondary).frame(width:25,height:25)
        .background(draft.hovered == icon ? Color.secondary.opacity(0.14) : .clear,in:Circle())
    }
    .buttonStyle(.plain).help(title).accessibilityLabel(title)
    .onHover {draft.hovered=$0 ? icon : nil}
    .animation(.easeInOut(duration:0.16),value:draft.hovered == icon)
  }
  private func commit() {
    do {try save(draft.name);editing=false;draft.error=nil}
    catch {draft.error=error.localizedDescription}
  }
  private func cancel() {editing=false;draft.error=nil}
}

/// Observe outside clicks without consuming them: the clicked control still
/// performs its usual action. Monitoring exists only while this editor exists.
private struct WorkspaceRenameDismissArea:NSViewRepresentable {
  let cancel:()->Void
  func makeNSView(context:Context)->MonitorView { MonitorView(cancel:cancel) }
  func updateNSView(_ view:MonitorView,context:Context) {view.cancel=cancel}
  static func dismantleNSView(_ view:MonitorView,coordinator:()) {view.stop()}
  final class MonitorView:NSView {
    var cancel:()->Void
    private var monitor:Any?
    private var observers=[NSObjectProtocol]()
    init(cancel:@escaping()->Void) {
      self.cancel=cancel;super.init(frame:.zero)
      monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] event in
        guard let self,let window=self.window else {return event}
        let inside=event.window === window && self.bounds.contains(self.convert(event.locationInWindow,from:nil))
        if !inside {self.cancel()}
        return event
      }
      observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in self?.cancel() })
      observers.append(NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:nil,queue:.main) { [weak self] note in
        if let self,let window=note.object as? NSWindow,window === self.window {self.cancel()}
      })
    }
    required init?(coder:NSCoder) {fatalError()}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    func stop() {
      if let monitor {NSEvent.removeMonitor(monitor);self.monitor=nil}
      observers.forEach {NotificationCenter.default.removeObserver($0)};observers.removeAll()
    }
    deinit {stop()}
  }
}

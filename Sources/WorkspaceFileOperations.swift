import AppKit
import SwiftUI

enum WorkspaceFileOperations {
  static func editableName(_ source:URL) -> String {
    Family.isFolder(source) || source.pathExtension.isEmpty
      ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
  }

  static func rename(_ source:URL, to input:String) throws -> URL {
    var name = input.trimmingCharacters(in:.whitespacesAndNewlines)
    let suffix = Family.isFolder(source) || source.pathExtension.isEmpty ? "" : "."+source.pathExtension
    if !suffix.isEmpty, name.lowercased().hasSuffix(suffix.lowercased()) { name = String(name.dropLast(suffix.count)) }
    guard !name.isEmpty, name != ".", name != "..",
      !name.contains("/"), !name.contains(":"), !name.contains("\0"),
      !name.contains("\n"), !name.contains("\r") else {
      throw ClementineError(tr("Choisissez un nom valide, sans / ni :."))
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
      !Family.isFolder(source), source.pathExtension.lowercased() == "zip" else { return }
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
}

struct WorkspaceInlineName: View {
  let url:URL
  @Binding var editing:Bool
  let save:(String)throws->Void
  @StateObject private var draft=WorkspaceInlineDraft()
  @FocusState private var focused:Bool
  var body: some View {
    Group {
      if editing {
        HStack(spacing:5) {
          TextField(tr("Nouveau nom"),text:$draft.name)
            .textFieldStyle(.plain).focused($focused)
            .padding(.vertical,3)
            .overlay(alignment:.bottom) {Rectangle().fill(draft.error == nil ? citrus : .red).frame(height:1)}
            .onSubmit(commit).onExitCommand(perform:cancel)
          if let error=draft.error { Image(systemName:"exclamationmark.circle").foregroundStyle(.red).help(error) }
          Button(action:commit) {Image(systemName:"checkmark").frame(width:23,height:23)}
            .buttonStyle(.borderless).help(tr("Valider"))
          Button(action:cancel) {Image(systemName:"xmark").frame(width:23,height:23)}
            .buttonStyle(.borderless).help(tr("Annuler"))
        }
      } else {Text(url.lastPathComponent).lineLimit(1)}
    }
    .onChange(of:editing) { _,value in
      if value {draft.name=WorkspaceFileOperations.editableName(url);draft.error=nil;focused=true}
    }
  }
  private func commit() {
    do {try save(draft.name);editing=false;draft.error=nil}
    catch {draft.error=error.localizedDescription}
  }
  private func cancel() {editing=false;draft.error=nil}
}


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
      try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
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
    let unique = replacements.filter { !updated.contains($0) }
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

private final class WorkspaceRenameDraft: ObservableObject {
  @Published var name: String
  @Published var error: String?
  init(url:URL) { name = WorkspaceFileOperations.editableName(url) }
}

struct WorkspaceRenameSheet: View {
  let source: URL
  let onSave: (String) throws -> Void
  let onCancel: ()->Void
  @StateObject private var draft: WorkspaceRenameDraft
  init(source:URL,onSave:@escaping(String)throws->Void,onCancel:@escaping()->Void) {
    self.source=source; self.onSave=onSave; self.onCancel=onCancel
    _draft = StateObject(wrappedValue:WorkspaceRenameDraft(url:source))
  }
  var body: some View {
    VStack(alignment:.leading,spacing:18) {
      Label(tr("Renommer"),systemImage:"pencil").font(.system(size:19,weight:.semibold,design:.rounded))
      Text(source.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(2)
      HStack {
        TextField(tr("Nouveau nom"),text:$draft.name).textFieldStyle(.roundedBorder)
        if !Family.isFolder(source), !source.pathExtension.isEmpty {
          Text("."+source.pathExtension).foregroundStyle(.secondary)
        }
      }
      if let error = draft.error { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button(tr("Annuler"),action:onCancel).keyboardShortcut(.cancelAction)
        Button(tr("Renommer"),action:save).buttonStyle(.borderedProminent).tint(citrus)
          .keyboardShortcut(.defaultAction).disabled(draft.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width:400).tint(citrus)
  }
  private func save() {
    do { try onSave(draft.name) }
    catch { draft.error = error.localizedDescription }
  }
}

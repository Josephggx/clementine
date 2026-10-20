import AppKit
import Foundation

/// Native iWork exports use the installed Apple applications and macOS Automation permission.
enum NativeOffice {
  static func convert(_ source: URL, to destination: URL, engine: Engine, options: Options = Options()) throws {
    let ext = destination.pathExtension.lowercased()
    let bundleID: String
    let intermediate: String
    switch ext {
    case "pages":
      bundleID = "com.apple.Pages"
      intermediate = "docx"
    case "numbers":
      bundleID = "com.apple.Numbers"
      intermediate = "xlsx"
    case "key":
      bundleID = "com.apple.Keynote"
      intermediate = "pptx"
    default: throw ClementineError("Format Apple inconnu")
    }
    let app =
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
      ?? NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleID.replacingOccurrences(
          of: "com.apple.", with: "com.apple.iWork."))
    guard let app else {
      throw ClementineError(
        "Installez l’application Apple correspondante (Pages, Numbers ou Keynote) pour exporter ce format."
      )
    }
    let id = Bundle(url: app)?.bundleIdentifier ?? bundleID
    let temp = destination.deletingLastPathComponent().appendingPathComponent(
      "apple-" + UUID().uuidString
    ).appendingPathExtension(intermediate)
    defer { try? engine.fm.removeItem(at: temp) }
    if source.pathExtension.lowercased() == intermediate {
      try engine.fm.copyItem(at: source, to: temp)
    } else {
      try Documents.office(source, to: temp, engine: engine, options: options)
    }
    func quoted(_ value: String) -> String {
      "\""
        + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
          of: "\"", with: "\\\"") + "\""
    }
    let script = """
      tell application id \(quoted(id))
          set openedDocument to missing value
          try
              set openedDocument to open POSIX file \(quoted(temp.path))
              save openedDocument in POSIX file \(quoted(destination.path))
              close openedDocument saving no
          on error errorText number errorNumber
              if openedDocument is not missing value then
                  try
                      close openedDocument saving no
                  end try
              end if
              error errorText number errorNumber
          end try
      end tell
      """
    _ = try NativeOfficeScript.run(script, bundleID: id, operation: "Export Apple")
    guard engine.fm.fileExists(atPath: destination.path) else {
      throw ClementineError("L’application Apple n’a pas créé le fichier attendu.")
    }
  }
}

extension NativeOffice {
  /// Read sheet values directly so CSV keeps every sheet as a separate file.
  static func readNumbersSheets(_ source: URL, engine: Engine) throws -> [(name: String, tables: [[[String]]])] {
    let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Numbers")
      ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Numbers")
    guard let app, let bundleID = Bundle(url: app)?.bundleIdentifier else {
      throw ClementineError("Numbers doit être installé pour exporter ce tableur.")
    }
    let root = engine.fm.temporaryDirectory.appendingPathComponent("clementine-numbers-" + UUID().uuidString)
    try engine.fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? engine.fm.removeItem(at: root) }
    let copy = root.appendingPathComponent(source.lastPathComponent)
    try engine.fm.copyItem(at: source, to: copy)
    func quote(_ value: String) -> String {
      "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    let script = """
      with timeout of 600 seconds
        tell application id \(quote(bundleID))
          set openedDocument to missing value
          try
            set openedDocument to open POSIX file \(quote(copy.path))
            set sheetResults to {}
            repeat with oneSheet in sheets of openedDocument
              set tableResults to {}
              repeat with oneTable in tables of oneSheet
                set rowResults to {}
                repeat with rowNumber from 1 to (row count of oneTable)
                  set end of rowResults to (formatted value of cells of row rowNumber of oneTable)
                end repeat
                set end of tableResults to rowResults
              end repeat
              set end of sheetResults to {name of oneSheet, tableResults}
            end repeat
            close openedDocument saving no
            return sheetResults
          on error errorText number errorNumber
            if openedDocument is not missing value then
              try
                close openedDocument saving no
              end try
            end if
            error errorText number errorNumber
          end try
        end tell
      end timeout
      """
    let result = try NativeOfficeScript.run(script, bundleID: bundleID, operation: "Lecture Numbers")
    func items(_ descriptor: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
      guard let descriptor, descriptor.numberOfItems > 0 else { return [] }
      return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }
    }
    let sheets = items(result).compactMap { sheet -> (name: String, tables: [[[String]]])? in
      let fields = items(sheet)
      guard fields.count == 2, let name = fields[0].stringValue else { return nil }
      let tables = items(fields[1]).map { table in
        items(table).map { row in items(row).map { $0.stringValue ?? "" } }
      }
      return (name, tables)
    }
    guard sheets.count == result.numberOfItems, !sheets.isEmpty else {
      throw ClementineError("La lecture des feuilles Numbers est incomplète.")
    }
    return sheets
  }
  /// Only the copy opened by this operation is closed. Existing user documents stay open.
  static func export(_ source: URL, to destination: URL, engine: Engine) throws {
    let sourceFormat = source.pathExtension.lowercased()
    let output = destination.pathExtension.lowercased()
    let appName: String
    let exportFormat: String
    switch (sourceFormat, output) {
    case ("pages", "pdf"): appName = "Pages"; exportFormat = "PDF"
    case ("pages", "docx"): appName = "Pages"; exportFormat = "Microsoft Word"
    case ("numbers", "pdf"): appName = "Numbers"; exportFormat = "PDF"
    case ("numbers", "xlsx"): appName = "Numbers"; exportFormat = "Microsoft Excel"
    case ("key", "pdf"): appName = "Keynote"; exportFormat = "PDF"
    case ("key", "pptx"): appName = "Keynote"; exportFormat = "Microsoft PowerPoint"
    default: throw ClementineError("Export Apple non pris en charge : \(sourceFormat) → \(output)")
    }
    let root=destination.deletingLastPathComponent().appendingPathComponent("apple-export-"+UUID().uuidString)
    try engine.fm.createDirectory(at:root,withIntermediateDirectories:true)
    defer {try? engine.fm.removeItem(at:root)}
    let copy=root.appendingPathComponent(source.lastPathComponent);try engine.fm.copyItem(at:source,to:copy)
    func quote(_ s:String)->String {"\""+s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\""}
    let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple."+appName) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.iWork."+appName)
    guard let app,let bundleID=Bundle(url:app)?.bundleIdentifier else {throw ClementineError("\(appName) doit être installé pour cet export.")}
    let script="""
    with timeout of 600 seconds
      tell application id \(quote(bundleID))
        set openedDocument to missing value
        try
          set openedDocument to open POSIX file \(quote(copy.path))
          export openedDocument to POSIX file \(quote(destination.path)) as \(exportFormat)
          close openedDocument saving no
        on error errorText number errorNumber
          if openedDocument is not missing value then
            try
              close openedDocument saving no
            end try
          end if
          error errorText number errorNumber
        end try
      end tell
    end timeout
    """
    _ = try NativeOfficeScript.run(script, bundleID: bundleID, operation: "Export " + appName)
    guard engine.fm.fileExists(atPath:destination.path) else {throw ClementineError("\(appName) n’a pas créé le document attendu")}
  }
}

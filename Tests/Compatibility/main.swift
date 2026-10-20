import AppKit
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
  checks += 1
  if !value() { fatalError(message) }
}
let reference = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
check(reference.count == 46, "Tangerine reference has 46 formats")
check(reference.values.reduce(0) { $0 + $1.count } == 275, "Tangerine reference has 275 edges")
check(Compatibility.conversions.count == reference.count + 2, "Numbers and Keynote source formats")
check(Compatibility.conversions.values.reduce(0) { $0 + $1.count } == 284, "275 reference edges plus nine iWork routes")
check(Compatibility.conversions["numbers"] == ["xlsx", "ods", "csv", "tsv", "pdf"], "Numbers matches spreadsheet outputs")
check(Compatibility.conversions["key"] == ["pptx", "pdf", "jpg", "png"], "Keynote matches presentation outputs")
check(Compatibility.conversions["pages"] == ["docx", "pdf", "txt", "md", "html", "epub", "png", "jpg"], "Pages matches document outputs")
check(abs(Options().quality - 0.80) < 0.000_001, "Conversion quality defaults to 80 percent")
for (source, targets) in reference {
  check(Compatibility.conversions[source] == targets, "Ordered targets for \(source)")
  for target in reference.keys {
    check((Compatibility.conversions[source] ?? []).contains(target) == targets.contains(target), "Edge \(source) -> \(target)")
  }
}
func urls(_ extensions: [String]) -> [URL] { extensions.map { URL(fileURLWithPath: "/sample.\($0)") } }
check(Compatibility.targets(urls(["jpg", "png"])) == ["webp", "heic", "tiff", "avif", "bmp", "pdf"], "Mixed images intersection")
check(Compatibility.targets(urls(["html"])).isEmpty, "HTML output-only")
check(Compatibility.targets(urls(["gif"])).count == 6, "GIF is video input")
check(Compatibility.targets(urls(["mp4"])).filter { audioFormats.contains($0) } == ["mp3"], "Video audio export")
check(Tool.available(urls(["png"])).map(\.id) == ["compress", "strip", "adjust", "annotate", "frame", "crop", "redact", "archive"], "Single image tools")
check(Tool.available(urls(["png", "jpg"])).map(\.id) == ["compress", "crop", "mergepdf", "collage", "archive"], "Image group tools")
check(Tool.available(urls(["pdf", "pdf"])).map(\.id) == ["compress", "split", "mergepdf", "archive"], "PDF group tools")
for formats in [["svg", "svg"], ["gif", "gif"], ["mp3", "wav"], ["mp4", "mov"],
                ["zip", "rar"], ["docx", "csv"], ["unknown", "unknown"], ["pdf", "png"]] {
  check(!Tool.available(urls(formats)).contains { $0.id == "strip" || $0.id == "metadata" },
        "No metadata tool for multiple files: \(formats)")
}
check(Tool.available(urls(["ogg"])).map(\.id) == ["strip", "archive"], "Metadata and ZIP for OGG")
check(Tool.available(urls(["txt"])).map(\.id) == ["strip", "archive"], "Metadata and ZIP for text")
check(Tool.available(urls(["docx"])).map(\.id) == ["strip", "archive"], "Metadata and ZIP for documents")
check(Tool.available(urls(["csv"])).map(\.id) == ["strip", "archive"], "Metadata and ZIP for sheets")
check(Tool.available(urls(["key"])).map(\.id) == ["strip", "archive"], "Metadata and ZIP for presentations")
check(Tool.available(urls(["unknown"])).map(\.id) == ["strip", "archive"], "Metadata and ZIP for unknown files")
let folderFixture = FileManager.default.temporaryDirectory.appendingPathComponent("clementine-folder-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: folderFixture, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folderFixture) }
for folder in [folderFixture, folderFixture.appendingPathComponent("Photos.png", isDirectory: true)] {
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  check(!Tool.available([folder]).contains { $0.id == "strip" || $0.id == "metadata" }, "No metadata for directories: \(folder.lastPathComponent)")
  check(Tool.available([folder]).contains { $0.id == "archive" }, "Directories retain ZIP")
  check(Family.icon(for: folder) == "folder", "Directory preview uses folder icon")
  check(Family.singularName(for: folder) == "Dossier", "Directory label")
  check(Compatibility.targets([folder]).isEmpty, "Directory has no document conversions")
  check(Tool.catalogue(for: folder).map(\.id) == ["archive"], "Directory catalogue only offers ZIP")
}
let catalogueFolder = URL(fileURLWithPath: "/Dossier", isDirectory: true)
check(Tool.catalogue(for: catalogueFolder).map(\.id) == ["archive"], "Synthetic directory catalogue matches real directories")
check(Tool.available(urls(["zip"])).map(\.id) == ["strip", "extract"], "Existing ZIP does not offer ZIP")
check(Tool.available(urls(["rar"])).map(\.id) == ["strip", "extract"], "Existing archive does not offer ZIP")
check(Tool.catalogue(for: urls(["pdf"])[0]).map(\.id) == ["compress", "strip", "split", "organize", "mergepdf", "archive"], "PDF feature catalogue includes batch actions")
check(Tool.catalogue(for: urls(["jpg"])[0]).map(\.id) == ["compress", "strip", "adjust", "annotate", "frame", "crop", "redact", "mergepdf", "collage", "archive"], "Image feature catalogue includes batch actions")
check(Tool.catalogue(for: urls(["mp3"])[0]).map(\.id) == ["compress", "strip", "normalize", "visualize", "trim", "channels", "bleep", "join", "archive"], "Audio feature catalogue includes assembly")
check(Tool.catalogue(for: urls(["docx"])[0]).map(\.id) == ["strip", "archive"], "Document feature catalogue includes archive")
check(Tool.catalogue(for: urls(["zip"])[0]).map(\.id) == ["strip", "extract", "archive"], "Archive catalogue includes batch ZIP")
check(Tool.batchCandidates(urls(["pdf"])).isEmpty, "Single PDF hides batch actions")
check(Tool.batchCandidates(urls(["pdf", "pdf"])).map(\.id) == ["mergepdf", "archive"], "PDF batch actions")
check(Tool.batchCandidates(urls(["pdf", "png"])).map(\.id) == ["mergepdf", "archive"], "Mixed PDF and image merge")
check(Tool.batchCandidates(urls(["jpg", "png"])).map(\.id) == ["mergepdf", "collage", "archive"], "Image batch actions")
check(Tool.batchCandidates(urls(["mp3", "wav"])).map(\.id) == ["join", "archive"], "Audio batch actions")
check(Tool.batchCandidates(urls(["mp4", "mov"])).map(\.id) == ["join", "archive"], "Video batch actions")
check(Tool.batchCandidates(urls(["docx", "txt"])).map(\.id) == ["archive"], "Document batch archive")
check(Tool.batchCandidates(urls(["pdf", "docx"])).map(\.id) == ["archive"], "Incompatible files only show archive")
for formats in [["zip", "zip"], ["zip", "rar"], ["zip", "txt"], ["pdf", "zip"], ["zip", "jpg", "csv"]] {
  check(Tool.available(urls(formats)).filter { $0.id == "archive" }.count == 1,
        "Batch may include archives: \(formats)")
  check(Tool.batchCandidates(urls(formats)).map(\.id) == ["archive"],
        "Archive batch offers ZIP: \(formats)")
}
check(Tool.batchCandidates([]).isEmpty, "No batch actions without files")
let center = NSPoint(x: 136, y: 136)
for count in 2...12 {
  check(WheelGeometry.hit(center, count: count, center: center) == nil, "Centre cancels")
  for index in 0..<count {
    let angle = WheelGeometry.angle(index, count: count)
    let position = WheelGeometry.point(84.53, angle, center: center)
    check(WheelGeometry.hit(position, count: count, center: center) == index, "Petal centre \(count)/\(index)")
    let gutter = WheelGeometry.point(85, angle + Double.pi / Double(count), center: center)
    check(WheelGeometry.hit(gutter, count: count, center: center) == nil, "Gutter cancels")
  }
}
var gesture = WheelGesture()
func mode(_ flags: NSEvent.ModifierFlags) -> String? {
  switch flags { case .shift: return "formats"; case .command: return "tools"; case .control: return "actions"; default: return nil }
}
check(gesture.update(dragging: true, flags: [], resolve: mode) == nil, "Drag without shortcut")
check(gesture.update(dragging: true, flags: .shift, resolve: mode) == "formats", "Tap opens")
check(gesture.update(dragging: true, flags: [], resolve: mode) == "formats", "Release keeps wheel")
check(gesture.update(dragging: true, flags: .command, resolve: mode) == "tools", "Switch mode")
check(gesture.update(dragging: true, flags: [], resolve: mode) == "tools", "Keep switched mode")
check(gesture.update(dragging: false, flags: [], resolve: mode) == nil, "Drop closes")
print("PASS \(checks) assertions; Tangerine 46 formats / 275 routes, plus Numbers and Keynote inputs")

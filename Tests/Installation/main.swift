import AppKit

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("Clementine-install-test-\(UUID().uuidString)")
try manager.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: root) }

for path in ["/Applications/Clémentine.app", "/Users/test/Clémentine.app",
  "/Volumes/External/Clémentine.app"] {
  precondition(!ApplicationInstallation.needsInstallationHandoff(
    source: URL(fileURLWithPath: path), readOnlyVolume: false))
}
precondition(ApplicationInstallation.needsInstallationHandoff(
  source: URL(fileURLWithPath: "/Volumes/Clémentine/Clémentine.app"), readOnlyVolume: true))
precondition(ApplicationInstallation.needsInstallationHandoff(
  source: URL(fileURLWithPath: "/private/var/folders/test/AppTranslocation/UUID/d/Clémentine.app"),
  readOnlyVolume: false))

let source = root.appendingPathComponent("Source.app")
let executable = source.appendingPathComponent("Contents/MacOS/Fixture")
try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
let info: [String: Any] = ["CFBundleIdentifier": "io.joseph.clementine.installfixture",
  "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
  .write(to: source.appendingPathComponent("Contents/Info.plist"))
try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
let destination = root.appendingPathComponent("Installed.app")
try ApplicationInstallation.copyFirstInstallation(from: source, to: destination)
precondition(manager.isExecutableFile(atPath: destination.appendingPathComponent("Contents/MacOS/Fixture").path))
precondition(manager.fileExists(atPath: executable.path), "A first installation copies, never moves the source")
let marker = destination.appendingPathComponent("keep-existing.txt")
try Data("user installation".utf8).write(to: marker)
try ApplicationInstallation.copyFirstInstallation(from: source, to: destination)
let existingMarker = try String(contentsOf: marker)
precondition(existingMarker == "user installation", "Never overwrite an existing app")

let invalid = root.appendingPathComponent("Invalid.app")
try manager.createDirectory(at: invalid, withIntermediateDirectories: true)
let failedTarget = root.appendingPathComponent("MustNotExist.app")
do {
  try ApplicationInstallation.copyFirstInstallation(from: invalid, to: failedTarget)
  preconditionFailure("An incomplete app cannot be installed")
} catch {
  precondition(!manager.fileExists(atPath: failedTarget.path))
  let leftovers = try manager.contentsOfDirectory(atPath: root.path)
  precondition(!leftovers.contains(where: { $0.hasPrefix(".Clementine-install-") }))
}
print("PASS: disque en lecture seule, translocation, copie complète, original conservé, installation existante préservée, nettoyage après erreur")

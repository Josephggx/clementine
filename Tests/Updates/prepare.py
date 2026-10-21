"""Build a separate two-version fixture; never touches the installed app or its defaults."""
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = root / ".build/update-results"
out.mkdir(exist_ok=True)
binary = out / "Clementine"
vendor = root / ".build/vendor/Sparkle-2.10.0"
sources = sorted(str(p) for p in (root / "Sources").glob("*.swift") if p.name != "Main.swift")
cmd = ["xcrun", "swiftc", "-swift-version", "5", "-target", "arm64-apple-macosx14.0",
       "-module-cache-path", str(root / ".build/cache"), *sources, str(Path(__file__).with_name("Main.swift")),
       "-o", str(binary), "-F", str(vendor), "-framework", "Sparkle",
       "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]
for framework in ["AppKit", "SwiftUI", "AVKit", "AVFoundation", "PDFKit", "Vision", "CoreImage", "ImageIO",
                  "CoreText", "ServiceManagement", "JavaScriptCore", "CoreServices", "QuickLookThumbnailing"]:
    cmd.extend(["-framework", framework])
if "--reuse-binary" not in sys.argv:
    subprocess.run(cmd, check=True)
base = plistlib.loads((root / "Info.plist").read_bytes())
bundle_id = "io.joseph.clementine.updatetest"
skipping = "--skip-versions" in sys.argv
latest_version, latest_build = ("1.0.9", "19") if skipping else ("1.0.1", "11")
versions = [("installed", "1.0.0", "10"), ("release", latest_version, latest_build)]
if skipping:
    versions.append(("intermediate", "1.0.8", "18"))
for folder, version, build in versions:
    app = out / folder / "Clémentine.app"
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    frameworks = app / "Contents/Frameworks"
    for path in [macos, resources, frameworks]: path.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, macos / "Clementine")
    subprocess.run(["ditto", str(vendor / "Sparkle.framework"), str(frameworks / "Sparkle.framework")], check=True)
    for name in ["AppIcon.icns", "AppIconLight.icns"]: shutil.copy2(root / "Resources" / name, resources / name)
    shutil.copytree(root / "Resources/Demo", resources / "Demo", dirs_exist_ok=True)
    info = dict(base)
    info.update(CFBundleIdentifier=bundle_id, CFBundleName="Clémentine Update Test",
                CFBundleDisplayName="Clémentine Update Test", CFBundleShortVersionString=version,
                CFBundleVersion=build, SUFeedURL="http://localhost:8765/appcast.xml", TestRoot=str(out),
                TestAutomaticUpdate=(folder == "installed"), TestExpectedVersion=latest_version,
                NSAppTransportSecurity={"NSAllowsLocalNetworking": True})
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", bundle_id,
                    "--requirements", f'=designated => identifier "{bundle_id}"', str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
archive = out / "update.zip"
old_archive = out / "previous.zip"
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(out / "installed/Clémentine.app"), str(old_archive)], check=True)
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(out / "release/Clémentine.app"), str(archive)], check=True)
if skipping:
    # Advertise only the 1.0.8 -> 1.0.9 delta: a 1.0.0 client must still choose
    # 1.0.9 directly, using the full archive, without installing 1.0.8 first.
    old_archive = out / "intermediate.zip"
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(out / "intermediate/Clémentine.app"), str(old_archive)], check=True)
subprocess.run([sys.executable, str(root / "Scripts/prepare-update.py"), str(archive),
                "--plist", str(out / "release/Clémentine.app/Contents/Info.plist"),
                "--previous-archive", str(old_archive),
                "--url", "http://localhost:8765/update.zip", "--notes", "Vérification locale de mise à jour."], check=True)
if "--modified-base" in sys.argv:
    installed = out / "installed/Clémentine.app"
    (installed / "Contents/Resources/extra-user-file.txt").write_text("Simulate a modified installation.\n")
    subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", bundle_id,
                    "--requirements", f'=designated => identifier "{bundle_id}"', str(installed)], check=True)
print("Fixture prête :", out)

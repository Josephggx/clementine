#!/usr/bin/env python3
"""Build signed full + verified differential updates from immutable release archives."""
from datetime import datetime, timezone
from pathlib import Path
from contextlib import contextmanager
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
TOOLS = ROOT / ".build/vendor/Sparkle-2.10.0/bin"
CACHE = ROOT / ".build/update-archives"


def sha256(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


@contextmanager
def mounted(archive):
    raw = subprocess.check_output(["hdiutil", "attach", "-plist", "-nobrowse", "-readonly", str(archive)])
    entities = plistlib.loads(raw)["system-entities"]
    mount = next(Path(entry["mount-point"]) for entry in entities if "mount-point" in entry)
    try:
        yield mount
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)


def extracted_app(archive):
    """Cache by archive digest, never use the mutable build or installed app as a base."""
    folder = CACHE / sha256(archive)
    ready = folder / ".complete"
    if not ready.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="extract-", dir=CACHE) as temporary:
            stage = Path(temporary)
            if archive.suffix.lower() == ".dmg":
                with mounted(archive) as volume:
                    apps = list(volume.glob("*.app"))
                    if len(apps) != 1:
                        raise ValueError(f"Expected exactly one app in {archive.name}")
                    subprocess.run(["ditto", str(apps[0]), str(stage / "Application.app")], check=True)
            elif archive.suffix.lower() == ".zip":
                subprocess.run(["ditto", "-x", "-k", str(archive), str(stage)], check=True)
                apps = list(stage.glob("*.app"))
                if len(apps) != 1:
                    raise ValueError(f"Expected exactly one app in {archive.name}")
                apps[0].rename(stage / "Application.app")
            else:
                raise ValueError(f"Unsupported release archive: {archive.name}")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(stage / "Application.app")], check=True)
            (stage / ".complete").write_text(sha256(archive))
            if folder.exists():
                shutil.rmtree(folder)
            shutil.copytree(stage, folder, symlinks=True)
    return folder / "Application.app"


def app_info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def bundle_manifest(app):
    """Compare file contents, symlink targets and executable modes after patching."""
    result = {}
    for parent, directories, files in os.walk(app, followlinks=False):
        for name in directories + files:
            path = Path(parent) / name
            relative = str(path.relative_to(app))
            mode = stat.S_IMODE(path.lstat().st_mode)
            if path.is_symlink():
                result[relative] = ("link", os.readlink(path))
            elif path.is_file():
                result[relative] = ("file", mode, sha256(path))
            else:
                result[relative] = ("directory", mode)
    return result


def sign(path, account):
    signer = TOOLS / "sign_update"
    signature = subprocess.check_output([str(signer), "--account", account, "-p", str(path)], text=True).strip()
    subprocess.run([str(signer), "--account", account, "--verify", str(path), signature], check=True)
    return signature


def create_delta(before, after, output):
    binary = str(TOOLS / "BinaryDelta")
    subprocess.run([binary, "create", "--version", "4", str(before), str(after), str(output)], check=True)
    # Applying the real patch also checks Sparkle's before/after bundle hashes.
    with tempfile.TemporaryDirectory(prefix="verify-delta-", dir=CACHE) as temporary:
        patched = Path(temporary) / "Application.app"
        subprocess.run([binary, "apply", str(before), str(patched), str(output)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(patched)], check=True)
        if bundle_manifest(patched) != bundle_manifest(after):
            raise ValueError(f"Patched bundle differs from signed release: {output.name}")


def prepare(archive, plist, feed, download_url, notes, account, previous_archives=(), no_deltas=False):
    info = plistlib.loads(plist.read_bytes())
    archive_app = extracted_app(archive) if not no_deltas else None
    if archive_app and any(app_info(archive_app).get(key) != info.get(key)
                           for key in ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString"]):
        raise ValueError("Release archive and version plist do not match")
    signature = sign(archive, account)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Clémentine"
    ET.SubElement(channel, "language").text = "fr"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Clémentine " + info["CFBundleShortVersionString"]
    ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    ET.SubElement(item, "{" + SPARKLE + "}version").text = info["CFBundleVersion"]
    ET.SubElement(item, "{" + SPARKLE + "}shortVersionString").text = info["CFBundleShortVersionString"]
    ET.SubElement(item, "{" + SPARKLE + "}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
    ET.SubElement(item, "description").text = notes
    ET.SubElement(item, "enclosure", {
        "url": download_url, "length": str(archive.stat().st_size),
        "type": "application/octet-stream", "{" + SPARKLE + "}edSignature": signature,
    })
    assets = [{"path": str(archive), "bytes": archive.stat().st_size, "sha256": sha256(archive)}]
    candidates = []
    for old_archive in previous_archives if not no_deltas else ():
        if old_archive.resolve() == archive:
            continue
        old_app = extracted_app(old_archive)
        old_info = app_info(old_app)
        if old_info.get("CFBundleIdentifier") != info["CFBundleIdentifier"]:
            raise ValueError(f"Different application identity: {old_archive.name}")
        old_build = old_info["CFBundleVersion"]
        if int(old_build) >= int(info["CFBundleVersion"]):
            continue
        candidates.append((int(old_build), old_app, old_info))
    deltas = None
    seen = set()
    # Each patch goes straight from its installed base to this release. Do not
    # force lagging users through an intermediate build to get a small update.
    for old_build, old_app, old_info in sorted(candidates, key=lambda candidate: candidate[0], reverse=True):
        if old_build in seen:
            continue
        seen.add(old_build)
        delta = archive.with_name(f'Clementine-{old_info["CFBundleShortVersionString"]}-to-{info["CFBundleShortVersionString"]}-arm64.delta')
        create_delta(old_app, archive_app, delta)
        if delta.stat().st_size >= archive.stat().st_size:
            delta.unlink()
            continue
        delta_signature = sign(delta, account)
        if deltas is None:
            deltas = ET.SubElement(item, "{" + SPARKLE + "}deltas")
        ET.SubElement(deltas, "enclosure", {
            "url": download_url.rsplit("/", 1)[0] + "/" + delta.name,
            "length": str(delta.stat().st_size), "type": "application/octet-stream",
            "{" + SPARKLE + "}edSignature": delta_signature,
            "{" + SPARKLE + "}deltaFrom": str(old_build),
        })
        assets.append({"path": str(delta), "from": old_info["CFBundleShortVersionString"],
                       "fromBuild": str(old_build), "bytes": delta.stat().st_size, "sha256": sha256(delta)})
    ET.indent(rss, space="  ")
    ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
    subprocess.run([str(TOOLS / "sign_update"), "--account", account, str(feed)], check=True)
    subprocess.run([str(TOOLS / "sign_update"), "--account", account, "--verify", str(feed)], check=True)
    assets.append({"path": str(feed), "bytes": feed.stat().st_size, "sha256": sha256(feed)})
    report = ROOT / ".build/release-assets.json"
    report.write_text(json.dumps({"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                                 "assets": assets}, indent=2) + "\n")
    print(report)
    for asset in assets:
        print(Path(asset["path"]).name, f'{asset["bytes"] / 1024 / 1024:.2f} MiB')
    print(feed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--plist", type=Path, default=ROOT / "Info.plist")
    parser.add_argument("--feed", type=Path)
    parser.add_argument("--url")
    parser.add_argument("--notes", default="Améliorations et corrections de Clémentine.")
    parser.add_argument("--account", default="io.joseph.clementine.desktop")
    parser.add_argument("--previous-archive", type=Path, action="append",
                        help="Immutable older archive; defaults to earlier sibling Clementine DMG/ZIP archives")
    parser.add_argument("--no-deltas", action="store_true", help="Only for full-only update fixtures")
    parser.add_argument("--verify-archive-only", action="store_true",
                        help="Verify the application extracted from a finished archive without signing a feed")
    args = parser.parse_args()
    archive = args.archive.resolve()
    info = plistlib.loads(args.plist.read_bytes())
    if args.verify_archive_only:
        extracted = app_info(extracted_app(archive))
        if any(extracted.get(key) != info.get(key) for key in ["CFBundleIdentifier", "CFBundleVersion"]):
            raise ValueError("Packaged application identity/version differs from source Info.plist")
        print("Verified application signature inside", archive.name)
        raise SystemExit(0)
    version = info["CFBundleShortVersionString"]
    url = args.url or f"https://github.com/Josephggx/clementine/releases/download/v{version}/{archive.name}"
    previous = args.previous_archive
    if previous is None:
        previous = sorted([*archive.parent.glob("Clementine-*-arm64.dmg"),
                           *archive.parent.glob("Clementine-*-arm64.zip")])
    prepare(archive, args.plist.resolve(), args.feed or archive.parent / "appcast.xml",
            url, args.notes, args.account, previous, args.no_deltas)

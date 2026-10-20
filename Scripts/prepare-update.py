#!/usr/bin/env python3
"""Sign a release archive and its GitHub-hosted Sparkle feed. No private key files."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def prepare(archive, plist, feed, download_url, notes, account):
    with plist.open("rb") as source:
        info = plistlib.load(source)
    signer = ROOT / ".build/vendor/Sparkle-2.10.0/bin/sign_update"
    signature = subprocess.check_output(
        [str(signer), "--account", account, "-p", str(archive)], text=True
    ).strip()
    subprocess.run([str(signer), "--account", account, "--verify", str(archive), signature], check=True)
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
    ET.indent(rss, space="  ")
    ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
    subprocess.run([str(signer), "--account", account, str(feed)], check=True)
    subprocess.run([str(signer), "--account", account, "--verify", str(feed)], check=True)
    print(feed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--plist", type=Path, default=ROOT / "Info.plist")
    parser.add_argument("--feed", type=Path)
    parser.add_argument("--url")
    parser.add_argument("--notes", default="Améliorations et corrections de Clémentine.")
    parser.add_argument("--account", default="io.joseph.clementine.desktop")
    args = parser.parse_args()
    with args.plist.open("rb") as source:
        version = plistlib.load(source)["CFBundleShortVersionString"]
    url = args.url or f"https://github.com/Josephggx/clementine-releases/releases/download/v{version}/{args.archive.name}"
    prepare(args.archive.resolve(), args.plist.resolve(),
            args.feed or args.archive.resolve().parent / "appcast.xml", url, args.notes, args.account)

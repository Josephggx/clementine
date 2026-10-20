#!/usr/bin/env python3
"""Remove empty, xattr-signed placeholders that cannot survive a delta patch.

The local LibreOffice bundle inherited four empty non-executable placeholders.
Their detached signatures live only in extended attributes. Sparkle deliberately
does not preserve those attributes; leaving them makes a reconstructed bundle
fail strict signature validation. Real runtime code and nonempty files stay intact.
"""
from pathlib import Path
import subprocess
import sys

runtime = Path(sys.argv[1]) / "Contents/Helpers/LibreOffice.app"
removed = []
for relative in ["Contents/MacOS/senddoc", "Contents/MacOS/unoinfo", "Contents/MacOS/urelibs",
                 "Contents/Frameworks/intl/fbintl.conf"]:
    path = runtime / relative
    if path.is_file() and not path.is_symlink() and path.stat().st_size == 0:
        path.unlink()
        removed.append(relative)
if removed:
    subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", "org.libreoffice.script",
                    "--requirements", '=designated => identifier "org.libreoffice.script"',
                    str(runtime)], check=True)
    print("Normalized empty runtime placeholders:", ", ".join(removed))
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(runtime)], check=True)

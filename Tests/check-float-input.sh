#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
# Native view routing only: no NSApplication, window, activation or .app bundle.
python3 - <<'PYTEST'
from pathlib import Path
import subprocess,tempfile
source=Path('Sources/FloatIsland.swift').read_text()
views=source[source.index('enum FloatPointer {'):]
fixture=r"""
import AppKit
final class FloatModel {
  var expanded=false
  var thumbnails:[URL:NSImage]=[:]
  func carried(_ file:URL?)->[URL] {file.map {[$0]} ?? []}
}
func trString(_ value:String)->String {value}
"""
checks=r"""
let root=NSView(frame:CGRect(x:0,y:0,width:400,height:350))
let content=NSView(frame:CGRect(x:40,y:50,width:240,height:260))
root.addSubview(content)
let file=FloatDragSource(frame:CGRect(x:10,y:15,width:80,height:92))
file.file=URL(fileURLWithPath:"/tmp/Float-input-fixture.pdf")
content.addSubview(file)
let input=FloatDragSource(frame:CGRect(x:20,y:30,width:220,height:280))
input.backgroundOnly=true;input.fileHitRoot=root
root.addSubview(input)
precondition(input.hitTest(CGPoint(x:30,y:40)) === input,"Background must retain a native click target")
precondition(input.hitTest(CGPoint(x:65,y:80)) === file,"File target must be returned directly across different parent views")
precondition(input.acceptsFirstMouse(for:nil) && file.acceptsFirstMouse(for:nil),"Inactive clicks must be accepted")
file.isHidden=true
precondition(input.hitTest(CGPoint(x:65,y:80)) === input,"Hidden files cannot leave holes in the input surface")
file.isHidden=false;content.isHidden=true
precondition(input.hitTest(CGPoint(x:65,y:80)) === input,"Hidden ancestors cannot block the background")
content.isHidden=false
precondition(input.hitTest(CGPoint(x:0,y:0)) == nil,"Outside points must not intercept the desktop")
content.frame.origin=CGPoint(x:110,y:130)
precondition(input.hitTest(CGPoint(x:65,y:80)) === input,"Moving content removes the previous hit area")
precondition(input.hitTest(CGPoint(x:130,y:155)) === file,"The hit area follows native layout changes")
print("PASS: 8 native Float input checks; no windows or application activation")
"""
with tempfile.TemporaryDirectory(prefix='float-input-') as temporary:
    root=Path(temporary);main=root/'main.swift';binary=root/'check'
    main.write_text(fixture+views+checks)
    subprocess.run(['xcrun','swiftc','-swift-version','5','-module-cache-path','.build/cache','Sources/FloatLayout.swift',str(main),'-framework','AppKit','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
PYTEST

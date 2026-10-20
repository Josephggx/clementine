"""Finder layout, built without driving Finder or changing user preferences."""
from pathlib import Path
import unicodedata

app = Path(defines["app"])
files = [str(app)]
symlinks = {"Applications": "/Applications"}
icon = str(app / "Contents/Resources/AppIcon.icns")
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
window_rect = ((180, 180), (720, 540))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 14
label_pos = "bottom"
arrange_by = None
icon_locations = {unicodedata.normalize("NFD", "Clémentine.app"): (190, 242),
                  "Applications": (530, 242)}
# Do not use SetFile on a signed app: its FinderInfo xattr invalidates strict
# code-signature verification. Finder already hides application extensions.
hide_extensions = []

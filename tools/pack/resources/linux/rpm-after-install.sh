#!/bin/sh
# RPM post-install fixup: KDE cannot resolve icon-theme names containing
# spaces, and the rpm target names the desktop entry and icon after the
# display product name ("Open Design"). Rename both to the
# spec-conventional space-free form so the menu icon renders.
set -e
icon_dir=/usr/share/icons/hicolor/1024x1024/apps
if [ -f "$icon_dir/Open Design.png" ]; then
  mv -f "$icon_dir/Open Design.png" "$icon_dir/open-design.png"
fi
entry="/usr/share/applications/Open Design.desktop"
if [ -f "$entry" ]; then
  sed -i 's|^Icon=Open Design$|Icon=open-design|' "$entry"
fi
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
exit 0

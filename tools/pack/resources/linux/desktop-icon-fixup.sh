#!/bin/sh
# Post-install icon fixup (deb and rpm): electron-builder installs the icon
# at its native pixel size — hicolor/1024x1024/apps — but the hicolor theme
# index declares only the standard sizes (…, 256x256, 512x512, scalable).
# Per the Icon Theme Specification the lookup iterates exclusively over the
# declared Directories, so an icon in an undeclared size directory is never
# found and the menu entry renders without an icon. Move it into the
# declared 512x512 context and point the entry at the space-free name.
set -e
src_dir=/usr/share/icons/hicolor/1024x1024/apps
dst_dir=/usr/share/icons/hicolor/512x512/apps
mkdir -p "$dst_dir"
for name in "open-design.png" "Open Design.png"; do
  if [ -f "$src_dir/$name" ]; then
    mv -f "$src_dir/$name" "$dst_dir/open-design.png"
    break
  fi
done
# The rpm lane names both entry and icon after the display product name;
# repoint the Icon key at the space-free file (the deb lane is already
# space-free — the sed is a harmless no-op there).
entry="/usr/share/applications/Open Design.desktop"
if [ -f "$entry" ]; then
  sed -i 's|^Icon=Open Design$|Icon=open-design|' "$entry"
fi
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
exit 0

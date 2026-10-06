#!/bin/sh
# OpenDesign for GNU/Linux — community installer.
# Resolves the latest stable release, verifies the sha256 checksum and
# installs the package for your distribution.
#
# Usage: curl -fsSL <this script> | sh            (auto-detect deb/rpm)
#        curl -fsSL <this script> | sh -s deb      (force .deb)
#        curl -fsSL <this script> | sh -s rpm      (force .rpm)
#        curl -fsSL <this script> | sh -s flatpak  (Flatpak bundle, user install)
# Works with curl or wget.
set -e
REPO="kacperpaczos/OpenDesign-For-GNU-Linux"
BASE="https://github.com/$REPO/releases/download"
WANT="${1:-auto}"

say() { printf '\n==> %s\n' "$*"; }

if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1"; }
  fetch_to() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO- "$1"; }
  fetch_to() { wget -qO "$2" "$1"; }
else
  echo "curl or wget is required"; exit 1
fi

say "Resolving the latest release"
TAG=$(fetch "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
[ -n "$TAG" ] || { echo "Could not resolve the latest release"; exit 1; }
VERSION=${TAG#open-design-v}
echo "    $TAG"

# Resolve the package type: explicit argument wins, otherwise detect from
# the available package manager.
if [ "$WANT" = "auto" ]; then
  if command -v dnf >/dev/null 2>&1; then WANT=rpm
  elif command -v zypper >/dev/null 2>&1; then WANT=rpm
  elif command -v apt-get >/dev/null 2>&1; then WANT=deb
  else WANT=flatpak
  fi
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fetch_sums() {
  fetch_to "$BASE/$TAG/sha256sums.txt" "$TMP/sha256sums.txt" || true
}

verify() {
  [ -s "$TMP/sha256sums.txt" ] || { echo "    (sha256sums.txt unavailable — skipping verification)"; return 0; }
  (cd "$TMP" && sed "s|output/||" sha256sums.txt | grep " $1\$" | sha256sum -c -) \
    || { echo "Checksum mismatch — aborting"; exit 1; }
}

if [ "$WANT" = "deb" ] || [ "$WANT" = "rpm" ]; then
  if [ "$WANT" = "deb" ]; then PKG=apt-get; EXT=deb; ARCH=amd64; else PKG=dnf; EXT=rpm; ARCH=x86_64; fi
  ASSET="open-design_${VERSION}_${ARCH}.${EXT}"
  say "Downloading $ASSET"
  fetch_to "$BASE/$TAG/$ASSET" "$TMP/$ASSET"
  fetch_sums
  verify "$ASSET"
  say "Installing with $PKG (sudo may ask for your password)"
  if [ "$(id -u)" = "0" ]; then
    $PKG install -y "$TMP/$ASSET"
  else
    sudo $PKG install -y "$TMP/$ASSET"
  fi
  say "Done. Launch 'Open Design' from your application menu."

elif [ "$WANT" = "flatpak" ]; then
  command -v flatpak >/dev/null 2>&1 || { echo "flatpak is required (install flatpak first)"; exit 1; }
  ASSET="open-design.flatpak"
  say "Downloading $ASSET"
  fetch_to "$BASE/$TAG/$ASSET" "$TMP/$ASSET"
  fetch_sums
  verify "$ASSET"
  say "Installing the Flatpak bundle (user installation)"
  if [ "$(id -u)" = "0" ]; then
    flatpak install --system -y "$TMP/$ASSET"
  else
    flatpak install --user -y "$TMP/$ASSET"
  fi
  say "Done. Launch 'Open Design' from your application menu."

else
  echo "Unknown package type: $WANT (expected deb, rpm or flatpak)"
  exit 1
fi

echo "    Community build — unsigned, no auto-update. Upstream: https://open-design.ai"

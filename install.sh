#!/bin/sh
# OpenDesign for GNU/Linux — community installer.
# Resolves the latest stable release, verifies the sha256 checksum and
# installs the native package for your distribution (deb or rpm).
set -e
REPO="kacperpaczos/OpenDesign-For-GNU-Linux"
BASE="https://github.com/$REPO/releases/download"

say() { printf '\n==> %s\n' "$*"; }

command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }

say "Resolving the latest release"
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
[ -n "$TAG" ] || { echo "Could not resolve the latest release"; exit 1; }
VERSION=${TAG#open-design-v}
echo "    $TAG"

# Pick the package type from the available package manager.
if command -v dnf >/dev/null 2>&1; then
  PKG=dnf; EXT=rpm; ARCH=x86_64
elif command -v zypper >/dev/null 2>&1; then
  PKG=zypper; EXT=rpm; ARCH=x86_64
elif command -v apt-get >/dev/null 2>&1; then
  PKG=apt; EXT=deb; ARCH=amd64
else
  echo "No supported package manager found (dnf / zypper / apt-get)."
  echo "Grab a Flatpak from https://github.com/$REPO/releases instead."
  exit 1
fi

ASSET="open-design_${VERSION}_${ARCH}.${EXT}"
URL="$BASE/$TAG/$ASSET"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "Downloading $ASSET"
curl -fsSL -o "$TMP/$ASSET" "$URL"

say "Verifying sha256"
curl -fsSL -o "$TMP/sha256sums.txt" "$BASE/$TAG/sha256sums.txt" || true
if [ -s "$TMP/sha256sums.txt" ]; then
  (cd "$TMP" && sed "s|output/||" sha256sums.txt | grep " $ASSET\$" | sha256sum -c -) \
    || { echo "Checksum mismatch — aborting"; exit 1; }
else
  echo "    (sha256sums.txt unavailable — skipping verification)"
fi

say "Installing with $PKG (sudo may ask for your password)"
if [ "$(id -u)" = "0" ]; then
  $PKG install -y "$TMP/$ASSET" || zypper --non-interactive install "$TMP/$ASSET"
else
  sudo $PKG install -y "$TMP/$ASSET" || sudo zypper --non-interactive install "$TMP/$ASSET"
fi

say "Done. Launch 'Open Design' from your application menu."
echo "    Community build — unsigned, no auto-update. Upstream: https://open-design.ai"

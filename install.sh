#!/bin/sh
# OpenDesign for GNU/Linux — community installer.
# Resolves the latest release, verifies its sha256 checksum and installs the
# package for your distribution, without asking any questions.
#
# Usage: curl -fsSL <this script> | sh            (auto-detect deb/rpm/flatpak)
#        curl -fsSL <this script> | sh -s deb      (force .deb, apt-get)
#        curl -fsSL <this script> | sh -s rpm      (force .rpm, zypper on openSUSE, dnf otherwise)
#        curl -fsSL <this script> | sh -s flatpak  (Flatpak bundle, user install)
# Works with curl or wget. Download progress is written to stderr.
#
# Everything lives in functions and only runs from the last line, so a
# truncated download never executes half a script, and the shell has read the
# whole file before any installer starts.

set -eu

REPO="kacperpaczos/OpenDesign-For-GNU-Linux"
# Overridable for testing only.
API_URL="${OD_INSTALL_API_URL:-https://api.github.com/repos/$REPO/releases/latest}"
BASE_URL="${OD_INSTALL_BASE_URL:-https://github.com/$REPO/releases/download}"

TMP=""

say()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: curl -fsSL https://kacperpaczos.github.io/OpenDesign-For-GNU-Linux/install.sh | sh -s [deb|rpm|flatpak]

  deb      install the .deb with apt-get
  rpm      install the .rpm with zypper (openSUSE) or dnf
  flatpak  install the Flatpak bundle (user installation)
  (none)   auto-detect from the available package manager
EOF
}

cleanup() {
  if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- downloads ---------------------------------------------------------------

setup_fetch() {
  if have curl; then
    DL=curl
  elif have wget; then
    DL=wget
    WGET_PROGRESS=""
    if wget --help 2>&1 | grep -q -- '--show-progress'; then
      WGET_PROGRESS="--show-progress"
    fi
  else
    die "curl or wget is required"
  fi
}

# fetch URL OUT — small files, no progress.
fetch() {
  if [ "$DL" = curl ]; then
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$2" "$1"
  else
    wget -q --tries=3 --timeout=20 -O "$2" "$1"
  fi
}

# fetch_progress URL OUT — package download, progress bar on stderr.
fetch_progress() {
  if [ "$DL" = curl ]; then
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --progress-bar -o "$2" "$1"
  else
    # shellcheck disable=SC2086 # WGET_PROGRESS is empty or a single flag
    wget -q $WGET_PROGRESS --tries=3 --timeout=20 -O "$2" "$1"
  fi
}

# --- release resolution ------------------------------------------------------

resolve_release() {
  say "Resolving the latest release"
  fetch "$API_URL" "$TMP/release.json" \
    || die "could not query the GitHub API for the latest release (network down or rate limited?)"
  TAG=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$TMP/release.json" | head -n 1)
  [ -n "$TAG" ] || die "could not find a release tag in the GitHub API response"
  VERSION=${TAG#open-design-v}
  VERSION=${VERSION%-linux}   # tags are open-design-vX.Y.Z-linux; assets use X.Y.Z
  info "$TAG"
}

# --- checksum ----------------------------------------------------------------

sha256_of() {
  if have sha256sum; then
    sum=$(sha256sum "$1")
  elif have shasum; then
    sum=$(shasum -a 256 "$1")
  else
    die "sha256sum (coreutils) or shasum is required to verify the download"
  fi
  printf '%s\n' "${sum%% *}"
}

# download_verified ASSET — downloads ASSET into $TMP and checks it against
# the release's sha256sums.txt (entries may carry a directory prefix).
download_verified() {
  asset=$1
  say "Downloading $asset"
  fetch_progress "$BASE_URL/$TAG/$asset" "$TMP/$asset" \
    || die "download failed: $BASE_URL/$TAG/$asset"
  fetch "$BASE_URL/$TAG/sha256sums.txt" "$TMP/sha256sums.txt" \
    || die "download failed: $BASE_URL/$TAG/sha256sums.txt"
  expected=$(awk -v name="$asset" '{ f = $2; sub(/^\*/, "", f); sub(/.*\//, "", f); if (f == name) { print $1; exit } }' "$TMP/sha256sums.txt")
  [ -n "$expected" ] || die "sha256sums.txt has no entry for $asset"
  actual=$(sha256_of "$TMP/$asset")
  [ "$actual" = "$expected" ] \
    || die "checksum mismatch for $asset (expected $expected, got $actual)"
  info "sha256 OK"
}

# --- installation ------------------------------------------------------------

# run_installer CMD... — never let an installer read the piped script on
# stdin. With `curl | sh`, stdin is the curl pipe: anything reading it eats
# the rest of the script, and flatpak's progress table asks the terminal for
# the cursor position and waits for the reply on stdin, so it never redraws
# (no progress, stray ^[[..R codes). Give it the terminal when there is one.
run_installer() {
  if (: </dev/tty) 2>/dev/null; then
    "$@" </dev/tty
  else
    FLATPAK_FANCY_OUTPUT=0 "$@" </dev/null
  fi
}

as_root() {
  if [ "$(id -u)" = "0" ]; then
    run_installer "$@"
  else
    have sudo || die "sudo is required to install system packages (or run as root)"
    run_installer sudo "$@"
  fi
}

is_opensuse() {
  [ -r /etc/os-release ] && grep -qiE '^(ID|ID_LIKE)=.*suse' /etc/os-release
}

install_deb() {
  have apt-get || die "apt-get is required for the deb package (try: sh -s flatpak)"
  ASSET="open-design_${VERSION}_amd64.deb"
  download_verified "$ASSET"
  chmod 755 "$TMP"; chmod 644 "$TMP/$ASSET"   # readable by apt's _apt sandbox user
  say "Installing with apt-get (sudo may ask for your password)"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$TMP/$ASSET" \
    || die "apt-get install failed"
}

install_rpm() {
  if have zypper && { is_opensuse || ! have dnf; }; then
    RPM_TOOL=zypper
  elif have dnf; then
    RPM_TOOL=dnf
  else
    die "dnf or zypper is required for the rpm package (try: sh -s flatpak)"
  fi
  ASSET="open-design_${VERSION}_x86_64.rpm"
  download_verified "$ASSET"
  say "Installing with $RPM_TOOL (sudo may ask for your password)"
  if [ "$RPM_TOOL" = zypper ]; then
    as_root zypper --non-interactive install --allow-unsigned-rpm "$TMP/$ASSET" \
      || die "zypper install failed"
  else
    as_root dnf install -y "$TMP/$ASSET" || die "dnf install failed"
  fi
}

install_flatpak() {
  have flatpak || die "flatpak is required (install flatpak first)"
  ASSET="open-design.flatpak"
  download_verified "$ASSET"
  if [ "$(id -u)" = "0" ]; then
    say "Installing the Flatpak bundle (system installation)"
    run_installer flatpak install --system --assumeyes --bundle "$TMP/$ASSET" \
      || die "flatpak install failed"
  else
    say "Installing the Flatpak bundle (user installation)"
    run_installer flatpak install --user --assumeyes --bundle "$TMP/$ASSET" \
      || die "flatpak install failed"
  fi
}

# --- main --------------------------------------------------------------------

main() {
  if [ $# -gt 1 ]; then usage; die "expected at most one argument, got $#"; fi
  WANT="${1:-auto}"
  case "$WANT" in
    auto|deb|rpm|flatpak) ;;
    -h|--help) usage; exit 2 ;;
    *) usage; die "unknown package type: $WANT (expected deb, rpm or flatpak)" ;;
  esac

  # Explicit argument wins, otherwise detect from the package manager.
  if [ "$WANT" = auto ]; then
    if have dnf || have zypper; then WANT=rpm
    elif have apt-get; then WANT=deb
    else WANT=flatpak
    fi
  fi

  setup_fetch
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  TMP=$(mktemp -d) || die "could not create a temporary directory"

  resolve_release
  case "$WANT" in
    deb) install_deb ;;
    rpm) install_rpm ;;
    flatpak) install_flatpak ;;
  esac

  say "Done. Launch 'Open Design' from your application menu."
  info "Community build — unsigned, no auto-update. Upstream: https://open-design.ai"
}

main "$@"

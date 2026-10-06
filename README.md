# OpenDesign for GNU/Linux

> **Community packaging of [OpenDesign](https://github.com/nexu-io/open-design) — the open-source, local-first Claude Design alternative.**

**This project is, at the moment, literally just packaging.** No product code is
developed here. We take every **stable upstream release**, apply a small,
reviewed series of Linux-packaging patches, build native packages
(`.deb`, `.rpm`, Flatpak) through CI, and publish them as releases.
**Long-term, everything in this repository is destined for upstream** —
each patch either already exists as an upstream PR we track, or is written to
be proposed upstream.

[![Linux community packages](https://github.com/kacperpaczos/OpenDesign-For-GNU-Linux/actions/workflows/linux-packages.yml/badge.svg)](https://github.com/kacperpaczos/OpenDesign-For-GNU-Linux/actions/workflows/linux-packages.yml)

## Install

Grab an artifact from [Releases](https://github.com/kacperpaczos/OpenDesign-For-GNU-Linux/releases) (every release carries `sha256sums.txt` — verify before installing):

```bash
# Fedora / RHEL / openSUSE
sudo dnf install ./open-design_<version>_x86_64.rpm

# Debian / Ubuntu
sudo apt install ./open-design_<version>_amd64.deb

# Any distro (Flatpak, user install)
flatpak --user install ./open-design.flatpak
```

Releases are built automatically: a daily job watches
[nexu-io/open-design](https://github.com/nexu-io/open-design) for a new stable
tag, cherry-picks the packaging series onto it, builds, and publishes
`<tag>-linux`. Manual builds: `gh workflow run linux-packages.yml`.

## What the packaging series fixes (vs. upstream's missing Linux lane)

- **Web runtime**: ships the Next.js standalone tree so the web sidecar boots
  from an installed package (upstream's Linux lane is pinned to a mode that
  requires the source workspace — packages die at startup with exit 75).
- **Native modules**: explicit install policy + fail-closed validation for
  `better-sqlite3` (upstream PR #7979), so the daemon's database actually works.
- **`.deb` target** (upstream PR #6010, plus `libgbm1`/`libasound2t64`
  runtime deps) and a **`.rpm` target** in the same spirit.
- **Flatpak** manifest (best-effort; deliberately permissive sandbox — this
  app spawns your local coding-agent CLIs by design; not Flathub-grade).

Tracking upstream: [issue #4368](https://github.com/nexu-io/open-design/issues/4368)
("NO Linux app image"). Our intent is to fold this whole series back upstream.

## Honest caveats

- Packages are **unsigned**; verify with `sha256sums.txt`.
- No auto-update — install a newer release to upgrade.
- The Flatpak sandbox is loose **by design** (the product runs your tools);
  do not treat it as a security boundary.
- AppImage is intentionally skipped: its extract-and-run semantics are
  hostile to this app's detached-daemon architecture (see upstream #8406/#8446).

## License

OpenDesign is Apache-2.0. Everything here is derived from it under the same
license; upstream remains the single source of truth for the product.

---

*Upstream README (product docs, screenshots, full tour) lives in
[nexu-io/open-design](https://github.com/nexu-io/open-design#readme).*

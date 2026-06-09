# lamboot-tools Packaging — Conventions (decoupled model)

**Status:** authoritative for all lamboot-tools downstream packaging. Lives in
the dev tree (`lamboot-tools-dev/packaging/`); the lamco-admin pipeline
(`pipelines/lamboot-tools/`) is the *orchestration* that consumes this — it
never holds a second copy of any metadata.

This mirrors the lamboot packaging model (`lamboot-dev/packaging/PACKAGING.md`):
packaging metadata iterates independently of source releases, the upstream
version lives in one place, and channel checksums are computed at publish rather
than hand-propagated. lamboot-tools diverges from lamboot where the product
forces it — it is a shell suite that bundles private prebuilt binaries, not a
Secure Boot-signed bootloader. The differences are spelled out below.

---

## 1. One upstream artifact (immutable per version)

lamboot ships two artifacts (a `-bin` convenience tarball and a clean source
tree) because its `.efi` must be cross-built + signed. lamboot-tools is
different: there is **one** release tarball, and it already carries the prebuilt
component binaries.

| Artifact | Built by | Contents | Feeds |
|---|---|---|---|
| **release tarball** | `publish/build-tarball.sh` | the shell suite (`tools/`, `lib/`, `pve/`), man pages, docs, tests, **and** the vendored static-musl component binaries under `vendor/bin/<arch>/` (`lamboot-capcheck`, `lamboot-reader`) plus their `THIRD_PARTY_NOTICES` | GitHub Releases, apt.lamco.ai deb, AUR `lamboot-tools-bin`, Copr/OBS rpm |

Because the binaries are bundled in the tarball, the prebuilt channels do not
download a separate `-bin` artifact: they unpack this tarball and install the
arch-matching binaries from `vendor/bin/<arch>/`. The `vendor/` binaries are
built by `publish/vendor-binaries.sh` from the sibling repos
(`lamco-admin/lamboot-capcheck`, `lamco-admin/lamboot-reader`) at a pinned tag.

## 2. Why this is NOT eligible for Debian main / Fedora official

**lamboot-tools bundles private, prebuilt binaries.** `lamboot-capcheck` and
`lamboot-reader` are compiled Rust components that currently live in private
repos, are not on crates.io, and travel into the release only as stripped
static-musl binaries. Both Debian and Fedora forbid this in their reviewed
archives:

- **Debian main** requires building from source and forbids vendored prebuilt
  binaries in the binary package. (Debian Policy: the source must build the
  binaries; no "convenience" precompiled blobs.)
- **Fedora official** requires building all binaries from source in Koji and
  forbids bundled prebuilt executables.

So the eligible channels for lamboot-tools today are the **self-hosted /
user-repo** ones only:

- **apt.lamco.ai** (our own apt repo — `packaging/deb/`)
- **AUR `lamboot-tools-bin`** (AUR explicitly allows `-bin` packages that
  repackage upstream binaries — `packaging/aur/lamboot-tools-bin/`)
- **Fedora Copr** and **openSUSE OBS** (user repos, no review gate that forbids
  bundled binaries — `packaging/rpm/lamboot-tools.spec`)

The path to Debian main / Fedora official is: open-source `lamboot-capcheck`
and `lamboot-reader`, publish them to crates.io, and package them as their own
source packages; then lamboot-tools can `Depends`/`Requires` them instead of
bundling. Until then, the reviewed archives are out of scope. This is the same
boundary noted in `lamboot-dev/packaging/PACKAGING.md` §7.

## 3. Canonical install-path contract (shared across ALL channels)

Every channel installs to the same layout so behavior is identical everywhere.
This is the runtime contract the shell suite assumes — deviating from it breaks
library sourcing or the capcheck bridge.

| Path | Content | Why this exact path |
|---|---|---|
| `/usr/bin/lamboot-{diagnose,esp,backup,repair,doctor,toolkit,uki-build,signing-keys,migrate}` | the shell tools, on PATH | user-facing CLIs |
| `/usr/lib/lamboot-tools/lamboot-toolkit-lib.sh`, `lamboot-toolkit-help.sh`, `esp-deploy.sh`, `_nvram_set_first_boot.py` | shared shell library + python helper | the tools source `${LAMBOOT_LIB_DIR:-/usr/lib/lamboot-tools}/...` — this literal default is hardcoded, arch-independent. **Do not** use `%{_libdir}`/`$(get_libdir)` — that resolves to `/usr/lib64` on x86_64 and the tools do not look there. |
| `/usr/lib/lamboot-tools/lamboot-inspect` + `/usr/lib/lamboot-tools/lamboot_inspect/` | the python `lamboot-inspect` shim **and** its sibling package | the shim's `_bootstrap()` adds `dirname(realpath(__file__))` to `sys.path`, so the script and the `lamboot_inspect/` package must share a directory |
| `/usr/bin/lamboot-inspect` → `../lib/lamboot-tools/lamboot-inspect` | relative symlink onto PATH | realpath resolves through the symlink so the sibling package is still found |
| `/usr/bin/lamboot-capcheck`, `/usr/bin/lamboot-reader` | the vendored static-musl binaries (arch-matching) | `lib/lamboot-capcheck-bridge.sh` finds capcheck via `command -v lamboot-capcheck` (PATH); `lamboot-reader` is a standalone user CLI. **They go on PATH, not in a libexec dir** — a private libexec path would break the bridge's PATH lookup and hide the reader CLI. |
| `/usr/share/man/man1/*.1`, `man5/lamboot-tools-schema.5`, `man7/lamboot-tools.7` | man pages | standard |
| `/usr/share/doc/lamboot-tools/` | README, CHANGELOG, the public design spec, and the vendored `THIRD_PARTY_NOTICES` | standard |
| licenses | `LICENSE-MIT`, `LICENSE-APACHE` | deb: `/usr/share/doc/lamboot-tools/`; rpm/AUR: `/usr/share/licenses/lamboot-tools/` |

Differences from the lamboot contract (do not blind-copy lamboot here):

- lamboot stages a whole tree under `/usr/share/lamboot` because
  `lamboot-install` searches for it at runtime. **lamboot-tools has no such
  staging** — there is no installer that re-deploys a tree. Files go straight to
  their final FHS paths.
- The shared-library dir is `/usr/lib/lamboot-tools` (the suite's hardcoded
  default), the analogue of lamboot's literal `/usr/lib/lamboot`. Both are
  arch-independent literals, **never** `%{_libdir}`.
- There is no ESP, no Secure Boot signature, no systemd units, and no kernel
  hooks in this package. The only "stripping" caveat (below) is about not
  re-stripping the already-stripped vendored binaries — there is no PE
  signature to protect.

## 4. The vendored binaries: stripping + debuginfo

The `vendor/bin/<arch>/` binaries are already stripped static-musl executables
with no usable debuginfo. Each channel must keep packaging from choking on them:

- **deb:** `debian/rules` overrides `dh_strip`/`dh_dwz` (they are already
  stripped; there are no `.debug` sections to extract) and `dh_shlibdeps` (the
  binaries are static — no shared-library dependencies to scan, and scanning a
  musl static binary produces nothing useful).
- **rpm:** `%global debug_package %{nil}` so rpmbuild does not try to extract
  build-ids and fail; **and** neutralise the strip BRP scripts
  (`%global __strip /bin/true`, `__brp_strip*` set to `%{nil}`) so rpmbuild does
  not re-strip the binaries. `debug_package %{nil}` alone is not enough — the
  BRP strip still runs and rewrites the bytes, which would break the
  BuildID/sha256 recorded in `vendor/BINARY-PROVENANCE.txt`. (Verified: with the
  BRPs neutralised the installed binary's sha256 equals the vendored source's.)
- **AUR:** `options=(!strip)` so makepkg does not re-strip them.

This is a different reason from lamboot's "never strip the signed PE" — there is
no signature here — but the mechanical effect (do not let the channel re-strip)
is the same, so the override shape is familiar.

## 5. Decoupling: version + checksum injected at publish time

- **No committed checksums.** Channel metadata uses `SKIP` (AUR) or a rendered
  placeholder; the lamco-admin `render` step computes the artifact checksum at
  publish and stamps it. This deletes the "propagate SHA256 to N files / re-tag
  on rebuild" failure class.
- **Per-channel revision counter**, independent of the upstream version:
  - deb: `debian/changelog` version `UPSTREAM-REVISION` (`0.8.0-1` → `0.8.0-2`)
  - rpm: `Release:` (`1%{?dist}` → `2%{?dist}`)
  - AUR: `pkgrel` (`1` → `2`)
  A packaging-only fix bumps the revision, re-renders, and re-publishes **that
  one channel** — no source re-tag, no cross-channel fan-out.

## 6. Layout

```
packaging/
  PACKAGING.md            # this file
  release.toml            # single source of truth: upstream version
  deb/                    # apt.lamco.ai prebuilt binary deb
    debian/               # control, rules, changelog, copyright, install, postinst, ...
    README.md
  aur/
    lamboot-tools-bin/    # prebuilt -bin PKGBUILD (+ .SRCINFO)
  rpm/
    lamboot-tools.spec    # Copr / OBS share this (existing build-from-source
                          # spec ALSO lives here; see §7)
    lamboot-tools.rpmlintrc
  copr/                   # Copr build configs (existing)
```

## 7. Two rpm specs (intentional)

`packaging/rpm/lamboot-tools.spec` is the existing **build-from-source** Copr
spec: it runs `make build-inlined`, `make man`, and `%make_install`, then
installs the arch binaries from `vendor/`. It is correct for Copr/OBS, which
clone the source (`source_type: git`, `source_build_method: make_srpm` in
`copr/lamboot-tools.yml`) and build. It remains the canonical rpm for Copr.

`packaging/rpm/lamboot-tools-bin.spec` is the **prebuilt-repackage** rpm: its
`Source0` is the published release tarball, it compiles nothing, and it installs
the already-built shell tools + the arch-matching `vendor/bin/<arch>/` binaries.
Use it where building from source is not wanted (e.g. an OBS prebuilt project,
or generating the rpm from the same release artifact the deb/AUR `-bin` packages
consume). It produces the same four (sub)packages as the Copr spec
(`lamboot-tools`, `lamboot-tools-firmware`, `lamboot-migrate`,
`lamboot-toolkit-pve`).

The deb and AUR `lamboot-tools-bin` packages in this directory are the prebuilt
repackage model too. This is the same split lamboot uses (build-from-source vs
prebuilt repackage), applied to the channels each model fits.

## 8. dev vs lamco-admin

- **dev (`lamboot-tools-dev/packaging/`):** the metadata — single source of truth.
- **lamco-admin (`pipelines/lamboot-tools/`):** orchestration only — per-channel
  build+publish scripts that consume `packaging/<channel>/`, render
  version/checksum, push to the channel; plus the live channel tracker. No
  metadata is duplicated there.
- Public channels (apt repo, AUR git, Copr, OBS) receive contents **only** via
  those scripts. No hand-edits to any public channel. Every publish is
  per-action approval-gated.

## 9. lamboot and lamboot-tools

Two independent packages, **never combined**, versioned on their own cadence
(lamboot `0.15.2`, lamboot-tools `0.8.0`). They co-reside on self-hosted
channels (apt.lamco.ai pool, OBS project, AUR) but are distinct packages. They
diverge most on archive eligibility: lamboot's source can (eventually) build in
Debian/Fedora, while lamboot-tools cannot enter those archives until its bundled
components are open-sourced + packaged separately (§2).

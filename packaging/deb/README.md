# lamboot-tools deb packaging (apt.lamco.ai prebuilt binary)

This `debian/` packages the **published lamboot-tools release tarball** into a
binary `.deb` for `apt.lamco.ai`. It does **not** run the suite's Makefile build
- it repackages the upstream artifact, so it builds anywhere with no special
toolchain.

## Why apt.lamco.ai only (not Debian main)

lamboot-tools bundles the **prebuilt** static-musl binaries `lamboot-capcheck`
and `lamboot-reader` (the suite's Rust components, which live in separate private
repos and are not yet on crates.io). Debian main forbids vendored prebuilt
binaries in a binary package: the source must build everything. So this package
is distributed from the Lamco apt repository only. The route to Debian main is
to open-source those two components and package them as their own source
packages; until then this is an apt.lamco.ai / AUR / Copr / OBS package. See
`../PACKAGING.md` §2.

## Decoupling (see ../PACKAGING.md §5)

- **Upstream version** = `[upstream] version` in `../release.toml` (`0.8.0`).
- **Packaging revision** = the `-N` in `debian/changelog` (`0.8.0-1`). A
  packaging-only fix bumps to `0.8.0-2` with **no upstream re-tag**.
- **No checksums committed.** The orig tarball is the published release tarball;
  the pipeline provides + verifies it at build time.

## Install contract

This `debian/` mirrors the runtime contract in `../PACKAGING.md` §3:

- shell tools -> `/usr/bin`;
- shared library + the `lamboot_inspect` Python package -> the **literal**
  `/usr/lib/lamboot-tools` (the tools source `${LAMBOOT_LIB_DIR:-/usr/lib/lamboot-tools}`,
  so this is a hardcoded path, never a multiarch libdir);
- `/usr/bin/lamboot-inspect` is a relative symlink to the real script in
  `/usr/lib/lamboot-tools`, so its `_bootstrap()` realpath still finds the
  sibling `lamboot_inspect/` package;
- the arch-matching `lamboot-capcheck` + `lamboot-reader` -> `/usr/bin` (the
  capcheck bridge does `command -v lamboot-capcheck`; `lamboot-reader` is a
  standalone CLI), selected from `vendor/bin/<arch>/` by `debian/rules` using
  `DEB_HOST_GNU_CPU`.

`debian/rules` disables `dh_strip`/`dh_dwz` (the vendored binaries are already
stripped, no debuginfo to extract) and `dh_shlibdeps` (they are static, no
shared-library deps to scan).

## How the lamco-admin pipeline builds + publishes it (per-arch)

```
# 1. Fetch the published release tarball and present it as the orig tarball
curl -L -o lamboot-tools_0.8.0.orig.tar.gz \
    https://github.com/lamco-admin/lamboot-tools/releases/download/v0.8.0/lamboot-tools-0.8.0.tar.gz
# (verify the .sha256/.asc before use)

# 2. Assemble the build tree: extracted upstream + this debian/
tar xf lamboot-tools_0.8.0.orig.tar.gz        # -> lamboot-tools-0.8.0/
cp -a packaging/deb/debian lamboot-tools-0.8.0/debian

# 3. Build the binary deb for the host arch (no compile; just install + package)
cd lamboot-tools-0.8.0 && debuild -us -uc -b   # -> ../lamboot-tools_0.8.0-1_amd64.deb

# 4. Publish to apt.lamco.ai (reprepro on toom) - PER-ACTION APPROVAL REQUIRED
ssh greg@toom "reprepro -b /var/www/apt.lamco.ai includedeb stable \
    /tmp/lamboot-tools_0.8.0-1_amd64.deb"
```

arm64: build on (or cross to) arm64 so `DEB_HOST_GNU_CPU=aarch64` selects the
`vendor/bin/aarch64/` binaries, then publish the `arm64` deb the same way.

## Notes

- The package never modifies the ESP or `/etc`. The suite acts only when the
  operator runs a tool.
- Publishing is per-action approval-gated and must run via the pipeline, never
  by editing the public apt repo or this `debian/` in a public clone.

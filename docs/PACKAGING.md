# Packaging runbook

Release engineer's guide to building + publishing `lamboot-tools` and its sibling packages. Follow top-to-bottom for a coordinated release.

**Authoritative spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §7 + §14
**Tracked state:** `CROSS-REPO-STATUS.md`

---

## 1. Overview — one source repo, three RPM outputs

The toolkit ships as **three RPM packages built from one source**:

| RPM | Built from | Copr project | Target |
|---|---|---|---|
| `lamboot-tools` | `lamboot-tools-dev` (this repo), spec `packaging/rpm/lamboot-tools.spec` main | `lamco/lamboot-tools` | Core tools — any Linux UEFI host |
| `lamboot-toolkit-pve` | Same repo + spec, `%package -n lamboot-toolkit-pve` subpackage | `lamco/lamboot-tools` (same Copr project) | Proxmox VE hosts only |
| `lamboot-migrate` | Same repo + spec, `%package -n lamboot-migrate` subpackage (also dual-published via `lamboot-migrate-standalone.spec`) | `lamco/lamboot-migrate` (dual-pub) | Users who want just migration |

Per founder decision 2026-04-22: the PVE tooling lives in the `pve/` subtree
of the same dev repo and ships as an RPM subpackage — no separate repo,
no separate Copr project. The single `packaging/rpm/lamboot-tools.spec`
produces all three subpackage RPMs in one Copr build.

`lamboot-migrate` is **dual-published** per R22 of the spec: it ships BOTH as a subpackage of `lamboot-tools` AND as the standalone `lamboot-migrate` package (via `packaging/rpm/lamboot-migrate-standalone.spec`). Both install to `/usr/bin/lamboot-migrate`; RPM's file-conflict resolution plus an explicit `Conflicts:` directive prevents double-install.

---

## 2. Pre-release checklist

Before any release, confirm:

- [ ] `CHANGELOG.md` has an entry for the new version
- [ ] `scripts/verify-claims.sh` passes
- [ ] All bats tests pass locally (`make test` + `make test-pve`)
- [ ] CI green on `main`
- [ ] Fleet-test matrix passed within the last 7 days (or waived in CHANGELOG with justification)
- [ ] `docs/CROSS-REPO-STATUS.md` coordination items resolved or explicitly deferred
- [ ] Version bumped in `lib/lamboot-toolkit-lib.sh` (strip `-dev` suffix)
- [ ] Per-tool versions reviewed (stripped of `-dev` suffixes as appropriate)
- [ ] Man pages regenerated (`make man`)
- [ ] Website pages regenerated (`make website`)

Last-step sanity check: `make test-all && scripts/verify-claims.sh`.

---

## 3. Building artifacts

```bash
# Core toolkit tarball
publish/build-tarball.sh

# Standalone lamboot-migrate (dual-publication)
publish/build-standalone-migrate.sh

# Mirror lamboot-dev canonical sources (lamboot-inspect, etc.)
LAMBOOT_DEV_ROOT=~/lamboot-dev \
    publish/mirror-from-lamboot-dev.sh

# Mirror lamboot-dev PVE sources (lamboot-monitor.py, build-ovmf-vars.sh)
LAMBOOT_DEV_ROOT=~/lamboot-dev \
    publish/mirror-pve-from-lamboot-dev.sh
# (these become lamboot-pve-monitor + lamboot-pve-ovmf-vars in pve/tools/)
```

Each build script verifies preconditions and writes to `build/` with sha256 + size reported.

---

## 4. Local spec validation

Before pushing to Copr, lint each RPM spec locally:

```bash
sudo dnf install -y rpmlint mock

# Lint (two specs: unified + standalone)
rpmlint packaging/rpm/lamboot-tools.spec
rpmlint packaging/rpm/lamboot-migrate-standalone.spec

# Build SRPM + RPM in mock
mock -r fedora-44-x86_64 --buildsrpm \
    --spec packaging/rpm/lamboot-tools.spec \
    --sources build/tarball/

mock -r fedora-44-x86_64 \
    $(ls /var/lib/mock/fedora-44-x86_64/result/lamboot-tools-*.src.rpm | head -1)
```

Address all rpmlint warnings before proceeding. Acceptable warnings should be documented in the spec (if any).

---

## 5. Copr publishing

Copr projects are pre-configured per `packaging/copr/*.yml`. Publish a new version:

### 5.1 Prerequisites

```bash
# One-time setup
sudo dnf install -y copr-cli
copr-cli whoami           # verify auth
```

### 5.2 Trigger builds

```bash
# Unified build — one Copr invocation produces three subpackage RPMs
# (lamboot-tools, lamboot-migrate, lamboot-toolkit-pve)
copr-cli build lamco/lamboot-tools \
    build/tarball/lamboot-tools-0.2.0.tar.gz

# Standalone lamboot-migrate (dual-published per R22)
copr-cli build lamco/lamboot-migrate \
    build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz
```

Build status visible at https://copr.fedorainfracloud.org/coprs/lamco/lamboot-tools/. Each build produces chroot-specific RPMs (Fedora 44, 45, Rawhide, EPEL 9/10). Users install whichever subpackage(s) they need: `dnf install lamboot-tools` for core, `dnf install lamboot-toolkit-pve` for Proxmox hosts, `dnf install lamboot-migrate` as a dependency-free alternative.

### 5.3 User install

Once builds are green:

```bash
# User on Fedora
sudo dnf copr enable lamco/lamboot-tools
sudo dnf install lamboot-tools

# For Proxmox hosts (same Copr project — already enabled above)
sudo dnf install lamboot-toolkit-pve

# For standalone migrate (users who want just migration, no toolkit lib)
sudo dnf copr enable lamco/lamboot-migrate
sudo dnf install lamboot-migrate
```

---

## 6. GitHub release

```bash
# Sign the tarball
gpg --armor --detach-sign build/tarball/lamboot-tools-0.2.0.tar.gz

# Create release via gh CLI
gh release create v0.2.0 \
    build/tarball/lamboot-tools-0.2.0.tar.gz{,.asc} \
    build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz{,.asc} \
    --title "lamboot-tools 0.2.0 — first public release" \
    --notes-file CHANGELOG.md \
    --repo lamco-admin/lamboot-tools
```

!!! warning "Governance"
    Per project governance (~/.claude/CLAUDE.md):
    **NEVER push releases without explicit founder approval.** All `gh release create` invocations require confirmation.

---

## 7. Public repo mirror

```bash
# Requires founder confirmation per governance
LAMBOOT_EXPORT_CONFIRMED=1 \
    publish/export-to-public.sh v0.2.0
```

This stages the tagged commit in `~/lamboot-tools` (public). Still requires explicit `git push` + `gh release create` invocation.

---

## 8. Coordinated release with lamboot-dev

`lamboot-tools v0.2.0` coordinates with `lamboot-dev v0.8.4` per `docs/CROSS-REPO-STATUS.md` §4.1. Procedure:

1. **lamboot-dev** ships v0.8.4 FIRST (hookscript rewrite)
2. **lamboot-tools-dev** confirms mirrors succeed against the v0.8.4 sources:
   ```bash
   LAMBOOT_DEV_ROOT=~/lamboot-dev publish/mirror-from-lamboot-dev.sh
   LAMBOOT_DEV_ROOT=~/lamboot-dev publish/mirror-pve-from-lamboot-dev.sh
   ```
3. **lamboot-tools-dev** builds artifacts + publishes Copr (single build
   produces all three subpackage RPMs: `lamboot-tools`, `lamboot-migrate`,
   `lamboot-toolkit-pve`)
4. Combined announcement covering both repos

**If lamboot-dev v0.8.4 slips:** two options:
- (a) Defer toolkit v0.2.0 until v0.8.4 ships. Preferred if timeline allows.
- (b) Ship toolkit v0.2.0 with `lamboot-toolkit-pve` clearly marked "requires
  lamboot-dev >= 0.8.4; `lamboot-pve-setup` will refuse to run against
  earlier hookscripts." Other subpackages (`lamboot-tools`, `lamboot-migrate`)
  ship unaffected.

---

## 9. Debian/Ubuntu PPA (v0.3+)

PPA packaging is a v0.3 deliverable. Sketch:

```bash
# Build debian packages (requires debian packaging machinery)
cd packaging/debian
dpkg-buildpackage -us -uc

# Upload to PPA
dput ppa:lamco/lamboot-tools ../lamboot-tools_0.2.0_source.changes
```

Full Debian packaging template is TBD. See `packaging/debian/README.md` (placeholder for v0.3).

---

## 10. Homebrew tap (v0.5+)

Formula maintained at `lamco-admin/homebrew-tap`. Update procedure:

```bash
cd ~/lamco-admin/homebrew-tap
./update-formula.sh lamboot-tools 0.2.0
git commit -am "lamboot-tools 0.2.0"
git push
```

Users install via:

```bash
brew tap lamco-admin/tap
brew install lamboot-tools
```

Primary audience: Linux-fleet admins managing remote hosts from a macOS workstation.

---

## 11. Post-release

- [ ] Monitor issue tracker for install problems over first 72 hours
- [ ] Update `docs/CROSS-REPO-STATUS.md` archival entry (move release-cycle items to closed)
- [ ] Tag `lamboot-tools-dev` repo with `v0.2.0` for internal traceability
- [ ] Update `ROADMAP.md` with next-session plan
- [ ] Close corresponding `lamco-admin/pipelines/lamboot-tools/` checklist

---

## 12. Rollback

If a shipped release has a critical bug:

1. `copr-cli delete` the affected chroot/version (users' next `dnf update` picks up)
2. `gh release edit` to mark as pre-release or delete (users' direct downloads stop)
3. Post advisory to issue tracker + release notes
4. Fix in dev, ship patch release (e.g., v0.2.1)

Do NOT delete a published release entirely — leaves users in a confused state. Mark it and ship a fix.

---

## 13. See also

- `SPEC-LAMBOOT-TOOLKIT-V1.md` §7 (distribution + packaging strategy)
- `SPEC-LAMBOOT-TOOLKIT-V1.md` §14 (cross-repo coordination)
- `CROSS-REPO-STATUS.md` (rolling state tracker)
- `publish/` scripts — referenced from this runbook

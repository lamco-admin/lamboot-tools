# Release runbook — v0.2.0

**Purpose:** Exact step-by-step for executing a `lamboot-tools` release. Supersedes `PACKAGING.md` for the act of releasing (PACKAGING.md remains the reference for spec/infrastructure details).

**Governance:** Every public action requires founder approval. This runbook marks **GATE** at each such point.

**Audience:** release engineer executing under founder direction.

---

## 0. Pre-work (done — not in release window)

Everything below has been completed during Sessions A–P:

- ✅ All 11 tools implemented, tested, documented
- ✅ Man pages generated (`make man`)
- ✅ Website pages generated (`make website`)
- ✅ RPM specs written (`packaging/rpm/*.spec`)
- ✅ Copr configs written (`packaging/copr/*.yml`)
- ✅ Publish scripts written (`publish/*.sh`)
- ✅ CHANGELOG.md has v0.2.0 entry
- ✅ CROSS-REPO-STATUS.md tracks lamboot-dev coordination

**Before starting release work, confirm:**

- Founder has explicitly approved a release window.
- Fleet-test Tier 1 green in the last 7 days **OR** explicit disclosure of the
  pending-baseline state in `CHANGELOG.md` (see v0.2.0 CHANGELOG Known-limits).
- **lamboot-dev v0.8.4 state resolved** via one of two paths (§0.1 below).

### 0.1 lamboot-dev v0.8.4 coordination — choose one path before releasing

The `lamboot-toolkit-pve` subpackage depends on lamboot-dev ≥ 0.8.4 (fw_cfg
file-reference hookscript rewrite). As of audit 2026-04-22, lamboot-dev
v0.8.4 is PAUSED in `lamboot-dev/docs/STATUS-2026-04-22-TOOLKIT-PIVOT.md`.
Pick one path and document the choice in the CHANGELOG + announcement:

**Path A — coordinated release (preferred when schedule allows):**
1. Unpause lamboot-dev v0.8.4; complete hookscript rewrite in a dedicated sprint.
2. Ship `lamboot-dev v0.8.4` first.
3. Re-run `publish/mirror-pve-from-lamboot-dev.sh` against the v0.8.4 tag.
4. Proceed with this runbook §1.
5. Announcement covers both releases in one post.

**Path B — toolkit-first with runtime guard (ship now, coordinate later):**
1. Confirm `lamboot-pve-setup doctor-hookscript` correctly refuses old hookscripts
   with remediation text (already implemented).
2. Add disclosure to `CHANGELOG.md` v0.2.0: "`lamboot-toolkit-pve` subpackage
   installs but `lamboot-pve-setup` refuses to run against lamboot-dev < 0.8.4.
   Coordinated update arrives with lamboot-dev v0.8.4 (planned v0.2.1 toolkit refresh)."
3. `lamboot-tools` + `lamboot-migrate` subpackages ship fully functional.
4. `lamboot-dev v0.8.4` follows on its own schedule; no toolkit re-release needed
   since the runtime guard self-clears when users upgrade lamboot-dev.

**Path C — partial release (toolkit without PVE subpackage):**
- Not recommended. Leaves PVE users waiting; fractures the "one release" story.
- Only pick this if Path A is infeasible AND Path B's runtime guard is judged
  insufficient (e.g., Copr policy concerns about shipping a subpackage that may
  refuse to run).
- Remove `%package -n lamboot-toolkit-pve` from spec + adjust CHANGELOG.

---

## 1. Preflight (no external actions; ~5 minutes)

```console
$ cd ~/lamboot-tools-dev
$ git status                           # clean working tree
$ git log -1                           # latest commit is the one we'll release
$ scripts/verify-claims.sh                # 84/84 claims verified
$ make test-all                        # all bats suites green
$ scripts/release-rehearsal.sh         # 10-point release-readiness check
```

**All commands must exit 0.** If any fail, stop here. Fix, re-verify, restart.

---

## 2. Version bump (no external actions)

Strips `-dev` suffixes. Run in dry-run mode first to verify:

```console
$ publish/bump-version.sh --release --dry-run    # preview all changes
$ publish/bump-version.sh --release              # apply
$ git diff                                       # review the bump diff
```

Expected: 12 files change (`lib/lamboot-toolkit-lib.sh` + 9 core tools + 2 PVE tools). Toolkit `0.2.0-dev → 0.2.0`, `lamboot-migrate` `1.0.0-dev → 1.0.0`, all others `0.2.0-dev → 0.2.0`.

Commit:

```console
$ git add -u
$ git commit -m "release: v0.2.0"
$ git tag -a v0.2.0 -m "lamboot-tools 0.2.0 — first public release"
```

Do **NOT** push yet.

---

## 3. Regenerate docs (ensures docs match new versions)

```console
$ make man                             # regenerates man/*.1 with new versions
$ make website                         # regenerates website/tools/*.md
$ git status                           # expect regenerated files
$ git add -u                           # stage the regenerations
$ git commit -m "release: regenerate docs for v0.2.0"
```

(These would have been caught by the bump-version step, but the bump script doesn't run make; this step ensures parity.)

---

## 4. Build artifacts (no external actions)

```console
$ publish/build-tarball.sh
# Produces build/tarball/lamboot-tools-0.2.0.tar.gz

$ publish/build-standalone-migrate.sh
# Produces build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz
```

### 4.1 Mirror freshness check

Mirrors from `lamboot-dev` should be **committed to this repo before the
release window**, not run mid-release. This guarantees the tarball built
in §4 contains the mirrored files deterministically. Before entering the
release window:

```console
$ LAMBOOT_DEV_ROOT=~/lamboot-dev publish/mirror-from-lamboot-dev.sh
# Mirrors lamboot-inspect + Python package + man page from lamboot-dev
# Writes MIRROR-CHECKSUMS.txt at repo root

$ LAMBOOT_DEV_ROOT=~/lamboot-dev publish/mirror-pve-from-lamboot-dev.sh
# Mirrors lamboot-monitor.py + build-ovmf-vars.sh into pve/tools/
# Writes pve/MIRROR-CHECKSUMS.txt
# (these ship in the lamboot-toolkit-pve RPM subpackage, same source repo)

$ git diff MIRROR-CHECKSUMS.txt pve/MIRROR-CHECKSUMS.txt
# Review what changed since last mirror; commit if fresh.

$ git add tools/lamboot-inspect tools/lamboot_inspect/ man/lamboot-inspect.1 \
    pve/tools/lamboot-pve-monitor pve/tools/lamboot-pve-ovmf-vars \
    MIRROR-CHECKSUMS.txt pve/MIRROR-CHECKSUMS.txt
$ git commit -m "chore: refresh mirrors from lamboot-dev @ <tag>"
```

Rerun the mirror only if `lamboot-dev` has moved since the last commit —
`scripts/release-rehearsal.sh` verifies mirrored files are present and
refuses to green-light a release with stale or missing mirrors.

---

## 5. Local RPM validation (mock + rpmlint)

On a Fedora host (use VM 104 `fedora-gnome` on pve1 per the session practice;
start via `ssh root@pve1 qm start 104` and stop afterward with `qm stop 104`):

```console
$ sudo dnf install -y rpmlint mock rpmdevtools
$ sudo usermod -a -G mock greg && newgrp mock
$ rpmdev-setuptree

# Stage tarballs + specs onto the Fedora host (from the dev host):
$ rsync -a build/tarball/lamboot-tools-0.2.0.tar.gz \
    build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz \
    greg@<fedora-ip>:~/rpmbuild/SOURCES/
$ rsync -a packaging/rpm/*.spec packaging/rpm/*.rpmlintrc \
    greg@<fedora-ip>:~/rpmbuild/SPECS/

# Lint the specs first (catches packaging policy issues like noarch-in-libdir):
$ ssh greg@<fedora-ip> 'rpmlint ~/rpmbuild/SPECS/lamboot-tools.spec \
                                 ~/rpmbuild/SPECS/lamboot-migrate-standalone.spec'
# Expected: 0 errors, 0 warnings.

# Build the main SRPM + binary RPMs. The %check block runs verify-claims.sh
# and the full bats suite against a pristine Fedora 44 chroot.
$ ssh greg@<fedora-ip> \
    'mock -r fedora-44-x86_64 --buildsrpm \
       --spec ~/rpmbuild/SPECS/lamboot-tools.spec \
       --sources ~/rpmbuild/SOURCES/ \
       --resultdir=/tmp/mock-result &&
     mock -r fedora-44-x86_64 --rebuild --no-clean \
       /tmp/mock-result/lamboot-tools-*.src.rpm \
       --resultdir=/tmp/mock-rebuild'

# Same for standalone-migrate:
$ ssh greg@<fedora-ip> \
    'mock -r fedora-44-x86_64 --buildsrpm \
       --spec ~/rpmbuild/SPECS/lamboot-migrate-standalone.spec \
       --sources ~/rpmbuild/SOURCES/ \
       --resultdir=/tmp/mock-migrate-srpm &&
     mock -r fedora-44-x86_64 --rebuild --no-clean \
       /tmp/mock-migrate-srpm/lamboot-migrate-*.src.rpm \
       --resultdir=/tmp/mock-migrate'

# Final rpmlint on the produced binary + source RPMs:
$ ssh greg@<fedora-ip> \
    'rpmlint --ignore-unused-rpmlintrc \
       -r ~/rpmbuild/SPECS/lamboot-tools.rpmlintrc \
       /tmp/mock-rebuild/*.rpm /tmp/mock-migrate/*.rpm'
# Expected: 6 packages checked; 0 errors, 0 warnings. ~100 filters applied
# via the packaging/rpm/lamboot-tools.rpmlintrc config (domain-specific
# spelling, noarch-shell-library conventions, etc).
```

The mock chroot is created fresh (~2 min first time) and cached thereafter.
Each `--rebuild` runs the full `%check` including verify-claims.sh (76 claims)
and the 214-test bats suite.

---

## 6. Sign artifacts (GATE: founder's GPG key)

```console
# GATE: founder signs with lamco-admin's release key
$ gpg --armor --detach-sign build/tarball/lamboot-tools-0.2.0.tar.gz
$ gpg --armor --detach-sign build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz
```

Verify:

```console
$ gpg --verify build/tarball/lamboot-tools-0.2.0.tar.gz.asc
# "Good signature from Lamco Development"
```

---

## 7. GATE: founder review

Founder reviews before any public action:

- `git log -p HEAD~2..HEAD` — commits to publish
- `build/tarball/lamboot-tools-0.2.0.tar.gz` — extract + verify contents
- `build/tarball/lamboot-tools-0.2.0.tar.gz.asc` — GPG signature valid
- `CHANGELOG.md` — v0.2.0 entry accurate
- `docs/CROSS-REPO-STATUS.md` — coordination items resolved
- Announcement drafts in `docs/ANNOUNCEMENTS/` ready for publication

**Do not proceed without explicit founder "ship it" approval.**

---

## 8. Push dev repo (GATE: founder approval required)

```console
# GATE — requires founder "ship it" confirmation
$ git push origin main
$ git push origin v0.2.0
```

---

## 9. Mirror to public repo (governance-gated)

```console
$ LAMBOOT_EXPORT_CONFIRMED=1 publish/export-to-public.sh v0.2.0
# Stages commit in ~/lamboot-tools (public)
```

The script prints next-step commands but does NOT push. Founder executes:

```console
# GATE — final public publish
$ cd ~/lamboot-tools
$ git log -1                           # verify the staged commit
$ git push origin main
$ git push origin v0.2.0
```

---

## 10. GitHub release (GATE: founder approval)

```console
$ gh release create v0.2.0 \
    ~/lamboot-tools-dev/build/tarball/lamboot-tools-0.2.0.tar.gz \
    ~/lamboot-tools-dev/build/tarball/lamboot-tools-0.2.0.tar.gz.asc \
    ~/lamboot-tools-dev/build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz \
    ~/lamboot-tools-dev/build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz.asc \
    --title "lamboot-tools 0.2.0 — first public release" \
    --notes-file CHANGELOG.md \
    --repo lamco-admin/lamboot-tools
```

---

## 11. (removed — PVE companion ships as a subpackage of lamboot-tools)

The `lamboot-toolkit-pve` RPM subpackage is produced by the same
`packaging/rpm/lamboot-tools.spec` that produces `lamboot-tools` and
`lamboot-migrate`. No separate repo, no separate tag, no separate
`gh release`. Users on Proxmox hosts install it via:

    sudo dnf install lamboot-toolkit-pve

Section numbering kept for document stability; no step-11 action.

---

## 12. Standalone lamboot-migrate release

If the standalone repo has been created (v1.0 spin-off moment):

```console
$ cd ~/lamboot-migrate
# (extract-and-copy build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz here)
$ git add -A
$ git commit -m "release: v1.0.0"
$ git tag -a v1.0.0 -m "lamboot-migrate 1.0.0 — standalone release"

# GATE
$ git push origin main
$ git push origin v1.0.0
$ gh release create v1.0.0 \
    ~/lamboot-tools-dev/build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz \
    --title "lamboot-migrate 1.0.0 — standalone release" \
    --notes-file README.md \
    --repo lamco-admin/lamboot-migrate
```

(The standalone repo may not yet exist at v0.2.0 toolkit release — in that case, skip this step; it becomes a v1.0 coordinated release deliverable.)

---

## 13. Copr publishing

```console
$ copr-cli whoami                      # verify auth

$ copr-cli build lamco/lamboot-tools \
    ~/lamboot-tools-dev/build/tarball/lamboot-tools-0.2.0.tar.gz
# Single source build produces three subpackage RPMs:
#   lamboot-tools, lamboot-migrate, lamboot-toolkit-pve

$ copr-cli build lamco/lamboot-migrate \
    ~/lamboot-tools-dev/build/standalone-migrate/lamboot-migrate-1.0.0.tar.gz
# Standalone dual-publication per R22
```

Monitor at https://copr.fedorainfracloud.org/coprs/lamco/. Each build takes ~5 min per chroot; `lamboot-tools` matrix is ~8 chroots = ~45 min total.

Address build failures before announcing. User-visible install:

```console
# (to be included in the announcement)
$ sudo dnf copr enable lamco/lamboot-tools
$ sudo dnf install lamboot-tools
```

---

## 14. Announcement (GATE: founder approval)

See `docs/ANNOUNCEMENTS/v0.2.0.md` for the blog post draft.

Channels (founder decides which):

- Blog post at lamboot.dev (via lamco-admin website-deployment pipeline)
- Release notes on GitHub (auto-included from `gh release create`)
- Social media (founder-written)
- Email to downstream (if applicable)
- Update `~/lamco-admin/shared/strategy/` strategy docs

---

## 15. Post-release (immediately after announcement)

```console
$ cd ~/lamboot-tools-dev
$ publish/bump-version.sh --post-release
# Bumps to 0.2.1-dev (or 0.3.0-dev at founder direction)

$ git commit -am "chore: bump to 0.2.1-dev post-release"
$ git push
```

Archive:

```console
$ cp docs/CROSS-REPO-STATUS.md docs/archive/cross-repo-status-v0.2.0.md
# Update CROSS-REPO-STATUS.md to reflect post-release state
```

Monitor for 72 hours:
- `gh issue list` on the public repo
- User reports via issue tracker
- Copr build logs (any dependency changes breaking rebuilds)

---

## 16. Rollback procedure

If a critical bug surfaces within 72 hours:

1. `copr-cli delete-build <build-id>` — stops new dnf installs
2. `gh release edit v0.2.0 --prerelease` — marks as pre-release on GitHub
3. Post advisory issue
4. Fix in dev + ship v0.2.1 following this runbook from §2

Do NOT delete the tag or release entirely — users need traceability.

---

## 17. If the release is blocked

Common blockers + responses:

| Blocker | Response |
|---|---|
| lamboot-dev v0.8.4 not shipped | Defer v0.2.0 per PACKAGING.md §8 OR ship without PVE companion |
| Fleet-test not passing | Fix or explicitly waive in CHANGELOG "Known issues" section |
| CI red on main | Fix before release; never release with red CI |
| Copr build fails on a chroot | Remove that chroot from the Copr config, note in CHANGELOG |
| GPG key unavailable | Defer — unsigned tarballs are not released |
| Governance approval not given | Wait |

**In every case, respect the governance gates.** No unilateral release.

---

## 18. See also

- `docs/PACKAGING.md` — spec-level packaging reference
- `docs/CROSS-REPO-STATUS.md` — lamboot-dev coordination tracker
- `docs/SPEC-LAMBOOT-TOOLKIT-V1.md` §7 — distribution strategy
- `publish/` — every script invoked in this runbook

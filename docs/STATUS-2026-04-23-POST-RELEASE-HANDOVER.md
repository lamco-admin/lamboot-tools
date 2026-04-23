# Post-release handover — lamboot-tools v0.2.0 → lamco-admin

**Date:** 2026-04-23
**Release:** lamboot-tools v0.2.0 (including lamboot-migrate 1.0.0 standalone)
**Coordinated with:** lamboot-dev v0.8.4 (shipped 2026-04-23T04:39Z)
**Handover target:** `~/lamco-admin/pipelines/lamboot-tools/`

## 1. What shipped

**GitHub release:** <https://github.com/lamco-admin/lamboot-tools/releases/tag/v0.2.0>

| Artifact | Size | SHA256 |
|---|---|---|
| `lamboot-tools-0.2.0.tar.gz` | 297KB | `0d876863a13c5cd4aabd0e557727f4c49dad517d0eb78b85707df0e40d701e6b` |
| `lamboot-tools-0.2.0.tar.gz.asc` | 833B | detached signature |
| `lamboot-migrate-1.0.0.tar.gz` | 30KB | `600db8bf9f43019d25e9626dbc70ea717a0cbfd73e4d80b3bc442354d97558b2` |
| `lamboot-migrate-1.0.0.tar.gz.asc` | 833B | detached signature |

**Signing key:** `405CB1E36258DA1DA406A852A236DDB84E0EC96E` — Greg Lamberson (Debian packaging) <greg@lamco.io>

**Both signatures verified good** at §6 gate; see `RELEASE.md §6` for the commands.

## 2. Repos and tag state

| Repo | Visibility | main HEAD | tag v0.2.0 |
|---|---|---|---|
| `lamco-admin/lamboot-tools-dev` | private | `0da76d3` (post-tag main advance: R22 docs fix) | `c073097` |
| `lamco-admin/lamboot-tools` | public | `db76d27` (post-tag main advance: R22 docs fix) | `6a1663d` |
| `lamco-admin/lamboot-migrate` | — | **does not exist, will not exist** | — |

R22 dual-packaging confirmed: one source tree (`lamco-admin/lamboot-tools`),
two Copr projects, no separate `lamboot-migrate` GitHub repo. Stale references
corrected in `packaging/copr/lamboot-migrate.yml` + `docs/RELEASE.md §12`
at commit `0da76d3` (dev) / `db76d27` (public).

## 3. What's done (RELEASE.md §1 through §12)

- ✅ §0.1 lamboot-dev v0.8.4 coordination — Path A (coordinated release)
- ✅ §1 Preflight: `verify-claims` 84/0/1, `release-rehearsal` 28/0/0, `bats` 214/0/4, CI green on `c073097` + subsequent mains
- ✅ §2 Version bump 0.2.0-dev → 0.2.0 (core) / 1.0.0-dev → 1.0.0 (migrate)
- ✅ §3 Regenerate docs — 11 man pages + 11 website tool pages
- ✅ §4 Build tarballs — core + standalone-migrate, both reproducibly
- ✅ §4.1 Mirror lamboot-dev v0.8.4 artifacts (lamboot-inspect + lamboot_inspect/ + lamboot-inspect.1 + lamboot-pve-monitor + lamboot-pve-ovmf-vars)
- ✅ §5 Local RPM validation — mock on fedora-44-x86_64 via VM 104 (`fedora-gnome`); 4 binary RPMs + 2 src RPMs, rpmlint 0 errors 0 warnings with the new `packaging/rpm/lamboot-tools.rpmlintrc`
- ✅ §6 GPG signing — both tarballs signed with lamco-admin key, `gpg --verify` clean
- ✅ §7 Founder review gate — explicit "ship it" authorization granted
- ✅ §8 Push dev repo + v0.2.0 tag to `lamco-admin/lamboot-tools-dev`
- ✅ §9 Mirror to public repo (`lamco-admin/lamboot-tools`) + push main + tag
- ✅ §10 GitHub release created with all 4 signed assets
- ✅ §11 (removed — PVE companion ships as a subpackage, not a separate release)
- ✅ §12 Standalone lamboot-migrate tarball + sig attached to the core GitHub release (no separate repo per R22)

## 4. What's outstanding — lamco-admin pipeline scope

These are explicitly **not** in the scope of the `lamboot-tools-dev` dev
repo. They are handed off to `~/lamco-admin/pipelines/lamboot-tools/`.

### §13 Fedora Copr publishing

**Status:** not started. **Blocked on:** Copr account credentials.

**What's ready:**
- `packaging/copr/lamboot-tools.yml` — 8-chroot matrix (Fedora stable + Rawhide + EPEL + CentOS Stream), source_url points at the public repo, webhook URL pre-wired for tag-event auto-rebuild
- `packaging/copr/lamboot-migrate.yml` — 9-chroot matrix (adds rhel-9-x86_64), source_url pointed at the unified `lamco-admin/lamboot-tools` with explicit `spec: packaging/rpm/lamboot-migrate-standalone.spec` so Copr picks the standalone form from the same source
- `packaging/rpm/lamboot-tools.rpmlintrc` — filter set tuned to 0 errors / 0 warnings across all 6 RPMs (domain-specific spelling, sourced-library-not-executable, noarch-only-in-usr-lib — all documented with rationale)
- Mock validation passed at §5 — SRPM + binary builds succeeded, `%check` block (verify-claims + bats) ran to completion against pristine Fedora 44 chroot

**What lamco-admin needs to do:**
1. **Decide ownername** — `lamco` (group) or `glamberson` (personal). YAML configs use `lamco`.
2. **FAS + Copr login** at <https://copr.fedorainfracloud.org/>
3. **Create two projects** — `lamco/lamboot-tools` and `lamco/lamboot-migrate` — with the chroots listed in the YAML
4. **Choose trigger mechanism:**
   - **A. API token + `copr-cli build`** — fastest, requires writing `~/.config/copr` with the token
   - **B. GitHub webhook** — one-time per-project setup in Copr web UI, targets `lamco-admin/lamboot-tools` tag events; auto-rebuilds on every future `gh release`
5. **Trigger v0.2.0 build** either via `copr-cli build lamco/lamboot-tools <srpm>` (we have the SRPM from §5 mock) or via the webhook's one-time UI "build from SCM" form pointing at tag `v0.2.0`
6. **After success:** add the `dnf copr enable lamco/lamboot-tools` one-liner to the blog announcement (§14)

### §14 Release announcement

**Status:** draft exists, not published.

**What's ready:**
- `docs/ANNOUNCEMENTS/v0.2.0.md` — blog post draft, GitHub release body draft, README badge snippet, social copy, downstream email copy
- Date placeholder `2026-XX-XX` needs to be replaced with `2026-04-23`

**Channels (per RELEASE.md §14):**
1. Blog post at `lamboot.dev/blog/lamboot-tools-0-2-0.md` (via lamco-admin website-deployment pipeline)
2. GitHub release notes — already auto-populated by `--notes-file CHANGELOG.md` in §10
3. README badge — update README.md badge on both repos to show "v0.2.0 released"
4. Social media — founder-written
5. Downstream email — if applicable

### §15 Post-release monitoring (72-hour window)

Per RELEASE.md §15:
- `gh issue list --repo lamco-admin/lamboot-tools` — watch for user reports
- Copr build logs — watch for dependency-drift rebuild failures
- Fleet-test baseline — harness-ready but needs lamco-admin's self-hosted Proxmox runner registration before nightly Tier 1 can run

### §16 Rollback procedure (if needed)

Documented in RELEASE.md §16. Summary: `copr-cli delete-build` to stop dnf installs, `gh release edit v0.2.0 --prerelease` to flag on GitHub, fix in dev + ship v0.2.1 following §2-§10. **Do not delete the tag or release** — users need traceability.

## 5. Outstanding distribution channels (long-tail)

Per RELEASE.md §3-§7, each tracked as separate lamco-admin pipeline items:

| Channel | Status | Notes |
|---|---|---|
| Copr (`lamco/lamboot-tools`)            | 🟡 pending founder | See §13 above |
| Copr (`lamco/lamboot-migrate`)          | 🟡 pending founder | Standalone form; same source tree |
| RPM Fusion (main)                        | 🟡 pending founder | Per RELEASE.md §4 follow-up; package review + Koji |
| Debian RFS (standalone migrate)          | 🟡 pending founder | Per RELEASE.md §5 |
| AUR                                      | 🟡 pending founder | Per RELEASE.md §6 |
| OBS (openSUSE)                           | 🟡 pending founder | Per docs/PACKAGING.md |
| Flathub                                  | ⛔ deferred         | PR #7810 AI-Slop-labeled; per CLAUDE.md governance, no AI activity on it |

## 6. Known post-release items (v0.2.1 scope)

These were identified during §5/§9 mock validation but are not shipping
blockers — they affect internal tooling (mirror script, CI config
documentation) and can roll into a v0.2.1 point release:

- `publish/export-to-public.sh` — initial-empty-public-repo case: script assumes `git fetch origin main` succeeds. Manually handled this session for the first-ever populate. Add an `if empty-repo then skip fetch/pull` branch for resilience on repo recreation.
- `.github/workflows/ci.yml` — stale comment at line 271 still references `verify-structure.sh` rename history. Cosmetic; not blocking.
- `docs/RELEASE.md §1` — preflight commands list `scripts/verify-claims.sh` but §0 bullet list still says `verify-structure.sh` in one place. Already mostly fixed in `b44e07c`, one stray ref remains. Cosmetic.
- Integration-test fixture hosting at `fixtures.lamboot.dev` — SHAs committed, download-fixtures.sh has local/SSH/HTTPS paths. HTTPS endpoint creation is a one-time web-infra item.

## 7. Pointers

- **Runbook:** `docs/RELEASE.md`
- **Packaging playbook:** `docs/PACKAGING.md`
- **Fleet-test plan:** `docs/FLEET-TEST-PLAN.md`
- **Master spec:** `docs/SPEC-LAMBOOT-TOOLKIT-V1.md`
- **Cross-repo tracker:** `docs/CROSS-REPO-STATUS.md`
- **Mirror checksums:** `MIRROR-CHECKSUMS.txt`, `pve/MIRROR-CHECKSUMS.txt`
- **Audit record (origin of v0.2):** `docs/AUDIT-2026-04-22.md` (§9a post-Option-2, §9b disclaimer pass — superseded, §9c full-implementation pass)
- **Prior session handover:** `docs/STATUS-2026-04-22-SESSION-HANDOVER.md`

## 8. Contact/handoff

Any post-release issues filed on <https://github.com/lamco-admin/lamboot-tools/issues>
should be triaged per `CLAUDE.md` public-action governance: issues stay
open until the next release; AI agents do not close, comment on, or
modify them without explicit founder direction.

— end of handover —

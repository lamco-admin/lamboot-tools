# Cross-Repo Coordination Status

**Purpose:** Rolling tracker of coordination items between `lamboot-tools-dev` and `lamboot-dev` per `SPEC-LAMBOOT-TOOLKIT-V1.md` §14.5. (PVE tooling lives in `lamboot-tools-dev/pve/` subtree per founder decision 2026-04-22; there is no separate companion repo.)

**Review cadence:** Monthly. Update this file at every quarterly release-planning meeting + whenever a coordination item changes state.

**Last reviewed:** 2026-04-23 — lamboot-dev **v0.8.4 SHIPPED** publicly
at 2026-04-23T04:39Z
(<https://github.com/lamco-admin/lamboot/releases/tag/v0.8.4>).

**Mirror counterpart:** `~/lamboot-dev/docs/CROSS-REPO-STATUS.md` — keep
these two files in sync. Owner perspective is flipped between them.

---

## 1. Active coordination items (v0.2.0 release cycle)

### 1.1 Must have — blocks coordinated v0.2.0 release

| Item | Responsible repo | Status | Notes |
|---|---|---|---|
| Hookscript rewrite to fw_cfg file-reference pattern | lamboot-dev | ✅ SHIPPED in `v0.8.4` (lamboot-dev `2892446`) — integration test PASS | Proxmox integration test on pve.a.lamco.io VM 120 passed all 8 verifications. Rewritten hookscript is schema-compatible writer for `/var/lib/lamboot/<VMID>.json`. `lamboot-pve-setup doctor-hookscript` confirmed detection works. Test report in lamboot-dev `docs/analysis/V0.8.4-PROXMOX-INTEGRATION-TEST-2026-04-22.md`. |
| `/etc/lamboot/fleet.toml` schema consumption | lamboot-dev (hookscript, monitor.py) | ✅ SHIPPED in `v0.8.4` (lamboot-dev `2892446` + `ada5cb6`) | Verified working end-to-end in integration test: fleet.toml `[roles]."120"` override correctly produced `role=test-integration-subject` in the per-VM JSON. |
| `lamboot-install --toolkit-prompt` opt-in | lamboot-dev | ✅ Landed in lamboot-dev `c4a9b4e` | `--install-toolkit` / `--no-install-toolkit` flags + interactive `[y/N]` prompt on TTY. Distro-aware install guidance (Fedora/RHEL Copr; Debian/Ubuntu/Arch source tarball). Skipped on `--dry-run`, `--update`, `--quiet`, partial failure. |
| README / USER-GUIDE cross-reference to toolkit | lamboot-dev | ✅ Landed in lamboot-dev `b812fea` + `51ce546` | README has "Diagnostic and repair utilities" section linking `github.com/lamco-admin/lamboot-tools`. `docs/LAMBOOT-TOOLS-OVERVIEW.md` rewritten for 11 tools across three RPM subpackages. |

### 1.2 Should have — important but not blocking

| Item | Responsible repo | Status | Notes |
|---|---|---|---|
| Cross-reference `KEY-GENERATION.md` → `lamboot-signing-keys` | lamboot-dev | ✅ Landed in lamboot-dev `51ce546` | §10 "Operator tooling" section with subcommand list. |
| Cross-reference `SECURE-BOOT-AND-SIGNING-STRATEGY.md` → tool | lamboot-dev | ✅ Landed in lamboot-dev `51ce546` | Operator-tooling section maps `sign-binary`/`rotate`/`verify` subcommands to spec procedures. |
| Cross-reference `OVMF-VARS-PROXMOX.md` → `lamboot-pve-ovmf-vars` | lamboot-dev | ✅ Landed in lamboot-dev `51ce546` | §12 notes mirror relationship; `tools/build-ovmf-vars.sh` remains canonical source. |

### 1.3 Release coordination

| Item | Status | Notes |
|---|---|---|
| lamboot-tools v0.2.0 GitHub release | ✅ **SHIPPED 2026-04-23** | https://github.com/lamco-admin/lamboot-tools/releases/tag/v0.2.0 — four signed assets (lamboot-tools tarball + sig, lamboot-migrate tarball + sig), key `405CB1E36258DA1DA406A852A236DDB84E0EC96E`. Runbook sections §1 through §12 complete. |
| Dev repo push                       | ✅ **SHIPPED**           | `lamco-admin/lamboot-tools-dev` main @ `0da76d3`, tag `v0.2.0` @ `c073097`. |
| Public repo population + tag        | ✅ **SHIPPED**           | `lamco-admin/lamboot-tools` main @ `db76d27`, tag `v0.2.0` @ `6a1663d`. Populated from empty-placeholder by modified export-to-public.sh (fix committed post-tag: `f3a3459`). |
| Combined release announcement (bootloader v0.8.4 + toolkit v0.2.0 including PVE subpackage) | 🟡 **OWNED BY lamco-admin** | Draft at `docs/ANNOUNCEMENTS/v0.2.0.md` with `2026-XX-XX` date placeholder. Blog/social/email distribution is RELEASE.md §14 scope — lamco-admin pipelines. |
| Cross-linked release notes          | 🟡 **OWNED BY lamco-admin** | CHANGELOG already references the other repo; formal press-release-style cross-linking is lamco-admin scope. |
| Fedora Copr publishing               | 🟡 **OWNED BY lamco-admin** | RELEASE.md §13. Two Copr projects per R22: `lamco/lamboot-tools` (core + lamboot-migrate subpackage + lamboot-toolkit-pve subpackage from a single build) and `lamco/lamboot-migrate` (standalone, same source tree, `lamboot-migrate-standalone.spec`). Configs in `packaging/copr/*.yml` are current as of this release; corrected R22 stale reference in `0da76d3`. Needs founder Copr account + API token or web-UI webhook configuration — no credentials in this session. |
| RPM Fusion submission (main)         | 🟡 **OWNED BY lamco-admin** | Per RELEASE.md §4 follow-up. Package review bug + Koji builds. |
| Debian RFS (standalone migrate)      | 🟡 **OWNED BY lamco-admin** | Per RELEASE.md §5. |
| AUR update                           | 🟡 **OWNED BY lamco-admin** | Per RELEASE.md §6. |
| Flathub update                       | 🟡 **OWNED BY lamco-admin** | Deferred — PR #7810 AI-Slop-labeled per CLAUDE.md governance. |

**Handover to lamco-admin:** The dev-repo-scoped release work (§1–§12 of
`docs/RELEASE.md`) is complete. Remaining §13 (Copr) and §14 (announcement)
are tracked at `~/lamco-admin/pipelines/lamboot-tools/WORKFLOW.md`.
A post-release handover document is at
`docs/STATUS-2026-04-23-POST-RELEASE-HANDOVER.md`.

---

## 2. Canonical source map (§14.2 of spec)

Files mirrored at release-build time. **Canonical source is authoritative — never edit mirrors directly.**

| File | Canonical location | Mirrored to | Mirror script |
|---|---|---|---|
| `lamboot-inspect` (Python exec) | `~/lamboot-dev/tools/lamboot-inspect` | `lamboot-tools-dev/tools/lamboot-inspect` | `publish/mirror-from-lamboot-dev.sh` |
| `lamboot_inspect/` (Python pkg dir) | `~/lamboot-dev/tools/lamboot_inspect/` | `lamboot-tools-dev/tools/lamboot_inspect/` | same |
| `lamboot-inspect.1` (man page) | `~/lamboot-dev/tools/lamboot-inspect.1` | `lamboot-tools-dev/man/lamboot-inspect.1` | same |
| `lamboot-monitor.py` | `~/lamboot-dev/tools/lamboot-monitor.py` | `lamboot-tools-dev/pve/tools/lamboot-pve-monitor` (renamed) | `publish/mirror-pve-from-lamboot-dev.sh` |
| `build-ovmf-vars.sh` | `~/lamboot-dev/tools/build-ovmf-vars.sh` | `lamboot-tools-dev/pve/tools/lamboot-pve-ovmf-vars` (renamed) | same |
| `lamboot-hookscript.pl` | `~/lamboot-dev/tools/lamboot-hookscript.pl` | **NOT mirrored** — documented dependency; user installs via lamboot-dev | N/A |
| `KEY-GENERATION.md` | `~/lamboot-dev/docs/KEY-GENERATION.md` | Referenced by toolkit website; not mirrored | N/A |

### 2.1 Mirror verification

Each mirror script writes a `MIRROR-CHECKSUMS.txt` file recording sha256 of the canonical source at mirror time. CI verifies no drift between mirrored copy and canonical source (toolkit CI clones lamboot-dev at the matching release tag, re-mirrors, and diffs).

---

## 3. Schema stability commitments

| Schema | Owner | Consumers | Stability contract |
|---|---|---|---|
| `/etc/lamboot/fleet.toml` v1 | lamboot-tools-dev (§16 Appendix C) | `lamboot-pve-setup`, `lamboot-pve-fleet`, lamboot-dev's `lamboot-hookscript.pl`, lamboot-dev's `lamboot-monitor.py` | Additive changes OK within v1; breaking changes require `schema_version` bump + coordinated release |
| Per-VM JSON v1 (`/var/lib/lamboot/<VMID>.json`) | lamboot-tools-dev (`lamboot-pve-setup`) | LamBoot inside VM (reads via fw_cfg), lamboot-dev's hookscript (writes) | Same additive policy |
| Toolkit JSON output schema v1 | lamboot-tools-dev (SPEC §5) | External consumers (Grafana, Prometheus, custom tooling) | SEMVER-STABLE within major version; breaking changes bump toolkit major |
| Trust-log events v2 | lamboot-dev (SDS-4 §6) | `lamboot-diagnose` reads trust-log; `lamboot-inspect` deep-reads | Additive tokens OK; renames are major-version event |

---

## 4. Release coordination log

### 4.1 v0.2.0 target (coordinated across two repos)

Target window: 2026-Q3

**lamboot-dev v0.8.4:** ✅ **SHIPPED 2026-04-23T04:39Z** — <https://github.com/lamco-admin/lamboot/releases/tag/v0.8.4>

- [x] Hookscript rewrite (fw_cfg file-reference pattern) — `2892446`
- [x] `lamboot-install --toolkit-prompt` — `c4a9b4e`
- [x] README cross-reference — `b812fea`
- [x] Monitor + hookscript read `/etc/lamboot/fleet.toml` — `ada5cb6` + `2892446`
- [x] Should-have doc back-links (KEY-GENERATION.md, SECURE-BOOT-AND-SIGNING-STRATEGY.md, OVMF-VARS-PROXMOX.md) — `51ce546`
- [x] `docs/LAMBOOT-TOOLS-OVERVIEW.md` rewrite for 11 tools / 3 RPMs — `51ce546`
- [x] CHANGELOG entry — `c6f53ef` + `4267c1d`
- [x] Proxmox integration test on pve.a.lamco.io VM 120 — PASS (8/8)
- [x] Rebuild + re-sign + re-tarball `v0.8.4` — tarball SHA256 `4671691f...`
- [x] Tag `v0.8.4` signed with release key + push
- [x] Public export to `lamco-admin/lamboot` + `gh release create`

**Self-hosted infrastructure** (for tools-dev fleet-test):
- [x] GitHub Actions runner on pve.a.lamco.io registered + online (labels `self-hosted,pve-host,linux,x64`)
- [ ] Tier 1 VM matrix (26 VMs at 2100-2705, 2800-2801) NOT provisioned — blocks fleet-test.yml workflow. Separate infrastructure project.

**lamboot-tools-dev v0.2.0** (produces three RPM subpackages from one source):
- [x] 9 core tools (migrate, diagnose, esp, backup, repair, doctor, uki-build, signing-keys, toolkit)
- [x] PVE subtree under `pve/`: `lamboot-pve-setup`, `lamboot-pve-fleet`
- [ ] `lamboot-inspect` mirror run (via `mirror-from-lamboot-dev.sh`)
- [ ] `lamboot-pve-monitor` + `lamboot-pve-ovmf-vars` mirror run (via `mirror-pve-from-lamboot-dev.sh`)
- [x] `publish/*.sh` scripts (5 scripts; no companion extract)
- [x] Man pages (Session M)
- [x] Website docs (Session N)
- [x] CHANGELOG entry
- [x] Unified RPM spec (`lamboot-tools.spec`) producing `lamboot-tools`, `lamboot-migrate`, and `lamboot-toolkit-pve` subpackages

---

## 5. Process notes

- **Any item added to this file must have an owner repo and a status.**
- **Status values:** ⏳ Not started / 🔄 In progress / ✅ Done / ⚠️ Blocked / 🗑️ Cancelled.
- **Review cadence:** monthly at minimum; ad-hoc whenever a coordination item changes state.
- **Escalation path:** items blocked > 30 days surface to founder for direction.
- **Archival:** completed release cycles archived to `docs/archive/cross-repo-status-<release>.md` after release ships.

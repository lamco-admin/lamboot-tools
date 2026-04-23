# lamboot-tools Roadmap

**Authoritative spec:** [`docs/SPEC-LAMBOOT-TOOLKIT-V1.md`](docs/SPEC-LAMBOOT-TOOLKIT-V1.md)

This roadmap is a living tracker. It reflects the product scope, tool maturity, release cadence, and cross-repo coordination decided in the toolkit spec.

---

## Current status

**Session A** (research + spec) — **done 2026-04-22.**
Produced `docs/SPEC-LAMBOOT-TOOLKIT-V1.md`.

**Session B** (shared infrastructure) — **done.**
Shared library, help registry, dispatcher, Makefile with inlining, CI workflows, bats test harness, claims-verification script, pre-commit hooks.

**Session C** (SDS-7 gap-close on `lamboot-migrate`) — **done.**
10-phase pipeline, verify subcommand (11 checks), rollback subcommand, Proxmox method selector, top-5+2 failure guardrails, 5 distro recipes, 29 bats tests. Tool at v1.0.0-dev.

**Session D** (`lamboot-diagnose` hardening) — **done.**
Rewrite with shared lib + unified JSON; 11 categories, ~30 checks; `--offline DISK` support; `--category`/`--skip`/`--id` filters; remediation URLs for every warning+ finding; 17 bats tests. Tool at v0.2.0-dev.

**Session E** (`lamboot-esp` hardening) — **done.**
Rewrite with shared lib + unified JSON; 3 subcommands (check/inventory/clean); `--offline DISK` support; `--apply`/`--keep-backups` for safe mutation; stale-file detection with bootloader-critical safety; 20 bats tests. Tool at v0.2.0-dev.

**Session F** (`lamboot-backup` hardening) — **done.**
Rewrite with shared lib + unified JSON; 4 subcommands (save/restore/show/list); snapshot JSON schema v1 with nvram/entries/lamboot_nvram sections; interactive restore with safety confirmation; jq-free JSON parsing; 23 bats tests. Tool at v0.2.0-dev.

**Session G** (`lamboot-repair` hardening) — **done.**
Rewrite with shared lib + six-phase flow (diagnose/plan/show/confirm/execute/verify); risk tiers (safe/moderate/destructive) with `--risk-limit`; 8 repair actions; offline ESP-level repairs (NVRAM v0.3+); `--fix-fstab` scoped mode; 12 bats tests. Tool at v0.2.0-dev.

**Session H** (`lamboot-doctor` — new, guided wrapper) — **done.**
New tool orchestrating diagnose → policy-matrix-driven plan → repair/esp-clean with single-sudo-escalation via `--doctor-resume <run_id>`. Critical findings always require typed-yes regardless of `--auto`. Never auto-invokes `lamboot-migrate`. 16 bats tests. Tool at v0.2.0-dev (beta).

**Session I** (`lamboot-uki-build` — new, host-side UKI builder) — **done.**
New tool wrapping ukify/objcopy + sbsign/sbverify. 4 subcommands (build/inspect/sign/verify) with automatic backend selection. Pure-bash PE header parser (via `od`) for inspect with no external dependencies. 18 bats tests. Tool at v0.2.0-dev (beta).

**Session J** (`lamboot-signing-keys` — new, dual-mode Secure Boot key lifecycle) — **done.**
New tool covering Scope 3 (both release-eng + user-facing) per founder decision Q1. 10 subcommands: generate / inspect / status / mok-enroll / mok-list / mok-delete / ovmf-vars / generate-hierarchy / sign-binary / rotate. **RSA-2048 enforcement on db/leaf keys** per Debian bug #1013320; RSA-4096 allowed for PK/KEK. Refusal exits EXIT_UNSAFE with remediation. Rotation cross-signs the new cert with the parent key when provided (db←KEK, KEK←PK, PK←self). `sign-binary` auto-injects `.sbat` PE sections per shim's SBAT spec. 23 bats tests. Tool at v0.2.0-dev (experimental).

**Session K** (PVE companion: `lamboot-pve-setup` + `lamboot-pve-fleet`) — **done.**
Two new tools under the `pve/` subtree of this repo (ship as the `lamboot-toolkit-pve` RPM subpackage per founder decision 2026-04-22 — one source repo, one public repo, one Copr project producing three subpackage RPMs). Per-VM setup tool (beta) with idempotent fw_cfg args: append + hookscript attachment + per-VM JSON at `/var/lib/lamboot/<VMID>.json` + hookscript version check against 0.8.4. Fleet orchestrator (experimental) with inventory / setup / status / report subcommands and `--all` / `--vmid` / `--tag` / `--exclude` filters invoking per-VM tool serially. 25 bats tests total. Tools share toolkit library.

**Session L** (PVE companion mirrors + cross-repo coordination) — **done.**
Four publish scripts in `publish/`: mirror-from-lamboot-dev.sh (lamboot-inspect + Python package + man page → core toolkit); mirror-pve-from-lamboot-dev.sh (lamboot-monitor.py + build-ovmf-vars.sh → `pve/tools/` in-tree with rename + checksum manifest); build-standalone-migrate.sh (per R22 dual-publication — standalone lamboot-migrate tarball with Makefile + README + tests); export-to-public.sh (with LAMBOOT_EXPORT_CONFIRMED safety gate per governance). Makefile gains install-pve, mirror-lamboot-dev, mirror-pve targets. CI workflow picks up pve/tools/ + publish/*.sh for shellcheck and runs bats on pve/tests/. `docs/CROSS-REPO-STATUS.md` created as rolling coordination tracker per spec §14.5. **Originally authored per pre-2026-04-22 spec interpretation with a planned `lamboot-toolkit-pve-dev` sibling repo; corrected 2026-04-22 to the single-repo / three-subpackage model per founder Option 2 decision — no `extract-pve-companion.sh`.**

**Session M** (Docs: man pages from registry) — **done.**
`scripts/registry-to-man` (392-line generator) extracts subcommand registry from each tool's `_register_subcommands()` function and emits groff-format `man(1)` pages. 11 per-tool `.1` pages auto-generated from registries + hand-authored `lamboot-tools.7` (suite overview, 220 lines) + `lamboot-tools-schema.5` (JSON schema v1 reference, 255 lines). Makefile `make man` target regenerates all pages with per-file dependency tracking. **All 13 pages render clean** under `man --warnings=w`. Total man/ tree: ~4,200 lines.

**Session N** (Docs: website content) — **done.**
`website/` subtree under MkDocs + Material. `scripts/registry-to-markdown` generator produces 11 per-tool walkthrough pages from the same help registries driving man pages + inline help. Hand-authored: landing page (160 lines), 4 guides (quick-start, BIOS→UEFI migration, Proxmox fleet setup, diagnose workflow — ~480 lines), 3 reference pages (CLI contracts, JSON schema, exit codes — ~580 lines), findings index (90 lines) + 2 sample finding deep-dives (esp.free_space, esp.fallback_path). `make website` + `make serve-website` + `make build-website` targets. Total website/: ~3,600 lines across 24 Markdown files. Three-surface documentation complete (inline help + man pages + website, all driven from the same registry).

**Session O** (Fleet-test matrix + fixtures) — **done.**
Infrastructure + harness for Tier 1–3 testing. `docs/FLEET-TEST-PLAN.md` (3-tier matrix, 26-VM Tier 1 layout with specific VMIDs, pass criteria, escalation). `tests/fixtures/` catalog with 11 fixture specs + `download-fixtures.sh` + `fixtures.sha256` + `regen/` subtree (README + regen-all.sh + hybrid-mbr.sh as working example). `tests/integration/` bats tests (migrate-refusals, diagnose-fixtures, esp-fixtures) that skip gracefully without fixtures. `scripts/fleet-test.sh` (Tier 1 driver: snapshot-rollback, qm start, SSH install, scan, JSON capture, baseline diff). `scripts/publish-nightly.sh` (nightly report builder + uploader). Makefile targets: `test-integration`, `test-pve`, `test-all`, `fixtures`, `fleet-test`. CI workflow runs integration tests (skip-gracefully); nightly workflow triggers fleet-test.sh + publish-nightly.sh on self-hosted Proxmox runner. ~1,220 lines.

**Session P** (Packaging) — **done.**
Three RPM specs in `packaging/rpm/`: `lamboot-tools.spec` (core + `lamboot-migrate` subpackage with BuildRequires + chroot matrix + %check hooks), `lamboot-toolkit-pve.spec` (companion with `Requires: lamboot-tools >= 0.2.0` + %post install-hints), `lamboot-migrate-standalone.spec` (per R22 dual-publication — keeps `lamboot-migrate` name, Provides: uefi-migrate + linux-bios-uefi-migrate for search discovery). Three Copr configs in `packaging/copr/` with per-project chroot matrices + webhook setup. `publish/build-tarball.sh` core-release tarball builder. `CHANGELOG.md` with full v0.2.0 entry. `docs/PACKAGING.md` release-engineer runbook covering build + lint + mock + Copr + GitHub release + governance gates + rollback procedures. ~975 lines.

**Session Q** (Release rehearsal + publish preparation) — **done 2026-04-22.**
Version-bump automation: `publish/bump-version.sh` with `--release` / `--post-release` / `--dry-run` modes, 12-file bump list (lib + 9 core tools + 2 PVE tools), dry-run preview verified. Release runbook: `docs/RELEASE.md` with 19 sections covering preflight, version bump, artifact build, local RPM validation, GPG signing, founder review, dev-repo push, public mirror via governance-gated `export-to-public.sh`, GitHub release, companion extraction + release, standalone lamboot-migrate release, Copr publishing, announcement channels, post-release patch bump, rollback procedure, and blocker responses. Rehearsal script: `scripts/release-rehearsal.sh` with 10 readiness checks covering verify-claims, CHANGELOG, bash syntax, RPM field completeness, Copr configs, help registries, man pages, website pages, publish-script executability, governance-gate active verification. **Rehearsal result: 28 checks passed, 0 warnings, 0 failed.** Announcement drafts: `docs/ANNOUNCEMENTS/v0.2.0.md` with blog post body, GitHub release notes, README badge snippet, Twitter/LinkedIn social copy, downstream email template, pre-publication checklist, and out-of-scope list. **v0.2.0 ready-to-ship pending founder approval at each GATE in docs/RELEASE.md.**

**All A–Q sessions complete.** Release execution is founder-gated (not a session).

---

## v0.2.0 — publishable launch

**Target:** 2026-Q3
**Coordinated release with:** LamBoot v0.8.4 (hookscript rewrite + install script prompt)

### Core toolkit (package `lamboot-tools`)

| Tool | Maturity at v0.2 | Source | Session |
|---|---|---|---|
| `lamboot-diagnose` | stable | existing, harden | Session D |
| `lamboot-esp` | stable | existing, harden | Session E |
| `lamboot-backup` | stable | existing, harden | Session F |
| `lamboot-repair` | stable | existing, harden | Session G |
| `lamboot-migrate` | stable (tool v1.0.0) | SDS-7 gap-close | Session C |
| `lamboot-doctor` | beta | new | Session H |
| `lamboot-toolkit` | stable | done in Session B | ✓ |
| `lamboot-inspect` | stable (mirror) | from lamboot-dev | Session L |
| `lamboot-uki-build` | beta | new | Session I |
| `lamboot-signing-keys` | experimental | new | Session J |

### PVE companion (package `lamboot-toolkit-pve`)

| Tool | Maturity at v0.2 | Source |
|---|---|---|
| `lamboot-pve-setup` | beta | new |
| `lamboot-pve-fleet` | experimental | new |
| `lamboot-pve-monitor` | stable | mirror from lamboot-dev |
| `lamboot-pve-ovmf-vars` | stable | mirror from lamboot-dev |

### Infrastructure gates (§9 of spec)

- [x] Shared library `/usr/lib/lamboot-tools/lamboot-toolkit-lib.sh`
- [x] Help registry library `/usr/lib/lamboot-tools/lamboot-toolkit-help.sh`
- [x] `lamboot-toolkit` dispatcher
- [x] Makefile with sourced + inlined build paths
- [x] GitHub Actions CI (shellcheck + bash -n + bats + install smoke + claims)
- [x] bats-core test harness with initial coverage
- [x] `scripts/verify-structure.sh` enforcing §13
- [x] `.githooks/pre-commit` + `.pre-commit-config.yaml`
- [x] `.shellcheckrc` at severity=style
- [x] `.editorconfig`
- [ ] Nightly fleet-test infrastructure active on founder's Proxmox host *(harness ready; runner registration ops-pending)*
- [ ] Fixture disk image catalog built (§9.3) *(catalog + regen scripts ready; image build + upload to fixtures.lamboot.dev ops-pending)*
- [x] All core tools shellcheck-clean *(verified by CI + release-rehearsal §3)*
- [ ] Tier 1 test matrix passing end-to-end *(baseline capture ops-pending; requires Proxmox host)*
- [ ] Fedora Copr publishing pipeline validated *(configs written; first actual Copr build ops-pending)*
- [x] Man pages generated and installed for every tool *(13 pages, `make install` wires them)*
- [x] `lamboot.dev/tools/` website section ready *(content complete; DNS + deploy pipeline ops-pending)*
- [x] `publish/export-to-public.sh` operational *(governance-gate tested in release-rehearsal §10)*
- [x] `publish/build-standalone-migrate.sh` produces standalone `lamboot-migrate` tarball *(verified; output under build/standalone-migrate/ at release time)*

### Per-tool SDS writing sessions

Each tool gets its own spec in `docs/SPEC-LAMBOOT-<TOOL>.md`:

- [x] `SPEC-LAMBOOT-DIAGNOSE.md` (Session D prerequisite)
- [x] `SPEC-LAMBOOT-ESP.md` (Session E prerequisite)
- [x] `SPEC-LAMBOOT-BACKUP.md` (Session F prerequisite)
- [x] `SPEC-LAMBOOT-REPAIR.md` (Session G prerequisite)
- [x] `SPEC-LAMBOOT-DOCTOR.md` (Session H prerequisite)
- [x] `SPEC-LAMBOOT-UKI-BUILD.md` (Session I prerequisite)
- [x] `SPEC-LAMBOOT-SIGNING-KEYS.md` (Session J prerequisite)
- [x] `SPEC-LAMBOOT-PVE-SETUP.md` (Session K prerequisite) *(in `pve/docs/`)*
- [x] `SPEC-LAMBOOT-PVE-FLEET.md` (Session K prerequisite) *(in `pve/docs/`)*

### Ops-pending between "feature-complete" (now) and "shipped" (founder-gated)

**Every advertised feature is implemented as of AUDIT-2026-04-22 §9c full-
implementation remediation pass.** What remains is infrastructure, not code,
and requires founder-side operations or cross-repo work:

- **Execute `docs/RELEASE.md` §1–§15** at a founder-approved release window
  (every §6/§7/§8/§9/§10/§14 GATE is founder-only). §11 is a no-op under
  Option 2 (PVE companion is a subpackage, not a separate repo).

- **Fixture disk images** — ✅ **BUILT** 2026-04-22 on `pve.a.lamco.io`;
  persisted at `/var/lib/lamboot-fixtures/` (3.1 GB across 11 .raw
  images). Real SHAs committed to `tests/fixtures/fixtures.sha256`. The
  `download-fixtures.sh` script supports three fetch methods:
  `FIXTURES_SSH_HOST=root@pve.a.lamco.io` (default internal, works now),
  `FIXTURES_LOCAL_DIR=...` (copy), or `FIXTURES_BASE_URL=...` (HTTPS).
  **Founder decision pending:** whether to also upload the 3.1 GB to a
  public host (fixtures.lamboot.dev) or ship the toolkit with SSH-only
  fetch for internal testing + a documented "regen-all.sh on your own
  host" path for external contributors.

- **Register self-hosted GitHub Actions runner** on founder's Proxmox host
  for the `.github/workflows/fleet-test.yml` workflow. DARK status
  disclosed in the workflow header comment. Until registered, nightly
  Tier-1 runs wait for the runner.

- **Capture baseline Tier-1 results** via `scripts/fleet-test.sh` once
  runner is registered, and publish via `scripts/publish-nightly.sh`.

- **Coordinate with lamboot-dev v0.8.4** — hookscript rewrite to fw_cfg
  file-reference pattern is required before the `lamboot-toolkit-pve`
  subpackage reaches its full capability. Runtime guard already
  implemented in `lamboot-pve-setup doctor-hookscript` (Option B in
  RELEASE.md §0.1). Three ship paths:
    - Path A: complete lamboot-dev v0.8.4 first, then ship toolkit.
      Separate engineering task in the lamboot-dev repo (~200-400 lines
      of Perl hookscript + Proxmox testing).
    - Path B (recommended): ship toolkit v0.2.0 with runtime guard;
      `lamboot-pve-setup` refuses against old hookscripts with
      remediation pointing at v0.8.4.
    - Path C: drop PVE subpackage from v0.2.0. Not recommended.

- **Founder operations with public-write side effects** (per
  `~/lamco-admin/pipelines/lamboot-tools/WORKFLOW.md` §2):
    - `git push` to `lamco-admin/lamboot-tools-dev` (private)
    - `git push` to `lamco-admin/lamboot-tools` (public) via
      `LAMBOOT_EXPORT_CONFIRMED=1 publish/export-to-public.sh`
    - `gh release create v0.2.0 --repo lamco-admin/lamboot-tools`
    - `copr-cli build lamco/lamboot-tools <tarball>`
    - `copr-cli build lamco/lamboot-migrate <tarball>`
    - Announcement publication per `docs/ANNOUNCEMENTS/v0.2.0.md` and
      WORKFLOW.md §3.
- **Local RPM validation** (mock + rpmlint — `docs/RELEASE.md §5`) requires a
  Fedora host. Not done in dev environment.

### Cross-repo coordination with lamboot-dev (v0.8.4)

Tracked in both repos' ROADMAPs. Cross-references:

- **Hookscript rewrite** to fw_cfg file-reference pattern — blocks `lamboot-pve-setup`. lamboot-dev v0.8.4 deliverable.
- **`lamboot-install --toolkit-prompt`** adding opt-in for toolkit install — lamboot-dev v0.8.4.
- **`/etc/lamboot/fleet.toml` schema** — authored in this spec §16 Appendix C, consumed by `lamboot-hookscript.pl` in lamboot-dev.
- **`lamboot-inspect` mirror** — canonical in `lamboot-dev/tools/`; release-build copies into toolkit tarball. Never edit in toolkit directly.
- **`lamboot-monitor.py` + `build-ovmf-vars.sh`** — canonical in `lamboot-dev/tools/`; release-build copies into PVE companion with rename.

---

## v0.3.0 — maturing + broadening

**Target:** 2026-Q4 or 2027-Q1

- `lamboot-doctor` → stable (expanded policy matrix after field feedback)
- `lamboot-uki-build` → stable
- `lamboot-pve-setup` → stable
- `lamboot-migrate --offline DISK` shipped
- Ubuntu/Debian PPA published
- `lamboot-pve-fleet` → beta
- `lamboot-signing-keys` → beta
- Tier 1 test matrix expanded with additional distro coverage (Rocky, openSUSE Leap)

---

## v0.5.0 — full coverage

**Target:** 2027-Q2

- `lamboot-signing-keys` → stable (Scope 1 + Scope 2)
- `lamboot-pve-fleet` → stable
- Homebrew tap for Linux-from-macOS admins
- Additional hypervisor companions considered (`lamboot-toolkit-nutanix`, `lamboot-toolkit-vmware`) — evaluation only, no commitment

---

## v1.0.0 — mature, enterprise-ready

**Target:** 2027-Q4

- Every core tool stable
- Every PVE companion tool stable
- Debian upstream submission for standalone `lamboot-migrate`
- Proxmox Phase 3 (native `lamboot` config option) submission or companion upgrade
- `lamboot-migrate` spin-off milestone: tool v2.0 with distinct product page at `lamboot.dev/migrate/`, dedicated distro package, independent release cadence

---

## Out of roadmap (permanent)

- GUI in any form. Web/dashboard UIs consuming the JSON API are separate products.
- Non-Linux support (Windows, macOS, BSD).
- `lamboot-doctor` default-behavior becoming aggressive auto-fix. Default stays conservative.
- Snap / Flatpak packaging. Sandbox incompatibility with host device access.

---

## Rolling cross-repo status

See `docs/CROSS-REPO-STATUS.md` (to be created) for monthly review of coordination items per spec §14.5.

---

## Reporting + measurement

- **Release cadence:** 2–4 months for minor versions; patch releases on demand.
- **Test coverage:** Tier 1 matrix blocks release; Tier 2 gates per-tool v1.0; Tier 3 reported in release notes.
- **Claim honesty:** every claim in `docs/SPEC-LAMBOOT-TOOLKIT-V1.md` §13.2 has a code-path backing verified by `scripts/verify-structure.sh` in CI.

---

## Amendment procedure

Changes to this roadmap that aren't purely status updates (new tools, deferred tools, version target changes) require updates to `docs/SPEC-LAMBOOT-TOOLKIT-V1.md` first. This file tracks execution; the spec tracks scope.

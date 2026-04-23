# Changelog

All notable changes to `lamboot-tools` are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: hybrid model per `SPEC-LAMBOOT-TOOLKIT-V1.md` §8 — unified
`lamboot-tools X.Y.Z` version bundles per-tool semvers.

---

## [Unreleased]

---

## [0.2.0] — UNRELEASED (rehearsal-verified 2026-04-22; release date pending founder approval)

**First public release.** Nine core tools + two PVE companion tools, all
sharing one help-registry pattern, one JSON schema v1, and one Makefile.
Every advertised feature is fully implemented — no flags are accepted
that don't actually do something.

### Release infrastructure status at v0.2.0

Fully implemented features. The following are infrastructure items that
are separate from tool feature-completeness and require founder-side
operations to reach their green state:

- **Tier 1 fleet-test baseline** — the 26-VM matrix in
  `docs/FLEET-TEST-PLAN.md` is harness-ready (`scripts/fleet-test.sh`,
  `scripts/publish-nightly.sh`, `.github/workflows/fleet-test.yml`)
  but requires registration of founder's self-hosted Proxmox runner
  before nightly baselines can be captured. Pre-release validation was
  manual.
- **Integration-test fixture images** — all 11 fixtures have working
  regen scripts in `tests/fixtures/regen/*.sh`, each producing a
  synthetic image in minutes. Hosting at `fixtures.lamboot.dev` is a
  separate step; `download-fixtures.sh` resolves checksums from the
  repo's `fixtures.sha256`. Integration tests skip cleanly when
  fixtures are absent (and will pass once the SHAs are populated).
- **`lamboot-toolkit-pve` subpackage requires `lamboot-dev >= 0.8.4`** —
  the `lamboot-pve-setup doctor-hookscript` subcommand refuses cleanly
  if an older hookscript is detected. Two release paths documented in
  `docs/RELEASE.md §0.1` — coordinated (ship after v0.8.4) or runtime-
  guarded (ship now; `lamboot-pve-setup` self-disables until lamboot-dev
  is upgraded). The code-side guard is fully functional either way.

### Added

- **`lamboot-diagnose` v0.2.0** (stable) — flagship UEFI boot-chain scanner. 11 check categories, ~30 individual checks. Unified JSON output with dotted-path IDs, severity/status orthogonality, and remediation URLs for every warning+ finding. `--offline DISK`, `--category`, `--skip`, `--id` filters. Detects LamBoot / GRUB / systemd-boot / rEFInd / Limine / Windows Boot Manager on the ESP with PE32+ validation.
- **`lamboot-esp` v0.2.0** (stable) — EFI System Partition health, inventory, and cleanup. Three subcommands (check/inventory/clean). `clean --apply` with typed-yes confirmation and bootloader-critical safety (never removes active bootloader binaries, UKIs, BLS entries, or fallback path files).
- **`lamboot-backup` v0.2.0** (stable) — UEFI boot configuration save/restore/show/list. Snapshot JSON schema v1 with nvram + entries + lamboot_nvram sections. jq-free internal JSON parsing. Offline mode via `--vars-file OVMF_VARS.fd` reads/writes NVRAM through `virt-fw-vars`; Boot#### entries are decoded from the EFI_LOAD_OPTION LE UTF-16 layout and output is indistinguishable between online and offline paths (`source` field in the snapshot JSON discriminates). Offline restore snapshots the vars file before mutating, so rollback is always possible via the `*.pre-restore.<timestamp>` backup.
- **`lamboot-repair` v0.2.0** (stable) — six-phase guided repair (diagnose → plan → show → confirm → execute → verify). Risk tiers (safe / moderate / destructive) with `--risk-limit`. 9 repair actions: ESP mount, ESP filesystem fsck, fallback loader install, boot entry creation, BootOrder setup, fstab ESP entry creation, LamBoot crash-count reset, LamBoot state reset, mark-success service enablement.
- **`lamboot-migrate` v1.0.0** (stable) — **the first automated Linux BIOS→UEFI migration tool**. 10-phase pipeline. Preflight: an already-UEFI short-circuit check + 7 guardrail findings (missing tools, LVM/dm-crypt root, hybrid MBR, Windows dual-boot, fstab device paths, insufficient free space) that refuse unsafe migrations with remediation. Distro-aware bootloader recipes (apt / dnf / pacman / zypper / generic). Proxmox method selector (A pre-convert, B live-chroot, C add-disk). `to-uefi`, `to-lamboot`, `verify` (11 checks), `rollback`, `status` subcommands (5 total). `to-lamboot --remove-grub` implements post-verify GRUB removal: runs the 11-check verify, uninstalls distro-matched GRUB packages (apt/dnf/pacman/zypper/generic), removes GRUB/shim directories from the ESP (`/EFI/GRUB`, `/EFI/ubuntu`, `/EFI/debian`, `/EFI/fedora`, etc.), deletes GRUB/shim NVRAM `Boot####` entries via `efibootmgr -B`, and records a rollback manifest at `$backup_dir/grub-packages.txt`. Requires typed-yes confirmation unless `--force`.
- **`lamboot-doctor` v0.2.0** (beta) — guided diagnose → policy-matrix-driven plan → repair/esp-clean orchestrator with single-sudo-escalation. Critical findings always require typed-yes confirmation regardless of `--auto`. Never auto-invokes `lamboot-migrate` (BIOS→UEFI always user-initiated). `--offline DISK` propagates through every sub-tool invocation (diagnose, repair, esp); ESP clean actions are suppressed in offline mode because they require live bootloader-active detection the offline snapshot can't provide.
- **`lamboot-uki-build` v0.2.0** (beta) — host-side Unified Kernel Image builder wrapping `ukify` (preferred) and `objcopy` (fallback). Pure-bash PE header parser for `inspect` subcommand. `sign` + `verify` wrappers around `sbsign` / `sbverify`.
- **`lamboot-signing-keys` v0.2.0** (experimental) — dual-mode Secure Boot key lifecycle tool (release-engineering + user-facing). **Enforces RSA-2048 for MOK-enrolled keys** per Debian bug #1013320; RSA-4096 allowed for PK/KEK (firmware-level). 10 subcommands: `generate`, `inspect`, `status`, `mok-enroll`, `mok-list`, `mok-delete`, `ovmf-vars`, `generate-hierarchy`, `sign-binary`, `rotate`. Key rotation cross-signs the new cert with the parent key (db←KEK, KEK←PK, PK←self) when parent credentials are provided; produces a timestamped rotation directory with both old and new keypairs plus a JSON manifest. `sign-binary` auto-injects an `.sbat` PE section (resolution order: `--sbat-file > --sbat > /etc/lamboot/sbat.csv > built-in default`) before calling `sbsign`; preserves existing SBAT sections; `--no-sbat` available for debugging.
- **`lamboot-toolkit` v0.2.0** (stable) — suite dispatcher with `status`, `help`, `run`, `version`, `verify` subcommands. Tab-completion-discoverable via `lamboot-<TAB>`.
- **`lamboot-inspect`** (stable, mirrored from lamboot-dev) — LamBoot-specific deep introspection. Python tool mirrored at release-build time; canonical source stays in lamboot-dev.
- **`lamboot-pve-setup` v0.2.0** (beta, PVE companion) — per-VM LamBoot integration setup. Idempotent fw_cfg args append (never overwrites other users), hookscript attachment, per-VM JSON at `/var/lib/lamboot/<VMID>.json`. Hookscript version check against 0.8.4. `doctor-hookscript` subcommand to verify the host's hookscript is present + current.
- **`lamboot-pve-fleet` v0.2.0** (experimental, PVE companion) — fleet-wide orchestration. `inventory`, `setup`, `status`, `report` subcommands. Filters: `--all`, `--vmid`, `--tag`, `--exclude`. Reads `/etc/lamboot/fleet.toml` for defaults.
- **`lamboot-pve-monitor`** (stable, mirrored from lamboot-dev) — host-side NVRAM health reader.
- **`lamboot-pve-ovmf-vars`** (stable, mirrored from lamboot-dev) — OVMF variables builder with cert pre-enrollment.

### Infrastructure

- **Shared library** at `/usr/lib/lamboot-tools/lamboot-toolkit-lib.sh` + `lamboot-toolkit-help.sh`. Sourced by every tool. Functions: ESP/disk detection, logging, privilege checks, dry-run wrapper, backup discipline, unified JSON emission, offline-mode setup/teardown, common flag parsing.
- **Inlined-build path**: tarball users get single-file self-contained binaries (library concatenated into each tool).
- **Help registry pattern** (based on rdpdo's `ALL_COMMANDS` pattern): every subcommand declared once, three documentation surfaces (inline help, man pages, website) auto-generated from the registry.
- **`scripts/registry-to-man`** — generates `man(1)` pages from help registries.
- **`scripts/registry-to-markdown`** — generates per-tool website walkthroughs.
- **11 auto-generated man pages** + `lamboot-tools(7)` suite overview + `lamboot-tools-schema(5)` JSON schema reference.
- **MkDocs website** at `lamboot.dev/tools/` with landing page, 4 guides (quick-start, BIOS→UEFI migration, Proxmox fleet setup, diagnose workflow), 3 reference pages (CLI contracts, JSON schema, exit codes), per-tool walkthroughs, findings index.
- **Fleet-test plan** (`docs/FLEET-TEST-PLAN.md`) with 3-tier model and 26-VM Tier 1 matrix.
- **Fixture disk image catalog** (`tests/fixtures/`) with download + regen scripts.
- **Integration tests** (`tests/integration/`) using fixtures; skip gracefully when fixtures absent.
- **GitHub Actions CI** running shellcheck + bash -n + bats (core + PVE + integration) + install smoke on Ubuntu 24.04 + Fedora 44 + openSUSE Tumbleweed containers.
- **Nightly fleet-test workflow** on self-hosted Proxmox runner.
- **Fedora Copr packaging**: two Copr projects — `lamco/lamboot-tools` (single source spec producing three subpackages: `lamboot-tools` core + `lamboot-migrate` + `lamboot-toolkit-pve`) and `lamco/lamboot-migrate` (standalone per R22 dual-publication).
- **Publish pipeline**: `publish/{build-tarball,build-standalone-migrate,mirror-from-lamboot-dev,mirror-pve-from-lamboot-dev,export-to-public}.sh`. Public export gated by `LAMBOOT_EXPORT_CONFIRMED=1` per governance.

### Cross-repo coordination (v0.2.0 release requirements)

Coordinated with `lamboot-dev v0.8.4` per `docs/CROSS-REPO-STATUS.md`:
- Hookscript rewrite to fw_cfg file-reference pattern (blocks `lamboot-pve-setup`)
- `lamboot-install --toolkit-prompt` opt-in flag
- README / USER-GUIDE cross-references
- `/etc/lamboot/fleet.toml` schema v1 authored in toolkit, consumed by lamboot-dev

### Schema stability

- **JSON output schema v1** frozen for the v0.x.y series. Additive changes to fields, categories, finding IDs, action verbs, severity/status tokens are permitted without bump. Breaking changes require `schema_version` bump + toolkit major bump.
- **`/etc/lamboot/fleet.toml` schema v1** frozen for the v0.x.y series.
- **Per-VM JSON schema v1** (`/var/lib/lamboot/<VMID>.json`) frozen for the v0.x.y series.
- **Finding ID stability**: dotted-path IDs are SEMVER-STABLE within the major version. Rename = major bump with advance-notice deprecation.

### Deferred to future versions

See `ROADMAP.md` for full detail.

- **v0.3 targets**: `lamboot-doctor` → stable (policy matrix expanded); `lamboot-uki-build` → stable; `lamboot-pve-setup` → stable; `lamboot-migrate --offline DISK`; Ubuntu/Debian PPA published; `lamboot-pve-fleet` → beta.
- **v0.5 targets**: `lamboot-signing-keys` → stable (Scope 1 + Scope 2 fully covered); `lamboot-pve-fleet` → stable; Homebrew tap; parallel PVE fleet operations.
- **v1.0 targets**: every core tool stable; Debian upstream submission for standalone `lamboot-migrate`; Proxmox Phase 3 (native config option) submission; `lamboot-migrate` formal spin-off with own product page + distro package + independent release cadence (keeping `lamboot-migrate` name per R22 — no off-brand rename).

---

## Previous unreleased work

v0.1.0 — internal dev release of the five original tools (lamboot-diagnose, lamboot-esp, lamboot-backup, lamboot-repair, lamboot-migrate). Not tagged publicly.

---

[Unreleased]: https://github.com/lamco-admin/lamboot-tools/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/lamco-admin/lamboot-tools/releases/tag/v0.2.0

# Changelog

All notable changes to `lamboot-tools` are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: hybrid model per `SPEC-LAMBOOT-TOOLKIT-V1.md` §8 — unified
`lamboot-tools X.Y.Z` version bundles per-tool semvers.

---

## [Unreleased]

## [0.9.1] — 2026-06-09 — first public release of the 0.9 line

Umbrella-only release: no tool-behavior changes since 0.9.0. The 0.9.0 work
(below) was an internal milestone; 0.9.1 is its first public publication, with
the suite documentation and version metadata brought current. Per-tool versions
are unchanged from 0.9.0.

### Changed

- **Documentation brought current for publication.** The README, the website,
  and the `lamboot-tools(7)` suite overview now list `lamboot-nvram` and
  `lamboot-pve-migrate` (both introduced in 0.9.0). The website install guide
  leads with the GPG-signed release tarball and no longer advertises channels
  that are not yet live.
- **Suite umbrella version `0.9.0 → 0.9.1`**; packaging metadata
  (`packaging/release.toml`) aligned to the published tag.
- **Documentation home consolidated.** Per-finding `doc_url` values and the JSON
  output's `$schema` id now reference the public repository; a defunct
  placeholder domain was removed across the tools, packaging, and docs.
  The detailed guides are maintained as standalone documents under `docs/`, and
  the unused site generator was retired. README links point at the canonical
  lamco.ai pages.

## [0.9.0] — 2026-06-08 — boot audit & hygiene: inspect verdicts, NVRAM cleanup, PVE migration lifecycle

Minor release. The toolkit gains a boot-audit-and-hygiene capability set: every
troubleshooting or migration action a human takes now has a corresponding tool,
each one dry-run-by-default with backup, restore, and logging. Toolkit
`0.8.2 → 0.9.0`.

Per-tool semvers in this bundle:
`lamboot-inspect 0.8.3 → 0.9.0`, `lamboot-nvram 0.1.0` (new),
`lamboot-pve-migrate 0.1.0` (new), `lamboot-pve-fleet 0.7.2 → 0.8.0`,
`lamboot-doctor 0.7.5 → 0.8.0`, `lamboot-migrate 0.7.5 → 0.7.6`.

### Added

- **`lamboot-nvram` (new tool) — UEFI boot-entry inventory and cleanup.**
  `inventory` lists every `Boot####` and classifies it (live / dangling /
  duplicate / dead-OS / orphaned BootOrder), resolving each entry against the
  partitions actually present. `clean` removes dead entries and `restore` puts
  them back from a backup. Operates on live `efivarfs` (inventory is
  unprivileged) or, with `--efidisk FILE`, an offline OVMF_VARS image via
  `virt-fw-vars`. Never touches `BootCurrent`, the running entry, or the first
  `BootOrder` slot. Backs up (`efibootmgr` dump) and logs every mutation to
  `/var/log/lamboot/`.
- **`lamboot-inspect` `diagnose` — boot-verdict rules engine.** Reads the last
  boot's trust log and renders a verdict (pass / warn / fail), flagging
  crash-loops, missing entries, firmware-fallback boots, skipped measurement,
  kernel mismatch, and explicit load/policy failures. Exit `0` (clean/warnings)
  or `2` (problems); `--strict` escalates integrity violations to `4`.
- **`lamboot-inspect` `history` / `diff` / `attest` — audit surfaces.**
  `history` reads the per-boot log archive; `diff` compares two boots and
  reports regressions (e.g. a boot that loaded native last time and didn't
  this time); `attest` surfaces the measured-boot PCRs.
- **`lamboot-inspect.service` — post-boot oneshot.** Runs
  `lamboot-inspect diagnose --severity warn` and writes the verdict to the
  journal (`journalctl -u lamboot-inspect`). Read-only; treats both exit `0`
  and `2` as a successful *run* — it logs the verdict, never blocks boot.
- **`lamboot-doctor` `clean` / `restore` — boot hygiene orchestration.**
  `clean` backs up to a timestamped directory (with a MANIFEST + log), delegates
  NVRAM cleanup to `lamboot-nvram`, owns ESP-file backup, and stays deferential
  to the package manager on `/boot`. `restore` requires a backup before it will
  run. Hygiene surfaces default to ESP + NVRAM (never `/boot`).
- **`lamboot-pve-migrate` (new tool) — PVE BIOS→UEFI migration lifecycle.**
  `snapshot` / `prep-uefi` / `finalize-uefi` / `rollback`, with strict
  power-discipline: the tool never starts, stops, or resets a VM — it refuses
  (exit `4`, before privilege checks) if the VM is running and leaves power to
  the operator.
- **`lamboot-pve-fleet` `verify` / `exec`.** `verify` runs the post-migration
  check suite across the fleet; `exec` runs a `lamboot-*` tool inside a guest
  via `qm guest exec`, restricted to the suite's own tools.
- **`lamboot-migrate` verify check 12 (`fallback_identity`).** Confirms
  `\EFI\BOOT\BOOTX64.EFI` is byte-identical to the primary loader (status
  `skip` when not applicable).
- **`lamboot_toolkit` Python infra package.** The toolkit-owned contracts
  (exit codes, JSON envelope schema v1, subcommand help-registry) expressed
  once for every Python tool — the Python analogue of
  `lib/lamboot-toolkit-lib.sh`. JSON output is byte-compatible with the bash
  `emit_json`; `summary.status` derives from the exit code identically.
- **Python tools render man/website from the help registry.**
  `registry-to-man` and `registry-to-markdown` now detect a Python shebang and
  extract the registry via `--dump-registry` (the same `0x1F` record envelope
  the bash tools source), so the three doc surfaces (inline / man / website)
  stay single-sourced across languages.

### Changed

- Toolkit version `0.8.2 → 0.9.0`; every tool's `--version` reports
  `lamboot-tools 0.9.0`.

## [0.8.2] — 2026-06-07 — migrate: Method B (live-ISO BIOS→UEFI) end-to-end

Patch release. `lamboot-migrate` 0.7.4 → 0.7.5; toolkit 0.8.1 → 0.8.2. Three
fixes that, together, make `to-uefi --method=B` complete a real BIOS→UEFI→LamBoot
conversion. Validated end-to-end on Ubuntu 25.10 (ext4 root, no separate /boot):
GPT conversion, 550 MB ESP, both kernels' BLS entries on the ESP with the
`/boot/` prefix, `\EFI\BOOT\BOOTX64.EFI` fallback byte-identical to LamBoot.

### Fixed

- **`to-uefi --method=B` no longer aborts with "system is already UEFI".**
  `guard_boot_mode_is_bios` treated any present `/sys/firmware/efi` as "nothing
  to convert" and `die_noop`'d. But Method B runs from a UEFI live ISO converting
  a BIOS *target* disk — the live environment's own UEFI firmware is required,
  not a no-op. The guard now returns early for Method B; the in-place methods
  (A / auto on the running system) keep the already-UEFI short-circuit.
- **`to-uefi` Phase 9 no longer fails with "cannot determine ESP partition
  number for efibootmgr".** Phase 5 computed the ESP partition number but
  persisted only the device path (`LAMBOOT_PHASE5_ESP_DEV`); Phase 9 re-derived
  the number from `sgdisk -p`, which returns nothing under `--dry-run` (no GPT
  was actually written) and is redundant on a real run. Phase 5 now also records
  `LAMBOOT_PHASE5_ESP_PARTNUM` and Phase 9 reuses it, falling back to the live
  GPT only if that global is unset (mid-pipeline resume with a pre-existing ESP).
- **`to-uefi --method=B --dry-run` no longer prints misleading warnings.** With
  the target left unmounted under dry-run, the bootloader-install detection and
  fallback-path population could not inspect the target and emitted alarming
  "lamboot-install not found; GRUB installed as fallback" / "could not find a
  source loader" warnings — neither of which reflects a real run, which mounts
  the target first. Both now emit honest `DRY-RUN: would …` lines instead.

## [0.8.1] — 2026-06-07 — migrate: LVM root no longer misread as dm-crypt

Patch release. `lamboot-migrate` 0.7.3 → 0.7.4; toolkit 0.8.0 → 0.8.1.

### Fixed

- **`lamboot-migrate to-uefi`: an LVM root is no longer misreported as dm-crypt.**
  `guard_root_not_on_lvm_or_crypt` trusted `cryptsetup status`'s *exit code*,
  which is 0 for any active device-mapper node — an LVM LV included (it prints
  `type: n/a`). So every LVM root tripped the crypt branch and died with
  `root on dm-crypt — automated conversion refused`, shadowing the accurate
  `root on LVM` finding directly below it. Observed live on RHEL 9.7
  (XFS-root-on-LVM, the RHEL default). The check now confirms a real LUKS/PLAIN
  mapping, so an LVM root correctly reports `root on LVM`. (The refusal itself is
  unchanged — LVM-root BIOS→UEFI is still out of scope for v1.0 auto-migration.)

---

## [0.8.0] — 2026-06-03

Re-architecture release. The toolkit returns to a shell-only codebase; the two
Rust components it grew during the 0.7.x line now live in their own
repositories and ship as prebuilt binaries. No tool behavior changed: this is a
structural, packaging, and ownership release.

### Changed

- **Architecture: lamboot-tools is now shell-only and federated.** The Rust
  crates developed across the 0.7.x line were extracted to their own
  repositories:
  - `grub-cfg` became **lamboot-reader** (GRUB config reader and resolver), and
  - `capcheck` became **lamboot-capcheck** (firmware and platform capability
    auditor).

  The toolkit no longer compiles Rust. It bundles their prebuilt, statically
  linked (musl) binaries instead (see Added), so the installed product keeps
  the same capability. `lamboot-doctor` and `lamboot-migrate --capcheck-gate`
  continue to consume `lamboot-capcheck` from PATH and degrade gracefully when
  it is absent.
- **Copyright holder is now Lamco Development LLC** across LICENSE-MIT,
  LICENSE-APACHE, the generated man pages, the website footer, the SBAT vendor
  field, and the X.509 signing-certificate subject. (IP transfer completed
  2026-06-02.)
- **Umbrella version reconciled to 0.8.0.** The last public release was 0.3.0;
  internal development reached 0.7.12 (the capcheck work that has now been
  extracted). 0.8.0 is the first public release of the federated, shell-only
  product.

### Added

- **Bundled component binaries**, shipped in the new arch-specific
  `lamboot-tools-firmware` RPM subpackage and inside the release tarball:
  `lamboot-capcheck` (12-domain firmware auditor) and `lamboot-reader`
  (standalone GRUB-config CLI), built static-musl for **x86_64 and aarch64**,
  vendored under `vendor/bin/<arch>/` with per-component `THIRD_PARTY_NOTICES`
  and a `vendor/BINARY-PROVENANCE.txt` audit record.
- **`publish/vendor-binaries.sh`**: a manifest-driven pipeline that builds and
  vendors the sibling binaries at a pinned tag. The aarch64 binaries are
  cross-linked with the toolchain's bundled `rust-lld`, so no C cross-toolchain
  is required.
- **Makefile `vendor` and `install-firmware` targets**, and `vendor/` inclusion
  in `publish/build-tarball.sh`.
- **Hand-authored man pages** `lamboot-capcheck(1)` and `lamboot-reader(1)`.

### Removed

- The in-repo Rust workspace and its build targets (the crates moved to their
  own repositories). `make clean` now also removes the stale `target/` cache.

## [0.7.12] — 2026-05-30

### Fixed

- **lamboot-diagnose (0.7.3): three false positives on LVM / mounted-ESP hosts.**
  - `partition_table.type` raised a false `error` ("partition table type
    unknown") on LVM roots: `resolve_root_disk` did not walk LVM/dm to the
    physical disk, so it fed the logical volume (which has no partition table)
    to `blkid`. It now follows the `lsblk -s` slave tree to the underlying disk.
  - `fstab.root_uuid_form` warned "dangerous device path" for `/dev/mapper/`
    (LVM / dm-crypt) roots, but device-mapper names are deterministic and
    stable (Debian's LVM default). `/dev/mapper/` and `/dev/dm-` are now treated
    as stable identifiers; only raw `/dev/sdXN`-style paths warn.
  - `esp.integrity` warned on every booted host because a mounted read-write
    FAT always carries the volume-dirty flag (set on mount, cleared on clean
    unmount) — not corruption. The strict `fsck.fat` verdict now runs only
    offline; online it reports info.

## [0.7.11]

Release pipeline + spec catch-up. No behavior changes.

### Added — release pipeline

- **`publish/build-capcheck-binary.sh`** — new release script that
  produces the canonical static-PIE binary for distribution alongside
  the source tarball. Default target `x86_64-unknown-linux-musl`
  (overridable via `TARGET=…`).

  Why musl: glibc-linked binaries built on Debian forky (glibc 2.39)
  cannot run on RHEL 9.x (glibc 2.34) or openSUSE Leap 15.x
  (glibc 2.31). Static-musl runs on every distro tested across the
  v0.7.6-v0.7.10 audit fleet (Debian forky, Arch, openSUSE Tumbleweed,
  Fedora 43, RHEL 9.7, Ubuntu 25.10, Manjaro, Kali Rolling) plus
  bare-metal pve1 — without runtime deps.

- **`make capcheck-musl`** / **`make release-binaries`** — new Makefile
  targets that invoke the script. Produces `build/capcheck/`-prefixed
  binary + tarball + .sha256 sidecars suitable for direct `gh release
  upload`.

### Added — SDS-8 catch-up

`SPEC-LAMBOOT-CAPCHECK-V1.md` gains a new §28 "Schema and behavior
evolution (v0.7.x)" that documents the additive schema changes
introduced through v0.7.6–v0.7.11:

- §28.1 RemediationAction enum + Risk classifier
- §28.2 MatchSpec runtime gates (`cmdline_contains`,
  `shim_binary_version_pattern`, `require_runtime_signal`,
  `requires_check_status`)
- §28.3 normalized quirk severity vocabulary (critical/major/minor/low/info)
- §28.4 distro detection (`os_release_id`, `is_distro_family`)
- §28.5 BLS interpolation handling (openSUSE absolute paths +
  Fedora grub `$variable` tokens)
- §28.6 parallel domain execution (`audit_parallel`)
- §28.7 canonical release artifact rationale
- §28.8 EFI variable GUID correction (PK/KEK vs db/dbx)
- §28.9 doctor↔capcheck bridge contract
- §28.10 lamboot-migrate `--capcheck-gate` flag

Schema version remains 1 throughout — all additions are backward-
compatible field additions. Future schema_version 2 bump requires
updating §11 and §28 in lockstep.

---

## [0.7.10]

BLS parser robustness on Fedora-style entries with grub variable
interpolation, surfaced by VM 104 (fedora-gnome).

### Fixed

- **BLS `initrd` parser** previously treated a line like
  `initrd /path/initramfs.img $tuned_initrd` as ONE path containing the
  literal `$tuned_initrd` token (Fedora's grub config templating leaves
  these in BLS entries for runtime expansion). Now splits on whitespace
  and discards tokens starting with `$` (grub variable refs). BLS spec
  also permits multiple initrd paths whitespace-separated; that's now
  handled correctly too.
- **BLS `linux` parser** similarly drops trailing `$var` tokens on the
  linux line for the (rare) case where Fedora's templating injects one.

### Validated on fedora-gnome (Fedora 43 Workstation, BIOS, i440FX, VM 104)

- Distro detection: `os_release_id=fedora`, no `id_like`.
- `bls-entries-parseable` went from WARN (3/4 entries reported broken)
  to PASS.
- `kernel-cmdline-drift` correctly WARNs (5/5 sources drifted from
  /proc/cmdline) and emits the `grub2-mkconfig -o /boot/grub2/grub.cfg`
  action with `risk: safe` — the first real-hardware case where a
  doctor `--auto` run could actually apply the fix without prompting.
- 6/12 domains pass (limited by BIOS mode skipping UEFI domains).
- Remaining issues only the cosmetic FACS + i440fx quirk.

---

## [0.7.9]

SUSE-family coverage and a BLS path-resolution fix, both surfaced by
VM 102 (tumbleweed, openSUSE Tumbleweed).

### Added — SUSE-family action coverage

Four wired actions now know how to dispatch zypper / openSUSE commands:

- `secure-boot.sbat-in-efi-binaries` → `zypper install -y --force shim`
- `cpu-platform.microcode-age` → `zypper install -y ucode-amd|ucode-intel`
- `storage-boot.esp-free-space` → `zypper purge-kernels`
- `boot-mode.kernel-cmdline-drift` → `update-bootloader --refresh`

Matched via `ctx.is_distro_family(&["opensuse", "suse", "opensuse-tumbleweed", "opensuse-leap", "sles"])` — covers Tumbleweed (`ID=opensuse-tumbleweed`, `ID_LIKE="opensuse suse"`), Leap, MicroOS, and SLES.

### Fixed

- **BLS path resolution false positive** — strict BLS spec resolves
  `linux` / `initrd` paths relative to the ESP root, but openSUSE
  (and some Fedora layouts) put the actual kernel/initrd files on
  the boot partition (`/boot/vmlinuz-*`), not on the ESP. Previously
  the probe reported `linux_exists: false` and `status: warn` for
  every valid openSUSE BLS entry. Now the probe tries both ESP-relative
  and filesystem-absolute resolution and only WARNs if neither
  matches. Tumbleweed went from `bls-entries-parseable WARN` (2/2
  entries reported broken) to PASS.

### Validated on tumbleweed (openSUSE Tumbleweed, UEFI, i440FX, VM 102)

- Distro detection: `os_release_id=opensuse-tumbleweed`,
  `id_like=["opensuse","suse"]`.
- 9/12 domains pass (was 8/12 before BLS fix).
- Remaining WARN/FAIL: only the cosmetic FACS checksum + the
  i440fx-PCIe-incompatible quirk (both known-and-benign with
  OpenUrl actions attached).

---

## [0.7.8]

Quirks DB severity vocabulary cleanup, surfaced by archie (Arch Linux,
i440FX, BIOS-booted, VM 101).

### Changed — quirks DB severity normalization

The quirks DB had been using six different severity strings; only four
were explicitly handled by the bridge mapping. Normalized to the
canonical vocabulary documented in `lamboot-capcheck-bridge.sh`:

- `critical` — hardware damage / unrecoverable (e.g. lenovo-ideapad-300)
- `major` — workflow-breaking but recoverable (was: `high` in two quirks)
- `minor` — cosmetic, performance, or convenience
- `low` — even lighter (was: `info` in qemu-q35-shpchp)
- `info` — purely informational

Renames:
- `asus-g10aj-conout-fat-coupling`: `high` → `major`
- `debian-bug-1013320-thinkpad-x280-rsa4096-mok-freeze`: `high` → `major`
- `qemu-q35-shpchp-error-16-benign`: `info` → `low`

### Fixed

- **Bridge severity map**: previously dropped `low`-severity quirks
  silently (mapped to doctor `info`, which doctor's plan stage filters).
  Now maps `low → warning` (alongside `minor → warning`). The
  qemu-i440fx-pcie-incompatible quirk now correctly surfaces as a
  doctor warning on i440FX VMs instead of being invisible.

### Validated on archie (Arch Linux, BIOS-booted, i440FX, VM 101)

- Distro detection: `os_release_id=arch`, `os_release_id_like=null`
  (Arch is a root distro family).
- 11 SKIPs for UEFI-only checks (first real-hardware exercise of the
  BIOS-mode path; previously only fixture coverage).
- Hypervisor classification three-way consistent (DMI=QEMU,
  CPUID-flag=true, product=i440FX → kvm-qemu).
- New quirk match: `qemu-i440fx-pcie-incompatible` (had never matched
  on any previously-audited target since debway/pve1 are Q35).
- `acpi.checksums` FACS-only failure correctly carries the benign-FACS
  OpenUrl from v0.7.7.

---

## [0.7.7]

Two more structured actions wired:

### Added — actions

- **`secure-boot.{pk,kek,db,dbx}-present`** WARN/FAIL → `FirmwareSetup`
  action ("Reboot → enter UEFI Setup → Security/Boot → Secure Boot →
  Restore Factory Keys"). No automation possible; this surfaces the
  no-command-fix case explicitly through the structured channel.
- **`acpi.checksums`** FAIL → `OpenUrl` action. Splits the FACS-only case
  (almost always benign — kernel exposes runtime-mutated copy) from
  any other table failure (real investigation needed via acpidump + iasl).
  Verified on debway: FACS-only failure now carries the "benign" URL.

---

## [0.7.6]

Structured remediation actions: capcheck checks now emit machine-actionable
commands alongside prose remediation, enabling lamboot-doctor to auto-apply
safe distro-aware fixes. Also: lamboot-migrate gets an opt-in capcheck
readiness gate.

### Added — schema (additive to v1)

- **`RemediationAction` enum** on `CheckResult.actions` with five variants:
  - `RunCommand { summary, argv, requires_root, idempotent, risk, distro_id, reboot_required }` — the most common; consumers can spawn the argv
  - `EditFile { summary, path, hint, risk }` — manual edit guidance
  - `OpenUrl { summary, url }` — operator follow-up
  - `EnrollMok { summary, cert_path, risk }` — MOK enrollment workflow
  - `RebootRequired { summary }` — flag a deferred-effect change
  - `FirmwareSetup { summary, menu_path }` — no automation possible
- **`Risk` enum**: Safe (idempotent, reversible), Moderate (modifies state, no data loss), Destructive (irreversible).
- **`RemediationAction::flat_command()`** — render argv as a POSIX-quoted command line for consumers that don't natively parse the structured form (lamboot-doctor's current bash impl).
- **`RemediationAction::safe_root_cmd()`**, **`pkg_install()`**, **`open_url()`**, **`firmware_setup()`** — constructor shortcuts.
- **`SystemSummary.os_release_id`** + **`os_release_id_like`** + **`os_release_codename`** — populated from `/etc/os-release`.
- **`Context::os_release_id()`**, **`os_release_id_like()`**, **`os_release_codename()`**, **`is_distro_family(&[&str])`** — distro-aware probe support.

### Added — wired actions (8 checks now ship structured remediation)

- `secure-boot.sbat-in-efi-binaries WARN` → distro-aware `apt-get install --reinstall -y shim-signed` (Debian/Ubuntu), `dnf reinstall shim-x64` (Fedora/RHEL), or AUR URL (Arch). Risk::Moderate, reboot_required.
- `cpu-platform.microcode-age WARN/FAIL` → `apt-get install intel-microcode|amd64-microcode`, `dnf install microcode_ctl|amd-ucode-firmware`, or `pacman -S intel-ucode|amd-ucode`. Risk::Moderate, reboot_required.
- `storage-boot.esp-free-space WARN/FAIL` → `proxmox-boot-tool clean` (if present), otherwise `apt-get autoremove --purge -y` or `dnf autoremove -y`. Risk::Moderate.
- `boot-mode.kernel-cmdline-drift WARN` → `proxmox-boot-tool refresh` (idempotent, Risk::Safe), `update-grub` (Debian/Ubuntu), or `grub2-mkconfig` (RHEL family). Risk::Safe.

### Added — bridge + doctor

- **`lib/lamboot-capcheck-bridge.sh`** jq filter now extracts the highest-priority structured action's argv into doctor's flat `remediation.command` field and surfaces the highest action `risk` in `remediation.risk`. POSIX-quoted argv joining handles spaces/special chars.
- **lamboot-doctor**:
  - `_remediation_risk_of()` extracts the new risk field.
  - `_map_action_from_command()` recognizes capcheck-emitted commands (`apt-get *`, `dnf *`, `pacman *`, `proxmox-boot-tool *`, `update-grub`, `grub2-mkconfig *`) and passes them through verbatim.
  - `build_plan_from_findings()` honors `--risk-limit` per capcheck risk field: `safe` rejects moderate+destructive, `moderate` rejects destructive only.
  - capcheck-spliced findings now preserve the full bridge-emitted remediation block (command, risk, summary, doc_url) in doctor's `--json` output instead of stripping to `command=""`.

### Added — lamboot-migrate

- **`--capcheck-gate`** flag (also `LAMBOOT_MIGRATE_CAPCHECK=1` env) — opt-in. Runs `lamboot-capcheck --json audit` in Phase 1 preflight. Critical-severity quirks abort migration with finding `migrate.capcheck.critical_quirks`; non-critical findings surface as `migrate.capcheck.warnings` but don't block. Degrades silently if capcheck or jq absent. No hard dependency.

### Validated on debway (Debian forky/sid, Q35 VM)

- Distro detection works: `os_release_id=debian`, `codename=forky`.
- `secure-boot.sbat-in-efi-binaries` (4/15 LamBoot module binaries lack SBAT) now emits a structured `RunCommand` action with argv `["apt-get", "install", "--reinstall", "-y", "shim-signed"]`, risk=moderate, reboot_required=true.
- Bridge translates to flat `remediation.command = "apt-get install --reinstall -y shim-signed"` with `risk: "moderate"`.
- Doctor `--no-repair`: shows the command as `Suggestion: (run manually) apt-get install --reinstall -y shim-signed`, policy = `warning — user action`.
- Doctor `--no-repair --risk-limit safe`: same finding but explicitly downgraded to manual via the new risk gate (verified by `verbose: risk-gated: ... (risk=moderate, limit=safe)`).
- All 7 unit + 20 bats tests still pass.

---

## [0.7.5]

Cross-tool integration release. Three threads:
(a) v0.7.4 known-limitation cleanup,
(b) parallel domain execution,
(c) **lamboot-doctor ↔ capcheck bridge**.

### Added — capcheck

- **`crates/capcheck/src/verify/lvm_thin_root.rs`** — new probe
  `storage-boot.lvm-thin-root` parses `lvs --noheadings --options segtype`
  for the root LV (extracted from `/proc/cmdline` with proper
  device-mapper dash-escaping). Returns Warn when segtype contains
  "thin", Pass otherwise, Skip when not LVM-managed.
- **`MatchSpec::requires_check_status`** + **`CheckStatusGate`** — quirks
  can now gate on a named domain check's status. `lvm-thin-pool-not-
  supported-v1` now gates on `storage-boot.lvm-thin-root` status=warn
  (closes the v0.7.4 known-limitation carryforward).
- **`lib::audit_parallel(ctx, threads)`** — new public API. Domains run
  in `std::thread::scope` workers with a shared work-queue; results
  collected into a Vec preserving deterministic input order. The
  `--threads` flag now picks worker count (clamped to [1, 8], default =
  `available_parallelism().min(8)`). Identical output to the sequential
  path on pve1 (verified bit-for-bit).
- **`quirks --diff-runtime`** — was wired in v0.7.3 but consumed
  Layer-2 only. Now produces a usable JSON diff between capcheck's
  compiled-in quirks DB and the lamboot-core manifest.

### Added — lamboot-doctor

- **`lib/lamboot-capcheck-bridge.sh`** — new soft-included library.
  Detects `lamboot-capcheck` on PATH, runs `--json audit`, and
  translates capcheck check + quirk records into doctor-shaped
  findings via jq:
    - `capcheck.domain.<domain>.<check>` for warn/fail checks
    - `capcheck.quirk.<quirk-id>` for matched quirks
  Severity mapping: capcheck status fail→error, warn→warning;
  capcheck quirk severity critical→critical, major/high→error,
  minor→warning. Degrades silently when capcheck or jq absent (emits
  empty array; doctor proceeds with just its own diagnose findings).
- **`tools/lamboot-doctor`** — splices capcheck findings into both:
    1. the plan-building `findings_blob` so policy matrix can act on them
    2. the `--json` output via `emit_finding` so consumers see them
  alongside doctor's own findings.
- Two new bats tests: capcheck-splice presence + ID structure validation.

### Fixed

- **Bridge bug: capcheck's non-zero exit code on WARN was treated as
  "no findings"** — the bridge now ignores the exit code and trusts the
  JSON if it parses. Capcheck's SDS-8 §4.6 exit code is the *data*, not
  an error signal for consumers.

### Known limitations carrying forward

- The `dm_split()` helper in lvm_thin_root.rs handles
  `vg-with--dashes-lv` correctly but doesn't yet handle the rare case
  of a `--` literal inside the LV name. The device-mapper escape rule
  is "double every dash" — round-trip parsing for non-pathological
  names works; pathological names produce a near-miss but never crash.

### Validated

- All 7 capcheck integration tests pass
- All 20 doctor bats tests pass (18 pre-existing + 2 new
  capcheck-integration tests)
- Re-audit on pve1: `dmi-quirks.match` PASS (zero quirks matched,
  down from 5 false-positives in v0.7.3 → 1 false-positive in v0.7.4
  → 0 in v0.7.5)
- `--threads 8` produces bit-identical output to `--threads 1` on
  pve1 (audit completes in ~64ms vs ~81ms on a 16-core host; the
  sequential path is already fast enough that threading is a marginal
  win, but the infrastructure is there for slow-probe scenarios)
- Doctor with bridge sees `capcheck.domain.dmi-quirks.match` and
  `capcheck.quirk.qemu-q35-shpchp-error-16-benign` on this VM,
  correctly assigns "warning — manual" policy (no auto-action because
  capcheck doesn't yet emit structured remediation commands)

---

## [0.7.4]

Bug-fix pass driven by the pve1 audit (ASRock X870E Taichi Lite, AMI BIOS
4.20, Ryzen 9 7950X bare-metal). Four real issues found during testing,
all fixed.

### Fixed

- **secure-boot.db-present / dbx-present false negative** —
  `crates/capcheck/src/domains/secure_boot.rs` was reading db/dbx with
  the `EFI_GLOBAL_VARIABLE` GUID (8be4df61-…) instead of the
  `EFI_IMAGE_SECURITY_DATABASE` GUID (d719b2cb-…). Per UEFI Spec 2.10
  §32.4, PK/KEK/SecureBoot live in EFI_GLOBAL_VARIABLE_GUID; db/dbx/dbt/dbr
  live in EFI_IMAGE_SECURITY_DATABASE_GUID. The bug caused every audit on
  a normally-provisioned system to report db/dbx absent, which then
  falsely matched the `ami-2024-secure-boot-cleared` quirk. New helper
  `efivar_path(var)` picks the correct GUID per variable.
- **Quirks DB matched indiscriminately when `[match]` was empty** —
  `shim-15-4-7-rsa4096-known-issue`, `proxmox-pve-zfs-on-root-pbt`,
  `lvm-thin-pool-not-supported-v1`, `efidisk0-zfs-1m-size` all matched
  every system because their match blocks had no constraints. The
  matcher now refuses to match any quirk with zero constraints, and
  three new MatchSpec fields gate the runtime probes:
    - `cmdline_contains` — substring match against `/proc/cmdline`
    - `shim_binary_version_pattern` — regex against shim binary version
      strings extracted from ESP `*.efi` files
    - `require_runtime_signal: bool` — when true, demands at least one
      runtime-knob constraint also be set
  All four affected quirks now have real match criteria.
- **`network-boot.devices` listed `bonding_masters`** as a network device.
  `/sys/class/net/` contains synthetic control files alongside real
  interfaces; we now require both `address` and `type` files to exist
  before treating an entry as a device.
- **`acpi.checksums` didn't name the failing table** in the human
  message. The verification JSON always had `tables_bad`; the human
  message now lists the failing tables inline so it surfaces in human
  + JUnit + CSV outputs without drilling into JSON.

### Added — Matcher

- `MatchSpec::cmdline_contains` (TOML field)
- `MatchSpec::shim_binary_version_pattern` (TOML field)
- `MatchSpec::require_runtime_signal` (TOML field)
- `MatchSpec::bios_version_min` / `_max` honored (was declared but inert
  in v0.7.3)
- Helper `collect_shim_versions(ctx)` walks ESP for `shim*.efi` and
  extracts embedded "shim version X.Y" or "Version: shim,X.Y" markers
- Helper `match_bios_version_range()` for lexicographic BIOS version
  comparisons

### Validated

- `cargo test -p lamboot-capcheck` — 7/7 integration tests still pass
- Re-audit on pve1: SB domain now reports PASS across all 6 checks
  including `secure-boot.cert-chain` parsing Microsoft Option ROM UEFI
  CA 2023 from db (7636-byte EFI_SIGNATURE_LIST), and
  `secure-boot.sbat-in-efi-binaries` confirming 8/8 *.efi files have SBAT
- Quirks-matched count on pve1 dropped from 5 (mostly false positives in
  v0.7.3) to 1 (lvm-thin-pool-not-supported-v1, which is a coarse match
  pending v0.7.5 `lvs --segments` parsing in the storage-boot domain)
- `acpi.checksums` now correctly names the failing FACS table on pve1

### Known limitations carrying forward

- `lvm-thin-pool-not-supported-v1` matches any system with
  `root=/dev/mapper/` in cmdline; it doesn't yet inspect whether the
  named LV is actually thin-provisioned. A storage-boot domain probe
  parsing `lvs --segments --options lv_name,segtype` is planned for
  v0.7.5 to gate this precisely.

---

## [0.7.3]

Phase 2 of `lamboot-capcheck` — full SDS-8 implementation; no corners cut.

### Added — Domain depth

- **`shim_mok.rs`** rewritten with full EFI_SIGNATURE_LIST parsing per UEFI
  Spec 2.10 §32.4.1: MokListRT, MokListXRT, MokListTrustedRT, SbatLevelRT
  each get their signature lists enumerated, X.509 certs extracted via
  x509-parser, SHA-256 hashes counted. Cross-checks shim binary version
  against the Debian #1013320 known-bug DB.
- **`tpm2.rs`** — narrow in-house TPM2 client (~370 LOC, no tss-esapi C
  dep). Implements `TPM2_GetCapability(TPM_CAP_TPM_PROPERTIES)` (manufacturer,
  family, revision), `TPM2_GetCapability(TPM_CAP_PCRS)` (banks), and
  `TPM2_PCR_Read(SHA-256, PCRs 0..7)`.
- **`acpi.rs`** — full table parsing for FADT/MADT/MCFG/DMAR/TPM2 with
  ACPI 8-bit-sum-to-zero checksum verification and IOMMU group
  cross-check against `/sys/class/iommu`.
- **`cpu_platform.rs`** — full security feature inventory (smep/smap/umip/
  cet/etc.) plus a compiled-in `MICROCODE_REFERENCE` table for Intel + AMD
  (Coffee Lake → Granite Rapids; Zen 4/5) with vendor-table date stamps.
- **`hypervisor.rs`** — three-way consistency probe across DMI signature,
  CPUID-leaf signature, and kernel hypervisor type, classifying QEMU,
  VMware, Hyper-V, Xen, AWS, GCP, VirtualBox.
- **`network_boot.rs`** — real device enumeration from `/sys/class/net/*`
  (operstate, driver, speed, MAC) with Boot#### entry MAC correlation
  for PXE/HTTP boot capability discovery.

### Added — Verification probes (`src/verify/`)

- **`bls.rs`** — `bls_entries_parseable`: walks `<ESP>/loader/entries/*.conf`,
  parses BLS keys, validates linux + initrd path resolution.
- **`cmdline_drift.rs`** — `kernel_cmdline_drift`: compares `/proc/cmdline`
  against `/etc/kernel/cmdline` and every BLS entry's `options` line.
- **`esp_free_space.rs`** — `esp_free_space`: thresholds at 80 MiB (WARN)
  and 32 MiB (FAIL); resolves ESP mount via `/proc/mounts`.
- **`mok_db_consistency.rs`** — `mok_db_consistency`: counts certs in
  MokListRT and db, flags MOK-enrolled-but-db-empty configurations.
- **`sbat_in_efi.rs`** — `sbat_in_efi_binaries`: scans every `*.efi` on
  the ESP for SBAT section presence; warns on pre-shim-15.7 binaries.
- **`nvram_round_trip.rs`** — `nvram_round_trip`: opt-in via `--invasive`,
  writes a 32-byte test variable, reads back, verifies, deletes.

### Added — Output formats (all four now real, none stubbed)

- **`output/junit_xml.rs`** — one `<testsuite>` per domain; status maps
  to `<failure/>`, `<error/>`, `<skipped/>`. Ingested by GitLab CI,
  Jenkins, GitHub Actions.
- **`output/markdown.rs`** — GitHub-flavoured tables, status emoji badges,
  PII redaction ON by default (override with `--no-redact`).
- **`output/csv.rs`** — one row per check; spreadsheet-friendly column
  layout for pivots.
- **`output/sarif.rs`** — SARIF 2.1.0 for GitHub Code Scanning and
  Defender for DevOps; one rule per domain, one result per check.

### Added — Subcommands & subsystems

- **`baseline.rs`** — full diff: `DiffReport` with regressions / improvements /
  claim_changes / new / removed / quirk_delta; verdict enum
  Unchanged/Improved/Regressed/Mixed. `baseline diff <path>` and
  `baseline diff <a> <b>` both work; `--exit-on-regression` gates exit 8.
- **`snapshot.rs`** — full capture: 23 sysfs/procfs paths, manifest.json
  with per-file bytes, recursive dir walk for `/sys/class/net`,
  `/sys/firmware/efi/efivars`, `/sys/block`, etc.
- **`evidence_bundle.rs`** — Microsoft shim-review evidence: report.json,
  secure-boot/{PK,KEK,db,dbx}.esl raw bytes (attribute prefix stripped),
  shim/{MokListRT,MokListXRT,MokListTrustedRT,SbatLevelRT}, tpm/pcrs.txt,
  acpi/{FADT,MADT,MCFG,DMAR,IVRS,TPM2}.bin, manifest.json with SHA-256.
- **`plugins.rs`** — subprocess plugin protocol: `--describe` /
  `--capcheck-schema-version` / `--run` contract. Default plugin dirs
  include /etc, /usr/lib, /usr/local/lib, XDG. Failures degrade gracefully
  to error-records in the discovery list.
- **`Command::Check`** — per-check granularity. `check secure-boot.cert-chain`
  runs the domain, filters to the matching probe, recomputes the summary.
- **`Command::Report`** — Markdown report with redaction ON default;
  `--no-redact` opt-out.
- **`Command::Output`** — re-render the in-memory report in a different
  format without re-running probes (useful for chained `audit output ...`).

### Added — Layer 2 LamBoot integration (`src/lamboot/`)

- **`quirks_mirror.rs`** — diff capcheck's compiled-in quirks DB against
  the JSON manifest emitted by lamboot-core's `firmware_quirks` table
  (default location: `/usr/share/lamboot/firmware-quirks.json`).
- **`install_hints.rs`** — derive recommended `lamboot-install` flags
  from a finished report (`--use-signed-shim`, `--tpm2-measure`,
  `--vm-friendly`, `--safe-mode`, `--aggressive-cleanup`).
- **`LambootReadiness`** enriched: now carries blockers, caveats,
  recommendations, install_flags, and quirks_mirror_diff.

### Added — Quirks DB (now 10 entries)

- `ami-2024-secure-boot-cleared` — AMI Aptio V 5.27–5.34 firmware-update
  silent db clear.
- `lenovo-ideapad-300-emergency-shutdown` — IdeaPad 80M/Q/R EC SMI bug
  on UEFI variable delete.
- `shim-15-4-7-rsa4096-known-issue` — Debian #1013320 / Ubuntu #1986373
  RSA-4096 verification truncation.
- `proxmox-pve-zfs-on-root-pbt` — `proxmox-boot-tool refresh` required
  after kernel updates on ZFS-on-root.
- `lvm-thin-pool-not-supported-v1` — LamBoot v1.x LVM thin pool gap.
- `efidisk0-zfs-1m-size` — Proxmox default 1 MiB efidisk0 too small
  for shim + grub + sbat.

### Added — Cross-cutting infrastructure

- **`config.rs`** — layered configuration: `/etc` < XDG < env < CLI.
  All CLI flags can be overridden via `CAPCHECK_*` environment variables
  or TOML configs.
- **`redact.rs`** — full PII redaction via regex: MAC addresses, UUIDs,
  IPv4, IPv6, serial-numberish runs. Tri-state CLI precedence:
  `--no-redact` always wins over format defaults.
- **`--schema-dump`** — emits a real JSON Schema draft-07 document for
  the v1 report format. CI can validate report outputs against it.
- **`--capabilities`** — adds `domains`, `formats`, and `quirks_count`
  alongside `checks` for machine-parseable feature discovery.

### Added — Tests

- **`tests/fixture_replay.rs`** — 7 integration tests against the new
  fixtures (uefi-q35-typical, bios-legacy). Covers: schema v1 invariants,
  Q35 quirk matching, BIOS-mode skip semantics, JSON round-trip,
  quirks DB validation, redactor, baseline diff regression detection,
  all 6 output formatters.
- **`tests/fixtures/uefi-q35-typical/`** + **`tests/fixtures/bios-legacy/`** —
  checked-in synthetic system bundles for deterministic test replay.

### Changed

- `output/mod.rs`: new `pick_with()` + `FormatterOptions` API alongside
  the original `pick()`. `format_default_redact()` exposes per-format
  redaction defaults to the bin layer.
- `lib.rs`: registers `config`, `evidence_bundle`, `plugins` as
  first-class modules.
- `quirks/schema.rs`: `MatchSpec` gains `bios_version_min` and
  `bios_version_max` fields for range-based BIOS version matches.
- `verify/mod.rs`: now a proper module with 6 probe submodules (was
  a single trait stub).

---

## [0.7.2]

Phase 1 of `lamboot-capcheck` — first usable cut of SDS-8
(SPEC-LAMBOOT-CAPCHECK-V1, written immediately before this implementation).

### Added

- **`crates/capcheck/`** — new Rust crate `lamboot-capcheck`. Library +
  binary. Implements the rdpdo-style dual-inline-help architectural
  pattern: a single static `[CheckDoc]` array drives clap's `--help`,
  the runtime `help` subcommand, and `help <NAME>` deep-dives. ~2.5K LOC
  including 12 capability domains (6 substantive, 6 stub), 2 output
  formats (human + JSON), and the chained-command CLI surface.
- **`crates/capcheck/quirks.d/`** — initial 4-entry firmware quirks
  knowledge base in TOML, compiled into the binary at build time:
  asus-g10aj-conout-fat-coupling, debian-bug-1013320-thinkpad-x280-
  rsa4096-mok-freeze, qemu-q35-shpchp-error-16-benign, qemu-i440fx-pcie-
  incompatible. Schema versioned + validated.
- **Workspace conversion** — root `Cargo.toml` at lamboot-tools-dev/
  establishes a Cargo workspace with `crates/grub-cfg/` and
  `crates/capcheck/` as members. Workspace-level dependency versions +
  per-package version inheritance via `version.workspace = true`. This
  is the convention going forward; new Rust crates land under
  `crates/<name>/` with `Cargo.toml` inheriting from the workspace.

### Validated

- `cargo build --release` clean across the workspace
- `cargo clippy --all-features` clean (pedantic warnings deliberately at
  warn-level, not deny)
- `cargo test --all-features` clean (no tests yet; integration fixtures
  arrive in v0.7.3 alongside Phase 2)
- `lamboot-capcheck audit` on aibox (KVM/Q35/AMD Ryzen 7950X)
  produces a 12-domain report with one quirk matched (Q35 shpchp)
- `lamboot-capcheck audit` on VM 118 (EndeavourOS post-conversion)
  correctly identifies BootCurrent=0700 (our LamBoot Boot0007 entry),
  SecureBoot=disabled, no shim/MOK, matched Q35 quirk
- `lamboot-capcheck --json audit` produces valid schema v1 JSON
- `lamboot-capcheck quirks --list` / `--validate` / `--match` all work
- `lamboot-capcheck help` / `help <name>` produce the expected three-
  surface help output

### Deferred

- Domains shipped as stubs (presence-only in v0.7.2; full coverage in
  later phases): shim-mok, tpm, acpi (checksum probe stubbed), cpu-platform
  (microcode age data table), network-boot (real device correlation),
  hypervisor (CPUID cross-check). All are listed in `lamboot-capcheck
  help`; v0.8 will fill them out per SDS-8 §6.
- Verification probes: `secure-boot.cert-chain` (x509-parser walk) and
  `storage-boot.esp-loader-pe` (PE32+ header check) are implemented;
  `tpm.pcr-read`, `iommu.dmar-vs-class-iommu`, `nvram-round-trip`, and
  `cert-revocation` are documented in SDS-8 §7 but deferred to v0.8.
- Output formats: junit-xml, markdown, csv, sarif documented in
  SDS-8 §9 but stubbed (currently fall through to JSON). v0.8.
- Baseline diff: SDS-8 §10 fully specified; `baseline save` works,
  `baseline diff` deferred to v0.8.
- Snapshot bundle: SDS-8 §16 fully specified; deferred to v0.9.
- Subprocess plugin protocol: SDS-8 §12 fully specified; deferred to v0.9.
- Microsoft shim-review evidence bundle: SDS-8 §17; deferred to v0.9.
- Test fixtures: SDS-8 §22.2 names 8 reference fixtures; v0.8 captures
  + replays them.

### Changed

- Cargo workspace conversion: `crates/grub-cfg/Cargo.toml` migrated to
  inherit workspace package metadata (`version.workspace = true` etc.).
  No functional change to the grub-cfg crate.

## [0.7.1]

Patch release surfaced by running `to-lamboot` against VM 118 (the
first post-`to-uefi` end-to-end test) immediately after v0.7.0 cut.

### Added

- **`lamboot-migrate to-lamboot --unsigned`**: install the unsigned
  LamBoot binary instead of the signed one. Previously `to-lamboot`
  hardcoded `--signed` in its `lamboot-install` invocation, making it
  unusable on Secure-Boot-OFF systems (the easier first-test setup).
  Default behavior unchanged — `--signed` is still implicit, matching
  the production-SB-on assumption. `--unsigned` is opt-in and the
  expected flag for development / SB-off fleet VMs. Surfaced by VM 118
  test where SB is off and `dist/EFI/LamBoot/lambootx64-signed.efi`
  would have required interactive key-passphrase unlock to refresh.

## [0.7.0]

Empirically derived from 9 commits + uncommitted changes since `v0.3.0`,
covering three minor-version-worthy features and ~18 bug fixes.
Also normalizes per-tool `LAMBOOT_TOOL_VERSION` drift back onto the
umbrella per `~/lamco-admin/projects/lamboot/VERSIONING-POLICY.md` §5
(`lamboot-migrate` 1.0.0 → 0.7.0; `lamboot-pve-{setup,fleet}` 0.2.0 → 0.7.0).

### Added

- **`lamboot-grub-cfg` Rust crate + `lamboot-grub-inspect` CLI**
  (`7f5aa62`, ~4060 LOC across 14 files). First Rust crate in
  `lamboot-tools`. Parses the three GRUB config artifacts that host-side
  install / postinst-hook / cmdline-sync tools need to reason about:
  `/etc/default/grub` (shell-sourceable key=value), `/boot/grub/grub.cfg`
  (full menuentry tree with submenu / load_video / set root= /
  initramfs handling), and `/boot/grub2/grubenv` (env block). Fixtures
  cover the pve2 production layout. CLI exposes `--default`,
  `--menuentries`, `--cmdline`, and `--emit-bls` (translate menuentries
  to BLS Type-1 entries for LamBoot consumption).

- **`lamboot-migrate` Phase 5: ext4 shrink path + Method B chroot
  orchestration** (`b6cd412`). Closes the `SPEC-LAMBOOT-MIGRATE` §3
  Phase 5 / §4.2 Method B gap. New `to_uefi_phase_5b_mount_target`
  mounts the shrunken target root + new ESP under
  `/mnt/lamboot-target` so Phases 6-10 operate on the target rather
  than the live ISO. `target_path()` + `target_run()` helpers degrade
  to identity / no-op under Method A. `cleanup_target_mounts` EXIT
  trap ensures bind-mounts are released even on Phase 6-10 failure.

- **`lamboot-migrate` Phase 3b: pre-MBR→GPT shrink** (uncommitted
  at `0.7.0` cut). Re-orders the conversion pipeline so the ext4
  shrink + MBR-partition resize (via `sfdisk -N`) happens *before*
  Phase 4 mbrtogpt rather than after. Closes the silent-abort window
  where `sgdisk --mbrtogpt` printed "Aborting write of new partition
  table" but exited 0 on a fully-allocated MBR disk, leaving
  lamboot-migrate to charge through Phases 5-10 against an unchanged
  on-disk state. First Method-B run that completes end-to-end against
  a real single-disk fixture (EndeavourOS VM 118, 2026-05-27).

- **`lamboot-migrate do_status`** now prints human-readable output.
  Previously `emit_finding` only populated the JSON buffer; without
  `--json` the subcommand printed nothing and exited 0.

- **`lamboot-migrate` argument parser** accepts both `--opt value` and
  `--opt=value` forms. Previously only the space-separated form
  parsed.

- **`lamboot-migrate` Phase 4** parses sgdisk stdout for "Aborting
  write" and dies even when sgdisk returns 0 (defense in depth for
  the silent-abort bug above).

- **`lamboot-migrate` Phase 1 idempotency**: when an existing ESP is
  detected on the target disk, Phase 1 skips the free-space + shrink
  check (ESP already takes the slack). Lets a failed mid-Phase-8 run
  be re-run without manual cleanup.

### Fixed

- **`lamboot-migrate` Phase 2 confirm** no longer prompts under
  `--dry-run`. `confirm()` in `lamboot-toolkit-lib.sh` now auto-passes
  when `LAMBOOT_DRY_RUN=1` (universal across all tools).

- **`lamboot-migrate` Phase 3 backup** no longer fails in dry-run
  trying to write `efi-vars.txt` to a backup dir that hasn't been
  created (`backup_dir_new` is a no-op under dry-run). Capture is now
  guarded by `LAMBOOT_DRY_RUN` check.

- **`lamboot-migrate` Phase 5 dry-run** synthesizes a plausible ESP
  partnum so the rest of the phase can print its planned actions.
  Previously dry-run died at "ESP partition created but not
  detectable" because sgdisk was a no-op.

- **`lamboot-migrate` Phase 6 dry-run** synthesizes an all-zero ESP
  UUID when blkid finds none (Phase 5 `mkfs.vfat` was a no-op under
  dry-run).

- **`lamboot-migrate install_grub_pacman`** uses `pacman -S --needed`
  to skip already-installed packages. Without `--needed`, pacman
  attempted to reinstall and failed to re-download the exact installed
  version when mirrors had moved on (404 on `efibootmgr-18-3` while
  mirror was on `19-1`). Surfaced by Method-B run on EndeavourOS
  VM 118.

- **`lamboot-migrate` 5 bugs from Method-C VM 102 test** (`20e0cea`).
  Production-grade testing of `to-uefi --method C --bootloader lamboot`
  on openSUSE Tumbleweed shook out 5 distinct bugs that any non-aibox
  install would have hit.

- **`lamboot-migrate` shellcheck CI** (`a15e04d`): 5 call sites in
  `install_grub_{apt,dnf,pacman,zypper,generic}` used unquoted command
  substitution to optionally inject `--no-nvram`; replaced with a
  properly-quoted array pattern.

- **lamboot-migrate Bug 6 / Bug 12** (`784acce`): `to-uefi` and
  `to-lamboot` both passed `--with-drivers` unconditionally to the
  child `lamboot-install` invocation, defeating
  `is_filesystem_natively_covered()` and falling back to EfiFs drivers
  even when the native (ext4-view / lambutter) backend would handle
  the filesystem. Both subcommands now omit the flag and let
  `lamboot-install`'s auto-detection win. Surfaced by VM 130 (Leap 16
  `to-lamboot`) and VM 133 (Fedora 44 `to-uefi`) test passes.

- **lamboot-signing-keys Bug 15** (`31e7d8d`): `_inject_sbat_section`
  invoked GNU `objcopy --add-section .sbat=...` without
  `--change-section-address`, so objcopy was free to place the new
  section at an arbitrary VMA. On signed LamBoot binaries with
  `ImageBase=0x140000000` and `SizeOfImage=0x93000`, objcopy chose
  `0x200000000` — **8 GB above ImageBase**, well outside the valid
  PE range `[ImageBase, ImageBase+SizeOfImage)`. shim 16+ enforces
  strict PE-section bounds and rejected the binary with
  `EFI_UNSUPPORTED` before any kernel could be verified, breaking
  Config 3 (shim+MOK) deployment entirely. Fixed by:
  - querying existing section layout via `objdump -h` and computing
    `max(VMA+size)` across all sections,
  - rounding up to `SectionAlignment` (read from `objdump -p`,
    default `0x1000`),
  - passing `--change-section-address .sbat=<computed_vma>` to
    objcopy so the new section lands inside the PE image.
  Verified locally — `.sbat` now placed at `0x140092000` (inside
  PE range), and end-to-end on VM 133 (`fedora44-uefi`) where the
  trust log records `verified_via=shim_mok` — the first real
  cryptographic-verification result on the matrix. Without this
  fix Config 3 was a non-starter on shim ≥ 16; with it, the chain
  works end-to-end.

### Documented

- **TROUBLESHOOTING.md §8.4**: Modern openSUSE Tumbleweed (snapshot
  ≥ 20260425, systemd ≥ 256) ships `/usr/bin/sudo` as a symlink to
  `/usr/bin/run0-sudo`. Classic `sudo -S` (stdin password) is
  unsupported; `/etc/sudoers.d/` doesn't exist out-of-the-box. The
  catalogue now documents the polkit-rule pattern for non-interactive
  privilege escalation. Discovered while bootstrapping VM 132
  (`osusetum-uefi`) for the Config 3 dress rehearsal. Tooling itself
  is compatible — `lamboot-doctor`'s self-re-exec via `sudo
  --preserve-env=…` works under run0-sudo with the same syntax — but
  scripts/runbooks that called `sudo -S` need the polkit-rule
  alternative.

---

## [0.3.0]

### Mirrored

- `lib/esp-deploy.sh` re-mirrored from `lamboot-dev` v0.9.0 (sha256
  `4f131bb37c425c03de6e7e8d9b6472c1b26b9506d6c29997a7e198750970031c`).
  Encodes the canonical ESP file-layout + -signed.efi → bare rename
  rule shared with `lamboot-install`. Same content as v0.2.0; bump
  reflects the coordinated v0.9.0 lamboot-dev release.

### Coordinated

- Coordinated release with `lamboot-dev v0.9.0` per
  `CROSS-REPO-STATUS.md` §1.3. Lamboot-dev v0.9.0 ships first-time
  Pop!_OS auto-discovery + EFI Fallback chainload self-loop guard +
  the complete v0.9.x SDS ladder. Toolkit v0.3.0 is the lockstep
  release exposing `lamboot-esp deploy` for the offline install path
  used during the Pop!_OS recovery.

## [0.2.0]

**Released.** Public at
https://github.com/lamco-admin/lamboot-tools/releases/tag/v0.2.0
Signed with lamco-admin release key
`405CB1E36258DA1DA406A852A236DDB84E0EC96E` (Greg Lamberson).

Coordinated with lamboot-dev v0.8.4 (fw_cfg file-reference hookscript
rewrite).

**Release artifact SHA256:**
- `lamboot-tools-0.2.0.tar.gz` → `0d876863a13c5cd4aabd0e557727f4c49dad517d0eb78b85707df0e40d701e6b`
- `lamboot-migrate-1.0.0.tar.gz` → `600db8bf9f43019d25e9626dbc70ea717a0cbfd73e4d80b3bc442354d97558b2`

**Post-release distribution channels are owned by lamco-admin** and are
out of dev-repo scope. Tracked at `~/lamco-admin/pipelines/lamboot-tools/`:
- Copr publishing (RELEASE.md §13) — two Copr projects per R22 dual-packaging
- Announcement (RELEASE.md §14) — blog, social, downstream email

**First public release.** Nine core tools + two PVE companion tools, all
sharing one help-registry pattern, one JSON schema v1, and one Makefile.
Every advertised feature is fully implemented — no flags are accepted
that don't actually do something.

### Release infrastructure status at v0.2.0

Fully implemented features. The following are infrastructure items that
are separate from tool feature-completeness and require founder-side
operations to reach their green state:

- **Tier 1 fleet-test baseline** — the 26-VM matrix in
  `FLEET-TEST-PLAN.md` is harness-ready (`scripts/fleet-test.sh`,
  `scripts/publish-nightly.sh`, `.github/workflows/fleet-test.yml`)
  but requires registration of founder's self-hosted Proxmox runner
  before nightly baselines can be captured. Pre-release validation was
  manual.
- **Integration-test fixture images** — all 11 fixtures have working
  regen scripts in `tests/fixtures/regen/*.sh`, each producing a
  synthetic image in minutes. Hosting at `https://lamco.ai/products/lamboot-tools/` is a
  separate step; `download-fixtures.sh` resolves checksums from the
  repo's `fixtures.sha256`. Integration tests skip cleanly when
  fixtures are absent (and will pass once the SHAs are populated).
- **`lamboot-toolkit-pve` subpackage requires `lamboot-dev >= 0.8.4`** —
  the `lamboot-pve-setup doctor-hookscript` subcommand refuses cleanly
  if an older hookscript is detected. Two release paths documented in
  `RELEASE.md §0.1` — coordinated (ship after v0.8.4) or runtime-
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
- **MkDocs website** at `https://lamco.ai/products/lamboot-tools/` with landing page, 4 guides (quick-start, BIOS→UEFI migration, Proxmox fleet setup, diagnose workflow), 3 reference pages (CLI contracts, JSON schema, exit codes), per-tool walkthroughs, findings index.
- **Fleet-test plan** (`FLEET-TEST-PLAN.md`) with 3-tier model and 26-VM Tier 1 matrix.
- **Fixture disk image catalog** (`tests/fixtures/`) with download + regen scripts.
- **Integration tests** (`tests/integration/`) using fixtures; skip gracefully when fixtures absent.
- **GitHub Actions CI** running shellcheck + bash -n + bats (core + PVE + integration) + install smoke on Ubuntu 24.04 + Fedora 44 + openSUSE Tumbleweed containers.
- **Nightly fleet-test workflow** on self-hosted Proxmox runner.
- **Fedora Copr packaging**: two Copr projects — `lamco/lamboot-tools` (single source spec producing three subpackages: `lamboot-tools` core + `lamboot-migrate` + `lamboot-toolkit-pve`) and `lamco/lamboot-migrate` (standalone per R22 dual-publication).
- **Publish pipeline**: `publish/{build-tarball,build-standalone-migrate,mirror-from-lamboot-dev,mirror-pve-from-lamboot-dev,export-to-public}.sh`. Public export gated by `LAMBOOT_EXPORT_CONFIRMED=1` per governance.

### Cross-repo coordination (v0.2.0 release requirements)

Coordinated with `lamboot-dev v0.8.4` per `CROSS-REPO-STATUS.md`:
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

[0.7.11]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.10...v0.7.11
[0.7.10]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.9...v0.7.10
[0.7.9]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.8...v0.7.9
[0.7.8]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.7...v0.7.8
[0.7.7]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.6...v0.7.7
[0.7.6]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.5...v0.7.6
[0.7.5]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.4...v0.7.5
[0.7.4]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.3...v0.7.4
[0.7.3]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/lamco-admin/lamboot-tools/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/lamco-admin/lamboot-tools/compare/v0.3.0...v0.7.0
[0.3.0]: https://github.com/lamco-admin/lamboot-tools/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/lamco-admin/lamboot-tools/releases/tag/v0.2.0

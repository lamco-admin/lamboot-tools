# SPEC-LAMBOOT-DIAGNOSE: Generic UEFI Boot Diagnostic Scanner

**Version:** 1.0 (tool v1.0 target)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.1 entry for `lamboot-diagnose`
**Existing implementation:** `tools/lamboot-diagnose` v0.1.0 (694 lines, 2026-04-05)
**Gap-close target:** v0.2.0 (flagship tool, must ship stable at toolkit v0.2)

---

## 1. Overview

`lamboot-diagnose` is the toolkit's flagship entry point: a read-only, generic, distro-agnostic UEFI boot-chain scanner that identifies issues, categorizes them by severity, and emits actionable remediation commands.

**Scope boundary:** diagnosis only. Never mutates state. Every finding includes a remediation hint pointing at either a sibling toolkit tool or a manual procedure documented at `lamboot.dev/tools/findings/<id>`.

**Positioning:** the README's primary sample output. The tool users run first when something is wrong, and the tool they run routinely during maintenance.

### 1.1 What this tool does

Runs ~30 checks across 11 categories:

1. Boot mode (UEFI vs BIOS)
2. Partition table (GPT vs MBR)
3. ESP health (mount, filesystem, space, integrity, fallback path)
4. UEFI boot entries (efibootmgr state)
5. Bootloader binaries on ESP (LamBoot / GRUB / sd-boot / rEFInd / Limine)
6. Kernels + initrds
7. BLS entries (`/boot/loader/entries/`)
8. Secure Boot state + key enrollment
9. fstab consistency (UUID form, ESP entry)
10. Virtualization context (KVM/QEMU → LamBoot NVRAM health)
11. LamBoot integration (if LamBoot installed: mark-success service, kernel-install plugin, boot report)

### 1.2 What this tool does NOT do

- Modify any state (no fixups; delegate to sibling tools via remediation)
- Require root for read-only checks (privilege model §4.5 of toolkit spec)
- Know about every bootloader in existence (enumerated set in §11.1 of toolkit spec)
- Replace `lamboot-inspect` (which goes deeper on LamBoot-specific state)
- Detect hardware-specific firmware issues (outside scope; suggest `lamboot.dev/troubleshoot`)

### 1.3 Constraints

- Single bash file sourcing toolkit shared library
- `set -uo pipefail` (no `set -e`)
- Root NOT required for diagnostic scans; some individual checks are skipped with "requires root" finding when invoked unprivileged
- Runs on any modern Linux (glibc-based, util-linux, coreutils; efibootmgr optional)
- Supports `--offline DISK` for operating on an unmounted disk image

---

## 2. CLI interface

### 2.1 Invocation

```
lamboot-diagnose [GLOBAL FLAGS] [CHECK FILTERS]
```

No subcommands — the default action IS the diagnostic scan. Subcommands reserved for future additions (e.g., `lamboot-diagnose explain <finding-id>`).

### 2.2 Options

All universal flags from toolkit §4.1 apply. Tool-specific:

```
--esp PATH        Override ESP mount point detection
--offline DISK    Operate on an unmounted disk/image
--category CAT    Only run checks in the given category (can repeat)
--skip CAT        Skip checks in the given category (can repeat)
--id ID           Only run the check with the given finding ID
--with-remediation  Always print the remediation section (even for info findings)
```

### 2.3 Exit codes

From toolkit §4.4 table:

- **0 EXIT_OK** — all checks passed, no findings at severity ≥ warning
- **1 EXIT_ERROR** — tool itself hit an error (not a finding)
- **2 EXIT_PARTIAL** — at least one finding at severity error or critical
- **3 EXIT_NOOP** — filtered set produced no checks to run
- **7 EXIT_PREREQUISITE** — a required external tool is missing (e.g., efibootmgr absent but `--category boot_entries` requested)

Warnings alone do NOT produce a non-zero exit. `--json` output preserves all severity info for consumers.

### 2.4 Output

**Human-readable** (default, on TTY): category headings with pass/warn/fail indicators per check, summary footer with totals.

**JSON** (`--json`): unified envelope per toolkit spec §5. Every check maps to a `finding` with `severity`, `status`, `message`, `context`, `remediation`.

---

## 3. Check categories (v0.2)

Each check has a stable dotted-path `id` per toolkit spec §5.3.

### 3.1 Category: `boot_mode`

| ID | Severity if fail | Description |
|---|---|---|
| `boot_mode.uefi` | info (BIOS → warning) | Reports UEFI or BIOS mode |

### 3.2 Category: `partition_table`

| ID | Severity | Description |
|---|---|---|
| `partition_table.type` | warning if MBR | Reports GPT or MBR on root disk |

### 3.3 Category: `esp`

| ID | Severity | Description |
|---|---|---|
| `esp.mounted` | critical | ESP is mounted at `/boot/efi` or `/efi` |
| `esp.partition_type_guid` | warning | Partition type GUID is standard EF00 |
| `esp.filesystem` | critical | Filesystem is vfat |
| `esp.free_space` | warning (<10%) or error (<5%) | Free bytes and percentage |
| `esp.integrity` | warning | `fsck.fat -n` clean |
| `esp.fallback_path` | warning | `EFI/BOOT/BOOTX64.EFI` exists |

### 3.4 Category: `boot_entries`

| ID | Severity | Description |
|---|---|---|
| `boot_entries.count` | error if 0 | Number of entries in NVRAM |
| `boot_entries.bootorder` | warning if unset | BootOrder variable present |
| `boot_entries.lamboot_present` | info | LamBoot entry present (informational only) |

### 3.5 Category: `bootloader`

One finding per detected bootloader with `id = bootloader.<name>.present` and `bootloader.<name>.pe_format` for the binary type check.

Known bootloaders: `lamboot`, `grub`, `systemd-boot`, `refind`, `limine`, `windows`.

### 3.6 Category: `kernel`

| ID | Severity | Description |
|---|---|---|
| `kernel.count` | error if 0 | Number of kernel images in `/boot/vmlinuz-*` |
| `kernel.<version>.initrd` | warning | Matching initrd exists for each kernel |
| `kernel.uki.count` | info | UKIs in `EFI/Linux/*.efi` |

### 3.7 Category: `bls`

| ID | Severity | Description |
|---|---|---|
| `bls.count` | info | Number of BLS `.conf` entries |
| `bls.<filename>.valid` | warning | Each entry has `linux` or `efi` field |

### 3.8 Category: `secure_boot`

| ID | Severity | Description |
|---|---|---|
| `secure_boot.enabled` | info (informational; off is not an error) | SB state |
| `secure_boot.mok_enrolled` | info | MOK list contents (if mokutil available) |

### 3.9 Category: `fstab`

| ID | Severity | Description |
|---|---|---|
| `fstab.esp_entry` | warning | ESP present in /etc/fstab |
| `fstab.esp_uuid_form` | warning | ESP uses UUID= not /dev/ |
| `fstab.root_uuid_form` | warning | Root uses UUID/LABEL/PARTUUID |
| `fstab.dev_paths` | warning | Count of /dev/ references |

### 3.10 Category: `vm`

| ID | Severity | Description |
|---|---|---|
| `vm.type` | info | systemd-detect-virt output |
| `vm.lamboot_state` | critical if crash loop | LamBoot NVRAM state (if KVM + LamBoot) |
| `vm.lamboot_crash_counter` | critical if ≥2 | Crash counter value |

### 3.11 Category: `lamboot`

Only surfaces if LamBoot is detected. IDs: `lamboot.mark_success`, `lamboot.kernel_install_plugin`, `lamboot.boot_report`, `lamboot.install_manifest`.

---

## 4. Remediation strategy

Every finding at severity ≥ warning has a `remediation` field with:

- `summary` — one-sentence human summary
- `command` — suggested follow-up command (advisory; not invoked automatically per toolkit §5)
- `doc_url` — deep-dive at `https://lamboot.dev/tools/findings/<category>/<id>`

Examples:

```json
{
  "id": "esp.free_space",
  "severity": "warning",
  "remediation": {
    "summary": "Remove stale kernel images to free space",
    "command": "sudo lamboot-esp clean --dry-run",
    "doc_url": "https://lamboot.dev/tools/findings/esp/free_space"
  }
}
```

```json
{
  "id": "partition_table.type",
  "severity": "warning",
  "remediation": {
    "summary": "Convert to GPT+UEFI for full UEFI support",
    "command": "sudo lamboot-migrate to-uefi",
    "doc_url": "https://lamboot.dev/tools/findings/partition_table/type"
  }
}
```

---

## 5. Offline mode

`--offline DISK` delegates to the shared library's `offline_setup` per toolkit §6.4. The tool then treats `$OFFLINE_ROOT` as root and `$OFFLINE_ESP` as ESP for the duration of the scan.

Checks that don't apply offline (e.g., `boot_entries.count` — requires running efivarfs) are marked `status: "skip"` with `message` explaining why.

---

## 6. Test plan

### 6.1 Unit tests (bats)

- `tests/diagnose-cli.bats` — flag parsing, help, JSON conformance
- `tests/diagnose-filter.bats` — `--category`, `--skip`, `--id` filtering
- `tests/diagnose-json.bats` — every check produces well-formed finding

### 6.2 Integration tests (fixture disk images)

- `clean-uefi-gpt.raw` → all critical checks pass, no warnings
- `hybrid-mbr.raw` offline → partition_table.type warning, no refusal (diagnose doesn't refuse)
- `full-esp.raw` offline → esp.free_space error
- `no-esp.raw` offline → esp.mounted critical

### 6.3 Fleet matrix

Per toolkit §9.2 Tier 1: 5 distros × 2 firmwares × 2 bootloaders. On each:
- Run `lamboot-diagnose --json`
- Expect exit 0 (or 2 if migration recommended)
- Expect findings count ≥ 20
- Expect no critical findings on clean systems

---

## 7. Acceptance criteria

- [ ] Implementation sources `lamboot-toolkit-lib.sh`
- [ ] All findings emit via `emit_finding` (no ad-hoc JSON construction)
- [ ] Unified JSON envelope validates against toolkit schema v1
- [ ] `--offline DISK` works for the subset of checks that are applicable
- [ ] `--category` and `--skip` filter correctly
- [ ] `--help` registers via `register_subcommand` for help-registry consistency
- [ ] Every warning/error/critical finding has a `remediation.doc_url` pointing at `lamboot.dev/tools/findings/`
- [ ] bats-core tests pass in CI
- [ ] Tier 1 fleet matrix green
- [ ] Shellcheck clean at severity=style

---

## 8. Deferred to v0.3+

- Checks for Limine (class 3 self-verified bootloader)
- TPM attestation state (`/sys/class/tpm/tpm0/`)
- UKI signature verification via `ShimLock::Verify` equivalent (complex; delegate to `lamboot-inspect`)
- `--watch` mode for continuous monitoring
- `lamboot-diagnose explain <finding-id>` subcommand with expanded narrative

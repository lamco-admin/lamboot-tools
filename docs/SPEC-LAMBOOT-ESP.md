# SPEC-LAMBOOT-ESP: EFI System Partition Health + Management

**Version:** 1.0 (tool v1.0 target)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.1 entry for `lamboot-esp`
**Existing implementation:** `tools/lamboot-esp` v0.1.0 (491 lines, 2026-04-05)
**Gap-close target:** v0.2.0 (stable at toolkit v0.2)

---

## 1. Overview

`lamboot-esp` is the ESP-focused companion to `lamboot-diagnose`. Where diagnose scans the whole boot chain, esp goes deep on one specific layer: the EFI System Partition's filesystem health, content inventory, and cleanup of stale files.

**Three subcommands** (spec §2 below).

### 1.1 What this tool does

- `check` — health scan: filesystem integrity, mount state, space, permissions, bootloader inventory, fallback path presence, stale-file detection
- `inventory` — structured listing: bootloaders, UKIs, BLS entries, directory sizes, total file count
- `clean` — remove stale/orphaned files (macOS remnants, .bak files, interrupted-install .tmp files) with user confirmation

### 1.2 What this tool does NOT do

- Modify ESP contents without explicit confirmation (clean is dry-run by default)
- Repair filesystem corruption (that's `fsck.fat -a`; tool suggests it)
- Recreate or resize the ESP (that's `lamboot-migrate`)
- Install bootloaders (delegate to each bootloader's own installer)
- Verify bootloader signatures (that's `lamboot-diagnose` for the general case, `lamboot-inspect` for LamBoot)

### 1.3 Constraints

- Read-only by default (only `clean --apply` writes)
- `check` and `inventory` run unprivileged where ESP is world-readable (common); `clean --apply` requires root
- Supports `--offline DISK` for VM disks from the Proxmox host

---

## 2. CLI interface

```
lamboot-esp [GLOBAL FLAGS] [SUBCOMMAND]

SUBCOMMAND (default: check):
    check        Run ESP health checks
    inventory    Show structured ESP contents inventory
    clean        Identify stale files; --apply to remove (default: dry-run)
    help         Show help (or help <subcommand>)

Tool-specific options:
    --esp PATH          Override ESP mount point detection
    --offline DISK      Operate on an unmounted disk or image
    --apply             (clean only) Actually remove files; default is preview
    --keep-backups      (clean only) Don't remove .bak files even if stale
```

All universal flags from toolkit §4.1 apply.

### 2.1 Exit codes

- **0 EXIT_OK** — health clean / inventory complete / clean dry-run reported
- **2 EXIT_PARTIAL** — health check found error-severity findings
- **3 EXIT_NOOP** — clean requested but no stale files found
- **5 EXIT_ABORT** — user declined confirmation during `clean --apply`
- **7 EXIT_PREREQUISITE** — tool missing or ESP not detectable

---

## 3. Check categories

### 3.1 `check` subcommand findings

| ID | Severity | Description |
|---|---|---|
| `esp.partition.type_guid` | warning | Partition type GUID is EF00 |
| `esp.partition.size` | warning if <100MB | ESP size |
| `esp.filesystem.type` | critical if not vfat | vfat expected |
| `esp.filesystem.integrity` | warning | `fsck.fat -n` clean |
| `esp.filesystem.space` | warning (<10%) or error (<5%) | Free space percentage |
| `esp.filesystem.mount_rw` | warning | Mounted read-write |
| `esp.fallback.bootx64` | warning | `EFI/BOOT/BOOTX64.EFI` exists |
| `esp.fallback.bootaa64` | info | aarch64 fallback present |
| `esp.inventory.bootloaders` | info | Count of bootloaders detected |
| `esp.inventory.ukis` | info | Count of UKIs in `EFI/Linux/` |
| `esp.inventory.bls_entries` | info | Count in `loader/entries/` |
| `esp.stale.macos_remnants` | warning | `mach_kernel`, `System/` directory |
| `esp.stale.backup_files` | warning | `*.bak`, `*.lamboot-backup` |
| `esp.stale.interrupted_tmp` | warning | `*.lamboot-tmp.*` from interrupted installs |
| `esp.fstab.present` | warning | ESP in `/etc/fstab` |
| `esp.fstab.uuid_form` | warning | Uses UUID= not /dev/ |

### 3.2 `inventory` subcommand output

Full JSON structure under `context`:

```json
{
  "esp_mount": "/boot/efi",
  "device": "/dev/nvme0n1p1",
  "fs_type": "vfat",
  "partition_uuid": "...",
  "partition_type_guid": "c12a7328-...",
  "bootloaders": [
    {"name": "lamboot", "path": ".../LamBoot/lambootx64.efi", "size_kb": 512},
    {"name": "grub", "path": ".../fedora/grubx64.efi", "size_kb": 2048}
  ],
  "ukis": [
    {"path": ".../Linux/linux-6.12.efi", "size_kb": 32768}
  ],
  "bls_entries": [
    {"file": ".../loader/entries/fedora.conf"}
  ],
  "directory_sizes": [
    {"path": "EFI/LamBoot", "size_bytes": 1048576},
    {"path": "EFI/fedora", "size_bytes": 2097152}
  ],
  "total_files": 42,
  "total_bytes": 15728640
}
```

### 3.3 `clean` subcommand behavior

Default mode: **dry-run**. Lists files that would be removed; exits 0.

With `--apply`: prompts for confirmation once (showing the full list), then removes. Each removal is recorded in `actions_taken[]` per toolkit spec §5.4.

Stale-file categories targeted:
- macOS remnants (`mach_kernel`, `System/` directory from Apple recovery media)
- LamBoot backup files (`*.lamboot-backup` from prior lamboot-install runs)
- Interrupted-install temp files (`*.lamboot-tmp.*`)
- Generic `*.bak` files (opt-out via `--keep-backups`)

Files NEVER touched by clean:
- Any binary in `EFI/<bootloader>/` directories
- Any file under `loader/entries/`
- Any UKI in `EFI/Linux/`
- Any file whose removal would leave the ESP unbootable

---

## 4. Offline mode

`--offline DISK` delegates to shared library's `offline_setup`. Sets `$OFFLINE_ESP` as the ESP mount point for the duration. `check` and `inventory` work normally against the offline mount; `clean --apply` is supported offline (useful for cleaning dormant VM ESPs).

---

## 5. Test plan

### 5.1 Unit tests (bats)

- `tests/esp-cli.bats` — flag parsing, help surfaces, JSON conformance
- `tests/esp-subcommands.bats` — check/inventory/clean routing

### 5.2 Integration tests (fixture disk images)

- `full-esp.raw` → check exits 2 with `esp.filesystem.space` error
- `corrupted-esp-fat.raw` → check exits 2 with `esp.filesystem.integrity` warning
- `lamboot-installed.raw` → inventory lists lamboot + grub
- Synthetic fixture with `*.bak` files → clean --apply removes them after confirmation

### 5.3 Fleet matrix

Tier 1: every VM in the matrix exercises `lamboot-esp check` and `lamboot-esp inventory`. No clean operations in fleet tests (state-changing; tested separately via offline fixtures).

---

## 6. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 on every subcommand
- [ ] `--offline DISK` works for check + inventory + clean
- [ ] `clean` is dry-run by default; `--apply` required to mutate
- [ ] `clean --apply` prompts once, records actions, and never removes bootloader-critical files
- [ ] Every warning+ finding has `remediation`
- [ ] bats-core tests pass in CI
- [ ] Shellcheck clean at severity=style

---

## 7. Deferred to v0.3+

- `esp resize` subcommand (ESP resize in-place; requires sgdisk + fsck + mkfs)
- `esp snapshot` / `esp restore` (quick ESP content backup before risky operations)
- Signed-binary verification in inventory (delegates to `lamboot-diagnose`/`lamboot-inspect` today)
- Integration with systemd-tmpfiles for automatic stale-file policy

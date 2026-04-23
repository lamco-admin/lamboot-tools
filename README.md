# lamboot-tools

Boot management, diagnostic, migration, and recovery toolkit for [LamBoot](https://github.com/lamco-admin/lamboot-dev).

Five standalone bash CLI tools that orchestrate existing Linux utilities (efibootmgr, sgdisk, dosfstools, virt-fw-vars) to provide:

- **Diagnostic intelligence** — comprehensive boot health scanning with actionable recommendations
- **ESP management** — filesystem integrity, space monitoring, stale file cleanup
- **Configuration backup** — export/restore UEFI boot entries, boot order, Secure Boot state
- **Boot repair** — automated diagnosis and repair for online systems and offline VM disks
- **Migration automation** — the first automated end-to-end Linux BIOS→UEFI migration tool

## Tools

| Tool | Description |
|------|-------------|
| [lamboot-diagnose](#lamboot-diagnose) | Comprehensive UEFI boot diagnostic scanner |
| [lamboot-esp](#lamboot-esp) | ESP health check and management |
| [lamboot-backup](#lamboot-backup) | Boot configuration backup and restore |
| [lamboot-repair](#lamboot-repair) | Boot repair for online and offline systems |
| [lamboot-migrate](#lamboot-migrate) | BIOS→UEFI and cross-bootloader migration |

## Quick Start

```bash
# Install
sudo make install

# Run a diagnostic scan
sudo lamboot-diagnose

# Check ESP health
sudo lamboot-esp check

# Back up boot config before changes
sudo lamboot-backup save
```

## Requirements

- bash 4.0+
- GNU coreutils or Rust uutils/coreutils
- util-linux (findmnt, lsblk, blkid, mountpoint)
- efibootmgr

**Optional** (for specific tools):
- dosfstools — ESP filesystem check (`lamboot-esp`)
- gdisk/sgdisk — partition table conversion (`lamboot-migrate`)
- virt-fw-vars or kernel-bootcfg — offline VM operations (`lamboot-backup`, `lamboot-repair`)
- qemu-nbd — offline VM disk access (`lamboot-repair`)

---

## lamboot-diagnose

Comprehensive UEFI boot diagnostic scanner. Checks the entire boot chain and reports issues with actionable fix recommendations.

```
lamboot-diagnose [OPTIONS]
```

| Flag | Description |
|------|-------------|
| `--json` | Output results as JSON |
| `--esp PATH` | Override ESP mount point |
| `--verbose` | Show additional details |
| `--quiet` | Only show warnings and failures |

**Checks**: partition table, ESP health, UEFI boot entries, bootloader files, kernels + initrds, BLS entries, Secure Boot state, fstab, VM NVRAM health.

---

## lamboot-esp

EFI System Partition health check and management.

```
lamboot-esp [OPTIONS] [check|inventory|clean]
```

| Command | Description |
|---------|-------------|
| `check` | (default) Full ESP health scan — integrity, space, permissions |
| `inventory` | List all files on ESP with sizes and bootloader identification |
| `clean` | Identify and remove stale/orphaned files (dry-run by default) |

| Flag | Description |
|------|-------------|
| `--esp PATH` | Override ESP mount point |
| `--json` | Output results as JSON |
| `--verbose` | Show additional details |

---

## lamboot-backup

UEFI boot configuration backup and restore.

```
lamboot-backup [OPTIONS] save [FILE]
lamboot-backup [OPTIONS] restore FILE
lamboot-backup [OPTIONS] show [FILE]
```

| Command | Description |
|---------|-------------|
| `save [FILE]` | Export boot config to JSON (default: `lamboot-backup.json`) |
| `restore FILE` | Restore boot entries from backup |
| `show [FILE]` | Display backup contents |

| Flag | Description |
|------|-------------|
| `--force` | Overwrite existing file / skip confirmation |
| `--dry-run` | Show what would happen |
| `--verbose` | Show additional details |

**Saves**: UEFI boot entries, boot order, timeout, Secure Boot state, LamBoot NVRAM variables.

Supports offline VM NVRAM operations via `kernel-bootcfg` or `virt-fw-vars`.

---

## lamboot-repair

Boot repair for online and offline systems. Workflow: **Diagnose → Plan → Show → Confirm → Execute → Verify**.

```
lamboot-repair [OPTIONS]                     # Online repair
lamboot-repair --offline DISK [OPTIONS]      # Offline VM repair from host
```

| Flag | Description |
|------|-------------|
| `--offline DISK` | Repair offline VM disk image |
| `--dry-run` | Show repair plan without executing |
| `--auto` | Execute fixes without confirmation |
| `--force` | Skip safety checks |
| `--yes`, `-y` | Answer yes to all prompts |
| `--verbose` | Show additional details |

**Fixes**: missing LamBoot binary, missing UEFI boot entry, invalid BLS entries, missing drivers, ESP filesystem errors, boot order issues, missing initrds, broken fallback path.

### Offline VM Repair

```bash
# Repair a VM that won't boot, from the Proxmox host
sudo lamboot-repair --offline /dev/pve/vm-201-disk-1
```

---

## lamboot-migrate

BIOS→UEFI migration and cross-bootloader migration.

```
lamboot-migrate status                       # Show current boot configuration
lamboot-migrate to-uefi [OPTIONS]            # BIOS/MBR → UEFI/GPT conversion
lamboot-migrate to-lamboot [OPTIONS]         # Install LamBoot alongside/replacing current
```

| Flag | Description |
|------|-------------|
| `--disk DEVICE` | Target disk (default: auto-detect) |
| `--esp-size MB` | ESP size in MB (default: 550) |
| `--bootloader NAME` | `lamboot`, `grub`, or `systemd-boot` (default: `lamboot`) |
| `--dry-run` | Show what would happen |
| `--force` | Skip safety checks |
| `--yes`, `-y` | Answer yes to all prompts |
| `--verbose` | Show additional details |

### to-uefi

Automated BIOS→UEFI conversion: MBR→GPT, ESP creation, bootloader install, fstab update. Run from live media when converting the boot disk.

### to-lamboot

Install LamBoot alongside or replacing GRUB/systemd-boot. Preserves existing bootloader as a chainload option.

---

## Exit Codes

All tools use consistent exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error |
| 2 | Partial — some steps succeeded, some failed |
| 3 | Nothing to do — system already in desired state |

---

## Installation

```bash
# From source
git clone https://github.com/lamco-admin/lamboot-tools-dev.git
cd lamboot-tools-dev
sudo make install

# Uninstall
sudo make uninstall
```

## Related

- [LamBoot](https://github.com/lamco-admin/lamboot-dev) — the UEFI bootloader
- [LamBoot User Guide](https://github.com/lamco-admin/lamboot-dev/blob/main/docs/USER-GUIDE.md)
- [LamBoot Troubleshooting Guide](https://github.com/lamco-admin/lamboot-dev/blob/main/docs/TROUBLESHOOTING-GUIDE.md)

## License

MIT OR Apache-2.0

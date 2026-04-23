# Boot Management Toolkit: Landscape Analysis and Design

**Date:** 2026-04-04
**Status:** Research Complete
**Goal:** Design a comprehensive toolkit for boot management, troubleshooting, migration, and recovery — serving beginners through experts on Proxmox VMs and bare metal

---

## 1. Existing Tools: Complete Evaluation

### 1.1 UEFI Boot Entry and Variable Management

| Tool | Language | License | Health | Scriptable | Key Capability | Key Limitation |
|------|----------|---------|--------|-----------|----------------|----------------|
| **efibootmgr** | C (87%) | GPL-2.0 | Slow (v18, Jul 2022, 44 open issues) | Yes | Standard online UEFI entry CRUD | Online only, no backup/restore, no validation |
| **virt-firmware** (10 tools) | Python | GPL-2.0+ | Active (v25.10, Oct 2025) | Yes | Offline NVRAM editing, Secure Boot, boot entry management | Offline only, UKI-centric, no BLS support |
| **efivar-rs** | Rust (100%) | MIT | Active/Early (v2.0, Jan 2024, 49 stars) | Yes (lib) | Cross-platform EFI variable library | Unstable API, no offline OVMF support |
| **UEFI Shell** | C (edk2) | BSD-2-Clause | Active | Yes (nsh scripts) | Firmware-level NVRAM backup (dmpstore), boot entry editing (bcfg) | Expert-only, not Secure Boot signed |

**virt-firmware** is the most important tool in this list. It ships **10 CLI tools** on PVE 9, not just `virt-fw-vars`:

| CLI Tool | Purpose |
|----------|---------|
| `virt-fw-vars` | NVRAM variable editing, Secure Boot key enrollment |
| `kernel-bootcfg` | **Boot entry CRUD, boot order, UKI management, boot assessment** |
| `virt-fw-dump` | Firmware volume decoder |
| `virt-fw-measure` | Firmware measurement |
| `virt-fw-sigdb` | Signature database editing |
| `host-efi-vars` | Host EFI variable access |
| `migrate-vars` | 2MB→4MB varstore migration |
| `uefi-boot-menu` | Boot menu display |
| `uki-addons` | UKI addon management |
| `pe-dumpinfo` | PE binary analysis |

**kernel-bootcfg** is the standout — tested on Proxmox host against VM 201 NVRAM, it provides:
- `--add-uki FILE` / `--remove-uki FILE` / `--update-uki FILE` — UKI boot entry lifecycle
- `--remove-entry NNNN` — remove arbitrary boot entry by number
- `--boot-order POS` — set boot order position
- `--boot-ok` — mark boot as successful (boot assessment)
- `--show --verbose` — display boot configuration with device paths
- `--dry-run` — preview changes without writing
- `--vars FILE` — operate on offline OVMF_VARS files
- `--shim FILE` — Secure Boot shim integration

**Source:** [gitlab.com/kraxel/virt-firmware](https://gitlab.com/kraxel/virt-firmware) by Gerd Hoffmann (Red Hat). 2 open MRs, 2 open issues.

### 1.2 Partition and Filesystem Management

| Tool | Language | License | Health | Scriptable | Replace? |
|------|----------|---------|--------|-----------|----------|
| **gdisk/sgdisk** | C++ | GPL-2.0 | Mature/Stable (v1.0.10, 2024) | Yes (sgdisk fully scriptable) | No — use as building block |
| **parted/gparted** | C | GPL-3.0+ | Slow/Mature | Yes (parted -s) | No — use for resize |
| **fdisk/sfdisk** | C (util-linux) | GPL-2.0+ | Active | Yes (sfdisk for backup/restore) | No — use as-is |
| **dosfstools** | C | GPL-3.0+ | Active | Yes | No — use for ESP |
| **resize2fs** | C (e2fsprogs) | GPL-2.0 | Active | Yes | No — use for ext4 resize |

All partition/filesystem tools are **building blocks** — mature, well-tested, scriptable. Don't replace any of them.

### 1.3 Bootloader Installation

| Tool | Language | License | Health | Key Strength | Key Weakness |
|------|----------|---------|--------|-------------|--------------|
| **grub-install** | C | GPL-3.0+ | Active | Universal, documented | Complex flags, #1 mistake: missing `--target=x86_64-efi` |
| **bootctl install** | C | LGPL-2.1+ | Active | Simple, atomic writes | No BLS generation |
| **refind-install** | Bash/Perl | GPL-3.0 | Active | Most robust: backup, SB, config preservation | Perl dependency |
| **lamboot-install** | Bash | MIT/Apache-2.0 | New | Binary validation, manifest, boot order safety | Less battle-tested |

### 1.4 Boot Repair and Recovery

| Tool | Language | License | Health | Scope | Verdict |
|------|----------|---------|--------|-------|---------|
| **boot-repair** | Bash (99%) | GPL-3.0 | Dead (27 commits since 2012) | GRUB-only auto-repair | Don't use. Study bootinfoscript detection heuristics. |
| **bootinfoscript** | Bash | MIT | Slow (v0.76) | Multi-bootloader detection/reporting | Adapt detection approach for lamboot-diagnose |
| **Rescatux** | Mixed | GPL | Active | Live rescue with GUI | Reference for rescue UX |
| **SystemRescue** | Arch-based | Various | Active | CLI rescue environment | Gold standard for rescue tooling |

### 1.5 Proxmox-Specific

| Tool | Purpose | Notes |
|------|---------|-------|
| `qm set --bios ovmf` | Change VM firmware | Host-side config |
| `qm set --efidisk0` | Add NVRAM disk | Not the ESP — this is OVMF's variable store |
| `qm snapshot/rollback` | Instant rollback | Essential safety net for migration |
| `qemu-nbd` | Expose VM disks from host | Mount VM partitions for offline repair |
| `kernel-bootcfg --vars FILE` | Offline boot entry management | Already on PVE 9, works on efidisk0 |
| `lamboot-monitor.py` | Read LamBoot health from OVMF_VARS | Custom tool (exists, working) |

---

## 2. Gap Analysis: What's Actually Missing

After discovering kernel-bootcfg's capabilities, the gap analysis narrows:

| Gap | Severity | Existing Partial Solution |
|-----|----------|--------------------------|
| **No unified boot diagnostic** | Critical | bootinfoscript (detection only, GRUB-centric, no JSON) |
| **No automated BIOS→UEFI migration for Linux** | High | None (Windows has mbr2gpt) |
| **No BLS entry management in kernel-bootcfg** | Medium | kernel-bootcfg is UKI-only; efibootmgr is online-only |
| **No ESP health check** | Medium | dosfsck (filesystem only, no boot-awareness) |
| **No cross-bootloader migration** | Medium | None |
| **No offline VM boot repair** | Medium | kernel-bootcfg + qemu-nbd (manual, unintegrated) |
| **No self-guided troubleshooting** | Medium | None |
| **No boot config backup/restore** | Low | UEFI Shell dmpstore (firmware-level only) |

---

## 3. Three Layers of EFI Variable Management

| Layer | Tool | Access | Scenario |
|-------|------|--------|----------|
| **Online** | efibootmgr, host-efi-vars | Running EFI-booted system | Normal operations |
| **Offline** | virt-fw-vars, kernel-bootcfg --vars | VM disk image from host | VM won't boot |
| **Firmware** | UEFI Shell (dmpstore, bcfg) | Pre-OS environment | Physical hardware, no OS |

The LamBoot toolkit must provide a unified interface across all three.

---

## 4. BIOS-to-UEFI Migration

### 4.1 The Pipeline

```
Backup → MBR→GPT (sgdisk) → ESP creation (sgdisk + mkfs.vfat) →
fstab update → Bootloader install → UEFI entry creation → Verify
```

### 4.2 Proxmox VM Migration (3 Methods)

**Method A (preferred):** Pre-convert inside running VM, verify BIOS still boots, then switch to OVMF.
**Method B:** Post-convert with live media chroot.
**Method C:** Add second disk as ESP (simplest for VMs).

Always `qm snapshot` before — instant rollback.

### 4.3 Top 5 Migration Failure Modes

1. `grub-install` without `--target=x86_64-efi` — **#1 most common mistake**, silently installs BIOS GRUB
2. fstab uses `/dev/sda1` instead of `UUID=` — partition numbers change during GPT conversion
3. Missing `/sys/firmware/efi/efivars` bind-mount during chroot — efibootmgr/grub-install silently fail
4. No fallback path (`EFI/BOOT/BOOTX64.EFI`) — fresh NVRAM has no boot entries
5. Hybrid MBR — Rod Smith explicitly warns these are "flaky and dangerous"

### 4.4 Verification Checklist

```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS"
gdisk -l /dev/sdX          # GPT, ef00 partition present
mount | grep efi            # ESP mounted
efibootmgr -v              # Entries present, correct order
ls /boot/efi/EFI/BOOT/BOOTX64.EFI  # Fallback path exists
blkid                      # UUIDs match fstab
```

---

## 5. Proposed Toolkit

### 5.1 Tools and Priority

| # | Tool | Purpose | Language | Priority | Lines (est.) |
|---|------|---------|----------|----------|-------------|
| 1 | **lamboot-diagnose** | Comprehensive boot diagnostic scanner | Bash | Highest | ~500 |
| 2 | **lamboot-esp** | ESP health check | Bash | High | ~200 |
| 3 | **lamboot-backup** | Boot config backup/restore | Bash | High | ~300 |
| 4 | **lamboot-migrate** | BIOS→UEFI + cross-bootloader migration | Bash | Medium | ~800 |
| 5 | **lamboot-repair** | Online + offline boot repair | Python | Medium | ~1000 |
| 6 | **lamboot-fleet** | Proxmox fleet operations | Python | Future | ~600 |
| — | **lamboot-install** | Bootloader installation | Bash | **Done** | 1525 |
| — | **lamboot-monitor** | VM health monitoring | Python | **Done** | 292 |

### 5.2 Design Principles

1. **Use existing tools as building blocks** — sgdisk, efibootmgr, virt-fw-vars, kernel-bootcfg, dosfstools are all scriptable. Don't reimplement.
2. **Provide orchestration and intelligence** — chain tools together, diagnose problems, suggest fixes.
3. **Dual-mode output** — guided text for beginners, JSON for experts/automation.
4. **Diagnose → Plan → Show → Confirm → Execute → Verify** — never run destructive operations without showing the plan and getting confirmation.
5. **Bash for orchestration, Python for VM integration** — Rust only inside the bootloader itself.

### 5.3 lamboot-diagnose Checks

1. Partition table type (MBR vs GPT)
2. ESP: presence, size, free space, filesystem integrity (dosfsck -n)
3. UEFI boot entries: exist? point to valid files? correct order?
4. Bootloader files on ESP: which bootloaders present? signed? correct architecture?
5. Kernels: exist? valid PE headers? matching initrds?
6. BLS entries: parseable? paths resolve to real files?
7. Secure Boot: enabled? keys enrolled? shim present?
8. fstab: ESP mounted? UUIDs correct?
9. Root partition: reachable? filesystem type?
10. For VMs: efidisk0 present? OVMF NVRAM valid?

### 5.4 Scriptability Assessment

All critical tools are fully scriptable with reliable exit codes:

| Operation | Command | Pipeable? |
|-----------|---------|-----------|
| MBR→GPT conversion | `sgdisk -g /dev/sdX` | Yes (immediate!) |
| Create ESP partition | `sgdisk -n 0:0:+550M -t 0:ef00 /dev/sdX` | Yes |
| Format ESP | `mkfs.vfat -F32 /dev/sdXN` | Yes |
| Resize ext4 | `resize2fs /dev/sdXN SIZE` | Yes |
| Create boot entry | `efibootmgr -c -d /dev/sdX -p N -l PATH -L NAME` | Yes |
| Set boot order | `efibootmgr -o 0001,0002,...` | Yes |
| Offline NVRAM edit | `virt-fw-vars -i FILE -o FILE -d VAR` | Yes |
| Offline boot entry management | `kernel-bootcfg --vars FILE --add-uki FILE` | Yes |

---

## 6. Upstream Contribution Opportunities

| Project | Contribution | Difficulty | Value |
|---------|-------------|-----------|-------|
| **virt-firmware** (kernel-bootcfg) | Add `--add-bls` for non-UKI kernel+initrd entries | Low (Python) | High — fills the only real gap |
| **efivar-rs** | Add offline OVMF variable support | Medium (Rust) | High — enables all-Rust toolkit |
| **efibootmgr** | Entry validation, JSON output | Medium (C) | Low — project is stale |

---

## 7. Key Recovery Technique: Chroot for UEFI Repair

```bash
mount /dev/sdXN /mnt                       # Root
mount /dev/sdXM /mnt/boot                  # /boot (if separate)
mount /dev/sdXP /mnt/boot/efi              # ESP
for d in dev dev/pts proc sys sys/firmware/efi/efivars run; do
    mount --bind /$d /mnt/$d
done
chroot /mnt
# CRITICAL: /sys/firmware/efi/efivars MUST be bound or UEFI operations silently fail
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
update-grub
exit
umount -R /mnt
```

---

## 8. Sources

- [virt-firmware (GitLab)](https://gitlab.com/kraxel/virt-firmware) — Gerd Hoffmann (Red Hat)
- [efibootmgr (GitHub)](https://github.com/rhboot/efibootmgr) — Red Hat bootloader team
- [efivar-rs (GitHub)](https://github.com/iTrooz/efivar-rs) — MIT, Rust EFI variables
- [GPT fdisk / gdisk](https://www.rodsbooks.com/gdisk/) — Rod Smith
- [Rod Smith on EFI Boot Loaders](https://www.rodsbooks.com/efi-bootloaders/)
- [bootinfoscript (GitHub)](https://github.com/arvidjaar/bootinfoscript) — MIT, boot detection
- [boot-repair (SourceForge)](https://sourceforge.net/p/boot-repair/home/Home/) — YannMRN
- [Proxmox OVMF/UEFI Boot Entries](https://pve.proxmox.com/wiki/OVMF/UEFI_Boot_Entries)
- [Proxmox Forum: SeaBIOS to OVMF](https://forum.proxmox.com/threads/convert-ubuntu-vm-from-seabios-to-ovmf.132657/)
- [Baeldung: Convert MBR to GPT](https://www.baeldung.com/linux/convert-disk-mbr-gpt-uefi)
- [Arch Wiki: EFI System Partition](https://wiki.archlinux.org/title/EFI_system_partition)
- [Arch Wiki: GRUB](https://wiki.archlinux.org/title/GRUB)
- [Arch Wiki: systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
- [TechRadar: Best Linux Rescue Distros 2026](https://www.techradar.com/best/best-linux-repair-and-rescue-distros)

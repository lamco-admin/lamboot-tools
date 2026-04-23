# SPEC-LAMBOOT-BACKUP: UEFI Boot Configuration Backup + Restore

**Version:** 1.0 (tool v1.0 target)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.1 entry for `lamboot-backup`
**Existing implementation:** `tools/lamboot-backup` v0.1.0 (359 lines, 2026-04-05)
**Gap-close target:** v0.2.0 (stable at toolkit v0.2)

---

## 1. Overview

`lamboot-backup` snapshots UEFI NVRAM state (boot entries, boot order, timeout, Secure Boot posture, LamBoot-specific NVRAM vars) into a versioned JSON file for disaster recovery and audit.

### 1.1 What this tool does

- **`save`** — snapshot current NVRAM state to a JSON file
- **`restore`** — apply a snapshot (boot order, timeout, selected entries) to NVRAM
- **`show`** — human-readable display of a snapshot's contents
- **`list`** — list snapshots in the default backup directory with timestamps

### 1.2 What this tool does NOT do

- Back up filesystem contents on the ESP (that's `lamboot-esp` snapshot, deferred to v0.3+)
- Restore individual boot entries from scratch (EFI device-path reconstruction is complex; v1.0 restores boot order + timeout only)
- Modify Secure Boot keys (that's `lamboot-signing-keys`)
- Back up LamBoot's trust log (that's ESP content; part of ESP snapshot scope)

### 1.3 Constraints

- Read-only for `save` + `show` + `list` (no NVRAM writes)
- `restore` requires root
- JSON output conforms to toolkit schema v1 §5
- Offline mode via `--offline DISK` for VM disks (uses `virt-fw-vars` or `kernel-bootcfg` for NVRAM read; write via `virt-fw-vars` for offline restore)

---

## 2. CLI interface

```
lamboot-backup [GLOBAL FLAGS] SUBCOMMAND [ARGS]

Subcommands:
    save [FILE]           Snapshot to FILE (default: /var/backups/lamboot-backup-<ts>.json)
    restore FILE          Apply snapshot FILE
    show FILE             Display snapshot contents
    list                  List snapshots in /var/backups/lamboot-backup-*.json
    help [<sub>]          Help

Tool-specific options:
    --force               save: overwrite existing file
                          restore: skip interactive confirmation
    --offline DISK        Read/write NVRAM from unmounted VM disk
    --include-entries     restore: also attempt to re-create missing entries (experimental)
```

### 2.1 Exit codes

Standard toolkit codes from §4.4:
- **0** save/show/list/restore success
- **2** restore partial (boot order set but some entries missing)
- **3** restore noop (current state already matches snapshot)
- **5** user declined interactive confirmation
- **7** prerequisite missing (efibootmgr absent online; virt-fw-vars absent offline)

---

## 3. Snapshot JSON format

```json
{
  "schema_version": "v1",
  "tool": "lamboot-backup",
  "version": "0.2.0",
  "toolkit_version": "0.2.0",
  "timestamp": "2026-04-22T14:37:22Z",
  "host": "laptop-01",
  "run_id": "...",
  "source": "online",
  "nvram": {
    "boot_order": "0008,0000,0001,2001,2002,2003",
    "boot_current": "0008",
    "boot_next": null,
    "timeout_seconds": 3,
    "secure_boot_enabled": true,
    "setup_mode": false
  },
  "entries": [
    {
      "bootnum": "0008",
      "label": "LamBoot",
      "active": true,
      "attributes": ["LOAD_OPTION_ACTIVE"],
      "devpath": "HD(1,GPT,abc-123,0x800,0x100000)/\\EFI\\LamBoot\\lambootx64.efi",
      "optional_data_hex": ""
    }
  ],
  "lamboot_nvram": {
    "state": "BootedOK",
    "crash_counter": 0,
    "last_successful_boot": "2026-04-22T14:00:00Z"
  }
}
```

The envelope reuses the toolkit's standard JSON header (tool/version/timestamp/run_id) for consistency; the `nvram` + `entries` + `lamboot_nvram` sections are tool-specific.

---

## 4. Save behavior

1. Preflight: verify EFI mode, efibootmgr availability
2. Read via `efibootmgr -v`
3. Parse entries: `BootNNNN*` lines, label, device path, optional data
4. Read Secure Boot + setup-mode + audit-mode flags from efivarfs
5. Read LamBoot-specific NVRAM (LamBootState + LamBootCrashCount) if present
6. Serialize to JSON at the target path
7. Emit finding `backup.save.complete` with `{"path": ..., "entry_count": N}`

Default target when FILE omitted: `/var/backups/lamboot-backup-<run_id>.json`.

With `--offline DISK`: invoke `virt-fw-vars -i <efivars-section>` to read NVRAM from the disk's efivars partition (Proxmox efidisk0 pattern).

---

## 5. Restore behavior

Conservative v1.0 scope: restore **boot order + timeout**. Entry recreation is deferred to v0.3+ under `--include-entries` flag (experimental, off by default).

1. Preflight: load snapshot, validate schema_version == v1
2. Read current NVRAM state
3. Compute diff (boot_order, timeout)
4. If no diff → EXIT_NOOP
5. Show diff to user, require confirmation (unless `--force`)
6. Apply via `efibootmgr --bootorder ... --timeout ...`
7. Re-read NVRAM, verify application, emit findings
8. Record each action to `actions_taken[]`

Entries referenced in `boot_order` but not present in current NVRAM → warning, not error. User may need to `--include-entries` (v0.3+) or manually re-create.

---

## 6. Show behavior

Read-only JSON parsing (no jq dependency — bash grep/sed). Formats the snapshot for humans:

```
Boot Configuration Snapshot: /var/backups/lamboot-backup-2026-04-22T14-37-22-a1b2c3.json
========================================================================
  Created:      2026-04-22T14:37:22Z
  Host:         laptop-01
  Source:       online
  Secure Boot:  enabled
  Setup Mode:   false
  Boot Order:   0008,0000,0001,2001,2002,2003
  Timeout:      3s

  Entries (6):
    Boot0008*  LamBoot                    /EFI/LamBoot/lambootx64.efi
    Boot0000*  ubuntu                     /EFI/ubuntu/shimx64.efi
    Boot0001   Windows Boot Manager       /EFI/Microsoft/Boot/bootmgfw.efi
    ...

  LamBoot NVRAM:
    State:           BootedOK
    Crash counter:   0
    Last success:    2026-04-22T14:00:00Z
```

With `--json`: emit the snapshot's JSON unmodified (pass-through).

---

## 7. List behavior

Enumerate `/var/backups/lamboot-backup-*.json`, sort by mtime desc, emit one finding per snapshot with metadata parsed from each file's header:

```json
{
  "id": "backup.list.snapshot",
  "context": {
    "path": "...",
    "timestamp": "...",
    "entry_count": 6,
    "age_days": 2
  }
}
```

Human output formats as a table.

---

## 8. Test plan

### 8.1 Unit tests (bats)

- `tests/backup-cli.bats` — CLI surface, JSON conformance, flag parsing
- `tests/backup-roundtrip.bats` — save + show parses correctly; restore is idempotent against its own snapshot

### 8.2 Integration tests (fixture disks)

- VM disk with OVMF_VARS.fd → `save --offline` extracts boot order
- Back up, change boot order, restore → original boot order reestablished
- Back up on Secure Boot on system → snapshot reflects SB state

### 8.3 Fleet matrix

Tier 1 VMs: each runs `save` + `show` + `restore` of its own snapshot; restore exits `EXIT_NOOP` since state hasn't changed.

---

## 9. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 on `save` + `show --json` + `list --json` + `restore --json`
- [ ] save default path under `/var/backups/lamboot-backup-*`
- [ ] restore prompts for confirmation unless --force; records actions
- [ ] `--offline DISK` works via virt-fw-vars or kernel-bootcfg
- [ ] Every warning+ finding has remediation
- [ ] bats tests pass
- [ ] Shellcheck clean

---

## 10. Deferred to v0.3+

- `--include-entries` for restore (device-path reconstruction)
- ESP content snapshot (separate `lamboot-esp snapshot` subcommand)
- Automated scheduled backup via systemd timer
- Encrypted snapshots (age / gpg integration)
- Differential snapshots (only-changes-since-last)

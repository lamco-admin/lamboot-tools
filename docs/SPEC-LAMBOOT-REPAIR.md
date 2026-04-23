# SPEC-LAMBOOT-REPAIR: Boot Repair Tool (Online + Offline)

**Version:** 1.0 (tool v1.0 target)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.1 entry for `lamboot-repair`
**Existing implementation:** `tools/lamboot-repair` v0.1.0 (637 lines, 2026-04-05)
**Gap-close target:** v0.2.0 (stable at toolkit v0.2)

---

## 1. Overview

`lamboot-repair` is the guided fix tool: diagnose issues, build a repair plan with risk tiers, show it to the user, execute with confirmation, verify afterward. The canonical implementation of the toolkit's six-phase mutating-operation flow (spec §4.7).

### 1.1 What this tool does

Six phases per invocation:

1. **Diagnose** — scan boot state (online from running system, or offline from unmounted disk)
2. **Plan** — compose a list of repair actions with per-action risk tier (safe / moderate / destructive)
3. **Show** — present the plan to the user with per-step descriptions
4. **Confirm** — require explicit user consent (bypass: `--auto` / `--yes`)
5. **Execute** — apply the plan, recording each action
6. **Verify** — re-run key checks; emit success/partial findings

### 1.2 Repair actions in v0.2

**Safe** (no data destruction; reversible):
- Mount an ESP that exists but isn't mounted
- Install fallback bootloader by copying existing `grubx64.efi`/`shimx64.efi`/`lambootx64.efi` to `EFI/BOOT/BOOTX64.EFI`
- Add missing ESP entry to `/etc/fstab` in UUID form
- Set BootOrder when unset
- Create a UEFI boot entry for an existing bootloader binary
- Enable `lamboot-mark-success.service`
- Reset LamBoot crash counter / state when in CrashLoop

**Moderate** (brief unmount, possible transient unavailability):
- Repair ESP filesystem with `fsck.fat -a` (unmount, repair, remount)

**Destructive** (v0.3+ only; not in v0.2 scope):
- Reformat ESP
- Recreate ESP partition

### 1.3 What this tool does NOT do

- Partition-table conversion (that's `lamboot-migrate`)
- Bootloader installation from scratch (that's the distro's native installer or `lamboot-install`)
- Signing-key management (that's `lamboot-signing-keys`)
- ESP content wipe / reformat (deferred to v0.3+)

### 1.4 Constraints

- Always requires root (repairs modify NVRAM / fstab / ESP)
- Every plan step includes a `risk` tier; moderate and destructive require explicit user acknowledgement
- Offline mode via `--offline DISK` (delegates to shared lib's `offline_setup`)
- Unified JSON schema v1 on `--json` output

---

## 2. CLI interface

```
lamboot-repair [OPTIONS]

Modes:
    (default)           Online — operate on running system
    --offline DISK      Offline — operate on unmounted disk or image

Options:
    --auto              Execute plan without interactive confirmation (implies --yes)
    --yes, -y           Answer yes to confirmation prompts
    --fix-fstab         Only run the fstab-repair actions; skip NVRAM changes
    --plan-only         Diagnose + show plan only; don't execute (same as --dry-run for this tool)
    --risk-limit LEVEL  Refuse to execute steps above this risk tier (safe|moderate|destructive)
    --json              Emit unified JSON output
```

Tool-specific flag: `--fix-fstab` is a scoped subset useful when called by sibling tools (`lamboot-diagnose` finding's remediation command).

### 2.1 Exit codes

- **0 EXIT_OK** — no issues found, or all planned fixes applied successfully
- **1 EXIT_ERROR** — diagnosis failed (missing prerequisites etc.)
- **2 EXIT_PARTIAL** — some fixes applied, some failed
- **3 EXIT_NOOP** — no issues found, nothing to fix
- **5 EXIT_ABORT** — user declined confirmation
- **7 EXIT_PREREQUISITE** — missing tools (efibootmgr, sgdisk) or no root

---

## 3. Diagnostic scope

Repair's diagnosis overlaps with `lamboot-diagnose` but only surfaces findings it can ACT on:

| Finding | Repair action |
|---|---|
| ESP exists but unmounted | `mount <dev> /boot/efi` |
| ESP filesystem issues | `fsck.fat -a` (moderate risk) |
| Missing fallback loader | Copy existing bootloader to `EFI/BOOT/BOOTX64.EFI` |
| Zero UEFI boot entries | Create entry via efibootmgr |
| BootOrder unset | Set to discovered entries list |
| ESP not in fstab | Append UUID= entry |
| LamBoot CrashLoop state | Reset counter + state |
| lamboot-mark-success.service disabled | `systemctl enable` |
| BLS entry kernel missing (informational) | Report only (can't recreate kernels) |

Findings that `lamboot-diagnose` reports but repair cannot fix are listed in the `unfixable` context field.

---

## 4. Plan model

Each plan step is an object with:

```json
{
  "id": "repair.action.unique_id",
  "description": "human-readable description",
  "command_preview": "the shell command that will execute",
  "risk": "safe|moderate|destructive",
  "reversible": true|false,
  "requires_backup": true|false
}
```

Steps with `requires_backup: true` are preceded by a `backup` action that records prior state to the run's backup directory.

### 4.1 Risk tiers

- **safe** — default. No data can be lost. Reversible by re-running with a different target state.
- **moderate** — brief service interruption (unmount). Data preserved. Reversible.
- **destructive** — data loss possible. Always requires typed-yes confirmation regardless of `--yes` / `--auto`.

`--risk-limit safe` refuses moderate and destructive steps (they're skipped with a warning finding).

---

## 5. Offline mode

`--offline DISK` invokes `offline_setup` from the shared library. Repair capabilities change:

Available offline:
- ESP filesystem check (`fsck.fat -n`; `-a` requires read-write mount)
- Fallback loader population
- BLS entry + boot-entry text repair
- Filesystem-level repairs via `fsck.fat -a` on the unmounted partition

Not available offline:
- UEFI boot entry (efibootmgr) operations — offline requires `virt-fw-vars` integration (deferred to v0.3+)
- Systemd service enablement (needs running system)
- LamBoot NVRAM state reset (same reason)

Offline-unsupported repairs are marked `status: skip` with rationale in the finding.

---

## 6. Findings

Per-step findings go into the unified JSON `findings[]` array. Per-action records go into `actions_taken[]`.

Example:

```json
{
  "findings": [
    {
      "id": "repair.esp.fallback_missing",
      "severity": "warning",
      "status": "fail",
      "title": "Fallback loader missing",
      "message": "/boot/efi/EFI/BOOT/BOOTX64.EFI not present",
      "remediation": {
        "summary": "Copy existing bootloader to fallback path",
        "command": "sudo lamboot-repair --auto",
        "doc_url": "..."
      }
    }
  ],
  "actions_taken": [
    {
      "action": "repair.fallback.install",
      "target": "/boot/efi/EFI/BOOT/BOOTX64.EFI",
      "result": "ok",
      "reversible": true,
      "details": {"source": "/boot/efi/EFI/debian/shimx64.efi"}
    }
  ]
}
```

---

## 7. Test plan

### 7.1 Unit tests (bats)

- `tests/repair-cli.bats` — CLI surface, help, JSON conformance, flag parsing, root refusal

### 7.2 Integration tests (fixture disks)

- `lamboot-installed.raw` minus BOOTX64.EFI → dry-run reports 1 fixable finding; apply installs it
- `no-esp.raw` → dry-run reports ESP-missing; no autofix (referrs user to `lamboot-migrate`)
- `grub-installed.raw` with no NVRAM entries → dry-run lists boot-entry creation

### 7.3 Fleet tier 1

Every VM runs `lamboot-repair --dry-run --json` post-setup; expected 0 issues. After intentionally breaking fstab (append `/dev/sda1` entry), `lamboot-repair --auto --yes` should heal it.

---

## 8. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 with findings[] + actions_taken[]
- [ ] Six-phase flow matches toolkit §4.7 canonical pattern
- [ ] Every plan step has a risk tier
- [ ] `--risk-limit` enforced at execution time
- [ ] Offline mode supported for ESP-level repairs
- [ ] `--dry-run` and `--plan-only` equivalent for this tool
- [ ] Every warning+ finding has remediation
- [ ] bats tests pass
- [ ] Shellcheck clean

---

## 9. Deferred to v0.3+

- `--offline DISK` NVRAM operations via virt-fw-vars
- Destructive repairs (ESP recreate, reformat)
- Rollback: record prior state, undo last repair run
- `--interactive` walk through each step with per-step y/N
- Integration with `lamboot-doctor` (doctor should delegate specific fixes to repair; dev not inverse)

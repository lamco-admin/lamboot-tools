# SPEC-LAMBOOT-PVE-SETUP: Per-VM LamBoot Integration Setup

**Version:** 1.0 (tool v0.2 target; maturity: **beta** at v0.2)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.2 entry for `lamboot-pve-setup`
**Related:** `~/lamboot-tools-dev/docs/PROXMOX-INTEGRATION-ROADMAP.md` (Phase 1)
**Package:** `lamboot-toolkit-pve` (companion, separate from core `lamboot-tools`)

---

## 1. Overview

`lamboot-pve-setup` performs the one-time per-VM setup that enables LamBoot integration on a Proxmox VE VM:

1. Sets `args:` in the VM config to reference a per-VM fw_cfg file
2. Attaches the `lamboot-hookscript.pl` as the VM's `hookscript:`
3. Writes the per-VM JSON at `/var/lib/lamboot/<VMID>.json` for initial state
4. Validates the rewritten hookscript (≥ 0.8.4) is installed on the host

The per-VM `args:` line is permanent and never modified by subsequent operations. Per-boot data injection happens via the hookscript rewriting `/var/lib/lamboot/<VMID>.json` at VM `pre-start` lifecycle.

### 1.1 What this tool does

- **`setup VMID`** — set up integration for one VM (idempotent)
- **`teardown VMID`** — remove integration for one VM
- **`check VMID`** — diagnose setup state for one VM (read-only)
- **`doctor-hookscript`** — verify the rewritten hookscript is present on the host

### 1.2 What this tool does NOT do

- Install LamBoot inside the guest (that's `lamboot-install` in the guest's own tarball)
- Manage the hookscript file itself (that's lamboot-dev's responsibility; this tool only *checks* its presence)
- Fleet-wide operations (that's `lamboot-pve-fleet`)
- Modify running VMs without explicit user-opt-in (always refuses by default; `--running-ok` accepts)

### 1.3 Constraints

- Host must be Proxmox VE (detected via `pvesh` or `/etc/pve/` directory)
- `qm` command must be available
- Rewritten `lamboot-hookscript.pl` (v0.8.4+) must be installed at `/usr/local/bin/lamboot-hookscript.pl` OR `/var/lib/vz/snippets/lamboot-hookscript.pl`
- Target VM must be `bios: ovmf` (not seabios) — will warn and refuse unless `--bios-override`
- Writes to `/var/lib/lamboot/` (created if missing, mode 0755)

---

## 2. CLI interface

```
lamboot-pve-setup [GLOBAL FLAGS] SUBCOMMAND [VMID] [OPTIONS]

Subcommands:
    setup VMID         Set up integration for VM
    teardown VMID      Remove integration
    check VMID         Diagnose setup state (read-only)
    doctor-hookscript  Verify hookscript is installed
    help [<sub>]

setup/teardown options:
    --role ROLE             Override role (default: from [roles] in fleet.toml or Proxmox tags)
    --fleet-id ID           Override fleet ID (default: from [fleet].id)
    --hookscript PATH       Override hookscript location
    --running-ok            Proceed on running VMs (changes take effect next boot)
    --bios-override         Set up even on non-OVMF VMs (not recommended)
```

### 2.1 Exit codes

- **0** success
- **2** partial (setup done but one sub-step warned)
- **3** noop (already set up)
- **4** unsafe (VM is running and `--running-ok` not set)
- **5** user aborted
- **6** not applicable (VM is BIOS/SeaBIOS)
- **7** prerequisite missing (qm absent, not on PVE host, hookscript missing)

---

## 3. Setup flow

1. **Preflight**
    - Verify running on Proxmox VE host (via `pvesh` or `/etc/pve/`)
    - Verify `qm` command is available
    - Verify target VMID exists (`qm list | grep VMID`)
    - Verify VM is not running (`qm status`) unless `--running-ok`
    - Verify hookscript is present and version ≥ 0.8.4 (parse version from hookscript file header)
    - Verify VM is OVMF (`qm config VMID | grep ^bios:`) unless `--bios-override`

2. **Plan**
    - Compute per-VM JSON contents from `/etc/lamboot/fleet.toml` + Proxmox tags
    - Check for existing `args:` line and existing `hookscript:` attachment
    - Emit a preview of changes

3. **Execute** (respects `--dry-run`)
    - Write `/var/lib/lamboot/<VMID>.json` with initial state
    - `qm set <VMID> --args '<existing args>-fw_cfg name=opt/lamboot/config,file=/var/lib/lamboot/<VMID>.json'` (appends to existing args, does NOT overwrite)
    - `qm set <VMID> --hookscript local:snippets/lamboot-hookscript.pl` (or configured location)

4. **Verify**
    - Re-read `qm config VMID`
    - Emit findings for each component present

### 3.1 Per-VM JSON format

```json
{
  "schema_version": "v1",
  "vmid": "100",
  "hostname": "pve-node-01",
  "fleet_id": "prod-cluster-01",
  "role": "webserver",
  "written_by": "lamboot-pve-setup 0.2.0",
  "written_at": "2026-04-22T14:37:22Z",
  "tags_at_setup": ["web", "nginx"]
}
```

LamBoot inside the VM reads this via fw_cfg at boot and uses `fleet_id` + `role` for display and boot-log enrichment.

### 3.2 Idempotency

`setup` is idempotent. Re-running:
- If `/var/lib/lamboot/<VMID>.json` is current → no-op (EXIT_NOOP=3)
- If args already contains the fw_cfg reference → skip args modification
- If hookscript already attached → skip

---

## 4. `args:` line handling

Proxmox `args:` is a single string concatenating all QEMU args. Setting it naively would clobber other users (SPICE enhancements, custom devices, etc.).

**Preserve-append strategy:**

1. Read existing `args:` via `qm config`
2. If existing value contains `-fw_cfg name=opt/lamboot/config` → already set up; skip
3. Append our `-fw_cfg name=opt/lamboot/config,file=/var/lib/lamboot/<VMID>.json` to existing
4. Write back via `qm set <VMID> --args '<preserved>-fw_cfg ...'`

`teardown` reverses: strip only our fw_cfg segment (regex-match `-fw_cfg name=opt/lamboot/config,file=[^ ]*`), preserving rest.

---

## 5. Hookscript verification

`doctor-hookscript` subcommand:

1. Search known locations: `/var/lib/vz/snippets/lamboot-hookscript.pl`, `/usr/local/bin/lamboot-hookscript.pl`, `/var/lib/lamboot/snippets/lamboot-hookscript.pl`
2. For each found: extract version from a `# version: X.Y.Z` header line
3. Compare against minimum required (`0.8.4` for fw_cfg file-reference-pattern fix)
4. Emit findings:
   - `pve.hookscript.present` (info): path + version
   - `pve.hookscript.missing` (critical): no hookscript found; user must install `lamboot-dev >= 0.8.4`
   - `pve.hookscript.outdated` (critical): hookscript present but version < 0.8.4; broken fw_cfg pattern

---

## 6. Test plan

### 6.1 Unit tests (bats)

- `tests/pve-setup-cli.bats` — CLI surface, help, JSON schema, flag parsing, error paths

### 6.2 Integration tests

- Mock Proxmox environment via fixture `/etc/pve/` tree + stub `qm` wrapper:
    - setup new VMID → args appended; json written; hookscript attached
    - setup already-set-up VMID → EXIT_NOOP
    - teardown → args stripped; hookscript optionally detached
    - setup with SeaBIOS VMID → EXIT_NOT_APPLICABLE
    - setup with missing hookscript → EXIT_PREREQUISITE

### 6.3 Live (Proxmox host)

Pending real Proxmox deployment (fleet-test matrix, Session O+).

---

## 7. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 on all subcommands
- [ ] `setup` is idempotent (re-running is no-op)
- [ ] `args:` line appended, not overwritten
- [ ] Per-VM JSON at `/var/lib/lamboot/<VMID>.json` with schema_version v1
- [ ] Hookscript version check against 0.8.4
- [ ] Refuses to operate on running VM without `--running-ok`
- [ ] Refuses SeaBIOS VMs without `--bios-override`
- [ ] bats tests pass with mocked `qm`
- [ ] Shellcheck clean

---

## 8. Deferred to v0.3+

- Auto-attach of `efidisk0` if missing (risky)
- Detection + repair of drifted args:/hookscript: lines
- Interactive wizard mode for first-time users
- Export CLI completion for Proxmox tag names as role argument values

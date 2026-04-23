# SPEC-LAMBOOT-PVE-FLEET: Fleet-Wide LamBoot Integration Manager

**Version:** 1.0 (tool v0.2 target; maturity: **experimental** at v0.2)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §3.2 entry for `lamboot-pve-fleet`
**Related:** Proxmox Integration Roadmap Phase 2
**Package:** `lamboot-toolkit-pve`

---

## 1. Overview

`lamboot-pve-fleet` is the batch-operation companion to `lamboot-pve-setup`. It reads `/etc/lamboot/fleet.toml` + Proxmox's VM inventory and performs setup / status / reporting across many VMs in one command.

Uses `lamboot-pve-setup` under the hood for each VM — this tool is pure orchestration, no per-VM mechanism.

### 1.1 What this tool does

- **`inventory`** — list all OVMF VMs + their current LamBoot integration state
- **`setup --all`** — setup on every VMID matching a filter (default: all OVMF VMs)
- **`status`** — fleet-wide health summary (read-only)
- **`report`** — structured JSON report for external consumers (monitoring, dashboards)

### 1.2 What this tool does NOT do

- Per-VM setup mechanics (delegates to `lamboot-pve-setup`)
- NVRAM health polling (that's `lamboot-pve-monitor`)
- OVMF vars building (that's `lamboot-pve-ovmf-vars`)
- Direct NVRAM writes or firmware modifications

### 1.3 Constraints

- Same as `lamboot-pve-setup`: Proxmox VE host, `qm` available, hookscript installed
- `/etc/lamboot/fleet.toml` may be absent — tool uses defaults and warns
- Parallel execution is SERIAL in v0.2 (safety; parallel deferred to v0.3+)

---

## 2. CLI interface

```
lamboot-pve-fleet [GLOBAL FLAGS] SUBCOMMAND [OPTIONS]

Subcommands:
    inventory [--json]                  List all OVMF VMs + integration state
    setup --all [--tag TAG]...          Setup on every matching VM
    setup --vmid VMID [--vmid VMID]...  Setup on specific VMIDs
    status [--json]                     Fleet-wide health summary
    report [--json]                     Structured JSON report
    help [<sub>]

Options:
    --tag TAG          Filter to VMs with matching Proxmox tag (repeatable)
    --vmid VMID        Specific VMID (repeatable; overrides --all)
    --exclude VMID     Exclude specific VMIDs (repeatable)
    --config PATH      Override fleet config (default: /etc/lamboot/fleet.toml)
    --running-ok       Pass --running-ok to each per-VM setup
    --continue-on-error  Don't stop on first failure; report at end
```

### 2.1 Exit codes

- **0** all operations succeeded
- **2** partial (some succeeded, some failed)
- **3** noop (no matching VMs)
- **7** prerequisite missing

---

## 3. Inventory subcommand

Enumerates every OVMF VM on the host:

1. `qm list` — get VMIDs
2. For each VMID: `qm config VMID` → extract `bios`, `tags`, `args`, `hookscript`
3. Parse for LamBoot integration state:
   - `has_fw_cfg`: args contains `-fw_cfg name=opt/lamboot/config`
   - `has_hookscript`: hookscript references `lamboot-hookscript.pl`
   - `has_json_file`: `/var/lib/lamboot/<VMID>.json` exists
   - State: `full` | `partial` | `not_set_up` | `not_applicable` (BIOS)
4. Emit one finding per VM: `fleet.vm.<VMID>.integration` with state enum
5. Emit summary finding: `fleet.inventory.summary` with totals by state

---

## 4. Fleet setup subcommand

`setup --all` flow:

1. Read fleet.toml (warn if missing)
2. Inventory VMs
3. Apply filters: `--tag`, `--exclude`, `--vmid`
4. For each filtered VM:
   - Skip if BIOS (or `--bios-override` in fleet.toml `[defaults]`)
   - Skip if running (unless `--running-ok`)
   - Skip if already fully set up
   - Otherwise invoke `lamboot-pve-setup setup VMID <flags>` (serial in v0.2)
   - Record result
5. Summary: N succeeded, M failed, K skipped

With `--continue-on-error` (default: set), one failure doesn't abort the batch.

---

## 5. Fleet.toml schema (§16 Appendix C of toolkit spec)

```toml
schema_version = 1

[fleet]
id = "prod-cluster-01"
cluster_name = "Production Cluster 1"

[roles]
"100" = "webserver"
"101" = "database"

[tags]
webserver = ["web", "nginx", "apache"]
database = ["db", "postgres"]

[monitor]
poll_interval_seconds = 300
alert_webhook = "https://hooks.lamco.io/fleet-alert"

[hookscript]
config_dir = "/var/lib/lamboot"
inject_fleet_id = true
inject_role = true
```

v0.2 consumes: `[fleet]`, `[roles]`, `[tags]`, and (for `status` post-monitor-integration in v0.3+) `[monitor]`.

Parsing: bash grep-based (no external TOML parser); tolerates unknown keys; rejects on schema_version mismatch.

---

## 6. Status subcommand

Human output:

```
Fleet: prod-cluster-01 (17 VMs)

Integration state:
  Fully set up:       12
  Partially set up:    1
  Not set up:          3
  Not applicable:      1 (BIOS)

Role distribution:
  webserver:  7
  database:   3
  loadbalancer:  2
  (untagged): 4

Recent issues (via lamboot-pve-monitor):
  VM 103 (webserver): crash counter at 2 [last 24h]
  VM 117 (database): state=Booting for 4h [stuck?]
```

JSON output: one finding per state bucket + one per-VM detail finding.

---

## 7. Report subcommand

Produces a machine-consumable JSON envelope for external tools (Grafana, Prometheus pushgateway, Splunk, etc.) combining:

- Per-VM: integration state, role, tags, last boot status (from NVRAM if readable)
- Fleet totals
- Timestamp + host

Schema adds a `report` section to the standard toolkit envelope. Consumers should subscribe to the toolkit schema v1 stability contract.

---

## 8. Test plan

### 8.1 Unit tests (bats)

- `tests/pve-fleet-cli.bats` — CLI surface, help, JSON schema, fleet.toml parsing, filter logic

### 8.2 Integration tests (mocked qm)

- Inventory with 0 VMs → empty summary
- Setup --all against 3-VM mock → serial invocation of pve-setup
- Setup with `--tag webserver` → only tagged VMs processed

### 8.3 Live Proxmox

Deferred to Session O+ fleet-test matrix.

---

## 9. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] Unified JSON schema v1 on all subcommands
- [ ] Invokes `lamboot-pve-setup` for per-VM operations (no duplicate mechanism)
- [ ] Reads fleet.toml with tolerant parser
- [ ] Filters `--tag`, `--exclude`, `--vmid` work correctly
- [ ] `--continue-on-error` gives useful partial results
- [ ] bats tests pass with mocked qm
- [ ] Shellcheck clean

---

## 10. Deferred to v0.3+

- Parallel per-VM setup (xargs -P or GNU parallel)
- `setup --auto-fix` — repair drifted integration state
- Scheduled fleet audit via systemd timer
- Integration with `lamboot-pve-monitor` for live health in `status` output
- CSV / Prometheus text-format output modes
- Cluster-wide coordination (multi-node Proxmox clusters)

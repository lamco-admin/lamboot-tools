# LamBoot Proxmox Integration Roadmap

**Updated:** 2026-04-05

---

## Vision

A Proxmox admin installs a host-side component once. From then on, every VM with LamBoot installed automatically receives its identity, fleet metadata, and boot health monitoring — no per-VM manual configuration, no `qm set --args` strings.

This integration grows in phases, from basic VMID display through fleet health dashboards.

---

## Architecture

### The fw_cfg File-Reference Pattern

The core mechanism is QEMU's fw_cfg device with file references:

```
INSTALL TIME (once per VM):
  lamboot-setup VMID
    → qm set VMID --args '-fw_cfg name=opt/lamboot/config,file=/var/lib/lamboot/VMID.json'
    → qm set VMID --hookscript local:snippets/lamboot-hookscript.pl

EVERY BOOT (automatic):
  Hookscript pre-start:
    → Writes /var/lib/lamboot/VMID.json with:
      {"vmid":"100","node":"pve","fleet_id":"prod","role":"webserver"}
  
  QEMU starts:
    → Reads /var/lib/lamboot/VMID.json into fw_cfg device
  
  LamBoot boots:
    → fw_cfg::read_file_string("opt/lamboot/config") → JSON
    → Parses VMID, fleet ID, role
    → Displays in GUI header, includes in boot report
```

**Why this pattern works:**
- `file=` is resolved when QEMU starts, not when args are parsed
- Hookscript can write to any host file (no config lock issue)
- The `args:` line is set once and never changes
- LamBoot already has a complete fw_cfg reader (`fw_cfg.rs`)
- Validated by other projects (Flatcar Ignition uses same approach)

### Why Not Other Mechanisms

| Mechanism | UEFI boot time? | Proxmox native? | Practical? | Verdict |
|-----------|-----------------|-----------------|------------|---------|
| **fw_cfg** | Yes | No (needs `args`) | Yes — already implemented | **Recommended** |
| **SMBIOS Type 11** | Yes | No (needs `args`) | Yes — static only | Fallback for non-hookscript setups |
| **virtio-serial** | Partial (OVMF driver exists) | No | No — requires full virtio transport in UEFI | Too complex |
| **QEMU Guest Agent** | No — OS only | Yes | No — not available at boot | OS-level only |
| **vsock** | No — needs kernel | No | No | OS-level only |
| **cloud-init NoCloud** | Partial (ISO on SCSI) | Yes — native GUI | No — needs ISO9660 + YAML parser | Excessive for config injection |
| **Hookscript `qm set`** | N/A | Yes | **Broken** — config locked during hookscript | Does not work |

### Known Issue: Current Hookscript

The hookscript in `lamboot-hookscript.pl` calls `qm set` during `pre-start` to inject VMID. **This does not work** — Proxmox locks the VM config during hookscript execution. `qm set` times out trying to acquire the lock.

**Fix**: Rewrite to use the fw_cfg file-reference pattern. The hookscript writes a JSON file; the permanent `args:` line references it.

---

## Phase 1: Basic Integration (Current)

**What works today:**
- LamBoot reads fw_cfg (`opt/lamboot/config`) and SMBIOS OEM strings at boot
- VMID, fleet-id displayed in GUI header and boot report
- Boot health written to NVRAM (crash counter, boot state)
- `lamboot-monitor.py` reads NVRAM from host side

**What's broken:**
- Hookscript VMID injection via `qm set` (config lock)
- Per-VM setup requires manual `qm set --args` with exact syntax
- `args:` conflicts with other uses (e.g., D-Bus display for RDP)

**Deliverables for Phase 1 fix:**
- [ ] `lamboot-setup` script — one-time per-VM setup (sets args + hookscript)
- [ ] Rewrite hookscript to use fw_cfg file-reference pattern
- [ ] LamBoot: parse JSON from fw_cfg config blob (currently reads raw string)
- [ ] Handle `args:` append (don't overwrite existing args)
- [ ] Documentation updates

---

## Phase 2: Fleet Management

**Goal:** Manage LamBoot across many VMs from a single point.

**Deliverables:**
- [ ] `lamboot-fleet` tool — batch setup, status, and monitoring across VMs
  - `lamboot-fleet setup --all` — enable LamBoot integration for all OVMF VMs
  - `lamboot-fleet status` — boot health summary for all VMs
  - `lamboot-fleet report` — JSON fleet health report
- [ ] Central fleet config at `/etc/lamboot/fleet.toml` — defines fleet-id, roles, alert endpoints
- [ ] Hookscript reads fleet config and injects per-VM context (VMID from Proxmox, role from tags, fleet-id from central config)
- [ ] `lamboot-monitor.py` enhanced for fleet-wide health aggregation
- [ ] Systemd timer for periodic health polling + webhook alerts

---

## Phase 3: Proxmox Native Option

**Goal:** A native `lamboot` config option in Proxmox, similar to `spice_enhancements`.

**How `spice_enhancements` works (the model to follow):**
```perl
# In QemuServer.pm:
# 1. Declare the option schema
'spice_enhancements' => {
    type => 'string',
    format => {
        foldersharing => { type => 'boolean', optional => 1 },
        videostreaming => { type => 'string', enum => ['off','all','filter'], optional => 1 },
    },
},

# 2. In config_to_command(), translate to QEMU args
if (my $spice = $conf->{spice_enhancements}) {
    # Parse and add -device virtio-serial, -chardev spicevmc, etc.
}
```

**What a `lamboot` option would look like:**
```
qm set 100 --lamboot vmid=auto,fleet=prod-cluster-01,role=webserver,monitor=true
```

Proxmox would translate this to:
- `-fw_cfg name=opt/lamboot/config,file=/var/lib/lamboot/100.json`
- Hookscript attachment (automatic)
- NVRAM monitoring timer (automatic)

**Implementation path:**
- Option A: **Proxmox upstream patch** — submit to `pve-qemu-server` on `git.proxmox.com`. Requires Proxmox team buy-in. Aligns with their stated interest in IronRDP/QEMU display integration.
- Option B: **PVE API plugin** — Proxmox 8+ supports API plugins via Perl packages. Could add `/api2/json/nodes/{node}/qemu/{vmid}/lamboot` endpoints without patching core. Less invasive.
- Option C: **Custom pve-qemu-server package** — fork QemuServer.pm, add the option, distribute as a replacement package. Fragile across Proxmox upgrades.

**Recommendation:** Start with Option B (API plugin) as a proving ground. If adoption warrants it, propose Option A upstream.

---

## Phase 4: Web UI Dashboard

**Goal:** Boot health visible in the Proxmox web interface.

**Options:**
- **PVE Panel Plugin** — JavaScript plugin that adds a "Boot Health" tab to VM detail view. Shows crash counter, last boot state, boot timing, entry history.
- **Standalone Dashboard** — Separate web app (or Grafana dashboard) that polls `lamboot-monitor.py` output. Lower integration but works with any PVE version.
- **API-driven** — Phase 3's API plugin provides the data; the web UI panel just visualizes it.

**Data available for display:**
- Boot state (Fresh/Booting/BootedOK/CrashLoop)
- Crash counter and threshold
- Last booted entry (kernel version)
- Boot timing per phase (health, drivers, discovery, total)
- VMID, fleet-id, hypervisor, IOMMU status
- Historical boot audit log

---

## Phase 5: Advanced Integration

Longer-term ideas that build on the monitoring infrastructure:

- **Automated rollback** — if crash loop detected, host-side tooling auto-selects a known-good kernel via NVRAM manipulation (using `lamboot-repair --offline`)
- **Pre-boot network agent** — LamBoot connects to host via fw_cfg or virtio-serial for remote management commands (Phase D from bootloader roadmap)
- **Template auto-configuration** — when cloning a VM template, the clone hookscript auto-configures LamBoot with the new VMID and fleet role
- **Integration with lamco-rdp** — boot health data available via the RDP console, boot screen accessible via RDP before OS starts (requires QEMU D-Bus display integration)

---

## Component Inventory

| Component | Location | Language | Purpose |
|-----------|----------|----------|---------|
| `lamboot-setup` | lamboot-tools | bash | One-time per-VM setup (args + hookscript) |
| `lamboot-hookscript.pl` | lamboot-dev/tools | Perl | VM lifecycle hooks (pre-start config injection, post-stop health capture) |
| `lamboot-monitor.py` | lamboot-dev/tools | Python | Host-side NVRAM health reader |
| `lamboot-fleet` | lamboot-tools | bash/Python | Fleet-wide management and reporting |
| PVE API plugin | new repo | Perl | Native Proxmox API integration (Phase 3) |
| PVE panel plugin | new repo | JavaScript | Web UI dashboard (Phase 4) |

---

## Relationship to lamco-rdp

The Proxmox integration roadmap intersects with lamco-rdp at several points:

1. **`args:` line conflicts** — both LamBoot (fw_cfg) and lamco-qemu-rdp (D-Bus display) need `args:`. The native Proxmox option (Phase 3) would resolve this by managing args internally.
2. **Boot screen via RDP** — QEMU's D-Bus display exposes the GOP framebuffer, including LamBoot's GUI. An RDP client connected via D-Bus display would see the boot menu before the OS starts.
3. **Shared monitoring** — boot health and RDP session health could share a monitoring framework.
4. **Proxmox upstream engagement** — both LamBoot and lamco-rdp benefit from native Proxmox support. The Proxmox team (Thomas Lamprecht) has expressed interest in IronRDP for SPICE replacement. LamBoot integration could be part of that conversation.

---

## See Also

- [LamBoot ROADMAP.md](https://github.com/lamco-admin/lamboot-dev/blob/main/docs/ROADMAP.md) — bootloader roadmap
- [LamBoot Proxmox Guide](https://github.com/lamco-admin/lamboot-dev/blob/main/docs/PROXMOX-GUIDE.md) — current integration docs
- [LamBoot Architecture](https://github.com/lamco-admin/lamboot-dev/blob/main/docs/ARCHITECTURE.md) — fw_cfg and SMBIOS internals

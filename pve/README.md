# lamboot-toolkit-pve — Proxmox VE host-side subpackage

This subtree holds the Proxmox VE host-side tools. They are part of the
same `lamboot-tools` repository and ship as the `lamboot-toolkit-pve`
RPM subpackage alongside `lamboot-tools` and `lamboot-migrate` (all
three built from one `packaging/rpm/lamboot-tools.spec`).

## Tools

| Tool | Source | Status at v0.2 |
|---|---|---|
| `lamboot-pve-setup` | authored here | beta |
| `lamboot-pve-fleet` | authored here | experimental |
| `lamboot-pve-monitor` | mirrored from `~/lamboot-dev/tools/lamboot-monitor.py` via `publish/mirror-pve-from-lamboot-dev.sh` | stable (canonical = lamboot-dev) |
| `lamboot-pve-ovmf-vars` | mirrored from `~/lamboot-dev/tools/build-ovmf-vars.sh` via `publish/mirror-pve-from-lamboot-dev.sh` | stable (canonical = lamboot-dev) |

## Shared config: `/etc/lamboot/fleet.toml`

Schema defined in `docs/SPEC-LAMBOOT-TOOLKIT-V1.md` §16 Appendix C.
Consumed by three tools across two repos:

- `lamboot-pve-setup` (this subtree) — reads `[fleet]`, `[roles]`, `[tags]`
- `lamboot-pve-fleet` (this subtree) — reads `[fleet]`, `[roles]`, `[tags]`, `[monitor]`
- `lamboot-hookscript.pl` (lamboot-dev) — reads `[hookscript]`

## Cross-repo dependency

`lamboot-pve-setup` requires `lamboot-dev >= 0.8.4` for the rewritten
fw_cfg file-reference-pattern hookscript. Installation checks for the
hookscript's presence and version; refuses to proceed if missing.
See `docs/CROSS-REPO-STATUS.md` for coordination status.

## Tools inherit

- Shared library from `lamboot-tools` (same `lamboot-toolkit-lib.sh` +
  `lamboot-toolkit-help.sh`)
- Unified JSON schema v1
- Universal flags from toolkit spec §4.1
- Exit codes from toolkit spec §4.3

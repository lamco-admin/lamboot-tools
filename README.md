# lamboot-tools

The Linux UEFI boot toolkit — a suite of standalone CLI tools for boot
diagnosis, ESP management, backup, repair, migration, UKI building, and
Secure Boot key handling. Companion to [LamBoot](https://lamco.ai/products/lamboot/),
but every tool works on any UEFI Linux system regardless of which
bootloader is installed.

The tools orchestrate existing Linux utilities (efibootmgr, sgdisk,
dosfstools, virt-fw-vars, kernel-bootcfg, sbsign) and add diagnostic
intelligence, migration automation, and self-guided troubleshooting. No
runtime dependency on a specific bootloader.

## Tools

Install `lamboot-tools` for the core suite; `lamboot-toolkit-pve` adds
the Proxmox VE companion tools.

### Core

| Tool | Purpose |
|---|---|
| `lamboot-diagnose` | Read-only scan of the UEFI boot chain across 11 categories, with remediation commands |
| `lamboot-esp` | ESP health check, inventory, stale-file cleanup, and (offline) deploy |
| `lamboot-nvram` | UEFI boot-entry (`Boot####`/`BootOrder`) inventory, dead-entry cleanup, and restore — online or against an offline OVMF VARS image |
| `lamboot-backup` | Save / restore / show / list UEFI boot-config snapshots (NVRAM, boot order, Secure Boot state) |
| `lamboot-repair` | Diagnose-plan-confirm-execute-verify boot repair, online or against an offline disk |
| `lamboot-migrate` | BIOS→UEFI conversion, cross-bootloader migration, post-conversion verification, rollback |
| `lamboot-doctor` | Guided wrapper: chains diagnose → policy → repair / esp-clean |
| `lamboot-uki-build` | Build / inspect / sign / verify Unified Kernel Images |
| `lamboot-signing-keys` | Secure Boot key lifecycle: generate, rotate, inspect, MOK enroll, OVMF VARS, release-eng signing |
| `lamboot-inspect` | LamBoot-specific deep introspection of boot.json / trust log artefacts |
| `lamboot-toolkit` | Dispatcher: `status`, `help`, `run`, `version`, `verify` across the suite |

### Proxmox VE companion (`lamboot-toolkit-pve`)

| Tool | Purpose |
|---|---|
| `lamboot-pve-setup` | Per-VM LamBoot integration setup on a Proxmox host |
| `lamboot-pve-fleet` | Fleet-wide inventory, setup, and reporting |
| `lamboot-pve-migrate` | Host-side BIOS→UEFI migration lifecycle for Proxmox guests (snapshot, convert, verify, rollback) |
| `lamboot-pve-monitor` | Host-side reader of guest NVRAM boot-health state |
| `lamboot-pve-ovmf-vars` | Build OVMF_VARS.fd with a cert pre-enrolled in db |

Start with `lamboot-toolkit status` to see what's installed, or
`<tool> --help` for any tool.

## Versioning

lamboot-tools uses a **hybrid** version model: a unified toolkit umbrella
version bundles per-tool semantic versions. Each tool reports both via
`--version`:

```
$ lamboot-diagnose --version
lamboot-diagnose 0.7.3 (lamboot-tools 0.9.1)
```

The umbrella version (`lamboot-tools X.Y.Z`) is the release tag; a tool's
own version bumps when that tool changes. The JSON output schema carries
its own independent `schema_version` (currently `v1`).

## Common interface

Every tool shares one command shape and flag set:

```
<tool> [GLOBAL FLAGS] [SUBCOMMAND] [ARGS]
```

**Universal flags** (accepted by every tool and subcommand):

| Flag | Effect |
|---|---|
| `--help`, `-h` | Show help (suite help, or per-subcommand) |
| `--version` | Print tool + toolkit version |
| `--json` | Emit unified JSON output (schema v1) |
| `--json-schema` | Print the JSON schema the tool emits |
| `--verbose`, `-v` | Informational output beyond the default |
| `--quiet`, `-q` | Only warnings and errors |
| `--no-color` | Disable ANSI color (auto on non-TTY; honors `NO_COLOR`) |
| `--dry-run` | Print planned actions without executing |
| `--yes`, `-y` | Answer yes to interactive prompts |
| `--force` | Skip safety checks (per-subcommand semantics) |
| `--auto` | Non-interactive full automation (implies `--yes`) |
| `--offline DISK` | Operate on an unmounted disk or image |
| `--suggest-next-command` | Print the recommended follow-up command |

**Exit codes** (uniform across the suite, protocol v1):

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Fatal error |
| 2 | Partial — some operations succeeded, some failed |
| 3 | Nothing to do — already in the requested state |
| 4 | Refused due to a safety check |
| 5 | User declined an interactive confirmation |
| 6 | Operation does not apply to this system |
| 7 | A required tool or capability is missing |

## Subcommands at a glance

```
lamboot-diagnose      scan
lamboot-esp           check · inventory · clean · deploy
lamboot-nvram         inventory · clean · restore
lamboot-backup        save · restore · show · list
lamboot-repair        repair
lamboot-doctor        check
lamboot-migrate       to-uefi · to-lamboot · verify · rollback · status
lamboot-uki-build     build · inspect · sign · verify
lamboot-signing-keys  generate · rotate · inspect · status · mok-enroll ·
                      mok-list · mok-delete · ovmf-vars ·
                      generate-hierarchy · sign-binary
lamboot-toolkit       status · help · run · version · verify
```

Each subcommand documents its own arguments via `<tool> <subcommand>
--help` and in the per-tool man page.

## Quick start

```bash
sudo make install            # install the core suite

lamboot-toolkit status       # list installed tools + versions
sudo lamboot-diagnose        # full boot-chain scan
sudo lamboot-esp check       # ESP health
sudo lamboot-backup save     # snapshot boot config before changes
sudo lamboot-doctor          # guided diagnose → repair
```

## Requirements

- bash 4.0+ (associative arrays)
- GNU coreutils or Rust uutils/coreutils
- util-linux (findmnt, lsblk, blkid, mountpoint)
- efibootmgr

**Optional**, per tool:
- dosfstools — ESP filesystem check (`lamboot-esp`)
- gdisk/sgdisk — partition-table conversion (`lamboot-migrate`)
- virt-fw-vars or kernel-bootcfg — offline VM NVRAM (`lamboot-backup`, `lamboot-repair`)
- qemu-nbd — offline VM disk access (`lamboot-repair`)
- sbsign / sbverify — UKI + key signing (`lamboot-uki-build`, `lamboot-signing-keys`)

## Installation

```bash
git clone https://github.com/lamco-admin/lamboot-tools.git
cd lamboot-tools
sudo make install            # core suite + man pages
sudo make install-pve        # optional: Proxmox VE companion
sudo make uninstall
```

## Documentation

- **Website:** <https://lamco.ai/products/lamboot-tools/>
- **Install / download:** <https://github.com/lamco-admin/lamboot-tools/releases> (signed release tarball)
- **Repository:** <https://github.com/lamco-admin/lamboot-tools>
- Per-tool man pages: `man lamboot-diagnose`, `man lamboot-tools` (suite overview), `man lamboot-tools-schema` (JSON schema)

## Related

- [LamBoot](https://lamco.ai/products/lamboot/) — the memory-safe UEFI bootloader. The tools are bootloader-agnostic; LamBoot is the reference target.

## About

lamboot-tools is developed by **Lamco Development LLC** (<https://lamco.ai/about/>) and is licensed under **MIT OR Apache-2.0**.

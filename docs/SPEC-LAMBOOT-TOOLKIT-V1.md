# SPEC-LAMBOOT-TOOLKIT-V1: The LamBoot Tools Product Specification

**Version:** 1.0 (spec target)
**Date:** 2026-04-22
**Status:** Ready for founder review → implementation
**Authoring repo:** `lamco-admin/lamboot-tools-dev` (private)
**Public release target:** `lamco-admin/lamboot-tools` (tarball + distro packages)
**PVE subtree:** `pve/` within this repo — ships as the `lamboot-toolkit-pve` RPM subpackage (single source tree per founder decision 2026-04-22; no separate dev or public repo)
**Sibling spec:** `~/lamboot-dev/docs/specs/SPEC-LAMBOOT-MIGRATE.md` (SDS-7, tool-level)
**Session origin:** `~/lamboot-dev/docs/STATUS-2026-04-22-TOOLKIT-PIVOT.md` §5 Session A

---

## Table of Contents

1. Vision, tagline, audience
2. Product scope — what's in, what's out, what's deferred
3. Tool inventory + roles
4. CLI contracts
5. Data contracts
6. Shared architecture
7. Distribution + packaging
8. Versioning + release cadence
9. Quality bar for publication
10. Documentation plan
11. Ecosystem integration
12. Release roadmap (v0.2 → v0.5 → v1.0)
13. Claims appendix + marketing discipline
14. Cross-repo coordination
15. Open questions + deferred decisions
16. Appendices

---

## 1. Vision, tagline, audience

### 1.1 Tagline

> **The Linux UEFI boot toolkit.**

Genre-defining. Does not lead with LamBoot authorship. LamBoot branding is established in the second paragraph of any README, on the landing page, and in every tool's `--version` output.

### 1.2 Positioning statement

`lamboot-tools` is a comprehensive CLI suite for diagnosing, repairing, migrating, and maintaining UEFI boot configurations on Linux systems. Built by the authors of LamBoot; works on any Linux UEFI system regardless of which bootloader it uses.

The toolkit's identity is **ecosystem infrastructure**. It happens to have LamBoot-specific subcommands — `lamboot-migrate to-lamboot`, the `lamboot-inspect` deep-diagnostic — but its daily utility is bootloader-agnostic: ESP health, boot chain diagnostics, repair workflows, configuration backup, BIOS→UEFI migration.

### 1.3 Audience

Primary audience for README and marketing copy, in order:

1. **Linux sysadmin with a broken boot** — task-oriented. README leads with "Your system won't boot? Start here." Sample `lamboot-diagnose` output follows immediately.
2. **Linux user discovering us via search** — capability-oriented. The feature list is structured to be findable for queries like "bios to uefi tool", "repair esp", "ubuntu boot diagnostics".
3. **Proxmox VE operator / fleet admin** — scenario-oriented. Prominent callout of offline-VM-disk capabilities: diagnose, repair, and migrate VM disks from the Proxmox host without booting the VM.
4. **LamBoot user** — served implicitly by #1–3 plus explicit `lamboot-inspect` deep inspection and `lamboot-migrate to-lamboot` migration paths.

The toolkit serves non-LamBoot users as first-class citizens. LamBoot-specific workflows are prominent but never the default presentation.

### 1.4 Bootloader ecosystem stance — active reach

GRUB, systemd-boot, rEFInd, Limine, and other UEFI bootloaders are treated as first-class diagnostic and repair targets. The toolkit's checks recognize, classify, and report on all of them with equal fidelity. LamBoot is not privileged in diagnostic output — its installation is reported as one possible bootloader, not a recommended outcome.

LamBoot is surfaced honestly when a migration path is relevant: `lamboot-migrate to-lamboot` is a called-out conversion option alongside keeping the existing bootloader. Repair suggestions reference the user's current bootloader, not a push toward LamBoot.

This active-reach stance is load-bearing: it is what earns the toolkit credibility as a diagnostic suite rather than a brand-expansion vehicle.

### 1.5 CLI-only, permanent

Every tool in the suite is CLI. The toolkit will never ship a GUI. Future UI integrations (Proxmox web-UI dashboard, remote management consoles) consume the toolkit's unified JSON output (§5) as an integration surface but are separate products built by separate teams with separate release cadences.

This stance is durable, not temporal. A reader encountering the toolkit in 2028 or 2030 should find the CLI-only choice still in force.

---

## 2. Product scope

### 2.1 In scope for v0.2 (initial publishable release)

- **Core toolkit** (`lamboot-tools` package, 10 tools)
  - `lamboot-diagnose` — generic UEFI boot diagnostic scanner
  - `lamboot-esp` — ESP filesystem health + inventory + cleanup
  - `lamboot-backup` — UEFI boot config backup + restore
  - `lamboot-repair` — online and offline boot repair with diagnose→plan→confirm→execute→verify flow
  - `lamboot-migrate` — BIOS→UEFI conversion and cross-bootloader migration (SDS-7 `lamboot-migrate` v1.0)
  - `lamboot-doctor` — guided diagnose→repair→verify wrapper (beta)
  - `lamboot-toolkit` — suite dispatcher + unified entry point
  - `lamboot-inspect` — LamBoot-specific deep introspection (Python; mirror from lamboot-dev)
  - `lamboot-uki-build` — host-side Unified Kernel Image builder (beta)
  - `lamboot-signing-keys` — Secure Boot key lifecycle tool (experimental)
- **Proxmox companion** (`lamboot-toolkit-pve` package, 4 tools)
  - `lamboot-pve-setup` — per-VM LamBoot integration setup
  - `lamboot-pve-fleet` — fleet-wide inventory, setup, status, reporting
  - `lamboot-pve-monitor` — host-side NVRAM health reader (Python; mirror from lamboot-dev)
  - `lamboot-pve-ovmf-vars` — OVMF VARS builder with key pre-enrollment (mirror from lamboot-dev)
- **Shared infrastructure**
  - Sourced shared library `/usr/lib/lamboot-tools/lamboot-toolkit-lib.sh` + inlined-build path for single-file portability
  - Unified JSON output schema (§5) across every tool
  - Unified help registry driving `--help`, `help <cmd>`, man pages (§10)
  - Shared offline-mode scaffolding (`--offline DISK` uniformly supported except `lamboot-migrate`)
  - bats-core test harness + fixture disk images
  - GitHub Actions CI + pre-commit hooks
- **Three-surface documentation**
  - Extremely robust inline help via the shared registry
  - Full man-page set (`lamboot-tools(7)` + `lamboot-<tool>(1)` per tool)
  - Full website documentation at `lamboot.dev/tools`
- **Packaging**
  - Release tarball (primary)
  - Fedora Copr (v0.2 hard requirement)
  - `lamboot-migrate` dual-published as `lamboot-tools`-subset tarball + standalone `lamboot-migrate` distro package
  - LamBoot tarball ships opt-in installer prompt recommending the toolkit

### 2.2 In scope for v0.3–v1.0

- Ubuntu/Debian PPA; opt-in Homebrew tap
- Debian upstream submission for `lamboot-migrate` (standalone)
- Homebrew tap for Linux-fleet admins running from macOS
- Proxmox companion Phase 2+ (the Proxmox roadmap's Phase 2 tooling maturing to stable)
- `lamboot-signing-keys` maturing from experimental to stable
- `lamboot-uki-build` maturing from beta to stable

### 2.3 Explicitly out of scope, permanent

- **GUI in any form.** Web dashboards consuming the JSON schema are a different product.
- **bootloader-agnostic tools unrelated to UEFI Linux.** The toolkit's remit is UEFI Linux boot management. It will not grow into a generic Linux-admin swiss-army.
- **Tools that duplicate LamBoot tarball contents.** Bootloader installation (`lamboot-install`), key signing for Lamco releases (`sign-lamboot.sh`), and similar release-engineering infrastructure stay in `lamboot-dev` and never migrate to the toolkit.
- **Windows, macOS, or BSD target support.** Linux UEFI only.
- **Interactive ncurses / dialog-based UIs inside tools.** All interaction is stdin/stdout prompts or fully-flag-driven.
- **Telemetry, phone-home, or network connections from any tool** unless explicitly required by the tool's core function (none are in v0.2).

### 2.4 Explicitly deferred

- **Secure Boot key lifecycle (Scope 3 — both release-eng AND user-facing).** `lamboot-signing-keys` ships experimental at v0.2 with initial framework; full stable coverage is v0.5 target. See §12.
- **`lamboot-doctor` auto-fix policy breadth.** Ships beta at v0.2 with conservative default-action policy (§6.7); expanded policy at v0.3.
- **`lamboot-migrate --offline DISK`.** Not a v0.2 deliverable; deferred to v0.3+.
- **Proxmox companion Phase 3 (native PVE option like `spice_enhancements`).** Requires Proxmox upstream engagement. v1.0+ target.
- **Proxmox companion Phase 4 (web UI panel plugin).** Separate product; not toolkit-internal.
- **Snap/Flatpak packaging.** These tools need host device access that sandboxes obstruct. Not a fit.
- **Other hypervisor companions** (`lamboot-toolkit-nutanix`, `lamboot-toolkit-vmware`). Future expansion; not v0.2.

---

## 3. Tool inventory + roles

### 3.1 Core toolkit (package `lamboot-tools`)

| Tool | Role | Maturity at v0.2 | Lang | Individual SDS target |
|---|---|---|---|---|
| `lamboot-diagnose` | Generic UEFI boot-chain scanner with actionable findings | stable | bash | To be written — §D.1 |
| `lamboot-esp` | ESP health, inventory, cleanup | stable | bash | To be written — §D.2 |
| `lamboot-backup` | UEFI boot config save + restore | stable | bash | To be written — §D.3 |
| `lamboot-repair` | Online + offline boot repair | stable | bash | To be written — §D.4 |
| `lamboot-migrate` | BIOS→UEFI + cross-bootloader migration | stable (tool v1.0) | bash | Exists — `~/lamboot-dev/docs/specs/SPEC-LAMBOOT-MIGRATE.md` |
| `lamboot-doctor` | Guided diagnose→repair→verify wrapper | beta | bash | To be written — §D.5 |
| `lamboot-toolkit` | Suite dispatcher + unified help + next-command chaining | stable | bash | To be written — §D.6 |
| `lamboot-inspect` | LamBoot-specific deep diagnostic | stable (mirror) | Python | Canonical in lamboot-dev |
| `lamboot-uki-build` | Host-side UKI builder | beta | bash | To be written — §D.7 |
| `lamboot-signing-keys` | Secure Boot key lifecycle (user-facing + release-eng) | experimental | bash | To be written — §D.8 |

### 3.2 Proxmox companion (package `lamboot-toolkit-pve`)

| Tool | Role | Maturity at v0.2 | Lang | Source |
|---|---|---|---|---|
| `lamboot-pve-setup` | Per-VM LamBoot integration setup | beta | bash | NEW in pve/ subtree |
| `lamboot-pve-fleet` | Fleet-wide inventory, status, reporting | experimental | bash | NEW in pve/ subtree |
| `lamboot-pve-monitor` | Host-side NVRAM health reader | stable | Python | Mirror-renamed from `~/lamboot-dev/tools/lamboot-monitor.py` |
| `lamboot-pve-ovmf-vars` | OVMF VARS file builder with cert pre-enrollment | stable | bash | Mirror-renamed from `~/lamboot-dev/tools/build-ovmf-vars.sh` |

### 3.3 Tool-to-tool composition contract

Every tool emits JSON per §5 when `--json` is passed. Every finding's `remediation.command` field MAY reference another tool. Output from one tool can feed another via:

- Standard command chains (shell pipelines + redirection)
- `lamboot-toolkit run <tool> [args]` dispatch form
- `--suggest-next-command` flag on every tool (prints the most relevant next command to run based on findings)
- `lamboot-doctor` chaining (guided wrapper that executes the chain with user confirmation)

### 3.4 Maturity labels

Three explicit levels, surfaced in the help registry, man pages, website, and `lamboot-toolkit status`:

- **stable** — fully tested, production-ready, API-frozen within the current major version. Breaking changes require a major version bump.
- **beta** — feature-complete and fleet-tested on Tier 1 distros (§9.2), but may have rough edges. Minor API changes possible between minor versions.
- **experimental** — initial framework; API may change. May emit warnings on invocation. Users are explicit about trying it.

Maturity is per-tool, set at each release, and cannot silently regress. Demoting a tool from stable to beta is an explicit release-note event.

### 3.5 Language discipline

Core principle: **all new tools are bash.** Two documented exceptions, both historical:

- `lamboot-inspect` — Python, authored in `lamboot-dev`, mirrored into toolkit at release-build. Canonical source stays in `lamboot-dev/tools/`.
- `lamboot-pve-monitor` — Python, authored in `lamboot-dev`, mirrored with rename at release-build. Canonical source stays in `lamboot-dev/tools/lamboot-monitor.py`.

No other languages in v0.2. No Python, Perl, or Rust tools beyond the two exceptions. If a future tool genuinely requires a non-bash implementation (e.g., `lamboot-uki-build` hits complexity bash can't handle), the decision is escalated to a spec amendment.

---

## 4. CLI contracts

Every tool MUST conform to the contracts in this section. Conformance is tested in CI (§9.4). Deviations are release-blocking.

### 4.1 Argument and flag conventions

- **Subcommands first, flags second.** `lamboot-esp check --json`, not `lamboot-esp --json check`. Subcommands are required where the tool supports more than one operation; absent, the default is the most-read-only diagnostic action.
- **Long flags are the authoritative form.** Short aliases exist for high-frequency flags only: `-h` (`--help`), `-v` (`--verbose`), `-q` (`--quiet`), `-y` (`--yes`). No other short flags in v0.2.
- **Double-dash separator (`--`) honored** for positional arguments that resemble flags.
- **Universal flags** — every tool accepts, with identical semantics:
  - `--help` / `-h` — terse clap-style help with an after-help summary of subcommands
  - `--version` — prints `<tool>-<tool_version> (lamboot-tools-<toolkit_version>)`
  - `--json` — emit unified JSON output (§5)
  - `--json-schema` — print the JSON schema the tool would emit; does not require root
  - `--verbose` / `-v` — informational output beyond defaults
  - `--quiet` / `-q` — only warnings and errors; no informational output
  - `--no-color` — disable ANSI color codes (also auto-disabled on non-TTY stdout)
  - `--dry-run` — print planned actions; make no changes. Mandatory for every tool that mutates state.
  - `--yes` / `-y` — answer yes to interactive confirmations (required by `--auto` use)
  - `--suggest-next-command` — print the recommended follow-up command based on output; does not execute
- **Operation flags** (tools that mutate state):
  - `--force` — skip safety checks (tool MUST document which safety checks are skipped)
  - `--auto` — non-interactive full automation; implies `--yes` and accepts sensible defaults
  - `--offline DISK` — operate on an unmounted disk (every tool except `lamboot-migrate`)

### 4.2 Help text pattern

Two help surfaces per tool, both driven by a single static command registry analogous to `rdpdo`'s `help.rs`:

**Surface 1 — `--help` (terse):** clap-generated global flags list, followed by an `after_help` block listing subcommands grouped by category, a short coordinate/format reference if applicable, an offline-commands list, and a few example invocations.

**Surface 2 — `lamboot-<tool> help [subcommand]` (structured, deep):**
- `help` alone — full category-grouped listing of every subcommand with name, aliases, offline-marker, one-line summary, and syntax line
- `help <subcommand>` — name + aliases, summary, `SYNTAX:`, `ARGUMENTS:` (column-aligned), `EXAMPLES:`, `NOTES:` (word-wrapped 76 cols), `OFFLINE:` (yes/no), `SEE ALSO:` (related subcommands and sibling tools), `REMEDIATION LINKS:` (URL for deep-dive docs)

The shared help library (`lib/lamboot-toolkit-help.sh`) provides the registry data structures and rendering functions. Each tool declares its commands by sourcing the library and appending to the registry.

### 4.3 Color + TTY detection

- Color output is enabled on TTY stdout by default, disabled on non-TTY stdout, and overridable with `--no-color` / `--color=always|auto|never`.
- `NO_COLOR` environment variable (the freedesktop convention) is honored as `--no-color`.
- `TERM=dumb` forces `--no-color`.
- Color semantics are uniform across tools: red for errors, yellow for warnings, green for successes, cyan for informational headings, no color for regular text.
- Color never changes the textual content of output — only visual emphasis. `--no-color` output is byte-for-byte derivable from colored output by ANSI-stripping.

### 4.4 Exit codes

All tools use the unified exit-code table:

| Code | Constant | Meaning |
|---|---|---|
| 0 | `EXIT_OK` | Success. All requested operations completed. |
| 1 | `EXIT_ERROR` | Fatal error. Some state may have changed; see output for details. |
| 2 | `EXIT_PARTIAL` | Mixed success. Some operations succeeded; some failed. Output enumerates. |
| 3 | `EXIT_NOOP` | Nothing to do. System already in the requested state. |
| 4 | `EXIT_UNSAFE` | Refused due to a safety check. No state changed. Inspect and resolve. |
| 5 | `EXIT_ABORT` | User declined an interactive confirmation. No state changed. |
| 6 | `EXIT_NOT_APPLICABLE` | The requested operation does not apply to this system (e.g., `lamboot-migrate to-lamboot` on a BIOS/MBR system). |
| 7 | `EXIT_PREREQUISITE` | A required external tool or capability is missing. Output names it. |

Exit codes ≥ 8 are reserved for tool-specific use; tools document their use in their own man page. Unknown exit codes from a tool are always a bug.

### 4.5 Privilege model — read unprivileged, write requires root

Every tool implements Option C from the research session:

- **Read operations and informational paths** (`--help`, `--version`, `--json-schema`, diagnostic scans where available) run unprivileged. The tool does what it can as the calling user.
- **Write operations, operations requiring root-only capabilities** (efivarfs write, ESP write, partition operations, NVRAM access) refuse with a polite error: `error: this operation requires root; rerun with sudo` and `EXIT_PREREQUISITE`.
- **Offline mode** (`--offline DISK`) requires root because `losetup` / `qemu-nbd` require it.
- **Tools never self-escalate** — never invoke `sudo` internally. Mid-run credential prompts are unacceptable UX.
- **The shared library's `require_root` function** is the single enforcement point. It prints a consistent message and exits with `EXIT_PREREQUISITE`.
- **`lamboot-doctor` handles the escalation pattern** — runs diagnostic scans unprivileged, constructs a repair plan, then re-execs under `sudo` once with `--doctor-resume <run_id>` if the plan contains write actions. User confirms sudo escalation once, not per-action.

### 4.6 Dry-run semantics

Every state-changing tool supports `--dry-run`. Semantics are uniform:

- The tool performs **all read and diagnostic operations** normally.
- Every **write operation** is replaced by a printed description of what would have happened.
- Output format: `DRY-RUN: would <verb> <object>` for stdout-visible log lines; `"dry_run": true` flag at the root of JSON output and every `actions_taken` entry tagged `"dry_run": true`.
- Exit codes are the same as a non-dry-run would have produced (tools predict the outcome). A dry-run that would have failed with `EXIT_UNSAFE` exits `EXIT_UNSAFE` before doing anything else.
- Backup-directory creation is a read/setup operation, NOT a write; dry-run still creates an empty backup directory for inspection, then removes it at exit unless `--verbose`.

### 4.7 Interactive confirmation pattern

For destructive operations, every tool uses the same five-phase flow, borrowed from `lamboot-repair` and `lamboot-migrate`:

1. **Diagnose** — assess current state.
2. **Plan** — compute the full set of actions.
3. **Show** — print the plan in human-readable form with estimated blast radius.
4. **Confirm** — prompt `CONFIRM <action>: type 'yes' to proceed >`. Typing anything else is `EXIT_ABORT`. `--yes` / `--auto` bypass. `--force` bypasses for power users.
5. **Execute** — apply the plan with per-phase error handling.
6. **Verify** — re-check; write a success flag to the backup dir if applicable.

`lamboot-migrate` is the canonical implementation (SDS-7 §3); other tools mirror the pattern.

---

## 5. Data contracts

### 5.1 The unified JSON schema

Every tool that accepts `--json` emits this envelope:

```json
{
  "tool": "lamboot-diagnose",
  "version": "0.2.0",
  "toolkit_version": "0.2.0",
  "timestamp": "2026-04-22T14:37:22Z",
  "host": "laptop-01",
  "run_id": "2026-04-22T14-37-22-a1b2c3",
  "command": "lamboot-diagnose --json",
  "dry_run": false,
  "exit_code": 0,
  "summary": {
    "status": "pass",
    "findings_total": 24,
    "findings_by_severity": {"critical": 0, "error": 0, "warning": 1, "info": 23}
  },
  "findings": [
    {
      "id": "esp.free_space",
      "category": "esp",
      "severity": "warning",
      "status": "warn",
      "title": "ESP is 89% full",
      "message": "ESP at /boot/efi has 54 MB free of 512 MB (10.1% free)",
      "context": {
        "esp_mount": "/boot/efi",
        "free_bytes": 56623104,
        "total_bytes": 536870912,
        "percent_free": 10.1
      },
      "remediation": {
        "summary": "Remove stale kernel images to free space",
        "command": "sudo lamboot-esp clean --dry-run",
        "doc_url": "https://lamboot.dev/tools/esp#free-space"
      }
    }
  ],
  "actions_taken": [],
  "backup_dir": null
}
```

### 5.2 Field semantics

- **`tool`**: the executable name (`lamboot-diagnose`, `lamboot-pve-setup`, etc.).
- **`version`**: the tool's own semver. Per-tool, changes independently.
- **`toolkit_version`**: the unified `lamboot-tools` package version bundling this tool. Fleet aggregators filter on either.
- **`timestamp`**: ISO-8601 UTC with `Z` suffix. No local time, no fractional seconds.
- **`host`**: POSIX `hostname` output. Included even for offline-mode operations (reports host operating on the disk, not the disk's host identity).
- **`run_id`**: unique within host across time. Format: `<ISO-timestamp-with-dashes>-<6-hex-random>`. Correlates log lines, backup dirs, and JSON output from one invocation.
- **`command`**: exact argv joined by single spaces, with any `type-password` source values redacted to `***`.
- **`dry_run`**: `true` iff `--dry-run` was passed.
- **`exit_code`**: the code the process will return. Set at emit time; always accurate.
- **`summary.status`**: aggregate verdict — `pass` | `warn` | `fail` | `noop` | `error` | `unsafe` | `abort`.
- **`findings_by_severity`**: counts per `severity` value.

### 5.3 Findings

Every informational, warning, error, or diagnostic observation is a **finding**. The envelope allows one or many per invocation.

**`id`** — dotted-path stable identifier. Format: `<category>.<specific>[.<subspecific>]`. Examples: `esp.free_space`, `bootloader.grub.pe_format`, `fstab.uuid_form`, `trust.shim.absent`. IDs are **SEMVER-STABLE** within the toolkit's major version — tools adding new IDs is additive; renaming existing IDs is a major-version event. Consumers MAY match on `id` exactly; they MAY NOT parse `id` for structure beyond dotted-path grouping.

**`category`** — broad grouping, human-friendly: `esp`, `bootloader`, `partition`, `fstab`, `trust`, `kernel`, `initrd`, `fleet`, `tpm`, `firmware`, `distro`, `vm`, `boot_entry`.

**`severity`** — consequences of the finding if unaddressed:
- `critical` — booting the system will fail
- `error` — some capability is broken (not boot-fatal but degraded)
- `warning` — works but risky or suboptimal
- `info` — fine as-is, reported for visibility

**`status`** — the per-check verdict of what was measured:
- `pass` — the check ran, expected condition met
- `warn` — check ran, condition marginal
- `fail` — check ran, condition failed
- `skip` — check did not run (prerequisite missing, `--skip` flag, etc.)

`severity` and `status` are orthogonal. A check can run, fail, and the failure be `info` (reported but not actionable). Conversely, a failed `critical` check always has `status: fail`.

**`title`** — short, human-readable summary. Fixed per `id`. Safe to embed in menus and summaries.

**`message`** — detailed, context-aware description. Values are substituted; specific numbers and paths included.

**`context`** — open JSON object. Tool-specific keys with raw data the finding was computed from. Consumers use this for automated matching and escalation.

**`remediation`** — present for any finding with severity ≥ `warning`. Fields:
- `summary` — one-sentence human-readable remediation plan
- `command` — suggested shell command to run next. ADVISORY ONLY at v0.2; never invoked by tools automatically.
- `doc_url` — deep-dive documentation URL under `lamboot.dev/tools/`. Always resolves.

### 5.4 Actions taken (mutating tools only)

For tools that write state, `actions_taken` is an array of objects describing every action the tool executed:

```json
{
  "action": "partition.create",
  "target": "/dev/sda2",
  "result": "ok",
  "reversible": true,
  "backup_ref": "/var/backups/lamboot-migrate-2026-04-22T14-37-22-a1b2c3/",
  "details": {
    "partition_number": 2,
    "size_mb": 512,
    "typecode": "EF00"
  }
}
```

Verbs are dotted-path identifiers parallel to finding IDs: `partition.create`, `fstab.rewrite`, `efibootmgr.create_entry`, `esp.file_delete`, etc. `reversible: true` means `lamboot-migrate rollback` (or the tool's own rollback) can undo it.

### 5.5 Backup directory contract

Tools that produce backups follow a uniform layout, established by SDS-7 §7.1 and generalized here. Any tool writing a backup uses:

```
/var/backups/lamboot-<tool>-<ISO-timestamp-a1b2c3>/
├── MANIFEST.json               # {tool, version, toolkit_version, timestamp, run_id, host, command, planned_actions}
├── <per-tool artifacts>        # tool-defined
├── SUCCESS.flag                # written iff verification passed (empty file)
└── ROLLBACK.log                # append-only; any rollback attempts logged here
```

`MANIFEST.json` is the authoritative record; any tool reading a backup MUST validate the manifest before acting. `backup_dir` in the main JSON envelope points at this directory when present.

### 5.6 Schema versioning

The JSON schema itself carries a version: `$schema: "https://lamboot.dev/schemas/tools/v1"`. v0.2 emits `v1`. Breaking schema changes increment the schema version AND the toolkit major version in lockstep. Additive changes (new optional fields) do not bump. Consumers pin against the schema version they support.

### 5.7 Machine consumption guarantees

- Every tool's `--json` output passes `jq -e .` on stdout regardless of exit code.
- Every tool's `--json-schema` output is a valid JSON Schema (draft 2020-12) describing the envelope and the tool-specific `context` shape.
- No log lines on stdout when `--json` is active. All human output goes to stderr.
- Color codes are suppressed on stdout when `--json` is active.

---

## 6. Shared architecture

### 6.1 The shared library

The canonical source of truth for common operations lives at `/usr/lib/lamboot-tools/lamboot-toolkit-lib.sh`. Every tool sources it at startup:

```bash
#!/bin/bash
set -uo pipefail
source /usr/lib/lamboot-tools/lamboot-toolkit-lib.sh
# tool body follows
```

Library scope for v0.2:

**ESP + disk detection:**
- `detect_esp` — returns mount point or exits `EXIT_PREREQUISITE`
- `esp_mountpoint` — returns current ESP mount
- `find_disk_for_mount <mount>` — resolves mount to block device
- `detect_boot_mode` — `uefi` | `bios`
- `detect_distro` — parses `/etc/os-release`; returns `id` or `unknown`
- `list_bootloaders` — enumerates GRUB / sd-boot / rEFInd / LamBoot / other on ESP

**Logging + user interaction:**
- `die <message>` — stderr + `EXIT_ERROR`
- `die_unsafe <message>` — stderr + `EXIT_UNSAFE`
- `die_noop <message>` — stderr + `EXIT_NOOP`
- `warn <message>` — stderr, prefix `warning:`
- `info <message>` — stderr, prefix `info:`
- `verbose <message>` — stderr if `--verbose`
- `confirm <question>` — interactive prompt, respects `--yes`/`--force`

**Privilege + prerequisites:**
- `require_root` — exits `EXIT_PREREQUISITE` if not root
- `require_tool <name> [install-hint]` — checks command presence, prints install hint

**Dry-run + action logging:**
- `run <cmd...>` — executes unless `--dry-run`; logs either way
- `record_action <verb> <target> <result> <reversible> <details_json>` — appends to actions_taken

**Backup discipline:**
- `backup_dir_new <tool>` — creates `/var/backups/lamboot-<tool>-<ts>/` + MANIFEST.json
- `backup_file_to <backup_dir> <path>` — copies a file into backup dir
- `backup_success <backup_dir>` — writes SUCCESS.flag
- `backup_latest <tool>` — finds most recent backup dir for a tool

**JSON emission:**
- `emit_finding <id> <category> <severity> <status> <title> <message> <context_json> [<remediation_json>]` — appends to findings array
- `emit_json` — prints the complete envelope and exits

**Offline mode:**
- `offline_setup <disk>` — auto-detects raw/qcow2, sets up loopback or qemu-nbd, mounts filesystems; sets `$OFFLINE_ROOT` + `$OFFLINE_ESP`
- `offline_teardown` — reverses setup; idempotent; registered as EXIT trap

### 6.2 Single-file portability path

For rescue-media users and curl-pipe installers, every tool has an **inlined build** — the shared library is concatenated into the tool itself at build time. The Makefile produces two forms per tool:

- `build/sourced/lamboot-<tool>` — small file sourcing `/usr/lib/lamboot-tools/lamboot-toolkit-lib.sh`. Used by distro packages (Copr, PPA).
- `build/inlined/lamboot-<tool>` — self-contained file with the library concatenated at top, marked with `# INLINED LIBRARY BELOW — DO NOT EDIT; edit lib/ and rebuild`. Used by tarball, curl-pipe installer, and rescue-media deployment.

`make install` uses `sourced/` + `/usr/lib/lamboot-tools/` installation. `make install-inlined` uses `inlined/` with no library dependency — one `cp` per tool is enough.

Inlined build is tested in CI (§9.4) — every tool's inlined form passes shellcheck and bats tests identically to its sourced form.

### 6.3 No generic helper modules

In line with project naming discipline (`CLAUDE.md`), the shared library is **not** `common.sh`, `utils.sh`, or `helpers.sh`. It is `lamboot-toolkit-lib.sh`, with domain-specific function names (`detect_esp`, `emit_finding`, `offline_setup`). The library is the one exception to the "no helper modules" rule, and its content is strictly domain-specific.

### 6.4 Offline mode

Every tool except `lamboot-migrate` supports `--offline DISK`. Semantics:

- `DISK` is either a block device path or an image file (raw, qcow2, qcow2-compressed).
- `offline_setup` in the shared library auto-detects the format, sets up loopback (`losetup`) or NBD (`qemu-nbd`), waits for device enumeration (`partprobe`), and mounts:
  - `$OFFLINE_ROOT` — best-guess root filesystem (looks for `/etc/fstab`, `/etc/os-release`)
  - `$OFFLINE_ESP` — best-guess ESP (looks for `/EFI/` tree)
- If auto-detection can't find one or both, tool falls back to explicit flags (`--offline-root <path>`, `--offline-esp <path>`) or exits `EXIT_UNSAFE`.
- `offline_teardown` is registered as an EXIT trap. Unmounts, disconnects NBD, detaches loopback. Idempotent.
- Offline mode requires root.

`lamboot-migrate --offline` is explicitly deferred with an informative error citing v0.3.

### 6.5 Error handling + remediation idiom

Every tool's error paths MUST:

1. Produce a human-readable stderr message
2. Suggest the most plausible remediation (`hint: <command>`)
3. Exit with an appropriate code from §4.4
4. Record a corresponding finding if `--json` is active

Errors without remediation suggestions are release-blocking bugs. "Something went wrong" is never acceptable.

### 6.6 `lamboot-toolkit` dispatcher

Separate-binaries + dispatcher, per R7:

- `/usr/local/bin/lamboot-<tool>` — individual tools, tab-completion-discoverable on `lamboot-<TAB>`.
- `/usr/local/bin/lamboot-toolkit` — thin dispatcher that:
  - `lamboot-toolkit --help` — suite overview, lists every tool with maturity label, short summary
  - `lamboot-toolkit status` — prints tools present, version of each, maturity of each
  - `lamboot-toolkit help [<tool> [<subcommand>]]` — deep help (same as `lamboot-<tool> help <subcommand>` but discoverable via one entry point)
  - `lamboot-toolkit run <tool> [args...]` — invokes a tool (for scripting uniformity)
  - `lamboot-toolkit version` — toolkit version + every tool's version
  - `lamboot-toolkit verify` — sanity-check the install (every tool's `--version` works; library loaded; schema validates)

### 6.7 `lamboot-doctor` — guided wrapper

Beta at v0.2. The default-action policy matrix for findings:

| Finding severity | Default doctor behavior (interactive) | With `--auto` |
|---|---|---|
| `critical` | Stop. Show plan. Require explicit `yes` to proceed. Never auto-apply. | Stop. Show plan. Require explicit `yes` to proceed. (Critical never auto-applies even under `--auto`.) |
| `error` | Show plan. Prompt y/N per remediation block. | Auto-apply with backup. Report result. |
| `warning` | Show finding. Print the suggested command. Do not prompt. User runs manually. | Report as info-level. Do not apply. |
| `info` | Not surfaced in doctor (lives in `lamboot-diagnose --verbose`). | Not surfaced. |

Flow:

1. `lamboot-diagnose --json` (unprivileged)
2. If plan contains ANY write actions → re-exec under `sudo` with `--doctor-resume <run_id>` (single escalation)
3. For each finding at or above `warning`, walk the policy matrix
4. After each applied remediation, re-run the specific finding's check to verify resolution
5. Emit final JSON envelope summarizing what was fixed, what remains, and what the user needs to do manually

`lamboot-doctor` never invokes `lamboot-migrate` automatically (too destructive). BIOS→UEFI migration is always user-driven.

### 6.8 `--suggest-next-command` pattern

Every tool supports this flag. Output: a single command to stdout (not JSON) that represents the most-relevant follow-up action. Example:

```
$ sudo lamboot-diagnose --suggest-next-command
sudo lamboot-esp clean --dry-run
```

Selection logic: pick the finding with the highest severity, then lowest `id` alphabetically, and print its `remediation.command`. If no findings require action, print nothing and exit `EXIT_NOOP`.

---

## 7. Distribution + packaging

### 7.1 Channels and their v0.2 status

| Channel | v0.2 status | Rationale |
|---|---|---|
| GitHub release tarball | **Primary.** Ships with inlined single-file tools + Makefile. | Zero-dependency install on any Linux; curl-pipe-friendly. |
| Fedora Copr | **Required by v0.2.** `copr/lamco/lamboot-tools` + `copr/lamco/lamboot-toolkit-pve`. | Fedora / RHEL / Rocky users get `dnf install` convenience. Matches lamco-rdp-server operational pattern. |
| Ubuntu/Debian PPA | v0.3 | Incremental packaging work. |
| Homebrew tap | v0.5 | Linux-fleet admins running macOS. |
| Debian upstream | v1.0+ | Months-long process; earned credibility first. |
| `lamboot-migrate` standalone distro package | v1.0 (with tool v1.0 milestone) | Product spin-off per R22 revised decision. |
| LamBoot tarball symlink/recommendation | **v0.2.** LamBoot install script prompts opt-in; README references. | Brand coherence without bundling; independent cadence preserved. |
| Snap / Flatpak | **Out of scope permanently.** | Sandboxing incompatible with host device access. |

### 7.2 Installation layout

```
/usr/local/bin/
├── lamboot-diagnose
├── lamboot-esp
├── lamboot-backup
├── lamboot-repair
├── lamboot-migrate
├── lamboot-doctor
├── lamboot-toolkit
├── lamboot-inspect          # Python, mirror from lamboot-dev
├── lamboot-uki-build
└── lamboot-signing-keys

/usr/local/bin/               # from lamboot-toolkit-pve
├── lamboot-pve-setup
├── lamboot-pve-fleet
├── lamboot-pve-monitor       # Python, mirror from lamboot-dev
└── lamboot-pve-ovmf-vars

/usr/lib/lamboot-tools/
├── lamboot-toolkit-lib.sh    # the shared library
├── lamboot-toolkit-help.sh   # help registry driver
├── bash-completion/
│   ├── lamboot-diagnose
│   └── ...                   # one per tool
└── profiles/
    └── distro-recipes/       # distro-specific data tables

/usr/share/man/man1/
├── lamboot-diagnose.1
├── lamboot-esp.1
├── ...

/usr/share/man/man7/
└── lamboot-tools.7

/usr/share/doc/lamboot-tools/
├── CHANGELOG.md
├── README.md
├── CLAIMS.md                 # §13 claims appendix installed locally
└── LICENSE
```

Distro packages honor `DESTDIR`, `PREFIX`, `BINDIR`, `LIBDIR`, `MANDIR`, `DOCDIR` for FHS-compliant installs. Copr RPM spec uses `/usr/bin/` and `/usr/lib64/lamboot-tools/`.

### 7.3 Relationship to the LamBoot tarball

The LamBoot release tarball does **not** bundle the toolkit. It ships its 8 bootloader-coupled tools (lamboot-install, etc.) as today. It **does** gain:

- An opt-in prompt in `lamboot-install`: "Install lamboot-tools for diagnostic and repair utilities? [y/N]"
- A README reference: "For diagnostic, repair, and migration tools, install lamboot-tools: https://github.com/lamco-admin/lamboot-tools"
- No compiled-in dependency on lamboot-tools being present.

### 7.4 `lamboot-migrate` dual publication

Per R22 decision — keep the `lamboot-migrate` name, dual-publish, ride package description for search discovery.

**Primary publication:** inside the `lamboot-tools` tarball / package.

**Standalone publication:** a separate `lamboot-migrate` source tarball + its own Fedora Copr RPM + (v1.0+) its own Debian package. Builds from the same source — the standalone version is literally `tools/lamboot-migrate` + its portion of the shared library concatenated. Same binary, different wrapper.

Package descriptions explicitly enumerate the capability: "LamBoot's UEFI migration tool — automated Linux BIOS→UEFI conversion with rollback support. Works with GRUB, systemd-boot, rEFInd, and LamBoot."

Users find it via `dnf search uefi migration`, `apt search bios uefi`, etc. — via metadata, not name-neutrality.

### 7.5 Publish pipeline

A `publish/` subdirectory in `lamboot-tools-dev` contains:

- `publish/export-to-public.sh` — mirrors tested commits from dev repo to public `lamboot-tools` repo (analogous to `lamboot-dev/export-to-public.sh`)
- `publish/build-standalone-migrate.sh` — extracts `lamboot-migrate` + its library subset into a standalone source tarball
- `publish/mirror-from-lamboot-dev.sh` — at release-build time, copies:
  - `lamboot-dev/tools/lamboot-inspect` → `lamboot-tools/tools/lamboot-inspect` (no rename)
  - `lamboot-dev/tools/lamboot_inspect/` → `lamboot-tools/tools/lamboot_inspect/` (Python package dir)
  - `lamboot-dev/tools/lamboot-inspect.1` → `lamboot-tools/man/lamboot-inspect.1`
  - Checksum-verifies each
- `publish/build-copr-specs.sh` — generates RPM spec files for Copr publishing

The PVE subtree is mirrored from lamboot-dev via `publish/mirror-pve-from-lamboot-dev.sh`
in this same repo:
  - `lamboot-dev/tools/lamboot-monitor.py` → `pve/tools/lamboot-pve-monitor`
  - `lamboot-dev/tools/build-ovmf-vars.sh` → `pve/tools/lamboot-pve-ovmf-vars`

No separate companion repo or companion publish pipeline — the `lamboot-toolkit-pve`
RPM subpackage is built from the same source tarball as `lamboot-tools` and
`lamboot-migrate`. The single `export-to-public.sh` handles mirroring the entire
dev tree (including `pve/`) into the public `lamco-admin/lamboot-tools` repo.

### 7.6 Uninstallation

Every `make install` variant has a corresponding `make uninstall`. Uninstall removes:
- All installed binaries, man pages, library files, completion files
- `/usr/share/doc/lamboot-tools/` entirely
- Does NOT remove user data: backup directories under `/var/backups/`, config files under `/etc/lamboot/`, user fleet configs.

Uninstall is idempotent. Running it twice is a no-op on the second run.

---

## 8. Versioning + release cadence

### 8.1 Hybrid semver model

- **Toolkit-visible version** (`lamboot-tools 0.2.0`) — what users see on the tarball, in Copr, and as the primary version number.
- **Per-tool version** (`lamboot-migrate 1.0.0`, `lamboot-diagnose 0.2.0`) — each tool carries its own semver in `--version` output and the JSON `version` field.
- Every tool's `--version` prints BOTH:
  ```
  lamboot-diagnose 0.2.0 (lamboot-tools 0.2.0)
  ```

Toolkit major versions bump when:
- JSON schema breaks (§5.6)
- Install layout changes (moving files between paths)
- CLI contract breaks (flags removed or semantics changed)

Toolkit minor versions bump when:
- New tools added
- New capabilities on existing tools
- Any per-tool major bump

Toolkit patch versions bump for bug fixes.

Per-tool versions follow standard semver independent of the toolkit version.

### 8.2 Release cadence

- **Minor releases** (0.2, 0.3, 0.4, ...) — every 2–4 months; milestone-driven, not calendar-driven.
- **Patch releases** (0.2.1, 0.2.2, ...) — on demand for bug fixes.
- **Major releases** (1.0, 2.0) — rare; explicit roadmap event.

Each release:
- Produces a signed GitHub release
- Uploads tarballs (toolkit + standalone-migrate)
- Triggers Copr builds (`copr build lamco/lamboot-tools <tarball>`)
- Updates website docs at `lamboot.dev/tools/`
- Appends to `CHANGELOG.md`
- Coordinates with LamBoot release notes (cross-linking)

### 8.3 PVE subpackage versioning

`lamboot-toolkit-pve` is an RPM subpackage produced from the same
`packaging/rpm/lamboot-tools.spec` as `lamboot-tools` itself. Its package
version therefore matches core (`Requires: lamboot-tools = %{version}-%{release}`).

Per-tool `LAMBOOT_TOOL_VERSION` remains INDEPENDENT: `lamboot-pve-setup`
and `lamboot-pve-fleet` carry their own semver that floats against the
toolkit version. Tools print both:

```
lamboot-pve-setup 0.2.0 (lamboot-tools 0.2.0)
```

This preserves the ability to bump a single PVE tool's tool-level version
without forcing a toolkit-wide minor bump. The RPM package version is
always the toolkit-wide one.

Companion tools require the shared library from core toolkit. Companion package depends on core package. Installing companion without core is rejected at package level.

### 8.4 `lamboot-migrate` versioning under dual publication

`lamboot-migrate` tags its own semver independent of `lamboot-tools`. v1.0.0 ships at toolkit v0.2 per R22. Subsequently:

- Changes to `lamboot-migrate` bump its own semver.
- Toolkit release notes enumerate the `lamboot-migrate` version included.
- Standalone `lamboot-migrate` tarball version matches the per-tool version exactly.

### 8.5 Deprecation policy

Features are deprecated with:
- A warning message printed when used (`warning: --foo is deprecated, use --bar`)
- A `DEPRECATED:` marker in help text and man pages
- A minimum of one minor-version release between deprecation and removal
- An explicit `CHANGELOG.md` entry at both deprecation and removal

Breaking changes without deprecation are release-blocking bugs.

---

## 9. Quality bar for publication

### 9.1 shellcheck-clean is a ship gate

Every bash file in the toolkit MUST pass shellcheck with severity ≥ `style` at release time. `.shellcheckrc` at repo root lists specific per-line disables, each with a one-line justification comment at the disable site. No global severity threshold reductions are permitted.

Rationale: tools that manipulate disk state are exactly where SC2086 (unquoted variable in a device path) is catastrophic. `rm -rf $path` vs `rm -rf "$path"` is "file lost" vs "disk lost."

CI (§9.4) blocks any commit with shellcheck violations. `bash -n` syntax-checks every file.

### 9.2 Three-tier test matrix

**Tier 1 — release-blocking** (runs before every minor/major release):

| Distro | Version | Firmware | Bootloader |
|---|---|---|---|
| Ubuntu | 24.04 LTS | BIOS + UEFI | GRUB, systemd-boot |
| Debian | 13 (trixie) | BIOS + UEFI | GRUB |
| Fedora | 44 | BIOS + UEFI | GRUB, systemd-boot |
| Arch Linux | current | BIOS + UEFI | GRUB, systemd-boot |
| openSUSE | Tumbleweed | BIOS + UEFI | GRUB |

For each combination: every core tool runs its happy-path subcommand; `lamboot-migrate` runs `to-uefi` end-to-end on BIOS→UEFI pairs; negative cases (hybrid MBR, Windows present, encrypted root) exercise refusal paths.

**Tier 2 — per-tool v1.0 gate** (runs before each tool reaches stable v1.0):
- Tier 1 matrix plus
- Real-hardware smoke test on founder's laptop (or designated hardware)
- At least 3 VMs from the extended fleet covering DE/compositor diversity

**Tier 3 — reported, non-blocking** (community / founder fleet):
- Any distro or VM the founder has access to
- Results published in release notes as "also tested on X"
- Failures here don't block release but trigger investigation

### 9.3 Test infrastructure

- **bats-core** — primary test harness. Every tool has `tests/<tool>.bats`.
  - Unit-ish tests exercise shared library functions directly.
  - Integration tests invoke the tool end-to-end against fixture disk images.
- **Fixture disk images** — checked into git via git-lfs (or a download script for large images):
  - `clean-bios-mbr.raw` — 4GB, Debian 13 on MBR
  - `clean-uefi-gpt.raw` — 4GB, Fedora 44 on GPT
  - `hybrid-mbr.raw` — synthetically-constructed hybrid MBR
  - `encrypted-root.raw` — LUKS-encrypted root
  - `windows-mbr.raw` — Windows 11 on MBR
  - `no-esp.raw` — UEFI system missing ESP
  - `full-esp.raw` — ESP at 99% capacity
  - `corrupted-esp-fat.raw` — intentionally corrupted ESP FAT
  - `lamboot-installed.raw` — Fedora 44 with LamBoot installed
  - `grub-installed.raw` — Ubuntu 24.04 with GRUB only
  - `sdboot-installed.raw` — Arch with systemd-boot
- **Pre-commit hooks** (via `pre-commit`) — shellcheck + `bash -n` + relevant bats tests on changed files.
- **`tools/verify-structure.sh`** — CI job validating §13 claims appendix against actual code paths. Fails the build if a claim's referenced file/function doesn't exist.

### 9.4 CI pipeline

GitHub Actions, two workflows:

**`.github/workflows/ci.yml`** (every PR, every push to main):
1. `shellcheck` on all bash files
2. `bash -n` on all bash files
3. Build inlined tools from sourced tools + lib
4. bats-core unit tests (shared library + tool-level logic)
5. bats-core integration tests using fixture disk images
6. Build Matrix install smoke: Ubuntu 24.04 / Fedora 44 / openSUSE Tumbleweed containers; `make install`; every tool `--version` + `--help`; `make uninstall`; verify clean removal
7. `verify-structure.sh`

**`.github/workflows/fleet-test.yml`** (scheduled nightly, manually triggerable):
1. SSH to the founder's Proxmox host
2. For each Tier 1 VM: clone a baseline snapshot, install toolkit, run every tool, collect JSON output, assert expected outcomes
3. Post results to `lamboot.dev/tools/nightly/`

Fleet test is not GitHub-Actions-hosted; runs on founder's infrastructure. GitHub Actions triggers it via webhook to a self-hosted runner.

### 9.5 Performance budgets

| Operation | Budget |
|---|---|
| `lamboot-diagnose` on healthy system | <2s |
| `lamboot-diagnose --offline DISK` on 10GB qcow2 | <10s (including NBD setup) |
| `lamboot-esp check` | <1s |
| `lamboot-toolkit --help` | <100ms |
| Any tool `--version` | <100ms |
| `--json-schema` | <100ms |

Performance regressions are CI-tracked. A 20% slowdown is a blocker; smaller regressions get a warning.

### 9.6 Exit-on-first-error discipline

`set -uo pipefail` (not `set -e` — incompatible with `(( ))` arithmetic patterns per project CLAUDE.md). Each tool's main function explicitly handles expected non-zero exits from library functions; unexpected errors surface through the shared error-handler to `die`.

---

## 10. Documentation plan

### 10.1 Three surfaces, one registry

Per R17 refined: inline help is first-class alongside man pages and website; every surface drives from the same static registry.

**Surface 1 — Inline help** (extremely robust per founder direction):
- `lamboot-<tool> --help` — terse clap-style + after-help with subcommands grouped by category, flag summary, examples
- `lamboot-<tool> help` — full listing; categories; per-subcommand name + aliases + offline-marker + summary + syntax
- `lamboot-<tool> help <subcommand>` — deep dive: name, aliases, category, summary, SYNTAX, ARGUMENTS (aligned), EXAMPLES, NOTES (word-wrapped 76 cols), OFFLINE, SEE ALSO, REMEDIATION LINKS
- `lamboot-toolkit help` / `lamboot-toolkit help <tool>` / `lamboot-toolkit help <tool> <subcommand>` — same structure, dispatched through the suite entry point

**Surface 2 — Man pages**:
- `lamboot-tools(7)` — suite overview; when to use which tool; tool inventory; common conventions; exit codes; JSON schema reference
- `lamboot-<tool>(1)` per tool — canonical reference: SYNOPSIS, DESCRIPTION, SUBCOMMANDS, OPTIONS, EXIT STATUS, ENVIRONMENT, FILES, EXAMPLES, SEE ALSO, DIAGNOSTICS, BUGS
- Markdown source → pandoc → groff → installed at `/usr/share/man/`

**Surface 3 — Website docs** at `lamboot.dev/tools/`:
- Landing page with tagline, quickstart, sample diagnose output, link to each tool
- Per-tool detailed walkthroughs with screenshots (of terminal output), real-world scenarios, troubleshooting guides
- `/tools/schema/v1` — unified JSON schema published and versioned
- `/tools/findings/` — every finding `id` has a permanent URL (the `remediation.doc_url` targets)
- `/tools/guides/bios-to-uefi-migration` — flagship tutorial for `lamboot-migrate`
- `/tools/guides/proxmox-fleet-setup` — flagship tutorial for `lamboot-toolkit-pve`
- `/tools/reference/cli-contracts` — public contract documentation for integrators
- `/tools/reference/json-schema` — schema reference for machine consumers
- Plus, for every man page, an HTML rendering

### 10.2 Registry as single source of truth

The help registry (analogous to rdpdo's `ALL_COMMANDS: &[CommandDoc]`) stores per-subcommand:

- `name` (primary command name)
- `aliases` (array of alternates)
- `category` (enum)
- `summary` (one-line)
- `syntax` (full syntax line)
- `args` (array of `(name, description)` tuples)
- `examples` (array of invocations)
- `needs_connection` / `offline_capable` (boolean)
- `requires_root` (boolean)
- `notes` (multi-paragraph context)
- `see_also` (array of related subcommand names)
- `doc_url` (website URL for deep-dive)
- `maturity` (stable | beta | experimental)

Every surface is rendered from this registry. The website build pulls registries from all tools' installed binaries (via `--help-registry-dump` internal flag) and renders HTML.

### 10.3 CHANGELOG discipline

`CHANGELOG.md` at repo root. Every PR that users can see updates it under `## [Unreleased]`. Releases promote `[Unreleased]` to a dated section.

Format: "Keep a Changelog" style with `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security` subsections.

### 10.4 Writing discipline for the website

- Ledes are user-problem-first ("Your ESP is full. Here's how to clean it up.") not feature-first.
- Every flag or option used in an example is defined either in the example or at first use.
- Screenshots of terminal output are generated from real commands; a `make screenshots` target produces them consistently.
- Every page links back to its man page.
- Every claim references §13.

### 10.5 No automated doc generation from code comments

Registry-driven, not doc-comment-driven. Bash doesn't have a standard doc-comment convention; authoring docs as code comments then extracting them is fragile. The registry is authoritative; all surfaces render from it.

---

## 11. Ecosystem integration

### 11.1 Bootloader ecosystem

`lamboot-diagnose` and `lamboot-repair` recognize and classify:

- **LamBoot** — via ESP signatures, NVRAM variables, trust log presence
- **GRUB** — via `grub.cfg` presence, `grubx64.efi` binary, distro-specific paths
- **systemd-boot** — via `/boot/efi/EFI/systemd/`, `loader.conf`
- **rEFInd** — via `refind.conf`, `refind_x64.efi`
- **Limine** — via `limine.cfg`, `limine-bios-cd.bin` / `limine-uefi-cd.bin`
- **sdbootutil / bootctl** installations of systemd-boot
- **Windows Boot Manager** — reported as present, no repair offered
- **Unknown** — bootloader detected but not classified; reported with raw evidence

Repair capabilities vary by bootloader; see per-tool specs.

### 11.2 Proxmox companion integration

The `lamboot-toolkit-pve` companion coordinates with `lamboot-dev`'s existing Proxmox infrastructure through a **shared configuration schema** and **cross-repo tool boundaries**.

**Shared config: `/etc/lamboot/fleet.toml`**

```toml
# /etc/lamboot/fleet.toml — shared between lamboot-pve-fleet, lamboot-hookscript.pl, and lamboot-pve-monitor
[fleet]
id = "prod-cluster-01"                  # matches fleet_id in fw_cfg
cluster_name = "Production Cluster 1"

[roles]
# VMID → role mapping
100 = "webserver"
101 = "database"
102 = "loadbalancer"

[tags]
# Proxmox tags that trigger automatic role assignment
webserver = ["web", "nginx", "apache"]
database = ["db", "postgres", "mysql"]

[monitor]
# lamboot-pve-monitor / lamboot-monitor.py settings
poll_interval_seconds = 300
alert_webhook = "https://hooks.lamco.io/fleet-alert"
log_path = "/var/log/lamboot-monitor.log"

[hookscript]
# lamboot-hookscript.pl settings (read by the Perl hookscript)
config_dir = "/var/lib/lamboot"         # where VMID.json files live
inject_fleet_id = true
inject_role = true
inject_vmid = true
```

Authoritative schema reference lives in THIS document's §16 Appendix C. Three consumers:

1. **`lamboot-pve-setup`** (toolkit companion) — reads `[fleet]`, `[roles]`, `[tags]` to determine what to inject per-VM. Writes `/var/lib/lamboot/<VMID>.json` for hookscript consumption. Writes VM config updates via `qm set --args` for the permanent `-fw_cfg` line.
2. **`lamboot-hookscript.pl`** (lamboot-dev/tools, Perl) — reads `[hookscript]`. At VM `pre-start` lifecycle event, composes `/var/lib/lamboot/<VMID>.json` from the config + Proxmox VM metadata (tags, node, VMID). Does NOT call `qm set` (the broken v0.8.3 path) — the `args:` line is permanent, set once by `lamboot-pve-setup`.
3. **`lamboot-pve-monitor`** (companion, Python; mirror from lamboot-dev) — reads `[monitor]`. Polls NVRAM health, aggregates across `[roles]`, emits alerts.

**The Phase 1 fix coordination (must ship with v0.2):**

Per R18/Q3 decisions, the hookscript rewrite to fw_cfg file-reference pattern is a hard dependency for `lamboot-pve-setup` to work correctly. Release coordination:

1. `lamboot-dev` ships hookscript rewrite in its v0.8.4 (or next release post-toolkit-v0.2).
2. `lamboot-toolkit-pve` v0.2 ships `lamboot-pve-setup` that depends on the rewritten hookscript.
3. `lamboot-pve-setup` checks hookscript version at install time and refuses to proceed if pre-rewrite hookscript is detected; emits clear remediation (`hint: update lamboot to >= 0.8.4`).
4. Cross-repo release notes link each side's change to the other.

**Tool boundaries across repos:**

| Capability | Lives in | Exposed to user as |
|---|---|---|
| Bootloader install in a VM | lamboot-dev (`lamboot-install`) | `lamboot-install` inside guest |
| Per-VM `args:` line + hookscript attachment | companion (`lamboot-pve-setup`) | `lamboot-pve-setup <VMID>` on host |
| Hookscript lifecycle | lamboot-dev (`lamboot-hookscript.pl`) | Invisible; attached via `lamboot-pve-setup` |
| OVMF VARS file build with key | companion (`lamboot-pve-ovmf-vars`); mirror of `build-ovmf-vars.sh` | `lamboot-pve-ovmf-vars build` on host |
| NVRAM health read | companion (`lamboot-pve-monitor`); mirror of `lamboot-monitor.py` | `lamboot-pve-monitor` on host |
| Fleet-wide operations | companion (`lamboot-pve-fleet`) | `lamboot-pve-fleet setup --all` etc. |
| Native Proxmox config option | FUTURE Phase 3, new repo | Not v0.2 |
| Web UI dashboard | FUTURE Phase 4, new repo | Not v0.2 |

### 11.3 LamBoot-specific interactions

**`lamboot-migrate to-lamboot` ↔ `lamboot-install`:**
- `lamboot-migrate` v1.0 targets `lamboot-install` v0.8.3 API surface.
- If `lamboot-install` adds breaking flag changes, `lamboot-migrate` pin is advanced in a coordinated release.
- `lamboot-install` adds no knowledge of `lamboot-migrate` (it's an install tool, not a migration tool).
- `lamboot-migrate rollback` knows about `lamboot-install --remove` and coordinates.

**`lamboot-inspect` ↔ `lamboot-diagnose`:**
- `lamboot-diagnose` detects LamBoot presence and, if `lamboot-inspect` is available, recommends running it for deeper LamBoot-specific introspection.
- `lamboot-inspect` remains the canonical LamBoot-deep-diagnostic tool. `lamboot-diagnose` provides summaries and generic checks.
- No code sharing between the two beyond the shared library and JSON schema conformance.

**`lamboot-signing-keys` ↔ LamBoot signing infrastructure:**
- `lamboot-signing-keys` Scope 1 mode manages Lamco release-engineering keys per `~/lamboot-dev/docs/KEY-GENERATION.md`. The existing `sign-lamboot.sh`, `build-ovmf-vars.sh`, and `KEY-GENERATION.md` procedure become consumed by `lamboot-signing-keys` as internal implementation.
- Canonical source of the key-management procedure stays in `~/lamboot-dev/docs/KEY-GENERATION.md` (the authoritative document). `lamboot-signing-keys` references it, does not duplicate it.
- Scope 2 mode (user-facing) is independent of Lamco keys; users generate their OWN keys.
- The RSA-2048 constraint for MOK-enrolled keys (Debian #1013320 shim freeze) is enforced as a safety check in both modes.

### 11.4 Trust-log schema compatibility

`lamboot-diagnose` reads `\loader\boot-trust.log` written by LamBoot per `~/lamboot-dev/docs/specs/SPEC-NATIVE-TRUST-CHAIN.md` §6. The toolkit's schema for parsing trust-log events matches SDS-4 event schema v2 exactly. Toolkit findings map to trust-log `verified_via` values (Appendix A of SDS-4):

- `shim_mok` / `shim_vendor` → `info` severity, `bootloader.lamboot.trust.ok` finding
- `shim_sbat_rejected` / `shim_not_enrolled` → `error` severity, `bootloader.lamboot.trust.rejected` finding
- `degraded_trust_sb_off` → `warning` severity, `bootloader.lamboot.trust.sb_disabled` finding
- etc.

This mapping is documented explicitly in the toolkit's claims appendix (§13) and tested in CI.

### 11.5 UKI building and systemd ecosystem

`lamboot-uki-build` wraps `dracut --uefi`, `ukify`, and `objcopy` to build Unified Kernel Images. UKIs built by the tool:
- Follow UAPI.5 UKI Specification
- Include `.osrel`, `.cmdline`, `.uname`, `.linux`, `.initrd` sections at minimum
- Optionally include `.profile`, `.splash`, `.dtb`, `.dtbauto` per user input
- Are compatible with LamBoot's UKI parser per `~/lamboot-dev/docs/specs/SPEC-UKI-PE-PARSER.md`
- Are compatible with systemd-boot, any other UKI-aware bootloader, and firmware-direct-boot

The tool does NOT:
- Depend on LamBoot being installed
- Produce LamBoot-specific UKI variants (UKIs are a standard; LamBoot reads the standard)
- Replace distro-provided UKI builders (e.g., Fedora's `systemd-ukify` or CachyOS's tooling) — it's an alternative for users who want finer control or are on distros without one

---

## 12. Release roadmap

### 12.1 v0.2.0 — the publishable launch (target: 2026-Q3)

**Package scope:**
- `lamboot-tools 0.2.0` with 10 tools
- `lamboot-toolkit-pve 0.2.0` with 4 tools
- Shared library v1
- JSON schema v1
- Full three-surface documentation
- Fedora Copr published
- `lamboot-migrate 1.0.0` (tool-level) dual-published as standalone
- All tools shellcheck-clean
- Tier 1 test matrix passing
- GitHub Actions CI green
- Fleet test nightly infrastructure running

**Maturity at v0.2:**
- stable: `lamboot-diagnose`, `lamboot-esp`, `lamboot-backup`, `lamboot-repair`, `lamboot-migrate`, `lamboot-toolkit`, `lamboot-inspect`, `lamboot-pve-monitor`, `lamboot-pve-ovmf-vars`
- beta: `lamboot-doctor`, `lamboot-uki-build`, `lamboot-pve-setup`
- experimental: `lamboot-signing-keys`, `lamboot-pve-fleet`

**Cross-repo dependencies:**
- LamBoot v0.8.4 ships hookscript rewrite (fw_cfg file-reference pattern) in the same release window
- LamBoot v0.8.4 README adds toolkit recommendation
- `lamboot-install` v0.8.4 adds opt-in prompt

**Total estimated effort:** 150–200 hours, 8–14 calendar weeks of focused work at typical cadence. Session plan:

| Session | Scope | Estimate |
|---|---|---|
| Session A (done) | Research + this spec | ~6h |
| Session B | Shared library + dispatcher + CI scaffolding | ~12h |
| Session C | SDS-7 gap-close on `lamboot-migrate` | ~12h |
| Session D | `lamboot-diagnose` hardening + unified JSON | ~10h |
| Session E | `lamboot-esp` hardening + offline mode | ~8h |
| Session F | `lamboot-backup` hardening | ~6h |
| Session G | `lamboot-repair` hardening | ~10h |
| Session H | `lamboot-doctor` (new, beta) | ~14h |
| Session I | `lamboot-uki-build` (new, beta) | ~20h |
| Session J | `lamboot-signing-keys` (new, experimental) | ~20h |
| Session K | PVE companion: `lamboot-pve-setup`, `lamboot-pve-fleet` | ~20h |
| Session L | PVE companion mirrors + cross-repo coordination | ~8h |
| Session M | Docs: man pages + registry work | ~14h |
| Session N | Website docs | ~14h |
| Session O | Fleet-test matrix + fixtures | ~14h |
| Session P | Packaging: Copr, publish pipeline, standalone-migrate | ~10h |
| Session Q | Release rehearsal + publish | ~6h |

Total: ~204 hours.

### 12.2 v0.3.0 — maturing + broadening (target: 2026-Q4 or 2027-Q1)

- `lamboot-doctor` → stable (policy matrix expanded, more tested)
- `lamboot-uki-build` → stable
- `lamboot-pve-setup` → stable
- `lamboot-migrate --offline DISK` — implemented
- Ubuntu/Debian PPA published
- `lamboot-pve-fleet` → beta
- `lamboot-signing-keys` → beta
- Additional fleet-test distros

### 12.3 v0.5.0 — full coverage (target: 2027-Q2)

- `lamboot-signing-keys` → stable
- `lamboot-pve-fleet` → stable
- Homebrew tap
- Additional hypervisor companions considered (no commitment)

### 12.4 v1.0.0 — mature, enterprise-ready (target: 2027-Q4)

- Every core tool stable
- Every PVE companion tool stable
- Debian upstream submission for standalone `lamboot-migrate`
- Proxmox Phase 3 (native option) submission or companion upgrade
- `lamboot-migrate` formal spin-off milestone: `lamboot-migrate 2.0` with distinct product page at `lamboot.dev/migrate/`, dedicated distro package, independent release cadence from core toolkit

### 12.5 Out of roadmap

- `lamboot-doctor` default-behavior becoming "auto-fix without prompting for most findings" — never. Default stays conservative forever.
- GUI — never.
- Windows/macOS/BSD support — never.

---

## 13. Claims appendix + marketing discipline

### 13.1 Purpose

This appendix is the API that marketing copy consumes. Claims not on this list are not backed by code. Inspired by `~/lamboot-dev/docs/specs/SPEC-NATIVE-TRUST-CHAIN.md` §8.

### 13.2 Permitted claims (v0.2)

| Claim | Code path backing it | CI verification |
|---|---|---|
| "The Linux UEFI boot toolkit — works on any UEFI Linux system." | Every core tool's help text declares distro support. Tier 1 test matrix covers 5 distros × 2 firmwares × 2 bootloaders. | `verify-structure.sh` checks tier-1 matrix in `ci.yml` |
| "Diagnose boot issues without reboot, online or offline." | `lamboot-diagnose` `--offline DISK` support; `lamboot-repair` `--offline`; shared `offline_setup` in lib. | bats integration tests over fixture disk images |
| "Automated end-to-end BIOS→UEFI migration with rollback." | `lamboot-migrate to-uefi` per SDS-7; `lamboot-migrate rollback` per SDS-7 §7. | SDS-7 §10 test matrix |
| "All tools emit structured JSON for automation and fleet management." | §5 unified schema; every tool's `--json` mode tested. | `jq -e .` parse test on every tool's output |
| "Every finding includes actionable remediation." | §5.3 `remediation` field required for severity ≥ warning. | `verify-structure.sh` checks no finding lacks remediation |
| "Proxmox VE operators can diagnose and repair VMs offline from the host." | `lamboot-toolkit-pve` companion; core tools' `--offline DISK` mode. | Tier 1 fleet test includes offline-VM-diagnose scenarios |
| "LamBoot-specific deep introspection via `lamboot-inspect`." | Python tool mirror from lamboot-dev; 44/44 tests passing as of 2026-04-05. | lamboot-dev's CI is the authoritative gate |
| "UEFI-aware unified help with three surfaces: CLI, man pages, web." | §10 registry-driven rendering. | Build produces all three; CI asserts consistency |
| "Fedora Copr packages at every release." | `.copr/` directory with RPM specs; Copr builds triggered on release. | CI asserts Copr build succeeds before release tag |
| "Shellcheck-clean across the entire codebase." | `.shellcheckrc` at repo root; CI blocks on violations. | `ci.yml` step 1 |

### 13.3 Prohibited claims (until backing code exists)

- "Works on Windows / macOS / BSD" — FALSE permanently.
- "GUI available" — FALSE permanently.
- "Supports every bootloader on Earth" — FALSE. We support the enumerated set in §11.1.
- "Automatically fixes every boot issue" — FALSE. Doctor's policy is conservative; critical issues never auto-apply.
- "Replaces your distro's boot management tools" — FALSE. We're additive, not a replacement for `grub-install` / `bootctl` / etc.
- "Safe to run on production without backup" — FALSE for mutating tools. Doctor and migrate always back up first; users should still have tested backups.
- "Debian upstream package available" — FALSE until v1.0+.
- "Homebrew tap available" — FALSE until v0.5+.

### 13.4 Marketing-discipline rules

1. Any public claim not in §13.2 must be added HERE FIRST with its code-path backing before appearing in README, website, announcements, or sales copy.
2. If §13.2 changes (claim added or refined), the corresponding code-path reference is updated in the same commit as the claim itself.
3. Marketing copy authors reference this document by URL (`/docs/SPEC-LAMBOOT-TOOLKIT-V1.md#13-claims-appendix--marketing-discipline`) when drafting.
4. If a user disputes a claim, the resolution process is: open the CI verification job for the claim, inspect its output, confirm or refute.
5. When `lamboot-migrate` spin-off ships (v1.0 milestone), it inherits a parallel claims appendix in its own standalone documentation.

### 13.5 CI enforcement

`tools/verify-structure.sh` (copied pattern from SDS-4 §9.3):
1. Parses §13.2 for each claim and its code-path reference
2. Confirms the referenced file/function exists and contains the expected symbols
3. For claims backed by CI jobs, asserts the CI job is in `.github/workflows/ci.yml`
4. Fails the build if any reference is stale
5. Runs in every PR and every push to main

Keeps the claims appendix honest as the code evolves.

---

## 14. Cross-repo coordination

### 14.1 Coordination principles

1. **Bidirectional spec references.** Any capability spanning `lamboot-tools-dev` and `lamboot-dev` is documented in BOTH specs with cross-references.
2. **Shared schemas are single-source.** `/etc/lamboot/fleet.toml` schema is defined here (§16 Appendix C); lamboot-dev references it, doesn't re-define.
3. **Release coordination via cross-linked notes.** Every release on either side that affects the other links to the counterpart's release notes.
4. **Breaking changes require lockstep.** If toolkit depends on a lamboot-dev capability, bumping the capability is coordinated across both repos in the same release window.
5. **Canonical source is declared once per file.** Files mirrored between repos have a canonical source; mirror-copies are derived at release-build time, never edited directly.

### 14.2 Canonical source map

| File | Canonical location | Mirrored to | Mirror mechanism |
|---|---|---|---|
| `lamboot-inspect` (Python) | `~/lamboot-dev/tools/lamboot-inspect` | toolkit `/tools/lamboot-inspect` | `publish/mirror-from-lamboot-dev.sh` |
| `lamboot-inspect` man page | `~/lamboot-dev/tools/lamboot-inspect.1` | toolkit `/man/lamboot-inspect.1` | same |
| `esp-deploy.sh` (shared shell lib) | `~/lamboot-dev/lib/esp-deploy.sh` | toolkit `/lib/esp-deploy.sh` | same. Encodes the canonical ESP file-layout (paths, `-signed.efi`→bare rename rule, manifest format) consumed by `lamboot-install` (online) and `lamboot-esp deploy` (offline). |
| `lamboot-monitor.py` | `~/lamboot-dev/tools/lamboot-monitor.py` | toolkit `/pve/tools/lamboot-pve-monitor` (renamed) | `publish/mirror-pve-from-lamboot-dev.sh` |
| `build-ovmf-vars.sh` | `~/lamboot-dev/tools/build-ovmf-vars.sh` | toolkit `/pve/tools/lamboot-pve-ovmf-vars` (renamed) | same |
| `lamboot-hookscript.pl` | `~/lamboot-dev/tools/lamboot-hookscript.pl` | Not mirrored. Documented in toolkit spec; users install from lamboot-dev side. | N/A |
| `KEY-GENERATION.md` | `~/lamboot-dev/docs/KEY-GENERATION.md` | Toolkit website references; not mirrored | N/A |
| `fleet.toml` schema | THIS spec §16 Appendix C | lamboot-dev hookscript reads per this schema | Schema version in both specs |

### 14.3 Release coordination table for v0.2

Only two repos coordinate: `lamboot-dev` and `lamboot-tools-dev`. The
`lamboot-toolkit-pve` subpackage ships from the latter; no third repo.

| Item | lamboot-dev action | lamboot-tools-dev action |
|---|---|---|
| Hookscript rewrite (Phase 1 fix) | Ship in v0.8.4 | `lamboot-pve-setup` depends on v0.8.4+; `pve/README.md` notes prereq |
| `fleet.toml` schema | Read per §16 Appendix C | Author §16 Appendix C; used by `lamboot-pve-setup` and `lamboot-pve-fleet` |
| `lamboot-install` opt-in prompt for toolkit | Add in v0.8.4 | README explains the opt-in |
| README cross-references | Toolkit section updated | LamBoot reference updated (core + pve sections) |
| Website cross-links | `/tools/` landing on lamboot.dev linked | `/tools/` + `/tools/pve/` site content |
| Combined release announcement | Bootloader section | Toolkit + PVE-subpackage section |

### 14.4 Cross-repo CI coordination

- Toolkit CI pulls canonical files from lamboot-dev at release-build time. Requires lamboot-dev tag present at toolkit tag time.
- Toolkit CI verifies mirrored files match canonical source checksums.
- Toolkit CI tests `lamboot-inspect` with the mirror path.
- Fleet test nightly exercises both repos' integration together.

### 14.5 Ongoing maintenance

- Monthly review of cross-repo coordination items (in a rolling `CROSS-REPO-STATUS.md` in each dev repo).
- Quarterly alignment checkpoint: confirm `fleet.toml` schema hasn't diverged, mirror paths still correct, LamBoot install script still recommends toolkit.

---

## 15. Open questions + deferred decisions

### 15.1 Deferred to post-v0.2

- **`lamboot-migrate --offline DISK`** — complex (mount rootfs, chroot, exec migration pipeline from host). Deferred to v0.3.
- **`lamboot-doctor` policy expansion** — v0.2 ships a conservative policy; richer policy in v0.3 after field feedback.
- **`lamboot-signing-keys` Scope 1 + Scope 2 full coverage** — v0.2 ships initial framework; full coverage at v0.5.
- **Proxmox Phase 3 (native `--lamboot` config option)** — Proxmox upstream engagement. v1.0+.
- **Proxmox Phase 4 (web UI panel)** — separate product; post-toolkit-v1.0.
- **Homebrew tap** — v0.5.
- **Debian upstream** — v1.0.

### 15.2 Research items without decisions

- **Windows dual-boot handling in `lamboot-migrate`** — currently refused per SDS-7 §5.7. Re-opening this requires a research session on hybrid MBR + Windows BCD rewriting. Not prioritized.
- **btrfs snapshot integration for rollback** — could make rollback more robust on btrfs systems. Distro-specific; not planned for v0.2.
- **aarch64 toolkit support** — toolkit bash tools are architecture-agnostic by inheritance; `lamboot-uki-build` would need aarch64 codepaths. Deferred until aarch64 fleet exists.
- **Additional bootloader recognition** — Limine, Clover, GummyBoot legacy, Petitboot. Added as users request.

### 15.3 Questions escalating to founder

None outstanding as of 2026-04-22. All §4.1–§4.6 research questions answered.

### 15.4 Known-unknowns to watch

- **Microsoft UEFI CA 2011 expires June 2026** — affects Secure Boot signing. Toolkit's `lamboot-signing-keys` tool must document this and provide migration help before the deadline.
- **Shim 16+ adoption across distros** — changes the MOK enrollment path. `lamboot-diagnose` must recognize both shim 15.x and 16+ deployments.
- **Proxmox 9.x release** — may change hookscript API. Monitor and adapt.
- **Fedora 45 / Ubuntu 26.04 defaults** — may switch default bootloader; re-validate Tier 1 test matrix.

---

## 16. Appendices

### Appendix A — Tool naming conventions

**Core toolkit prefix:** every tool begins with `lamboot-`.

**Package prefix for hypervisor-specific companions:** `lamboot-<hypervisor>-*`.
- `lamboot-pve-*` for Proxmox VE (current)
- `lamboot-nutanix-*` for future Nutanix (not scoped)
- `lamboot-vmware-*` for future VMware (not scoped)

**Subcommand naming:**
- Imperative verbs: `setup`, `check`, `clean`, `save`, `restore`, `show`, `list`, `diagnose`, `repair`, `migrate`, `verify`, `rollback`.
- Never: `do-*`, `process-*`, `handle-*`, `run-*` as standalone subcommands. Domain verbs only.

**Forbidden generic names:** no `lamboot-utils`, `lamboot-helpers`, `lamboot-common`, `lamboot-lib` as user-facing tools. Internal libraries live under `/usr/lib/lamboot-tools/` with specific names (`lamboot-toolkit-lib.sh`, `lamboot-toolkit-help.sh`).

### Appendix B — `verified_via` vocabulary (trust-log)

Reference for `lamboot-diagnose` / `lamboot-inspect` consumers. Canonical list is in `~/lamboot-dev/docs/specs/SPEC-NATIVE-TRUST-CHAIN.md` Appendix A; reproduced here:

```
shim_mok                       — ShimLock accepted via MOK cert
shim_vendor                    — ShimLock accepted via shim vendor cert
shim_sbat_rejected             — ShimLock rejected on SBAT revocation
shim_not_enrolled              — ShimLock rejected; cert not enrolled
shim_absent_after_driver_load  — ShimLock disappeared mid-boot (v0.8.3 bug)
firmware_db_fallback           — Firmware DB Security2Arch accepted
firmware_db_rejected           — Firmware DB returned ACCESS_DENIED
degraded_trust_sb_off          — SB off; no verify attempted
security_override              — Legacy SecurityOverride hook (SDS-6 deprecates)
rejected                       — Catch-all; details in note
sb_disabled                    — Historical v0.8.3 token; preserved
```

`lamboot-diagnose` maps each to a toolkit finding per §11.4.

### Appendix C — `/etc/lamboot/fleet.toml` schema v1

Authoritative schema for the shared config consumed by `lamboot-pve-setup`, `lamboot-hookscript.pl`, and `lamboot-pve-monitor`.

```toml
# Schema version. Major bump breaks consumers; minor is additive.
schema_version = 1

[fleet]
# Required. Fleet identifier injected into fw_cfg.
id = "prod-cluster-01"                    # string; 1–64 chars; [a-zA-Z0-9_-]

# Optional. Human-readable cluster name.
cluster_name = "Production Cluster 1"     # string; 0–256 chars

[roles]
# Optional. VMID → role mapping (explicit override).
# Keys are VMIDs as strings (TOML doesn't allow integer keys well).
# Values are role names; arbitrary strings; semantic meaning is user-defined.
"100" = "webserver"
"101" = "database"

[tags]
# Optional. Proxmox tag → role mapping for automatic role assignment.
# Keys are role names; values are arrays of Proxmox tags that trigger the role.
webserver = ["web", "nginx", "apache"]
database = ["db", "postgres", "mysql"]
# Matching priority: [roles] explicit VMID overrides [tags] auto-assignment.

[monitor]
# Optional. lamboot-pve-monitor settings.
poll_interval_seconds = 300               # integer; default 300; min 60
alert_webhook = "https://..."             # string; optional; HTTPS only
log_path = "/var/log/lamboot-monitor.log" # string; default as shown

[hookscript]
# Optional. lamboot-hookscript.pl settings.
config_dir = "/var/lib/lamboot"           # string; default as shown; must be writable by root
inject_fleet_id = true                    # boolean; default true
inject_role = true                        # boolean; default true
inject_vmid = true                        # boolean; default true
```

Validation rules (enforced by `lamboot-pve-setup --check`):
- `schema_version` required; must be `1` in v0.2.
- `[fleet].id` required.
- `[roles]` keys must be valid Proxmox VMIDs (integers as strings).
- `[tags]` role names must not conflict with Proxmox reserved tag names.
- `alert_webhook` must be HTTPS.
- `config_dir` must exist and be root-writable.

Schema bumps follow toolkit major version cadence.

### Appendix D — Per-tool SDS outline template

Each core tool gets its own SDS during Session B onwards. Template:

```
# SPEC-<TOOL>: <tool name>

**Version:** 1.0 (tool v1.0 target; tool shipping maturity may differ)
**Date:** YYYY-MM-DD
**Status:** Draft | Ready for review | Implemented
**Parent spec:** SPEC-LAMBOOT-TOOLKIT-V1.md §3.1 entry

---

## 1. Overview
## 2. CLI interface (subcommands, flags, positional args)
## 3. Flow / algorithm (per-subcommand)
## 4. Dependencies (external tools, shared library functions)
## 5. JSON output schema (tool-specific `context` and `actions_taken` shapes)
## 6. Safety checks + refusal conditions
## 7. Backup + rollback (if mutating)
## 8. Distro-specific variations
## 9. Test plan (bats + fixture images)
## 10. Acceptance criteria
## 11. Risks + open questions
## 12. Reference commands + example output
```

Per-tool SDSes for D.1 through D.8 (see §3.1) are authored during Session B–J per the §12.1 session plan.

### Appendix E — References

- `~/lamboot-dev/docs/STATUS-2026-04-22-TOOLKIT-PIVOT.md` — session origin
- `~/lamboot-tools-dev/docs/SDS-7-GAP-ANALYSIS.md` — `lamboot-migrate` v0.1.0 → v1.0 gap analysis
- `~/lamboot-tools-dev/docs/PROXMOX-INTEGRATION-ROADMAP.md` — 5-phase Proxmox integration plan
- `~/lamboot-dev/docs/specs/SPEC-LAMBOOT-MIGRATE.md` — SDS-7, `lamboot-migrate` tool-level spec
- `~/lamboot-dev/docs/specs/SPEC-NATIVE-TRUST-CHAIN.md` — SDS-4, trust-log schema and claims discipline model
- `~/lamboot-dev/docs/specs/SPEC-UKI-PE-PARSER.md` — UKI section parser (bootloader-internal; informs `lamboot-uki-build` output format)
- `~/lamboot-dev/docs/specs/SPEC-PREFLIGHT-VALIDATION.md` — bootloader-internal preflight (clarifies `lamboot-preflight` is subsumed into `lamboot-diagnose`)
- `~/lamboot-dev/docs/specs/SPEC-LAMBOOT-INSTALL.md` — LamBoot installer; `lamboot-migrate to-lamboot` integration point
- `~/lamboot-dev/docs/SECURE-BOOT-AND-SIGNING-STRATEGY.md` — signing strategy consumed by `lamboot-signing-keys`
- `~/lamboot-dev/docs/KEY-GENERATION.md` — authoritative key-gen procedure; Scope 1 of `lamboot-signing-keys` consumes this
- `~/lamboot-dev/docs/MOK-ENROLLMENT-GUIDE.md` — user-facing MOK UX; Scope 2 of `lamboot-signing-keys` assists with this
- `~/lamboot-dev/docs/OVMF-VARS-PROXMOX.md` — Proxmox Config 4 deployment; `lamboot-pve-ovmf-vars` automates
- `~/lamboot-dev/docs/BOOT-TOOLKIT-LANDSCAPE-2026-04-04.md` — pre-spec thinking; superseded by this document
- `~/lamboot-dev/docs/ROADMAP.md` — LamBoot bootloader roadmap; coordinated with §12

---

## 17. Sign-off

This specification is **ready for implementation** when:

- [ ] Founder has reviewed and explicitly acknowledged
- [ ] Cross-repo coordination items in §14.3 are mirrored into `~/lamboot-dev/docs/ROADMAP.md`
- [ ] `lamboot-tools-dev/ROADMAP.md` is created or updated to reference this spec as authoritative
- [ ] Session B can begin

Amendments to this specification require:
- Documented rationale in the PR description
- Cross-references updated if any claim in §13.2 is affected
- `tools/verify-structure.sh` passing after the amendment
- Version bump to the spec (1.0 → 1.1 for additive, 2.0 for breaking)
- Corresponding CHANGELOG entry in both `lamboot-tools-dev` and, if cross-repo impact, `lamboot-dev`

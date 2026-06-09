# lamboot-tools Roadmap

This roadmap is a living tracker. It reflects the product scope, tool maturity,
release cadence, and the federated component architecture decided in the
toolkit spec.

---

## Current status

**Shipping release: lamboot-tools 0.9.1** (June 2026). The 0.9 line adds a
boot-audit-and-hygiene capability set (`lamboot-nvram`, `lamboot-pve-migrate`,
and the `lamboot-inspect` boot-verdict engine) on top of the federated,
shell-only 0.8.0 architecture. The suite is feature-complete across its core
tools and ships the bundled component binaries described below.

lamboot-tools is the Linux UEFI boot toolkit: a suite of standalone CLI tools
for boot diagnosis, ESP management, backup, repair, BIOS-to-UEFI and
cross-bootloader migration, UKI building, and Secure Boot key handling. It is
bootloader-agnostic and treats GRUB, systemd-boot, rEFInd, Limine, and LamBoot
as first-class peers. Every tool emits structured JSON (stable schema v1), and
every warning-or-above finding carries a machine-readable remediation command
and documentation URL.

All intellectual property is owned by Lamco Development LLC.

---

## Component architecture (federation)

lamboot-tools is the shell orchestration layer of a four-product family that
shares one brand and one design language:

| Product | Role | Form |
|---|---|---|
| **lamboot** | The memory-safe UEFI bootloader (reference target) | Rust, separate product |
| **lamboot-tools** | The shell CLI suite (this repository) | Shell |
| **lamboot-reader** | GRUB configuration reader and resolver | Rust, bundled binary |
| **lamboot-capcheck** | Firmware and platform capability auditor | Rust, bundled binary |

During the 0.7.x line the reader and the capability auditor were developed as
Rust crates inside this repository. As of 0.8.0 they live in their own
repositories and ship as **prebuilt, statically linked (musl) binaries**
bundled into the release. The shell suite no longer compiles Rust; it
orchestrates these components at runtime. `lamboot-doctor` and
`lamboot-migrate --capcheck-gate` consume `lamboot-capcheck` from `PATH` and
degrade gracefully when it is absent. `lamboot-reader` ships as a standalone
CLI.

This is a packaging decision, not a scope reduction: the installed product
keeps the same capability, while each component gains an independent release
cadence and toolchain floor.

### Two-phase trajectory

- **Phase 1 (current):** the Rust component source is private; their compiled
  binaries are bundled with lamboot-tools and shipped through the channels we
  control directly (GitHub Releases and Fedora COPR carry the full product;
  AUR and a Homebrew tap carry it as well). Curated distributions (RPM Fusion,
  Debian) receive the shell core, which is fully functional on its own.
- **Phase 2 (planned):** the components are published as public repositories
  and crates, `lamboot-reader` is integrated directly into the shell tools
  (for example to back `lamboot-migrate` command-line-drift checks), and the
  full product becomes eligible for build-from-source inclusion in curated
  distributions.

The bundling pipeline (`publish/vendor-binaries.sh`) is manifest-driven so a
new component, or a component's transition to a published tag, is a one-line
change.

---

## Released history

| Version | Date | Summary |
|---|---|---|
| 0.2.0 | 2026-04-23 | First public release (coordinated with lamboot 0.8.4). |
| 0.3.0 | 2026-04-26 | Follow-up release. |
| 0.8.0 | 2026-06-03 | Federated, shell-only re-architecture; bundled component binaries; copyright to Lamco Development LLC. |
| 0.9.1 | 2026-06-08 | Boot audit & hygiene: `lamboot-nvram` (boot-entry cleanup), `lamboot-pve-migrate` (host-side BIOS→UEFI lifecycle), `lamboot-inspect` boot-verdict engine; documentation brought current for publication. |

(The internal 0.7.x tags tracked the capability-auditor development that has
since been extracted to `lamboot-capcheck`; they were never published. The
internal 0.8.1, 0.8.2, and 0.9.0 milestones were folded into the public 0.9.1
release.)

---

## Core suite (package `lamboot-tools`)

| Tool | Maturity | Notes |
|---|---|---|
| `lamboot-diagnose` | stable | Read-only UEFI boot-chain scan, 11 categories, remediation per finding |
| `lamboot-esp` | stable | ESP health, inventory, stale-file cleanup, offline deploy |
| `lamboot-backup` | stable | Boot-config snapshot save / restore / show / list |
| `lamboot-repair` | stable | Diagnose-plan-confirm-execute-verify, online or offline |
| `lamboot-migrate` | stable | BIOS-to-UEFI and cross-bootloader migration, verify, rollback |
| `lamboot-doctor` | beta | Guided diagnose-to-repair wrapper; splices capcheck findings |
| `lamboot-uki-build` | beta | Build / inspect / sign / verify Unified Kernel Images |
| `lamboot-signing-keys` | experimental | Secure Boot key lifecycle |
| `lamboot-toolkit` | stable | Suite dispatcher |
| `lamboot-inspect` | stable | LamBoot-specific introspection + boot-verdict engine (Python, mirrored from lamboot) |
| `lamboot-nvram` | beta | UEFI boot-entry inventory + dead-entry cleanup (Python); online or offline OVMF VARS |

### Bundled component binaries (`lamboot-tools-firmware`)

| Binary | Maturity | Notes |
|---|---|---|
| `lamboot-capcheck` | beta | Firmware/platform capability auditor, 12 domains; consumed by doctor + migrate |
| `lamboot-reader` | beta | GRUB config reader/resolver; standalone CLI |

### Proxmox VE companion (`lamboot-toolkit-pve`)

| Tool | Maturity | Source |
|---|---|---|
| `lamboot-pve-setup` | beta | This repository (`pve/`) |
| `lamboot-pve-fleet` | experimental | This repository (`pve/`) |
| `lamboot-pve-migrate` | experimental | This repository (`pve/`) — host-side BIOS→UEFI guest lifecycle |
| `lamboot-pve-monitor` | stable | Mirrored from lamboot |
| `lamboot-pve-ovmf-vars` | stable | Mirrored from lamboot |

---

## Forward roadmap

> **Direction sketch (draft, unsettled):** a longer-term language and
> architecture direction is under exploration (selected tools graduating to
> self-contained Rust CLIs, with PVE integration as the expected accelerant).
> It is not yet promoted into the items below.

### Next (0.9.x / 0.10.0)

- Integrate `lamboot-reader` directly into the shell tools (command-line-drift
  detection for `lamboot-migrate`, GRUB compatibility reporting).
- Expand `lamboot-capcheck` domain coverage and the curated quirks database
  from field data.
- Ubuntu / Debian PPA for the shell core.
- `lamboot-doctor` policy matrix expansion after field feedback.

### Phase 2 enablement

- Publish `lamboot-reader` and `lamboot-capcheck` as public repositories and
  crates; reserve crate names.
- Build-from-source inclusion of the components in RPM Fusion and Debian.
- Additional architectures for the bundled binaries beyond x86_64 and aarch64
  as demand warrants.

### Maturity targets (1.0)

- Every core tool stable; every PVE companion tool stable.
- Debian upstream submission for the standalone `lamboot-migrate`.
- `lamboot-signing-keys` stable across the full key lifecycle.
- `lamboot-migrate` spin-off milestone: a distinct product page at
  `https://lamco.ai/products/lamboot-tools/` with an independent release cadence.

---

## Out of roadmap (permanent)

- GUI in any form. Web and dashboard UIs that consume the JSON API are separate
  products.
- Non-Linux support (Windows, macOS, BSD).
- `lamboot-doctor` defaulting to aggressive auto-fix. The default stays
  conservative.
- Snap and Flatpak packaging. Sandbox isolation is incompatible with host
  device access.

---

## Versioning and cadence

- **Hybrid version model** (spec section 8): the unified `lamboot-tools X.Y.Z`
  umbrella version bundles per-tool semantic versions plus the bundled
  component versions (`lamboot-capcheck`, `lamboot-reader`). The JSON output
  schema carries its own `schema_version` (currently v1).
- **Release cadence:** 2 to 4 months for minor versions; patch releases on
  demand.
- **Claim honesty:** every claim in the toolkit spec section 13.2 has a
  code-path backing verified by `scripts/verify-claims.sh` in CI.

---

## Amendment procedure

Changes to this roadmap that are not purely status updates (new tools, deferred
tools, version-target changes) require updating the toolkit design spec first.
This file tracks execution; the spec tracks scope.

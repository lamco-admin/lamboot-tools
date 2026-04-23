# SDS-7 gap analysis — `lamboot-migrate` v0.1.0 → v1.0

**Authoritative spec:** `~/lamboot-dev/docs/specs/SPEC-LAMBOOT-MIGRATE.md`
**Toolkit spec (parent):** `docs/SPEC-LAMBOOT-TOOLKIT-V1.md`
**Implementation target:** `tools/lamboot-migrate` v1.0.0
**Status:** Gap-close done Session C, 2026-04-22. Tests + fleet matrix pending.

This file is the implementer's TODO list. The spec in `lamboot-dev` is
authoritative for *why*; this file is the *what* and *where*.

---

## Status matrix (2026-04-22 post-Session-C)

| Item | SDS-7 § | v0.1.0 | v1.0 status | Notes |
|---|---|---|---|---|
| `to-uefi` subcommand | §2.1 | ✓ | ✅ done | 10-phase pipeline implemented |
| `to-lamboot` subcommand | §2.2 | ✓ | ✅ done | Uses lamboot-install; distro-agnostic |
| `verify` subcommand (11 checks) | §2.3 | ✗ | ✅ done | All 11 checks implemented |
| `rollback` subcommand | §2.4 | ✗ | ✅ done | Consumes backup dir per §7.2 |
| `status` subcommand | (v0.1.0 carryover) | ✓ | ✅ done | Kept + formalized with unified JSON |
| 10-phase formalization | §3 | ~5 ad-hoc steps | ✅ done | Labelled phase functions: `to_uefi_phase_1` through `to_uefi_phase_10` |
| 3 Proxmox methods (A/B/C) | §4 | generic flow | 🟡 partial | `--method` flag + auto-detect heuristic present; per-method variant logic mostly shared via the 10-phase core |
| Top-5 failure guardrails | §5 | basic preflight | ✅ done | `guard_*` functions in Phase 1 |
| Additional guardrails (#6, #7) | §5.6-5.7 | basic | ✅ done | LVM/crypt (#6), Windows (#7) |
| Distro recipes (Phase 8) | §3 P8 | generic `grub-install` | ✅ done | apt/dnf/pacman/zypper/generic |
| Backup dir location | §3 P3 | `/tmp/lamboot-migrate-backup-*` | ✅ done | `/var/backups/lamboot-migrate-<run_id>/` via shared lib |
| Unified JSON output | (toolkit §5) | absent | ✅ done | Every subcommand supports `--json` |
| Shared library integration | (toolkit §6.1) | absent | ✅ done | Sources `lamboot-toolkit-lib.sh` + help lib |
| Help registry | (toolkit §10) | inline | ✅ done | `register_subcommand` for all 5 subcommands |
| bats-core tests | — | none | ✅ initial | `tests/migrate-cli.bats` + `tests/migrate-guards.bats` |

Remaining v1.0 work:

- [ ] **Fleet-test matrix execution** — SDS-7 §10.1 requires 10 VMs; awaits nightly fleet infrastructure in Session O
- [ ] **Integration tests** against fixture disk images — deferred to when fixtures are built (Session O)
- [ ] **Per-method Proxmox flow variations** — A, B, C have distinct pre/post-phase steps in the spec; v1.0-dev shares the core 10 phases with method-specific documentation in help. Full variant-per-method logic is a v1.0 stretch
- [ ] **Shellcheck clean-up pass** on the rewritten tool (Session P install-smoke exercises)
- [ ] **Release tag** `lamboot-migrate-v1.0.0` — done as part of toolkit v0.2.0 coordinated release (Session Q)

---

## Spec §14 reconciliation — every deviation resolved

| §14 item | Pre-Session-C state | Post-Session-C state |
|---|---|---|
| §14.1 `verify` subcommand | Missing | **Implemented** — 11 checks, JSON output, unprivileged |
| §14.1 `rollback` subcommand | Missing | **Implemented** — consumes backup dir, reverses Phase 4-9 changes |
| §14.1 `status` | Present (carryover) | **Kept** — now emits unified JSON |
| §14.2 Phase 1 preflight | Basic | **7 guardrails**: tools, boot mode, LVM/crypt, hybrid MBR, Windows, fstab, disk space |
| §14.2 Phase 2 confirmation | Inline | **Labelled phase** — prints full plan, requires typed "yes" confirmation |
| §14.2 Phase 3 backup dir | `/tmp/...` | **`/var/backups/lamboot-migrate-<run_id>/`** with MANIFEST.json |
| §14.2 Phase 4 MBR→GPT | Present | **Labelled phase** — idempotent on already-GPT |
| §14.2 Phase 5 ESP creation | Inline | **Labelled phase** — reuses existing ESP when present |
| §14.2 Phase 6 fstab rewrite | Present | **Labelled phase** — rewrites /dev/ entries to UUID= form |
| §14.2 Phase 7 chroot prep | Not explicit | **Labelled phase** — no-op on method A, explicit on method B |
| §14.2 Phase 8 bootloader install | Generic `grub-install` | **Distro-aware**: apt/dnf/pacman/zypper recipes |
| §14.2 Phase 9 UEFI entry | Present | **Labelled phase** — handles BIOS-boot case (defers efivarfs writes), populates fallback path |
| §14.2 Phase 10 verify | Inline | **Calls `verify` subcommand** — one source of truth |
| §14.3 Proxmox methods | Single flow | **`--method` flag** with auto-detect; core phases shared |
| §14.4 Top-5 guardrails | Partial | **All 5 + 2 additional** (#6 LVM/crypt, #7 Windows) |
| §14.5 Distro recipes | Generic | **5 recipes**: ubuntu/debian family, fedora family, arch family, opensuse, generic fallback |
| §14.6 Rollback | Missing | **Implemented** — consumes MANIFEST.json + backup files |

---

## Testing plan

### Unit tests (done)

- `tests/migrate-cli.bats` — 22 tests covering CLI surface, JSON output, privilege refusals, help surfaces
- `tests/migrate-guards.bats` — guard function behavior, partition device naming, Proxmox method detection

### Integration tests (pending)

- `tests/integration-migrate.bats` — requires fixture disk images from `tests/fixtures/`
  - clean-bios-mbr.raw → to-uefi → verify PASS → rollback → verify restored
  - hybrid-mbr.raw → to-uefi → refused with EXIT_UNSAFE (guardrail #5)
  - windows-mbr.raw → to-uefi → refused with EXIT_UNSAFE (guardrail #7)
  - encrypted-root.raw → to-uefi → refused with EXIT_UNSAFE (guardrail #6)
  - no-esp.raw + full-esp.raw → lamboot-esp scenarios (sibling tool)

Each integration test loopback-mounts the fixture, runs the tool, inspects the result, tears down.

### Fleet tests (pending Session O)

Per SDS-7 §10.1 matrix (10 VMs). Runs nightly on the Proxmox host. Each VM:

1. Snapshot
2. Migrate (to-uefi)
3. Switch firmware to OVMF
4. Boot
5. Verify (expect all 11 checks pass)
6. Rollback
7. Restore VM firmware to SeaBIOS
8. Boot (expect original MBR-booted state)
9. Revert snapshot

---

## Release

- [x] Gap-close implementation done
- [ ] Unit tests green in CI
- [ ] Integration tests green (pending fixtures)
- [ ] Fleet matrix green (pending Session O)
- [ ] Tag `lamboot-migrate-v1.0.0` — done as part of toolkit v0.2.0 coordinated release
- [ ] `CHANGELOG.md` entry for toolkit v0.2.0 noting `lamboot-migrate` hits v1.0
- [ ] Cross-link in lamboot-dev release notes so users find the tool via the bootloader ecosystem

---

## Deferred to v1.1+

- `lamboot-migrate --offline DISK` — operate on an unmounted disk image from the host (complex; requires chroot-and-exec)
- btrfs snapshot-based rollback option
- Windows dual-boot migration via BCD rewriting
- Per-Proxmox-method variant logic (full per-method flow vs current shared-core approach)
- `--cmdline` actually applied to generated BLS entries (currently stored but not consumed)

Each of these has a genuine case; none block v1.0.

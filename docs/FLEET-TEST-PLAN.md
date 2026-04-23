# Fleet Test Plan

**Authoritative spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §9.2
**Matrix authority:** `~/lamboot-dev/docs/FLEET-TEST-PLAN-2026-04-21.md` (the bootloader's own fleet)
**Status tracker:** this file tracks *toolkit*-level testing; bootloader-level results stay in lamboot-dev

This plan defines the three-tier testing matrix for `lamboot-tools`, the infrastructure that runs it, and the pass/fail criteria for a release.

---

## 1. Three-tier model (recap)

| Tier | Blocking? | Scope | Runs |
|---|---|---|---|
| **Tier 1** | **Release-blocking** | 5 distros × 2 firmwares × 2 bootloaders | Nightly on founder's Proxmox host |
| **Tier 2** | Gate for per-tool `v1.0` | Tier 1 + real hardware smoke-test | Manual pre-release on laptop |
| **Tier 3** | Reported only | Extended fleet / community | Ad-hoc; noted in release notes |

A release cannot ship without Tier 1 green.

---

## 2. Tier 1 matrix

**5 distros × 2 firmware × 2 bootloaders = 20 VM slots.** Each VM runs the full toolkit smoke (every tool's read-only path + `lamboot-migrate status` + `lamboot-doctor --no-repair --json`). Mutating paths are exercised against intentionally-broken state (detailed in §4).

### 2.1 Distro / firmware / bootloader matrix

| Distro | VMID range | UEFI + GRUB | UEFI + sd-boot | BIOS + GRUB |
|---|---|---|---|---|
| Ubuntu 24.04 LTS | 2100–2109 | 2100 | 2101 | 2102 |
| Debian 13 (trixie) | 2200–2209 | 2200 | — | 2202 |
| Fedora 44 | 2300–2309 | 2300 | 2301 | 2302 |
| Arch Linux (current) | 2400–2409 | 2400 | 2401 | 2402 |
| openSUSE Tumbleweed | 2500–2509 | 2500 | — | 2502 |

Empty cells = distro doesn't ship that bootloader by default. 17 VM slots in the matrix; each is a Proxmox VM snapshotted at "freshly installed, pre-toolkit" state.

### 2.2 Negative-case VMs

Tier 1 also exercises refusal paths. These VMs are kept in a "broken" state; tests assert the toolkit refuses correctly:

| VMID | Broken state | Asserts |
|---|---|---|
| 2700 | Hybrid MBR (synthetic) | `lamboot-migrate to-uefi` exits `EXIT_UNSAFE` |
| 2701 | Windows 11 + NTFS with Boot Manager | `lamboot-migrate to-uefi` exits `EXIT_UNSAFE` |
| 2702 | LVM-on-root | `lamboot-migrate to-uefi` exits `EXIT_UNSAFE` |
| 2703 | dm-crypt-on-root | `lamboot-migrate to-uefi` exits `EXIT_UNSAFE` |
| 2704 | No ESP | `lamboot-esp check` exits with critical finding |
| 2705 | Corrupted ESP FAT | `lamboot-esp check` reports `esp.filesystem.integrity` warning |
| 2706 | 99% full ESP | `lamboot-esp check` reports `esp.filesystem.space` error |

### 2.3 LamBoot-specific VMs

LamBoot integration checks need an OVMF VM with LamBoot installed:

| VMID | Scenario | Asserts |
|---|---|---|
| 2800 | LamBoot healthy | `lamboot-inspect` runs; `lamboot-diagnose` finds `vm.lamboot_state=BootedOK` |
| 2801 | LamBoot in CrashLoop | `lamboot-diagnose` finds `vm.lamboot_state` with severity critical |

**Total Tier 1 fleet: 26 VMs.**

---

## 3. Pass criteria per VM

For each VM in the matrix, the nightly run executes:

```bash
# Read-only sweep — must complete without EXIT_ERROR
sudo lamboot-diagnose --json > results.json
sudo lamboot-esp check --json >> results.json
sudo lamboot-esp inventory --json >> results.json
sudo lamboot-backup list --json >> results.json
sudo lamboot-migrate status --json >> results.json
sudo lamboot-doctor --no-repair --json >> results.json
sudo lamboot-toolkit status --json >> results.json

# JSON envelopes must all parse
jq -e . < results.json > /dev/null
```

**VM passes Tier 1 if:**
- Every JSON envelope parses under `jq`
- Every envelope has `schema_version == "v1"`
- No tool exits with `EXIT_ERROR` (1) on read-only paths
- Findings align with expected state (negative-case VMs DO emit critical/error findings — that's the point)

---

## 4. Fixture disk images

Integration tests (bats) run against checked-in fixture disk images. See `tests/fixtures/README.md` for the full catalog and download procedure. Summary:

| Fixture | Purpose |
|---|---|
| `clean-bios-mbr.raw` | Baseline BIOS+MBR system |
| `clean-uefi-gpt.raw` | Baseline UEFI+GPT system |
| `hybrid-mbr.raw` | Synthetic hybrid-MBR refusal test |
| `encrypted-root.raw` | LUKS-encrypted root refusal test |
| `windows-mbr.raw` | Windows-present refusal test |
| `no-esp.raw` | UEFI without ESP |
| `full-esp.raw` | ESP at 99% capacity |
| `corrupted-esp-fat.raw` | Intentionally-corrupted ESP FAT |
| `lamboot-installed.raw` | Fedora + LamBoot |
| `grub-installed.raw` | Ubuntu + GRUB |
| `sdboot-installed.raw` | Arch + systemd-boot |

Fixtures are generated from kickstart / preseed / cloud-init recipes under `tests/fixtures/regen/`. Regeneration is reproducible and periodically re-run to track distro defaults.

---

## 5. Nightly test infrastructure

### 5.1 Runner

Self-hosted GitHub Actions runner on the founder's Proxmox host. Labels: `[self-hosted, pve-host]`.

Workflow: `.github/workflows/fleet-test.yml` (scheduled `17 3 * * *` — daily at 03:17 UTC; off-peak minute to avoid clashing with other cron activity).

### 5.2 Driver

`scripts/fleet-test.sh` orchestrates the matrix:

```
scripts/fleet-test.sh --tier 1
```

Flow:
1. Parse `docs/FLEET-TEST-PLAN.md` §2 tables to get the VMID list
2. For each VMID:
   a. `qm snapshot-rollback <VMID> pre-toolkit` (restore clean state)
   b. `qm start <VMID>` and wait for SSH
   c. `scp` latest toolkit tarball into VM
   d. Install via `make install`
   e. Run §3 command sequence, capture JSON to host
   f. `qm stop <VMID>`
3. Aggregate per-VM JSON into a single run report at `tests/results/<date>/<VMID>.json`
4. Compare against `tests/results/baselines/<VMID>.json` — flag regressions
5. Exit non-zero if any VM regressed or a release-blocking finding appeared unexpectedly

### 5.3 Baselines

`tests/results/baselines/<VMID>.json` files are captured once per distro release and committed. Nightly runs diff against these; changes are reviewed manually before updating the baseline.

### 5.4 Nightly publish

`scripts/publish-nightly.sh` uploads the run report to `lamboot.dev/tools/nightly/<date>/` and keeps the last 30 days public. Older results archive to `lamboot.dev/tools/nightly/archive/`.

---

## 6. Tier 2 — per-tool v1.0 gate

When a beta/experimental tool reaches stable v1.0, Tier 2 validates it:

1. Full Tier 1 matrix pass
2. Real-hardware smoke-test on the founder's laptop (one physical machine, not a VM)
3. Manual checklist per tool (documented in each tool's SDS `§ acceptance criteria`)

Tier 2 blocks the tool's own v1.0 tag, not the toolkit's periodic release.

---

## 7. Tier 3 — community reporting

Any VM or distro or scenario outside Tier 1 falls here. Results are:
- Tracked ad-hoc via `gh issue` label `fleet-test-tier-3`
- Summarized in release notes under "Also tested on"
- Not release-blocking

Contributors welcome. See `CONTRIBUTING.md` for the template.

---

## 8. Current status (2026-04-22)

| Item | Status | Notes |
|---|---|---|
| Tier 1 matrix documented | ✅ This document |
| Fixture catalog specified | ✅ `tests/fixtures/README.md` |
| Fixtures built | ⏳ Not started — requires generation time |
| `scripts/fleet-test.sh` driver | ✅ Stub + structure (Session O) |
| Nightly GH Actions workflow | ✅ Scaffold from Session B + refined Session O |
| Self-hosted runner configured | ⏳ Requires Proxmox host registration |
| Baselines captured | ⏳ Requires first fleet run |
| First Tier 1 run | ⏳ Post-Session-O ops activity |

**Before v0.2.0 release:** Tier 1 must have run at least once with all 26 VMs green (negative cases included). Integration-tests (bats + fixtures) must run in CI.

---

## 9. Escalation on failures

When a nightly Tier 1 run fails:

1. GitHub Actions posts result to `#lamboot-alerts` (Slack/Matrix — TBD)
2. Issue auto-filed under label `fleet-test-regression` with VMID + diff
3. Failures block the next release until resolved or explicitly waived in `CHANGELOG.md`
4. If the failure is persistent + environmental (runner offline, network flake), document in `docs/CROSS-REPO-STATUS.md` under §1 active coordination

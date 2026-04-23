# SPEC-LAMBOOT-DOCTOR: Guided Diagnose→Repair→Verify Wrapper

**Version:** 1.0 (tool v0.2 target; maturity: **beta** at v0.2 — spec §3.4 of toolkit)
**Date:** 2026-04-22
**Status:** Ready for implementation review
**Parent spec:** `SPEC-LAMBOOT-TOOLKIT-V1.md` §6.7 (default-action policy matrix)
**Existing implementation:** NEW — introduced in Session H

---

## 1. Overview

`lamboot-doctor` is the toolkit's "it just works" entry point for users who don't want to learn the five-tool pipeline. It chains:

1. `lamboot-diagnose --json` (unprivileged scan)
2. Parse findings; convert remediation commands into a plan
3. Walk the default-action policy matrix (§3 below) for each finding
4. Escalate to root **once** via re-exec with `--doctor-resume <run_id>` when the plan contains write actions
5. Execute the plan by invoking `lamboot-repair` / `lamboot-esp clean` / other sibling tools as appropriate
6. Re-verify via `lamboot-diagnose` filtered to the specific findings that were addressed
7. Emit a final JSON envelope summarizing what was fixed, what remains, what needs manual intervention

### 1.1 Why a separate tool

- Doctor is a **policy layer**; the underlying tools are mechanism. Doctor decides *what* to auto-fix; sibling tools decide *how*.
- Policy is conservative by default (never auto-apply critical fixes without typed confirmation).
- A single command for users: `sudo lamboot-doctor` — no need to remember which of five tools to run.
- Matches the rdpdo / docker-compose / kubectl pattern: a top-level UX that orchestrates underlying primitives.

### 1.2 What doctor does NOT do

- Invoke `lamboot-migrate` automatically. BIOS→UEFI migration is always user-initiated; doctor surfaces the recommendation but never runs it.
- Override user's `--risk-limit` preferences on underlying tools.
- Make new findings that aren't surfaced by sibling tools. Doctor is pure orchestration.
- Override critical-severity safety: critical findings always require typed confirmation regardless of `--auto`.

### 1.3 Maturity posture

- **v0.2 — beta.** Policy matrix ships with conservative defaults; limited fleet-test coverage; expected to evolve based on field feedback.
- **v0.3 — stable.** Policy matrix refined; edge cases documented; default stays conservative forever per spec §12.5.

---

## 2. CLI interface

```
lamboot-doctor [GLOBAL FLAGS] [--auto] [--risk-limit LEVEL]

Tool-specific options:
    --auto                    Non-interactive mode (implies --yes); still prompts typed-yes for critical
    --risk-limit LEVEL        safe | moderate | destructive (default: moderate)
    --no-repair               Diagnose + show plan; don't invoke repair (like --plan-only)
    --no-clean                Skip ESP clean steps even if they would apply
    --doctor-resume RUN_ID    Internal: re-entry point after sudo escalation
```

All universal flags from toolkit §4.1 apply.

### 2.1 Exit codes

- **0 EXIT_OK** — healthy, or all applied fixes succeeded and verification passed
- **2 EXIT_PARTIAL** — some fixes applied, some failed or deferred for manual attention
- **3 EXIT_NOOP** — no findings at severity >= warning; nothing to do
- **5 EXIT_ABORT** — user declined confirmation
- **7 EXIT_PREREQUISITE** — missing `lamboot-diagnose` or `lamboot-repair` siblings

---

## 3. Default-action policy matrix

Per toolkit spec §6.7, the policy is conservative by default. Each row maps finding severity to doctor's behavior:

| Finding severity | Interactive default | With `--auto` |
|---|---|---|
| `critical` | Stop; show plan; require typed `yes` regardless | Stop; show plan; require typed `yes` regardless — **never auto-applies** |
| `error` | Show step; prompt y/N per remediation | Auto-apply with backup; report result |
| `warning` | Show finding + remediation command; do NOT prompt; user runs manually | Report as info-silent; do NOT apply |
| `info` | Not surfaced by doctor (lives in `lamboot-diagnose --verbose`) | Not surfaced |

### 3.1 Policy exceptions

**`vm.lamboot_state` at `CrashLoop`** (severity: critical) — policy override: doctor offers to run `lamboot-repair --auto` with its reset action if and only if:
1. User is already in a stable OS (boot succeeded past LamBoot)
2. `lamboot-repair` can resolve without data risk (reset is safe per repair §1.2)

This override is coded explicitly, not inferred from severity.

**`partition_table.type` MBR finding** — never acted on by doctor. The remediation is `lamboot-migrate to-uefi` which is excluded per §1.2. Doctor prints the recommendation and continues.

**`esp.stale.*` findings** — trigger `lamboot-esp clean --dry-run` in doctor's plan. `--auto` mode invokes `lamboot-esp clean --apply` only if free space is below 10% (the ESP is meaningfully full). Otherwise the stale files are reported but not cleaned — doctor is not a cleanup utility by default.

### 3.2 Remediation → action mapping

Each finding with `remediation.command` gets parsed into an action. Doctor recognizes these remediation patterns:

| Remediation command pattern | Doctor action |
|---|---|
| `sudo lamboot-repair ...` | Invoke `lamboot-repair` with the appropriate subset flags (e.g., `--fix-fstab` for fstab findings) |
| `sudo lamboot-esp clean ...` | Invoke `lamboot-esp clean [--apply if auto+full]` |
| `sudo lamboot-migrate ...` | NEVER invoked automatically; print recommendation, continue |
| `sudo lamboot-backup save ...` | Invoked only if doctor is about to run a write operation (backup-before-repair) |
| Any other command | Print recommendation for user to run; don't invoke |

---

## 4. Escalation pattern

1. Doctor starts unprivileged (normal user invocation)
2. Runs `lamboot-diagnose --json` — works without root
3. Parses findings, builds plan
4. If plan has any write actions AND `EUID != 0`:
    - Print "This plan needs root; re-running under sudo..."
    - `exec sudo "$0" --doctor-resume <run_id> <all-original-args>`
    - The `--doctor-resume` flag signals that diagnostic data is already collected; re-run from the plan stage
5. Post-escalation, doctor re-reads the saved run_id's diagnostic output (cached at `/var/lib/lamboot-doctor/<run_id>.json`) and proceeds without re-diagnosing
6. Execute plan via sibling tools
7. Re-verify with `lamboot-diagnose` filtered to the addressed finding IDs
8. Clean up `/var/lib/lamboot-doctor/<run_id>.json` (or retain with `--keep-resume-state` for debugging)

Single-escalation property: user types sudo password ONCE, not per-remediation. This is the UX win vs. running the five tools individually.

---

## 5. Output

### 5.1 Human format (default, on TTY)

```
lamboot-doctor — guided boot health check and repair

Running diagnose... done (0.8s)

Found 3 issues:

  [critical] No UEFI boot entries in NVRAM
    Action: create a LamBoot boot entry via lamboot-repair
    Confirm required (critical-severity).

  [warning] Fallback loader missing
    Action: lamboot-repair will install EFI/BOOT/BOOTX64.EFI
    Policy: warning → user runs manually; doctor prints command.

  [warning] ESP is 87% full
    Action: `lamboot-esp clean` (dry-run preview; apply if --auto and <10% free)
    Policy: warning → show only.

Continue (y/N)? y

Escalating to root (sudo)...

Phase: Execute (1 action)
  [1/1] Create LamBoot UEFI boot entry ...
    ✓ applied

Phase: Verify
  ✓ boot_entries.count: 1 entry (was 0)

Summary:
  1 applied, 2 manual, 0 failed.
  Manual steps:
    - sudo lamboot-repair --auto   (installs fallback loader)
    - sudo lamboot-esp clean       (cleans ESP)

Next: re-run `sudo lamboot-doctor` after applying manual steps to verify.
```

### 5.2 JSON format (`--json`)

Standard toolkit envelope with additions:

```json
{
  "findings": [ ... from diagnose ... ],
  "actions_taken": [ ... from repair / esp-clean ... ],
  "context": {
    "plan": [
      {
        "finding_id": "boot_entries.count",
        "severity": "critical",
        "action": "lamboot-repair",
        "policy": "confirmed",
        "executed": true,
        "result": "ok"
      }
    ],
    "escalated": true,
    "unaddressed": [
      {"finding_id": "esp.free_space", "reason": "warning policy"}
    ]
  }
}
```

---

## 6. Inter-tool composition

Doctor is the first tool in the suite that depends on others at runtime:

| Dependency | Used for |
|---|---|
| `lamboot-diagnose` | Initial scan + post-execute verification |
| `lamboot-repair --fix-fstab` etc. | Repair actions |
| `lamboot-esp clean` | ESP cleanup when warranted |
| Never invokes | `lamboot-migrate` (user-initiated only) |

Missing sibling tools produce EXIT_PREREQUISITE with a clear message.

---

## 7. Test plan

### 7.1 Unit tests (bats)

- `tests/doctor-cli.bats` — CLI surface, help, JSON conformance, unprivileged paths
- `tests/doctor-policy.bats` — policy-matrix behavior for each severity × mode combination

### 7.2 Integration tests (fixture disks)

- Healthy `clean-uefi-gpt.raw` → doctor exits 0 with no actions
- `lamboot-installed.raw` minus BOOTX64.EFI → doctor detects fallback-missing (warning → manual prompt) → with `--auto` exits with guidance but no action
- Fixture with 0 NVRAM entries → doctor escalates to root, creates entry, exits 0
- `full-esp.raw` → doctor in `--auto` triggers `esp clean --apply` (below-10% threshold)

### 7.3 Fleet tier 1

Every VM runs `lamboot-doctor --json` post-setup; expected 0 findings for clean VMs. Intentional breakage (delete BOOTX64.EFI) → expected 1 finding, manual-prompt in default mode, applied in --auto.

---

## 8. Acceptance criteria

- [ ] Sources shared lib + help registry
- [ ] `--json` emits schema v1 envelope with findings + actions_taken + plan metadata
- [ ] Single-escalation pattern via `--doctor-resume <run_id>` works
- [ ] Policy matrix enforced correctly: critical always-confirm, warning-never-auto, etc.
- [ ] Never invokes `lamboot-migrate` automatically
- [ ] Cached diagnostic data cleaned up post-run unless `--keep-resume-state`
- [ ] Missing sibling tools produce EXIT_PREREQUISITE
- [ ] bats tests pass in CI
- [ ] Shellcheck clean

---

## 9. Deferred to v0.3+

- Expanded policy matrix (more nuanced per-finding behavior based on field feedback)
- `--policy FILE` — user-provided policy override (YAML/TOML)
- Automated scheduling via systemd timer for periodic health checks
- Integration with `lamboot-pve-fleet` for fleet-wide doctor runs
- Parallel diagnose + policy-parse stages for large fleets

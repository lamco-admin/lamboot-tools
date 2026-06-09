#!/bin/bash
# lamboot-capcheck-bridge.sh — convert capcheck JSON into diagnose-shaped
# findings so lamboot-doctor's policy matrix can act on them.
#
# Capcheck (Rust) discovers firmware capabilities and matches a curated
# quirks DB. Doctor (Bash) translates findings into remediation actions
# via its policy matrix. The bridge translates capcheck's check + quirk
# records into doctor finding objects with stable dotted IDs and the
# same severity/status vocabulary diagnose uses.
#
# Mapping rules (capcheck addendum):
#
#   capcheck status   →  doctor severity   →  default policy
#   pass               info                    none (filtered)
#   info               info                    none (filtered)
#   skip               info                    none (filtered)
#   warn               warning                 manual
#   fail               error                   confirm (or auto with --auto)
#   error              error                   manual (probe failed; can't act)
#
#   capcheck quirk severity → doctor severity
#   critical → critical (policy=confirm always)
#   major    → error
#   high     → error
#   minor    → warning
#   info     → info (filtered)
#
# Finding ID prefixes:
#   capcheck.domain.<domain>.<check>   for check results
#   capcheck.quirk.<quirk-id>          for quirk matches
#
# Remediation command field: copied from the capcheck check's
# `remediation` string (capcheck currently emits prose, not a literal
# command, so doctor's _map_action_from_command will downgrade these to
# "manual" — printed-only). When capcheck v0.8+ ships structured
# remediation actions, doctor will be able to auto-act on them.

CAPCHECK_BIN_OVERRIDE="${CAPCHECK_BIN_OVERRIDE:-}"
CAPCHECK_BRIDGE_DEBUG="${CAPCHECK_BRIDGE_DEBUG:-0}"

# ── Discovery ────────────────────────────────────────────────────────────

# capcheck_available — returns 0 if lamboot-capcheck is on PATH (or override).
capcheck_available() {
    if [[ -n "$CAPCHECK_BIN_OVERRIDE" ]]; then
        [[ -x "$CAPCHECK_BIN_OVERRIDE" ]]
        return $?
    fi
    command -v lamboot-capcheck >/dev/null 2>&1
}

_capcheck_bin() {
    if [[ -n "$CAPCHECK_BIN_OVERRIDE" ]]; then
        printf '%s' "$CAPCHECK_BIN_OVERRIDE"
    else
        command -v lamboot-capcheck
    fi
}

# capcheck_version — prints "lamboot-capcheck X.Y.Z" or empty on failure.
capcheck_version() {
    capcheck_available || return 1
    "$(_capcheck_bin)" --version 2>/dev/null
}

# ── Audit invocation ────────────────────────────────────────────────────

# capcheck_run_audit — runs `lamboot-capcheck --json audit` and writes
# the raw JSON to stdout. Returns 0 on success, non-zero on failure.
# Honors LAMBOOT_OFFLINE_DISK by passing --target-root if a disk is mounted.
capcheck_run_audit() {
    capcheck_available || {
        [[ "$CAPCHECK_BRIDGE_DEBUG" == "1" ]] && echo "capcheck-bridge: not on PATH" >&2
        return 2
    }
    local bin args=()
    bin=$(_capcheck_bin)

    # Offline-mode forwarding: the diagnose tool exposes the disk mount
    # point in $LAMBOOT_OFFLINE_MOUNT after attaching; if present, point
    # capcheck at it via --target-root.
    if [[ -n "${LAMBOOT_OFFLINE_MOUNT:-}" ]]; then
        args+=("--target-root" "$LAMBOOT_OFFLINE_MOUNT")
    fi

    args+=("--json" "audit")

    [[ "$CAPCHECK_BRIDGE_DEBUG" == "1" ]] && echo "capcheck-bridge: invoking $bin ${args[*]}" >&2
    "$bin" "${args[@]}" 2>/dev/null
}

# ── Finding translation ─────────────────────────────────────────────────

# Map capcheck check status to doctor severity (lowercase).
_severity_from_status() {
    case "$1" in
        fail)  printf 'error' ;;
        warn)  printf 'warning' ;;
        error) printf 'error' ;;
        *)     printf 'info' ;;
    esac
}

# Map capcheck quirk severity to doctor severity.
_severity_from_quirk() {
    case "$1" in
        critical) printf 'critical' ;;
        major|high) printf 'error' ;;
        minor) printf 'warning' ;;
        *) printf 'info' ;;
    esac
}

# capcheck_to_findings_jq — emit a JSON array of doctor-shaped findings
# from capcheck audit JSON on stdin. Requires jq. Filters out info/skip
# checks so only actionable items survive.
capcheck_to_findings_jq() {
    command -v jq >/dev/null 2>&1 || {
        echo "capcheck-bridge: jq not available; install jq to integrate capcheck" >&2
        return 2
    }
    jq -c '
      def sev_check(s):
        if   s == "fail"  then "error"
        elif s == "warn"  then "warning"
        elif s == "error" then "error"
        else "info" end ;
      def sev_quirk(s):
        # Quirk severity vocabulary (per CHANGELOG v0.7.8):
        #   critical → hardware damage / unrecoverable (e.g. NVRAM-delete bricks firmware)
        #   major/high → workflow-breaking but recoverable
        #   minor/low → cosmetic, performance, or convenience
        #   info → purely informational
        if   s == "critical" then "critical"
        elif s == "major"    then "error"
        elif s == "high"     then "error"
        elif s == "minor"    then "warning"
        elif s == "low"      then "warning"
        else "info" end ;
      def strip_domain_prefix(n):
        n | tostring | sub("^[^.]*\\.";"") ;
      # POSIX-ish shell quote: single-quote each argv element that contains
      # anything besides [A-Za-z0-9/._-=:+], escape embedded single quotes.
      def shellq:
        if test("^[A-Za-z0-9/._\\-=:+]+$") then .
        else "'\''" + (. | gsub("'\''"; "'\''\\'\'''\''")) + "'\''" end ;
      def join_argv(argv):
        argv | map(shellq) | join(" ") ;
      # Pick the first auto-applicable action: RunCommand with risk=safe and
      # idempotent=true; fall back to first RunCommand of any risk; else "".
      def first_safe_command(actions):
        (actions // [])
        | map(select(.kind == "run_command"))
        | (
            (map(select(.risk == "safe" and (.idempotent // false)))) +
            (map(select(.risk == "moderate"))) +
            .
          )
        | first
        | (if . == null then "" else join_argv(.argv) end) ;
      # Risk classifier: highest risk across all actions present.
      def highest_risk(actions):
        (actions // [])
        | map(select(.kind == "run_command") | .risk)
        | (if any(. == "destructive") then "destructive"
           elif any(. == "moderate")  then "moderate"
           elif any(. == "safe")      then "safe"
           else "none" end) ;
      [
        .domains[] as $d
        | $d.checks[]
        | select(.status == "fail" or .status == "warn")
        | . as $c
        | {
            id: "capcheck.domain.\($d.name).\(strip_domain_prefix($c.name))",
            category: "capcheck/\($d.name)",
            severity: sev_check($c.status),
            status: (if $c.status == "fail" then "fail" else "warn" end),
            title: $c.human,
            description: ($c.human + (if $c.remediation then "\nRemediation: \($c.remediation)" else "" end)),
            evidence: ($c.evidence // {}),
            actions: ($c.actions // []),
            remediation: {
              summary: ($c.remediation // ""),
              command: first_safe_command($c.actions),
              risk: highest_risk($c.actions),
              doc_url: "https://github.com/lamco-admin/lamboot-tools\($d.name)"
            }
          }
      ]
      +
      [
        .quirks_matched[]
        | . as $q
        | {
            id: "capcheck.quirk.\($q.id)",
            category: "capcheck/quirk",
            severity: sev_quirk($q.severity),
            status: "warn",
            title: $q.title,
            description: "\($q.one_line)\nAction: \($q.remediation_short // "(see docs)")",
            evidence: { matched_on: $q.matched_on },
            actions: [],
            remediation: {
              summary: ($q.remediation_short // ""),
              command: "",
              risk: "none",
              doc_url: $q.doc_url
            }
          }
      ]
    '
}

# capcheck_emit_diagnose_findings — high-level entry point. Runs audit,
# translates, prints the resulting array suitable for splicing into a
# diagnose `findings` field. Returns 0 even when capcheck isn't
# available — emits an empty array — so callers can unconditionally
# include the bridge.
#
# Note: capcheck's exit code is non-zero when WARN/FAIL findings exist
# (per SDS-8 §4.6) — that's expected. We ignore the exit code and trust
# the JSON output if it parses.
capcheck_emit_diagnose_findings() {
    if ! capcheck_available; then
        printf '[]'
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf '[]'
        return 0
    fi
    local audit
    audit=$(capcheck_run_audit || true)
    if [[ -z "$audit" ]]; then
        printf '[]'
        return 0
    fi
    # Validate JSON before translating; capcheck might have errored mid-output.
    if ! printf '%s' "$audit" | jq -e . >/dev/null 2>&1; then
        printf '[]'
        return 0
    fi
    printf '%s' "$audit" | capcheck_to_findings_jq
}

# ── Standalone test ─────────────────────────────────────────────────────

# Allow `bash lamboot-capcheck-bridge.sh test` to dump translated findings.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
    if capcheck_available; then
        echo "# capcheck binary: $(_capcheck_bin)"
        echo "# capcheck version: $(capcheck_version)"
        echo "# translated findings:"
        capcheck_emit_diagnose_findings | jq '.'
    else
        echo "lamboot-capcheck not on PATH; bridge inert"
        exit 0
    fi
fi

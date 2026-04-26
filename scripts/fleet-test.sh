#!/bin/bash
# fleet-test.sh — Tier 1 fleet-test driver
#
# Orchestrates the Tier 1 matrix documented in docs/FLEET-TEST-PLAN.md §2.
# Runs on a Proxmox VE host (self-hosted GitHub Actions runner).
#
# Flow per VMID:
#   1. Snapshot-rollback to the pre-toolkit baseline
#   2. Start VM, wait for SSH readiness
#   3. scp + install latest toolkit tarball
#   4. Run read-only scan sequence; capture JSON per tool
#   5. Stop VM
#
# Aggregates results into tests/results/<date>/<VMID>.json and diffs
# against tests/results/baselines/<VMID>.json to detect regressions.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIER="${TIER:-1}"
VM_USER="${VM_USER:-root}"
SSH_TIMEOUT_SEC="${SSH_TIMEOUT_SEC:-120}"
RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/tests/results/$(date -u +%Y-%m-%d)}"
BASELINES_DIR="$REPO_ROOT/tests/results/baselines"
TOOLKIT_TARBALL="${TOOLKIT_TARBALL:-$REPO_ROOT/build/lamboot-tools-0.2.0-dev.tar.gz}"

readonly RED=$'\033[0;31m'
readonly YELLOW=$'\033[0;33m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'

fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$1" >&2; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

# ── VMID matrix (from docs/FLEET-TEST-PLAN.md §2) ───────────────────────

TIER1_VMIDS_POSITIVE=(
    # Distro × UEFI+GRUB
    2100  # Ubuntu 24.04
    2200  # Debian 13
    2300  # Fedora 44
    2400  # Arch
    2500  # openSUSE Tumbleweed
    # Distro × UEFI+sd-boot
    2101  # Ubuntu
    2301  # Fedora
    2401  # Arch
    # Distro × BIOS+GRUB
    2102  # Ubuntu
    2202  # Debian
    2302  # Fedora
    2402  # Arch
    2502  # openSUSE
)

TIER1_VMIDS_NEGATIVE=(
    2700  # Hybrid MBR
    2701  # Windows dual-boot
    2702  # LVM root
    2703  # dm-crypt root
    2704  # No ESP
    2705  # Corrupted ESP FAT
    2706  # Full ESP
)

TIER1_VMIDS_LAMBOOT=(
    2800  # LamBoot healthy
    2801  # LamBoot CrashLoop
)

# ── Helpers ──────────────────────────────────────────────────────────────

require_proxmox() {
    # Graceful skip when the runner isn't a Proxmox host. The Tier 1 matrix
    # infrastructure is explicitly known-pending in docs/CROSS-REPO-STATUS.md
    # (handed off to lamco-admin). Hard-failing the scheduled workflow every
    # night while that's being provisioned generates false-positive noise.
    # When qm appears on the runner, this script proceeds normally without
    # any further code change.
    if ! command -v qm >/dev/null 2>&1; then
        warn "qm not found — fleet-test skipped (runner is not a Proxmox host)"
        warn "Tier 1 infrastructure is ops-pending per docs/CROSS-REPO-STATUS.md"
        warn "This exit code of 0 is deliberate; see scripts/fleet-test.sh:require_proxmox"
        mkdir -p "$RESULTS_DIR"
        printf '{"status":"skipped","reason":"qm-not-found","date":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RESULTS_DIR/SKIPPED.json"
        exit 0
    fi
    [[ -f "$TOOLKIT_TARBALL" ]] || fail "toolkit tarball not found: $TOOLKIT_TARBALL (run 'make build' first?)"
}

get_vm_ip() {
    local vmid="$1"
    # Use qm guest exec or Proxmox cloud-init helper — here's a placeholder
    # using qm guest cmd network-get-interfaces
    qm guest cmd "$vmid" network-get-interfaces 2>/dev/null | \
        python3 -c 'import json, sys; d=json.loads(sys.stdin.read()); print([i["ip-addresses"][0]["ip-address"] for i in d if i.get("name") != "lo" and i.get("ip-addresses")][0])' 2>/dev/null
}

wait_ssh() {
    local ip="$1"
    local deadline=$(( $(date +%s) + SSH_TIMEOUT_SEC ))
    while [[ $(date +%s) -lt $deadline ]]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o BatchMode=yes "$VM_USER@$ip" "true" 2>/dev/null; then
            return 0
        fi
        sleep 5
    done
    return 1
}

rollback_vm() {
    local vmid="$1"
    if qm listsnapshot "$vmid" 2>/dev/null | grep -q 'pre-toolkit'; then
        ok "rolling back VM $vmid to pre-toolkit snapshot"
        qm rollback "$vmid" pre-toolkit 2>&1 | tail -3
    else
        warn "VM $vmid has no 'pre-toolkit' snapshot; skipping rollback"
    fi
}

install_toolkit_in_vm() {
    local ip="$1"
    local remote_tarball="/tmp/lamboot-tools.tar.gz"

    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$TOOLKIT_TARBALL" "$VM_USER@$ip:$remote_tarball" || return 1

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@$ip" bash <<EOF
set -e
cd /tmp
tar xzf lamboot-tools.tar.gz
cd lamboot-tools-*
make install
EOF
}

run_scan_in_vm() {
    local ip="$1"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@$ip" bash <<'EOF'
set -uo pipefail
printf '['
first=1
for cmd in \
    "lamboot-diagnose --json" \
    "lamboot-esp check --json" \
    "lamboot-esp inventory --json" \
    "lamboot-backup list --json" \
    "lamboot-migrate status --json" \
    "lamboot-doctor --no-repair --json" \
    "lamboot-toolkit status --json" \
; do
    [[ $first -eq 1 ]] && first=0 || printf ','
    if output=$(eval "sudo $cmd" 2>/dev/null); then
        printf '{"cmd":"%s","output":%s}' "$cmd" "$output"
    else
        printf '{"cmd":"%s","output":null,"error":"command failed"}' "$cmd"
    fi
done
printf ']\n'
EOF
}

test_vm() {
    local vmid="$1"
    local report="$RESULTS_DIR/${vmid}.json"

    printf '\n=== VM %s ===\n' "$vmid"

    rollback_vm "$vmid" || { warn "rollback failed; continuing"; }

    qm start "$vmid" 2>&1 | tail -1 || { warn "qm start failed"; return 1; }
    sleep 10  # let cloud-init / initial boot settle

    local ip
    ip=$(get_vm_ip "$vmid")
    if [[ -z "$ip" ]]; then
        warn "no IP for VM $vmid; skipping"
        qm stop "$vmid" 2>/dev/null
        return 1
    fi

    if ! wait_ssh "$ip"; then
        warn "SSH never came up on VM $vmid ($ip)"
        qm stop "$vmid" 2>/dev/null
        return 1
    fi

    if ! install_toolkit_in_vm "$ip"; then
        warn "toolkit install failed on VM $vmid"
        qm stop "$vmid" 2>/dev/null
        return 1
    fi

    mkdir -p "$RESULTS_DIR"
    if run_scan_in_vm "$ip" > "$report"; then
        ok "VM $vmid: scan complete ($report)"
    else
        warn "VM $vmid: scan returned non-zero; report still written"
    fi

    qm stop "$vmid" 2>&1 | tail -1
    return 0
}

compare_against_baseline() {
    local vmid="$1"
    local current="$RESULTS_DIR/${vmid}.json"
    local baseline="$BASELINES_DIR/${vmid}.json"

    [[ -f "$current" ]] || { warn "no current report for $vmid"; return 1; }

    if [[ ! -f "$baseline" ]]; then
        warn "no baseline for VM $vmid; establishing from current run"
        mkdir -p "$BASELINES_DIR"
        cp "$current" "$baseline"
        return 0
    fi

    # Extract finding-ID sets from both, compare
    if command -v jq >/dev/null 2>&1; then
        local current_ids baseline_ids
        current_ids=$(jq -r '.[].output.findings[]?.id // empty' "$current" 2>/dev/null | sort -u)
        baseline_ids=$(jq -r '.[].output.findings[]?.id // empty' "$baseline" 2>/dev/null | sort -u)

        local new_findings removed_findings
        new_findings=$(comm -23 <(echo "$current_ids") <(echo "$baseline_ids"))
        removed_findings=$(comm -13 <(echo "$current_ids") <(echo "$baseline_ids"))

        if [[ -n "$new_findings" ]]; then
            warn "VM $vmid: new findings vs baseline:"
            echo "$new_findings" | sed 's/^/    /' >&2
        fi
        if [[ -n "$removed_findings" ]]; then
            ok "VM $vmid: findings resolved since baseline:"
            echo "$removed_findings" | sed 's/^/    /' >&2
        fi
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tier) TIER="${2:-1}"; shift 2 ;;
            --vmid) SINGLE_VMID="${2:-}"; shift 2 ;;
            --help|-h)
                cat <<HELP
usage: fleet-test.sh [--tier N] [--vmid VMID]

Runs the Tier 1 fleet test matrix against the Proxmox host's VMs.

Options:
  --tier N    Tier to run (default: 1; 2 and 3 not yet implemented)
  --vmid N    Test only a single VMID
HELP
                exit 0
                ;;
            *) fail "unknown arg: $1" ;;
        esac
    done
}

main() {
    parse_args "$@"
    require_proxmox

    mkdir -p "$RESULTS_DIR"

    local vmids=()
    if [[ -n "${SINGLE_VMID:-}" ]]; then
        vmids=("$SINGLE_VMID")
    else
        vmids+=("${TIER1_VMIDS_POSITIVE[@]}")
        vmids+=("${TIER1_VMIDS_NEGATIVE[@]}")
        vmids+=("${TIER1_VMIDS_LAMBOOT[@]}")
    fi

    local success=0 fail_count=0

    for vmid in "${vmids[@]}"; do
        if test_vm "$vmid"; then
            compare_against_baseline "$vmid"
            success=$((success + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    printf '\n%sFleet test complete:%s %d/%d VMs passed\n' \
        "$GREEN" "$RESET" "$success" "$((success + fail_count))"
    printf 'Results: %s\n' "$RESULTS_DIR"

    [[ $fail_count -eq 0 ]] || exit 2
    exit 0
}

main "$@"

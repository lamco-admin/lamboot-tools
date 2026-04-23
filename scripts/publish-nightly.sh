#!/bin/bash
# publish-nightly.sh — upload nightly fleet-test results to lamboot.dev/tools/nightly
#
# Called by .github/workflows/fleet-test.yml after scripts/fleet-test.sh.
# Builds a static report from the latest tests/results/<date>/ tree and
# publishes to the configured hosting location.
#
# Env:
#   FLEET_PUBLISH_URL     Target URL (default: https://lamboot.dev/tools/nightly/upload)
#   FLEET_PUBLISH_TOKEN   Auth token (required)
#   RESULTS_DIR           Source directory (default: tests/results/<today>)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$REPO_ROOT/tests/results/$(date -u +%Y-%m-%d)}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build/nightly-report}"
FLEET_PUBLISH_URL="${FLEET_PUBLISH_URL:-https://lamboot.dev/tools/nightly/upload}"

readonly RED=$'\033[0;31m'
readonly YELLOW=$'\033[0;33m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'

fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$1" >&2; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

[[ -d "$RESULTS_DIR" ]] || fail "results directory not found: $RESULTS_DIR"

# ── Build the nightly report ────────────────────────────────────────────

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy per-VM JSON results
cp -a "$RESULTS_DIR"/*.json "$BUILD_DIR/" 2>/dev/null || warn "no per-VM JSON in $RESULTS_DIR"

# Build index.json summarizing the run
today=$(date -u +%Y-%m-%d)
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

total_vms=$(ls "$RESULTS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')

# Count total findings across all VMs (requires jq)
total_findings=0
total_critical=0
total_error=0
total_warning=0
if command -v jq >/dev/null 2>&1; then
    for f in "$RESULTS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        vm_findings=$(jq '[.[].output.findings[]?] | length' "$f" 2>/dev/null || printf '0')
        vm_critical=$(jq '[.[].output.findings[]? | select(.severity == "critical")] | length' "$f" 2>/dev/null || printf '0')
        vm_error=$(jq '[.[].output.findings[]? | select(.severity == "error")] | length' "$f" 2>/dev/null || printf '0')
        vm_warning=$(jq '[.[].output.findings[]? | select(.severity == "warning")] | length' "$f" 2>/dev/null || printf '0')
        total_findings=$((total_findings + vm_findings))
        total_critical=$((total_critical + vm_critical))
        total_error=$((total_error + vm_error))
        total_warning=$((total_warning + vm_warning))
    done
fi

cat > "$BUILD_DIR/index.json" <<EOF
{
  "run_date": "$today",
  "generated_at": "$timestamp",
  "tier": "1",
  "total_vms": $total_vms,
  "total_findings": $total_findings,
  "by_severity": {
    "critical": $total_critical,
    "error": $total_error,
    "warning": $total_warning
  },
  "schema_version": "v1"
}
EOF

ok "built nightly report: $BUILD_DIR/index.json"
ok "$total_vms VMs, $total_findings findings ($total_critical crit / $total_error err / $total_warning warn)"

# Also build a minimal HTML index for human browsers
cat > "$BUILD_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>lamboot-tools nightly fleet test — $today</title>
<style>
  body { font-family: monospace; max-width: 900px; margin: 2em auto; padding: 0 1em; }
  table { border-collapse: collapse; width: 100%; }
  th, td { padding: 0.3em 0.6em; text-align: left; border-bottom: 1px solid #ddd; }
  .crit { color: #c0392b; font-weight: bold; }
  .err { color: #e67e22; }
  .warn { color: #f39c12; }
</style>
</head>
<body>
<h1>lamboot-tools nightly fleet test</h1>
<p><strong>Run date:</strong> $today &nbsp; <strong>Generated:</strong> $timestamp</p>
<h2>Summary</h2>
<table>
  <tr><th>Metric</th><th>Value</th></tr>
  <tr><td>Total VMs tested</td><td>$total_vms</td></tr>
  <tr><td>Total findings</td><td>$total_findings</td></tr>
  <tr><td>Critical</td><td class="crit">$total_critical</td></tr>
  <tr><td>Error</td><td class="err">$total_error</td></tr>
  <tr><td>Warning</td><td class="warn">$total_warning</td></tr>
</table>
<p>Per-VM JSON in this directory.</p>
<p><a href="/tools/">← back to lamboot-tools docs</a></p>
</body>
</html>
EOF

# ── Upload ───────────────────────────────────────────────────────────────

if [[ -z "${FLEET_PUBLISH_TOKEN:-}" ]]; then
    warn "FLEET_PUBLISH_TOKEN not set — building report locally only"
    ok "report ready at $BUILD_DIR (not uploaded)"
    exit 0
fi

# Package and POST
archive="/tmp/nightly-$today.tar.gz"
tar -czf "$archive" -C "$BUILD_DIR" .

curl -fL -X POST \
    -H "Authorization: Bearer $FLEET_PUBLISH_TOKEN" \
    -F "date=$today" \
    -F "payload=@$archive" \
    "$FLEET_PUBLISH_URL" \
    || fail "upload to $FLEET_PUBLISH_URL failed"

rm -f "$archive"
ok "uploaded to $FLEET_PUBLISH_URL"

exit 0

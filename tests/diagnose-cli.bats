#!/usr/bin/env bats
# lamboot-diagnose CLI + scan tests — read-only, safe anywhere.

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-diagnose"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-diagnose not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "diagnose --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-diagnose"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "diagnose help runs without root" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"subcommand reference"* ]]
}

@test "diagnose help scan shows detail" {
    run "$TOOL" help scan
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"EXAMPLES"* ]]
}

@test "diagnose --json-schema returns schema declaration" {
    run --separate-stderr "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "diagnose runs unprivileged and produces findings" {
    run --separate-stderr "$TOOL" --json
    # Exit 0 (all pass) or 2 (findings at error+). Not 1 or 7.
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "diagnose --json emits valid JSON schema v1" {
    require_jq
    run --separate-stderr "$TOOL" --json
    echo "$output" | jq -e '.schema_version == "v1"' >/dev/null
    echo "$output" | jq -e '.tool == "lamboot-diagnose"' >/dev/null
}

@test "diagnose --json has findings across multiple categories" {
    require_jq
    run --separate-stderr "$TOOL" --json
    local cat_count
    cat_count=$(echo "$output" | jq -r '.findings | map(.category) | unique | length')
    [ "$cat_count" -ge 3 ]
}

@test "diagnose --category esp only shows esp findings" {
    require_jq
    run --separate-stderr "$TOOL" --json --category esp
    local other_cats
    other_cats=$(echo "$output" | jq -r '.findings[] | select(.category != "esp") | .category' | wc -l)
    [ "$other_cats" -eq 0 ]
}

@test "diagnose --skip secures_boot omits secure_boot findings" {
    require_jq
    run --separate-stderr "$TOOL" --json --skip secure_boot
    local sb_count
    sb_count=$(echo "$output" | jq -r '.findings[] | select(.category == "secure_boot") | .id' | wc -l)
    [ "$sb_count" -eq 0 ]
}

@test "diagnose --id filters to a single finding" {
    require_jq
    run --separate-stderr "$TOOL" --json --id boot_mode.uefi
    local count
    count=$(echo "$output" | jq '.findings | length')
    [ "$count" -eq 1 ]
    echo "$output" | jq -e '.findings[0].id == "boot_mode.uefi"' >/dev/null
}

@test "diagnose warning findings include remediation" {
    require_jq
    run --separate-stderr "$TOOL" --json
    # Every warning/error/critical finding should have a remediation object
    local missing
    missing=$(echo "$output" | jq '[.findings[] | select(.severity == "warning" or .severity == "error" or .severity == "critical") | select(.remediation == {} or .remediation == null)] | length')
    # Allow 0 — strict policy per spec §13
    [ "$missing" -eq 0 ]
}

@test "diagnose exit code is 2 when critical or error findings exist" {
    require_jq
    run --separate-stderr "$TOOL" --json
    local has_bad
    has_bad=$(echo "$output" | jq -r '[.findings[] | select(.severity == "critical" or .severity == "error")] | length')
    if [ "$has_bad" -gt 0 ]; then
        [ "$status" -eq 2 ]
    else
        [ "$status" -eq 0 ]
    fi
}

@test "diagnose --quiet suppresses info findings in human output" {
    run "$TOOL" --quiet
    # Should have no ✓ info markers
    if echo "$output" | grep -q '^  ✓'; then
        echo "quiet mode still printed ✓ lines" >&2
        return 1
    fi
}

@test "diagnose --no-color emits no ANSI sequences" {
    run "$TOOL" --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        echo "--no-color still contained ANSI" >&2
        return 1
    fi
}

@test "diagnose unknown flag errors" {
    run "$TOOL" --definitely-not-a-flag
    [ "$status" -ne 0 ]
}

@test "diagnose finding IDs follow dotted path convention" {
    require_jq
    run --separate-stderr "$TOOL" --json
    # No finding ID should contain uppercase, spaces, or special chars
    local bad_ids
    bad_ids=$(echo "$output" | jq -r '.findings[].id' | grep -cvE '^[a-z0-9_]+(\.[a-z0-9_+.-]+)*$' || true)
    bad_ids="${bad_ids:-0}"
    [ "$bad_ids" -eq 0 ]
}

@test "diagnose run_id matches spec format" {
    require_jq
    run --separate-stderr "$TOOL" --json
    local run_id
    run_id=$(echo "$output" | jq -r '.run_id')
    [[ "$run_id" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9a-f]{6}$ ]]
}

@test "diagnose reports kernel findings in category 'kernel'" {
    require_jq
    run --separate-stderr "$TOOL" --json --category kernel
    local count
    count=$(echo "$output" | jq '.findings | length')
    [ "$count" -ge 1 ]
}

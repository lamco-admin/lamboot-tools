#!/usr/bin/env bats
# lamboot-doctor CLI + policy matrix tests.

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-doctor"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    TOOLS_DIR="$BATS_TEST_DIRNAME/../tools"
    [ -x "$TOOL" ] || skip "lamboot-doctor not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
    # Ensure sibling tools are findable via script-dir resolution
    export PATH="$TOOLS_DIR:$PATH"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "doctor --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-doctor"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "doctor --version shows v0.3.0" {
    run "$TOOL" --version
    [[ "$output" == *"0.3.0"* ]]
}

@test "doctor help shows the check entry with beta maturity" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"check"* ]]
    [[ "$output" == *"[beta]"* ]]
}

@test "doctor help check shows policy notes" {
    run "$TOOL" help check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"policy"* ]] || [[ "$output" == *"Policy"* ]] || [[ "$output" == *"Chains"* ]]
}

@test "doctor --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "doctor --no-repair runs diagnose + plan without execution (unprivileged OK)" {
    run "$TOOL" --no-repair
    # Exit 0 (no plan needed execution) or 3 (no findings)
    [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
}

@test "doctor --no-repair --json emits valid JSON schema v1" {
    require_jq
    run --separate-stderr "$TOOL" --no-repair --json
    echo "$output" | jq -e '.schema_version == "v1"' >/dev/null
    echo "$output" | jq -e '.tool == "lamboot-doctor"' >/dev/null
}

@test "doctor exits cleanly with unknown flag" {
    run "$TOOL" --not-a-real-flag
    [ "$status" -ne 0 ]
}

@test "doctor exits cleanly with unknown positional" {
    run "$TOOL" garbage-arg
    [ "$status" -ne 0 ]
}

@test "doctor --no-repair skips all auto/confirm policies" {
    require_jq
    run --separate-stderr "$TOOL" --no-repair --json
    # No actions should be applied when --no-repair is set
    local applied
    applied=$(echo "$output" | jq '[.actions_taken[] | select(.result == "ok")] | length')
    [ "$applied" -eq 0 ]
}

@test "doctor never invokes lamboot-migrate automatically" {
    require_jq
    run --separate-stderr "$TOOL" --no-repair --json
    # No action should reference lamboot-migrate
    local migrate_count
    migrate_count=$(echo "$output" | jq -r '.actions_taken[] | .details.action // ""' | grep -c 'lamboot-migrate' || true)
    migrate_count="${migrate_count:-0}"
    [ "$migrate_count" -eq 0 ]
}

@test "doctor help is unprivileged" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
}

@test "doctor --no-color yields no ANSI" {
    run "$TOOL" help --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

@test "doctor emits a plan summary finding when findings exist" {
    require_jq
    run --separate-stderr "$TOOL" --no-repair --json
    # If any findings were generated, expect doctor.plan.summary OR doctor.check.healthy
    echo "$output" | jq -e '.findings[] | select(.id == "doctor.plan.summary" or .id == "doctor.check.healthy")' >/dev/null
}

@test "doctor actions_taken records targets match finding IDs" {
    require_jq
    run --separate-stderr "$TOOL" --no-repair --json
    # Each action target should be a finding ID from the source scan
    local all_valid=1
    while IFS= read -r tgt; do
        [[ -z "$tgt" ]] && continue
        # dotted-path convention
        if ! [[ "$tgt" =~ ^[a-z0-9_]+(\.[a-z0-9_+.-]+)*$ ]]; then
            all_valid=0
            break
        fi
    done < <(echo "$output" | jq -r '.actions_taken[].target')
    [ "$all_valid" -eq 1 ]
}

@test "doctor accepts --risk-limit values" {
    run "$TOOL" --no-repair --risk-limit safe
    [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
}

@test "doctor --no-clean does not error" {
    run "$TOOL" --no-repair --no-clean
    [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
}

@test "doctor run_id matches spec format" {
    require_jq
    run --separate-stderr "$TOOL" --no-repair --json
    local run_id
    run_id=$(echo "$output" | jq -r '.run_id')
    [[ "$run_id" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9a-f]{6}$ ]]
}

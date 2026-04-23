#!/usr/bin/env bats
# JSON emission tests — the envelope must be jq-parseable and conform to §5.

setup() {
    LIB="$BATS_TEST_DIRNAME/../lib/lamboot-toolkit-lib.sh"
    # shellcheck source=../lib/lamboot-toolkit-lib.sh
    source "$LIB"
    LAMBOOT_TOOL_NAME="test-tool"
    LAMBOOT_TOOL_VERSION="0.0.1"
    LAMBOOT_JSON=1
    # Reset accumulators between tests
    LAMBOOT_JSON_FINDINGS=""
    LAMBOOT_JSON_ACTIONS=""
    LAMBOOT_JSON_BACKUP_DIR=""
    generate_run_id
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "json_escape handles backslashes" {
    result=$(json_escape 'path\to\file')
    [ "$result" = 'path\\to\\file' ]
}

@test "json_escape handles quotes" {
    result=$(json_escape 'she said "hi"')
    [ "$result" = 'she said \"hi\"' ]
}

@test "emit_json produces jq-parseable output with no findings" {
    require_jq
    output=$(emit_json 0)
    echo "$output" | jq -e . >/dev/null
}

@test "emit_json with a finding parses cleanly" {
    require_jq
    emit_finding "test.sample" "test" "info" "pass" "Sample" "ok" "{}" "{}"
    output=$(emit_json 0)
    echo "$output" | jq -e '.findings[0].id == "test.sample"' >/dev/null
}

@test "emit_json reports exit_code accurately" {
    require_jq
    output=$(emit_json 4)
    echo "$output" | jq -e '.exit_code == 4' >/dev/null
    echo "$output" | jq -e '.summary.status == "unsafe"' >/dev/null
}

@test "emit_json summary counts findings by severity" {
    require_jq
    emit_finding "a.one" "a" "error" "fail" "One" "msg" "{}" "{}"
    emit_finding "a.two" "a" "warning" "warn" "Two" "msg" "{}" "{}"
    emit_finding "a.three" "a" "warning" "warn" "Three" "msg" "{}" "{}"
    emit_finding "a.four" "a" "info" "pass" "Four" "msg" "{}" "{}"

    output=$(emit_json 0)
    echo "$output" | jq -e '.summary.findings_total == 4' >/dev/null
    echo "$output" | jq -e '.summary.findings_by_severity.error == 1' >/dev/null
    echo "$output" | jq -e '.summary.findings_by_severity.warning == 2' >/dev/null
    echo "$output" | jq -e '.summary.findings_by_severity.info == 1' >/dev/null
}

@test "emit_json includes schema_version v1" {
    require_jq
    output=$(emit_json 0)
    echo "$output" | jq -e '.schema_version == "v1"' >/dev/null
}

@test "run_id is populated by generate_run_id" {
    [ -n "$LAMBOOT_RUN_ID" ]
}

@test "record_action appends to actions_taken" {
    require_jq
    record_action "test.verb" "/dev/sda" "ok" "true" '{"size_mb":512}' "null"
    output=$(emit_json 0)
    echo "$output" | jq -e '.actions_taken | length == 1' >/dev/null
    echo "$output" | jq -e '.actions_taken[0].action == "test.verb"' >/dev/null
    echo "$output" | jq -e '.actions_taken[0].reversible == true' >/dev/null
}

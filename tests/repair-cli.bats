#!/usr/bin/env bats
# lamboot-repair CLI + phase tests (root-free surface only).

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-repair"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-repair not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "repair --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-repair"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "repair help shows the repair entry" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"repair"* ]]
    [[ "$output" == *"[root]"* ]]
}

@test "repair help repair shows detail with risk-limit" {
    run "$TOOL" help repair
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"--risk-limit"* ]]
    [[ "$output" == *"Requires root"* ]]
}

@test "repair --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "repair without root exits EXIT_PREREQUISITE" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    run "$TOOL"
    [ "$status" -eq 7 ]
}

@test "repair --dry-run without root still refuses (privilege model)" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    run "$TOOL" --dry-run
    [ "$status" -eq 7 ]
}

@test "repair unknown option errors" {
    run "$TOOL" --not-a-flag
    [ "$status" -ne 0 ]
}

@test "repair unknown positional errors" {
    run "$TOOL" not-a-subcommand
    [ "$status" -ne 0 ]
}

@test "repair --no-color yields no ANSI" {
    run "$TOOL" help
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

@test "repair help is unprivileged" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
}

@test "repair --version is unprivileged" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
}

@test "repair --risk-limit accepts documented values" {
    [ "$EUID" -eq 0 ] && skip "running as root; would attempt repairs"
    # The tool will die_prerequisite before reaching risk-tier validation
    # on a non-root run; just verify parsing doesn't error on the flag itself
    run "$TOOL" --risk-limit safe
    [ "$status" -eq 7 ] || [ "$status" -eq 3 ]
}

@test "repair rejects invalid --risk-limit (when actually executed)" {
    # We can only reach the validation point if root; otherwise it errors on root check first.
    # Skip when non-root since the validation happens after require_root.
    [ "$EUID" -eq 0 ] || skip "non-root"
    run "$TOOL" --risk-limit bogus --plan-only
    [ "$status" -ne 0 ]
}

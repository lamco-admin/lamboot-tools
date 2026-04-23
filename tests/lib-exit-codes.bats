#!/usr/bin/env bats
# Exit-code constants are invariants — tests guard against accidental drift
# that would break every downstream consumer of JSON output.

setup() {
    LIB="$BATS_TEST_DIRNAME/../lib/lamboot-toolkit-lib.sh"
    [ -f "$LIB" ] || skip "shared library not found: $LIB"
    # shellcheck source=../lib/lamboot-toolkit-lib.sh
    source "$LIB"
}

@test "EXIT_OK is 0" {
    [ "$EXIT_OK" -eq 0 ]
}

@test "EXIT_ERROR is 1" {
    [ "$EXIT_ERROR" -eq 1 ]
}

@test "EXIT_PARTIAL is 2" {
    [ "$EXIT_PARTIAL" -eq 2 ]
}

@test "EXIT_NOOP is 3" {
    [ "$EXIT_NOOP" -eq 3 ]
}

@test "EXIT_UNSAFE is 4" {
    [ "$EXIT_UNSAFE" -eq 4 ]
}

@test "EXIT_ABORT is 5" {
    [ "$EXIT_ABORT" -eq 5 ]
}

@test "EXIT_NOT_APPLICABLE is 6" {
    [ "$EXIT_NOT_APPLICABLE" -eq 6 ]
}

@test "EXIT_PREREQUISITE is 7" {
    [ "$EXIT_PREREQUISITE" -eq 7 ]
}

@test "toolkit version is set" {
    [ -n "$LAMBOOT_TOOLKIT_VERSION" ]
}

@test "schema version is v1" {
    [ "$LAMBOOT_TOOLKIT_SCHEMA_VERSION" = "v1" ]
}

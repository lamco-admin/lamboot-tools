#!/usr/bin/env bats
# parse_common_flag tests — every tool relies on consistent flag semantics.

setup() {
    LIB="$BATS_TEST_DIRNAME/../lib/lamboot-toolkit-lib.sh"
    # shellcheck source=../lib/lamboot-toolkit-lib.sh
    source "$LIB"
    # Reset state between tests
    LAMBOOT_JSON=0
    LAMBOOT_VERBOSE=0
    LAMBOOT_QUIET=0
    LAMBOOT_DRY_RUN=0
    LAMBOOT_YES=0
    LAMBOOT_FORCE=0
    LAMBOOT_AUTO=0
}

@test "--json sets LAMBOOT_JSON=1" {
    parse_common_flag --json || true
    [ "$LAMBOOT_JSON" -eq 1 ]
}

@test "--verbose sets LAMBOOT_VERBOSE=1" {
    parse_common_flag --verbose || true
    [ "$LAMBOOT_VERBOSE" -eq 1 ]
}

@test "-v short flag is recognized" {
    parse_common_flag -v || true
    [ "$LAMBOOT_VERBOSE" -eq 1 ]
}

@test "--quiet sets LAMBOOT_QUIET=1" {
    parse_common_flag --quiet || true
    [ "$LAMBOOT_QUIET" -eq 1 ]
}

@test "--dry-run sets LAMBOOT_DRY_RUN=1" {
    parse_common_flag --dry-run || true
    [ "$LAMBOOT_DRY_RUN" -eq 1 ]
}

@test "--yes sets LAMBOOT_YES=1" {
    parse_common_flag --yes || true
    [ "$LAMBOOT_YES" -eq 1 ]
}

@test "--force sets LAMBOOT_FORCE=1" {
    parse_common_flag --force || true
    [ "$LAMBOOT_FORCE" -eq 1 ]
}

@test "--auto implies --yes" {
    parse_common_flag --auto || true
    [ "$LAMBOOT_AUTO" -eq 1 ]
    [ "$LAMBOOT_YES" -eq 1 ]
}

@test "--help returns code 2 (signal)" {
    # bats runs tests with implicit `set -e`, so a non-zero return from
    # parse_common_flag aborts the test before `[ $? -eq N ]` can fire.
    # `run` captures status without triggering the abort.
    run parse_common_flag --help
    [ "$status" -eq 2 ]
}

@test "--version returns code 3 (signal)" {
    run parse_common_flag --version
    [ "$status" -eq 3 ]
}

@test "unknown flag returns code 0 (not consumed)" {
    parse_common_flag --some-tool-specific-flag
    [ "$?" -eq 0 ]
}

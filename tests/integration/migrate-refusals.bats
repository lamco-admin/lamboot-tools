#!/usr/bin/env bats
# Integration tests for lamboot-migrate refusal paths.
#
# Require fixture disk images; skip gracefully if not present.
# Run via: make test-integration

setup() {
    TOOL="$BATS_TEST_DIRNAME/../../tools/lamboot-migrate"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    FIXTURES_DIR="$BATS_TEST_DIRNAME/../fixtures"
    [ -x "$TOOL" ] || skip "lamboot-migrate not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

fixture() {
    local name="$1"
    local path="$FIXTURES_DIR/$name"
    [ -f "$path" ] || skip "fixture not present: $name (run tests/fixtures/download-fixtures.sh)"
    printf '%s' "$path"
}

@test "migrate refuses on hybrid MBR (EXIT_UNSAFE)" {
    [ "$EUID" -eq 0 ] || skip "integration tests need root (losetup + sgdisk)"
    local f
    f=$(fixture hybrid-mbr.raw)
    # Note: to-uefi doesn't support --offline in v1.0 per SDS-7 deferral.
    # This test uses losetup + sgdisk to verify the guardrail logic
    # against the fixture. Full end-to-end requires a live VM (Tier 1).
    skip "end-to-end hybrid-MBR refusal is Tier 1 (live VM test)"
}

@test "migrate refuses on Windows-present disk (EXIT_UNSAFE)" {
    skip "end-to-end Windows-present refusal is Tier 1 (live VM test)"
}

@test "migrate refuses on LVM-root (EXIT_UNSAFE)" {
    skip "end-to-end LVM-root refusal is Tier 1 (live VM test)"
}

@test "migrate status works against fixture (read-only offline)" {
    # migrate status doesn't support --offline; just verify it handles
    # the no-UEFI path gracefully on this host.
    run "$TOOL" status --json
    [ "$status" -eq 0 ]
}

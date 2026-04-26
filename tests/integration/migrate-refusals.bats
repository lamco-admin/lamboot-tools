#!/usr/bin/env bats
# Integration tests for lamboot-migrate refusal paths.
#
# SDS-7 §10.3 failure-mode tests. Two tiers of coverage:
#
#   * Guard-level (this file): we source the tool and call individual
#     guard functions (guard_no_hybrid_mbr / guard_no_windows) against
#     loopback-mounted fixtures. Requires root + losetup. Exercises the
#     exact code path that Phase 1 preflight runs.
#
#   * End-to-end (Tier 1 fleet): full to-uefi → to-lamboot → rollback
#     cycle against real VMs with SeaBIOS firmware. Scripted by
#     scripts/fleet-test.sh; awaits lamco-admin self-hosted runner
#     infrastructure. See docs/FLEET-TEST-PLAN.md.

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    TOOL="$REPO_ROOT/tools/lamboot-migrate"
    LIB_DIR="$REPO_ROOT/lib"
    FIXTURES_DIR="$REPO_ROOT/tests/fixtures"
    [ -x "$TOOL" ] || skip "lamboot-migrate not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
    LOOP_DEV=""
}

teardown() {
    if [ -n "${LOOP_DEV:-}" ] && [ -b "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}

require_root_and_losetup() {
    [ "$EUID" -eq 0 ] || skip "guard integration tests need root (losetup)"
    command -v losetup >/dev/null 2>&1 || skip "losetup not installed"
    command -v sgdisk >/dev/null 2>&1 || skip "sgdisk not installed"
    command -v lsblk >/dev/null 2>&1 || skip "lsblk not installed"
}

fixture() {
    local name="$1"
    local path="$FIXTURES_DIR/$name"
    [ -f "$path" ] || skip "fixture not present: $name (run tests/fixtures/download-fixtures.sh)"
    printf '%s' "$path"
}

attach_loop() {
    local fixture_path="$1"
    LOOP_DEV=$(losetup --show -Pf "$fixture_path")
    [ -b "$LOOP_DEV" ] || { echo "losetup did not return a block device" >&2; return 1; }
}

# --- guard_no_hybrid_mbr against hybrid-mbr.raw fixture -----------------

@test "guard_no_hybrid_mbr refuses a hybrid MBR+GPT disk (EXIT_UNSAFE)" {
    require_root_and_losetup
    local f; f=$(fixture hybrid-mbr.raw)
    attach_loop "$f"

    # Sourcing must not trigger main(), thanks to the BASH_SOURCE guard
    # added at the bottom of tools/lamboot-migrate.
    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        guard_no_hybrid_mbr '$LOOP_DEV'
    "
    # Hybrid MBR → die_unsafe → EXIT_UNSAFE=4
    [ "$status" -eq 4 ]
    [[ "$output" == *"Hybrid MBR detected"* ]] || [[ "$output" == *"hybrid MBR"* ]]
}

@test "guard_no_hybrid_mbr accepts a clean GPT disk" {
    require_root_and_losetup
    local f; f=$(fixture clean-uefi-gpt.raw)
    attach_loop "$f"

    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        guard_no_hybrid_mbr '$LOOP_DEV'
    "
    [ "$status" -eq 0 ]
}

@test "guard_no_hybrid_mbr accepts a clean BIOS/MBR-only disk" {
    require_root_and_losetup
    local f; f=$(fixture clean-bios-mbr.raw)
    attach_loop "$f"

    # Pure MBR (no GPT) is not a hybrid; the guard should pass.
    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        guard_no_hybrid_mbr '$LOOP_DEV'
    "
    [ "$status" -eq 0 ]
}

# --- guard_no_windows against windows-mbr.raw fixture -------------------

@test "guard_no_windows refuses a Windows-present disk (EXIT_UNSAFE)" {
    require_root_and_losetup
    local f; f=$(fixture windows-mbr.raw)
    attach_loop "$f"

    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        guard_no_windows '$LOOP_DEV'
    "
    # Windows Boot Manager detected → die_unsafe → EXIT_UNSAFE=4
    [ "$status" -eq 4 ]
    [[ "$output" == *"Windows"* ]]
}

@test "guard_no_windows accepts a disk with no NTFS partitions" {
    require_root_and_losetup
    local f; f=$(fixture clean-bios-mbr.raw)
    attach_loop "$f"

    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        guard_no_windows '$LOOP_DEV'
    "
    [ "$status" -eq 0 ]
}

# --- End-to-end SDS-7 §10.3 tests (Tier 1, fleet-only) ------------------
#
# These tests describe the scenarios SDS-7 §10.3 requires but which
# cannot be exercised without a BIOS-mode host (guard_boot_mode_is_bios
# fires first on any UEFI host and short-circuits to EXIT_NOOP). Left
# as explicit-skip placeholders so the intent is discoverable from the
# test output, not just the spec.

@test "to-uefi on already-UEFI host → EXIT_NOOP" {
    # The only §10.3 end-to-end case that can run without BIOS hardware.
    # do_to_uefi's first action is require_root (EXIT_PREREQUISITE=7);
    # past that, guard_boot_mode_is_bios fires die_noop (EXIT_NOOP=3) on
    # a UEFI host. Skip when non-root since we can't distinguish whether
    # the guard would have fired.
    [ "$EUID" -eq 0 ] || skip "require_root runs before guard_boot_mode_is_bios; need root to test the guard"
    if [ ! -d /sys/firmware/efi ]; then
        skip "host is BIOS; to-uefi would proceed past guard_boot_mode_is_bios"
    fi
    run "$TOOL" to-uefi --disk /dev/null --force --dry-run
    # guard_boot_mode_is_bios → die_noop → EXIT_NOOP=3
    [ "$status" -eq 3 ]
}

@test "to-uefi on BIOS + hybrid MBR → EXIT_UNSAFE end-to-end" {
    skip "Tier 1 only — requires BIOS-mode host + full Phase 1 preflight (scripts/fleet-test.sh)"
}

@test "to-uefi on BIOS + Windows present → EXIT_UNSAFE end-to-end" {
    skip "Tier 1 only — requires BIOS-mode host (scripts/fleet-test.sh)"
}

@test "to-uefi on BIOS + encrypted root → EXIT_UNSAFE end-to-end" {
    skip "Tier 1 only — requires BIOS-mode host + LVM/cryptsetup on the booted root"
}

@test "to-uefi → rollback → verify restored (full cycle)" {
    skip "Tier 1 only — destructive; requires snapshotted BIOS VM"
}

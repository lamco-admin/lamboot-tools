#!/usr/bin/env bats
# lamboot-migrate guardrail unit tests — spec SDS-7 §5
#
# Tests the individual guard_* functions for expected refusal behavior
# without actually invoking the full to-uefi pipeline.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-migrate"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    export LAMBOOT_LIB_DIR="$LIB_DIR"

    LIB="$LIB_DIR/lamboot-toolkit-lib.sh"
    HELP_LIB="$LIB_DIR/lamboot-toolkit-help.sh"
    [ -f "$LIB" ] || skip "shared library not found"
    # shellcheck source=../lib/lamboot-toolkit-lib.sh
    source "$LIB"
    # shellcheck source=../lib/lamboot-toolkit-help.sh
    source "$HELP_LIB"

    LAMBOOT_TOOL_NAME="lamboot-migrate"
    LAMBOOT_TOOL_VERSION="1.0.0-dev"
}

@test "detect_target_disk returns a /dev/ path on Linux host" {
    # This test runs on a real system; should always find a root disk.
    # shellcheck source=../tools/lamboot-migrate
    # Source just the helper functions we want to test:
    eval "$(sed -n '/^detect_target_disk()/,/^}/p' "$TOOL")"
    run detect_target_disk
    [ "$status" -eq 0 ] || skip "no root disk detectable in this env"
    [[ "$output" == /dev/* ]]
}

@test "partition_device_for produces pN suffix for NVMe" {
    eval "$(sed -n '/^partition_device_for()/,/^}/p' "$TOOL")"
    result=$(partition_device_for /dev/nvme0n1 3)
    [ "$result" = "/dev/nvme0n1p3" ]
}

@test "partition_device_for produces numeric suffix for SCSI" {
    eval "$(sed -n '/^partition_device_for()/,/^}/p' "$TOOL")"
    result=$(partition_device_for /dev/sda 3)
    [ "$result" = "/dev/sda3" ]
}

@test "partition_device_for handles loop devices with pN" {
    eval "$(sed -n '/^partition_device_for()/,/^}/p' "$TOOL")"
    result=$(partition_device_for /dev/loop0 1)
    [ "$result" = "/dev/loop0p1" ]
}

@test "partition_device_for handles mmcblk with pN" {
    eval "$(sed -n '/^partition_device_for()/,/^}/p' "$TOOL")"
    result=$(partition_device_for /dev/mmcblk0 2)
    [ "$result" = "/dev/mmcblk0p2" ]
}

@test "detect_proxmox_method returns A B C or auto-selected single char" {
    eval "$(sed -n '/^detect_proxmox_method()/,/^}/p' "$TOOL")"
    OPT_METHOD="A"
    result=$(detect_proxmox_method)
    [ "$result" = "A" ]

    OPT_METHOD="b"
    result=$(detect_proxmox_method)
    [ "$result" = "B" ]

    OPT_METHOD="auto"
    result=$(detect_proxmox_method)
    [[ "$result" == "A" || "$result" == "B" || "$result" == "C" ]]
}

@test "detect_proxmox_method rejects invalid --method value" {
    eval "$(sed -n '/^detect_proxmox_method()/,/^}/p' "$TOOL")"
    OPT_METHOD="Z"
    run detect_proxmox_method
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid --method"* ]] || [[ "$output" == *"invalid"* ]]
}

@test "guard_method_prerequisites Method B refuses without --disk" {
    # Source the whole tool (via BASH_SOURCE guard) so we get all the
    # helper functions guard_method_prerequisites depends on.
    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        OPT_METHOD='B'
        OPT_DISK=''
        guard_method_prerequisites
    "
    # Method B + no --disk → EXIT_UNSAFE (4)
    [ "$status" -eq 4 ]
    [[ "$output" == *"Method B"* ]] || [[ "$output" == *"method"* ]]
}

@test "guard_method_prerequisites Method C refuses with no extra disks" {
    # On a single-disk system (or however aibox is configured), Method C
    # should refuse with EXIT_PREREQUISITE. If the host happens to have
    # extra block devices visible to the tool, this test becomes moot —
    # accept EXIT_PREREQUISITE or a clean pass.
    run bash -c "
        set -uo pipefail
        export LAMBOOT_LIB_DIR='$LIB_DIR'
        source '$TOOL'
        OPT_METHOD='C'
        OPT_DISK='/dev/vda'   # pretend target
        guard_method_prerequisites
    "
    # EXIT_PREREQUISITE=7 when no extra disks (expected on most dev
    # hosts); also accept 0 if the host has multiple disks attached.
    [[ "$status" -eq 7 || "$status" -eq 0 ]]
}

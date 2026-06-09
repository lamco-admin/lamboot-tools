#!/usr/bin/env bats
# lamboot-pve-migrate CLI tests — parse/dispatch + the power-discipline invariant
# (never start/stop a VM; refuse a running VM with EXIT_UNSAFE). `qm` is mocked so
# no Proxmox host is required.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-pve-migrate"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    [ -x "$TOOL" ] || skip "lamboot-pve-migrate not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"

    # A mock `qm` whose VM state is controlled by MOCK_VM_STATE.
    QBIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$QBIN"
    cat > "$QBIN/qm" <<'EOF'
#!/bin/bash
cmd="$1"; shift
case "$cmd" in
  status)       echo "status: ${MOCK_VM_STATE:-stopped}" ;;
  config)       printf 'scsi0: local:vm-999-disk-0,size=80G\nbios: seabios\n' ;;
  listsnapshot) printf '%s\n' "${MOCK_SNAPSHOTS:-}" ;;
  set|snapshot|rollback) exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$QBIN/qm"
    export PATH="$QBIN:$PATH"
}

@test "pve-migrate --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-pve-migrate"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "help lists all four subcommands" {
    run "$TOOL" --help
    [ "$status" -eq 0 ]
    for sc in snapshot prep-uefi finalize-uefi rollback; do
        [[ "$output" == *"$sc"* ]]
    done
}

@test "unknown subcommand fails" {
    run "$TOOL" bogus
    [ "$status" -ne 0 ]
}

@test "snapshot without a VMID fails" {
    run "$TOOL" snapshot
    [ "$status" -ne 0 ]
}

@test "power discipline: prep-uefi refuses a RUNNING VM with EXIT_UNSAFE (4)" {
    MOCK_VM_STATE=running run "$TOOL" prep-uefi 999 --method B --iso local:iso/x.iso
    [ "$status" -eq 4 ]
    [[ "$output" == *"running"* ]]
}

@test "power discipline: rollback refuses a RUNNING VM with EXIT_UNSAFE (4)" {
    MOCK_VM_STATE=running run "$TOOL" rollback 999
    [ "$status" -eq 4 ]
}

@test "power discipline: finalize-uefi refuses a RUNNING VM with EXIT_UNSAFE (4)" {
    MOCK_VM_STATE=running run "$TOOL" finalize-uefi 999
    [ "$status" -eq 4 ]
}

@test "prep-uefi Method B requires --iso" {
    # Stopped VM, non-root: the stopped check passes, then root is required OR the
    # missing --iso is caught. Either way it must not silently proceed.
    MOCK_VM_STATE=stopped run "$TOOL" prep-uefi 999 --method B
    [ "$status" -ne 0 ]
}

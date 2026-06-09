#!/usr/bin/env bats
# lamboot-pve-fleet verify/exec — guest-side execution from the host.
# `qm` (incl. `qm guest exec`) is mocked so no Proxmox host is required.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-pve-fleet"
    LIB_DIR="$BATS_TEST_DIRNAME/../../lib"
    [ -x "$TOOL" ] || skip "lamboot-pve-fleet not executable"
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
    export LAMBOOT_LIB_DIR="$LIB_DIR"

    QBIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$QBIN"
    cat > "$QBIN/qm" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "guest exec" ]; then
    echo '{"exitcode":0,"out-data":"All 11 verification checks passed\n","exited":1}'
    exit 0
fi
case "$1" in
  status) echo "status: running" ;;
  list)   printf 'VMID NAME\n129 ubu\n' ;;
  config) printf 'bios: ovmf\nargs: -fw_cfg name=opt/lamboot/config,file=/var/lib/lamboot/129.json\nhookscript: local:snippets/lamboot-hookscript.pl\n' ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$QBIN/qm"
    export PATH="$QBIN:$PATH"
}

@test "help lists verify and exec" {
    run "$TOOL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"verify"* ]]
    [[ "$output" == *"exec"* ]]
}

@test "exec rejects a non-lamboot tool (not an arbitrary remote shell)" {
    run "$TOOL" exec 129 -- rm -rf /
    [ "$status" -ne 0 ]
    [[ "$output" == *"restricted to lamboot-"* ]]
}

@test "exec requires a tool after --" {
    run "$TOOL" exec 129
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a tool"* ]]
}

@test "exec requires a VMID" {
    run "$TOOL" exec -- lamboot-inspect summary
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a VMID"* ]]
}

@test "verify requires a VMID or --all" {
    run "$TOOL" verify
    [ "$status" -ne 0 ]
    [[ "$output" == *"VMID"* || "$output" == *"--all"* ]]
}

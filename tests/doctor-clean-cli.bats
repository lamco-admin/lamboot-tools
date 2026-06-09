#!/usr/bin/env bats
# lamboot-doctor clean/restore — guided, reversible, logged hygiene orchestration.
# Sibling workers (lamboot-nvram, lamboot-esp) are mocked so no ESP/NVRAM needed.

bats_require_minimum_version 1.5.0

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-doctor"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-doctor not executable"
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
    export LAMBOOT_LIB_DIR="$LIB_DIR"

    MBIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$MBIN"
    cat > "$MBIN/lamboot-nvram" <<'EOF'
#!/bin/bash
echo "NVRAM-MOCK $*" >&2
exit 0
EOF
    cat > "$MBIN/lamboot-esp" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "clean --json" ]; then
  echo '{"findings":[{"id":"esp.clean.preview","context":{"count":1,"files":["/boot/efi/EFI/junk/a.bak"]}}]}'
fi
exit 0
EOF
    chmod +x "$MBIN"/lamboot-*
    export PATH="$MBIN:$PATH"
}

@test "doctor --version reports tool + toolkit" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-doctor"* ]]
}

@test "help lists clean and restore" {
    run "$TOOL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
    [[ "$output" == *"restore"* ]]
}

@test "clean dry-run previews both surfaces and changes nothing" {
    run "$TOOL" clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"NVRAM-MOCK clean"* ]]      # nvram worker invoked (dry-run)
    [[ "$output" == *"stale file(s) would be removed"* ]]  # esp preview
    [[ "$output" == *"Dry-run preview complete"* ]]
}

@test "clean --only nvram does not touch the ESP surface" {
    run "$TOOL" clean --only nvram
    [ "$status" -eq 0 ]
    [[ "$output" == *"NVRAM-MOCK clean"* ]]
    [[ "$output" != *"stale file(s) would be removed"* ]]
}

@test "restore with a non-existent backup dir fails clearly (before the root check)" {
    run "$TOOL" restore --backup-dir /tmp/does-not-exist-xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"no lamboot-doctor backup found"* ]]
}

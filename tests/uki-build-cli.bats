#!/usr/bin/env bats
# lamboot-uki-build CLI + PE-parse tests.

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-uki-build"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-uki-build not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

require_ukify() {
    command -v ukify >/dev/null 2>&1 || skip "ukify not installed"
}

@test "uki-build --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-uki-build"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "uki-build help lists all four subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"build"* ]]
    [[ "$output" == *"inspect"* ]]
    [[ "$output" == *"sign"* ]]
    [[ "$output" == *"verify"* ]]
    [[ "$output" == *"[beta]"* ]]
}

@test "uki-build help build shows detail with arguments" {
    run "$TOOL" help build
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"--kernel"* ]]
    [[ "$output" == *"--initrd"* ]]
}

@test "uki-build help sign shows key + cert requirements" {
    run "$TOOL" help sign
    [ "$status" -eq 0 ]
    [[ "$output" == *"--key"* ]]
    [[ "$output" == *"--cert"* ]]
}

@test "uki-build --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "uki-build with no subcommand errors" {
    run "$TOOL"
    [ "$status" -ne 0 ]
}

@test "uki-build inspect without arg errors" {
    run "$TOOL" inspect
    [ "$status" -ne 0 ]
}

@test "uki-build sign without key errors" {
    TMP="$(mktemp)"
    run "$TOOL" sign "$TMP"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--key"* ]]
    rm -f "$TMP"
}

@test "uki-build verify without cert errors" {
    TMP="$(mktemp)"
    run "$TOOL" verify "$TMP"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--cert"* ]]
    rm -f "$TMP"
}

@test "uki-build build without kernel errors" {
    run "$TOOL" build /tmp/nonexistent.efi
    [ "$status" -ne 0 ]
    [[ "$output" == *"--kernel"* ]]
}

@test "uki-build build with missing kernel file errors" {
    run "$TOOL" build /tmp/nope.efi --kernel /tmp/definitely-not-a-kernel-$$
    [ "$status" -ne 0 ]
}

@test "uki-build inspect errors on non-PE file" {
    TMP="$(mktemp)"
    printf 'not a PE file' > "$TMP"
    run "$TOOL" inspect "$TMP"
    [ "$status" -ne 0 ]
    rm -f "$TMP"
}

@test "uki-build inspect errors on empty file" {
    TMP="$(mktemp)"
    run "$TOOL" inspect "$TMP"
    [ "$status" -ne 0 ]
    rm -f "$TMP"
}

@test "uki-build inspect parses installed UEFI binary (if available)" {
    require_jq
    # Find any available PE binary on the system to verify header parsing works
    local pe_file=""
    for candidate in /boot/efi/EFI/debian/shimx64.efi /boot/efi/EFI/ubuntu/shimx64.efi /boot/efi/EFI/fedora/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI; do
        if [ -r "$candidate" ]; then
            pe_file="$candidate"
            break
        fi
    done
    [ -n "$pe_file" ] || skip "no readable UEFI binary on this host"

    run "$TOOL" inspect "$pe_file" --json
    [ "$status" -eq 0 ]
    # Expect at least a PE header finding
    echo "$output" | jq -e '.findings[] | select(.id == "ukibuild.inspect.header")' >/dev/null
}

@test "uki-build unknown flag errors" {
    run "$TOOL" --not-a-flag
    [ "$status" -ne 0 ]
}

@test "uki-build unknown subcommand errors" {
    run "$TOOL" bogus-sub
    [ "$status" -ne 0 ]
}

@test "uki-build --backend with unknown value errors during build" {
    run "$TOOL" build /tmp/x.efi --kernel /tmp/nonexistent --backend bogus
    [ "$status" -ne 0 ]
}

@test "uki-build build --dry-run reports planned build" {
    require_jq
    # Find any kernel on the system
    local k=""
    for candidate in /boot/vmlinuz-* /boot/vmlinux /boot/kernel; do
        if [ -r "$candidate" ]; then
            k="$candidate"
            break
        fi
    done
    [ -n "$k" ] || skip "no readable kernel on this host"

    run --separate-stderr "$TOOL" build /tmp/test-uki.efi --kernel "$k" --cmdline "root=UUID=test" --dry-run --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.findings[] | select(.id == "ukibuild.build.dry_run")' >/dev/null
    # Should NOT have created the output
    [ ! -f /tmp/test-uki.efi ]
}

@test "uki-build --no-color yields no ANSI" {
    run "$TOOL" help --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

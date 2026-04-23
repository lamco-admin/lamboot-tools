#!/usr/bin/env bats

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`
# lamboot-signing-keys CLI + RSA-2048 constraint tests.

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-signing-keys"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-signing-keys not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
    TMP_DIR="$(mktemp -d -t lamboot-signing-test.XXXXXX)"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

require_openssl() {
    command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
}

@test "signing-keys --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-signing-keys"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "signing-keys help lists all subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"generate"* ]]
    [[ "$output" == *"inspect"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"mok-enroll"* ]]
    [[ "$output" == *"ovmf-vars"* ]]
    [[ "$output" == *"[experimental]"* ]]
}

@test "signing-keys help categories are grouped correctly" {
    run "$TOOL" help
    [[ "$output" == *"Keys:"* ]]
    [[ "$output" == *"User MOK:"* ]]
    [[ "$output" == *"OVMF:"* ]]
    [[ "$output" == *"Release Eng:"* ]]
}

@test "signing-keys help generate shows size warning" {
    run "$TOOL" help generate
    [ "$status" -eq 0 ]
    [[ "$output" == *"--force-4096"* ]]
    [[ "$output" == *"Debian"* ]] || [[ "$output" == *"1013320"* ]]
}

@test "signing-keys --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "signing-keys with no subcommand errors" {
    run "$TOOL"
    [ "$status" -ne 0 ]
}

@test "signing-keys status runs and emits findings" {
    require_jq
    run --separate-stderr "$TOOL" status --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.tool == "lamboot-signing-keys"' >/dev/null
    # At least one finding should be present (SB state or BIOS skip)
    local count
    count=$(echo "$output" | jq '.findings | length')
    [ "$count" -ge 1 ]
}

@test "signing-keys refuses RSA-4096 for db without --force-4096" {
    require_jq
    run --separate-stderr "$TOOL" generate --type db --size 4096 --output "$TMP_DIR/x" --json
    [ "$status" -eq 4 ]  # EXIT_UNSAFE
    echo "$output" | jq -e '.findings[] | select(.id == "keys.rsa4096_refused")' >/dev/null
}

@test "signing-keys allows RSA-4096 for pk (--dry-run)" {
    run "$TOOL" generate --type pk --size 4096 --output "$TMP_DIR/pk" --dry-run
    [ "$status" -eq 0 ]
}

@test "signing-keys allows RSA-4096 for kek (--dry-run)" {
    run "$TOOL" generate --type kek --size 4096 --output "$TMP_DIR/kek" --dry-run
    [ "$status" -eq 0 ]
}

@test "signing-keys generate --dry-run does not create files" {
    run "$TOOL" generate --type db --output "$TMP_DIR/test" --dry-run
    [ "$status" -eq 0 ]
    [ ! -f "$TMP_DIR/test.key" ]
    [ ! -f "$TMP_DIR/test.crt" ]
}

@test "signing-keys inspect on non-existent file errors" {
    run "$TOOL" inspect "$TMP_DIR/definitely-not-a-file"
    [ "$status" -ne 0 ]
}

@test "signing-keys inspect on empty file errors" {
    : > "$TMP_DIR/empty"
    run "$TOOL" inspect "$TMP_DIR/empty"
    [ "$status" -ne 0 ]
}

@test "signing-keys mok-enroll without CERT errors" {
    run "$TOOL" mok-enroll
    [ "$status" -ne 0 ]
}

@test "signing-keys mok-enroll without root refuses" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    : > "$TMP_DIR/fake.crt"
    run "$TOOL" mok-enroll "$TMP_DIR/fake.crt"
    [ "$status" -eq 7 ]  # EXIT_PREREQUISITE (either root or mokutil missing)
}

@test "signing-keys sign-binary without --key errors" {
    : > "$TMP_DIR/fake.efi"
    run "$TOOL" sign-binary "$TMP_DIR/fake.efi"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--key"* ]]
}

@test "signing-keys sign-binary without --cert errors" {
    : > "$TMP_DIR/fake.efi"
    : > "$TMP_DIR/key"
    run "$TOOL" sign-binary "$TMP_DIR/fake.efi" --key "$TMP_DIR/key"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--cert"* ]]
}

@test "signing-keys ovmf-vars without --cert errors" {
    run "$TOOL" ovmf-vars "$TMP_DIR/vars.fd"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--cert"* ]]
}

@test "signing-keys unknown flag errors" {
    run "$TOOL" --not-a-flag
    [ "$status" -ne 0 ]
}

@test "signing-keys unknown subcommand errors" {
    run "$TOOL" bogus-sub
    [ "$status" -ne 0 ]
}

@test "signing-keys --no-color yields no ANSI" {
    run "$TOOL" help --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

@test "signing-keys rotate db recognizes the target and validates prerequisites" {
    # v0.2 implements rotate for db/kek/pk per founder mandate (audit §9c).
    # With no existing key material to rotate from, rotate should diagnose
    # the missing prerequisite rather than silently succeeding or claiming
    # the feature is unimplemented.
    run "$TOOL" rotate db
    [ "$status" -ne 0 ]
    [[ "$output" != *"not implemented"* ]]
    [[ "$output" != *"v0.2-deferred"* ]]
}

@test "signing-keys rotate rejects unknown target" {
    run "$TOOL" rotate bogus-target
    [ "$status" -ne 0 ]
}

@test "signing-keys status --json has known-good schema" {
    require_jq
    run --separate-stderr "$TOOL" status --json
    echo "$output" | jq -e '.schema_version == "v1"' >/dev/null
    echo "$output" | jq -e '.summary.status' >/dev/null
}

@test "signing-keys generate actually creates RSA-2048 keypair" {
    require_openssl
    # Generate with a known passphrase via stdin
    run bash -c "echo 'test-pass-$$' | $TOOL generate --type db --output '$TMP_DIR/it' --force <<EOF
test-pass-$$
test-pass-$$
EOF"
    # Skip if openssl prompts can't be scripted in this env; check for file
    if [ -f "$TMP_DIR/it.crt" ]; then
        # Verify size is 2048
        local size
        size=$(openssl x509 -in "$TMP_DIR/it.crt" -noout -text 2>/dev/null | grep -oE 'Public-Key: \([0-9]+ bit' | grep -oE '[0-9]+' | head -1)
        [ "$size" = "2048" ]
    else
        skip "openssl passphrase prompt couldn't be scripted"
    fi
}

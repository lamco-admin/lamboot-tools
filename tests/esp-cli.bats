#!/usr/bin/env bats
# lamboot-esp CLI + subcommand tests (read-only, safe anywhere).

bats_require_minimum_version 1.5.0  # for `run --separate-stderr`

setup() {
    TOOL="$BATS_TEST_DIRNAME/../tools/lamboot-esp"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOL" ] || skip "lamboot-esp not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

require_esp() {
    if ! mountpoint -q /boot/efi 2>/dev/null && ! mountpoint -q /efi 2>/dev/null; then
        skip "no ESP mounted on this host"
    fi
}

@test "esp --version prints tool + toolkit version" {
    run "$TOOL" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-esp"* ]]
    [[ "$output" == *"lamboot-tools"* ]]
}

@test "esp help lists four subcommands" {
    run "$TOOL" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"check"* ]]
    [[ "$output" == *"inventory"* ]]
    [[ "$output" == *"clean"* ]]
    [[ "$output" == *"deploy"* ]]
}

@test "esp help check shows detail" {
    run "$TOOL" help check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
}

@test "esp help inventory shows detail" {
    run "$TOOL" help inventory
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXAMPLES"* ]]
}

@test "esp help clean shows --apply documentation" {
    run "$TOOL" help clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
}

@test "esp help deploy shows --src + --signed + --driver" {
    run "$TOOL" help deploy
    [ "$status" -eq 0 ]
    [[ "$output" == *"--src"* ]]
    [[ "$output" == *"--signed"* ]]
    [[ "$output" == *"--driver"* ]]
}

@test "esp deploy end-to-end on a fake ESP renames -signed -> bare and writes manifest" {
    [[ $EUID -eq 0 ]] || skip "deploy requires root"
    src=$(mktemp -d)
    esp=$(mktemp -d)
    mkdir -p "$src/EFI/LamBoot/modules"
    echo "FAKE_BIN_SIGNED" > "$src/EFI/LamBoot/lambootx64-signed.efi"
    echo "FAKE_DS"         > "$src/EFI/LamBoot/modules/diag-shell.efi"
    echo "FAKE_DS_SIGNED"  > "$src/EFI/LamBoot/modules/diag-shell-signed.efi"
    echo "[modules.diag-shell]" > "$src/EFI/LamBoot/modules/manifest.toml"
    echo "[lamboot]"       > "$src/EFI/LamBoot/policy.toml"

    run "$TOOL" deploy --esp "$esp" --src "$src" --signed \
                       --manifest-version "test" --manifest-distro "bats"
    [ "$status" -eq 0 ]
    [ -f "$esp/EFI/LamBoot/lambootx64.efi" ]
    [ ! -f "$esp/EFI/LamBoot/lambootx64-signed.efi" ]
    [ -f "$esp/EFI/LamBoot/modules/diag-shell.efi" ]
    [ ! -f "$esp/EFI/LamBoot/modules/diag-shell-signed.efi" ]
    [ -f "$esp/EFI/LamBoot/.install-manifest" ]
    grep -q "EFI/LamBoot/lambootx64.efi" "$esp/EFI/LamBoot/.install-manifest"
    ! grep -q "lambootx64-signed.efi" "$esp/EFI/LamBoot/.install-manifest"
    rm -rf "$src" "$esp"
}

@test "esp --json-schema returns schema declaration" {
    run "$TOOL" --json-schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"schema"* ]]
}

@test "esp check runs unprivileged" {
    require_esp
    run "$TOOL" check
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "esp check --json emits valid schema v1" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" check --json
    echo "$output" | jq -e '.schema_version == "v1"' >/dev/null
    echo "$output" | jq -e '.tool == "lamboot-esp"' >/dev/null
}

@test "esp check --json has multiple esp category findings" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" check --json
    local cats
    cats=$(echo "$output" | jq -r '.findings[].category' | sort -u | grep -c '^esp_')
    [ "$cats" -ge 3 ]
}

@test "esp check warning findings have remediation" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" check --json
    local missing
    missing=$(echo "$output" | jq '[.findings[] | select(.severity == "warning" or .severity == "error" or .severity == "critical") | select(.remediation == {} or .remediation == null)] | length')
    [ "$missing" -eq 0 ]
}

@test "esp inventory runs" {
    require_esp
    run "$TOOL" inventory
    [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "esp inventory --json emits findings" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" inventory --json
    local count
    count=$(echo "$output" | jq '.findings | length')
    [ "$count" -ge 1 ]
}

@test "esp clean without --apply is dry-run only" {
    require_esp
    run "$TOOL" clean
    # Exits 0 (preview) or 3 (no stale); never 2 or 1
    [ "$status" -eq 0 ] || [ "$status" -eq 3 ]
}

@test "esp clean --apply without root fails" {
    [ "$EUID" -eq 0 ] && skip "running as root"
    run "$TOOL" clean --apply
    # Requires root; should exit 7 (prerequisite) — after ESP detection succeeds
    # On hosts where ESP is invisible to non-root, may exit 7 earlier
    [ "$status" -eq 7 ]
}

@test "esp with unknown subcommand errors" {
    run "$TOOL" bogus-command
    [ "$status" -ne 0 ]
}

@test "esp --no-color emits no ANSI" {
    require_esp
    run "$TOOL" check --no-color
    # shellcheck disable=SC2196
    if printf '%s' "$output" | grep -qE $'\033\\['; then
        return 1
    fi
}

@test "esp finding IDs follow dotted-path convention" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" check --json
    local bad
    bad=$(echo "$output" | jq -r '.findings[].id' | grep -cvE '^[a-z0-9_]+(\.[a-z0-9_+.-]+)*$' || true)
    bad="${bad:-0}"
    [ "$bad" -eq 0 ]
}

@test "esp default subcommand is check" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" --json
    # Default should run check; should produce findings in esp_filesystem category
    echo "$output" | jq -e '[.findings[] | select(.category == "esp_filesystem")] | length > 0' >/dev/null
}

@test "esp check includes fstab finding" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" check --json
    echo "$output" | jq -e '[.findings[] | select(.category == "esp_fstab")] | length > 0' >/dev/null
}

@test "esp inventory includes bootloaders summary" {
    require_esp
    require_jq
    run --separate-stderr "$TOOL" inventory --json
    echo "$output" | jq -e '.findings[] | select(.id == "esp.inventory.bootloaders")' >/dev/null
}

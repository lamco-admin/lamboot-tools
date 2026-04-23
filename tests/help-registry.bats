#!/usr/bin/env bats
# Help registry tests — three surfaces from one registry.

setup() {
    LIB="$BATS_TEST_DIRNAME/../lib/lamboot-toolkit-help.sh"
    # shellcheck source=../lib/lamboot-toolkit-help.sh
    source "$LIB"
    LAMBOOT_HELP_REGISTRY=""
}

@test "register_subcommand with minimal fields succeeds" {
    register_subcommand \
        --name "check" \
        --category "Diagnostics" \
        --summary "Run ESP health check" \
        --syntax "lamboot-esp check [--esp PATH]"
    [ -n "$LAMBOOT_HELP_REGISTRY" ]
}

@test "register_subcommand without --name fails" {
    run register_subcommand \
        --category "Diagnostics" \
        --summary "Missing name" \
        --syntax "foo"
    [ "$status" -ne 0 ]
}

@test "dispatch_help with no args prints full listing" {
    register_subcommand \
        --name "check" --category "Diag" --summary "run check" --syntax "foo"
    run dispatch_help
    [ "$status" -eq 0 ]
    [[ "$output" == *"subcommand reference"* ]]
    [[ "$output" == *"run check"* ]]
}

@test "dispatch_help <subcommand> prints detail" {
    register_subcommand \
        --name "check" \
        --category "Diag" \
        --summary "run check" \
        --syntax "foo check" \
        --arg "target:path to check" \
        --example "foo check /tmp"
    run dispatch_help check
    [ "$status" -eq 0 ]
    [[ "$output" == *"SYNTAX"* ]]
    [[ "$output" == *"ARGUMENTS"* ]]
    [[ "$output" == *"EXAMPLES"* ]]
    [[ "$output" == *"foo check /tmp"* ]]
}

@test "dispatch_help with unknown subcommand returns error" {
    register_subcommand \
        --name "check" --category "Diag" --summary "run check" --syntax "foo"
    run dispatch_help nonexistent
    [ "$status" -ne 0 ]
}

@test "aliases are resolved to canonical name" {
    register_subcommand \
        --name "check" \
        --alias "validate" \
        --alias "verify" \
        --category "Diag" \
        --summary "run check" \
        --syntax "foo"
    run dispatch_help validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aliases"* ]]
}

@test "maturity labels surface in full listing" {
    register_subcommand \
        --name "unstable-cmd" \
        --category "Experimental" \
        --summary "experimental command" \
        --syntax "foo" \
        --maturity "experimental"
    run dispatch_help
    [[ "$output" == *"[experimental]"* ]]
}

@test "offline and root markers surface in full listing" {
    register_subcommand \
        --name "repair" \
        --category "Repair" \
        --summary "repair boot" \
        --syntax "foo" \
        --offline-capable "true" \
        --requires-root "true"
    run dispatch_help
    [[ "$output" == *"[offline]"* ]]
    [[ "$output" == *"[root]"* ]]
}

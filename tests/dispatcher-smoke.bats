#!/usr/bin/env bats
# lamboot-toolkit dispatcher smoke tests — help, version, subcommand parsing.

setup() {
    TOOLKIT="$BATS_TEST_DIRNAME/../tools/lamboot-toolkit"
    LIB_DIR="$BATS_TEST_DIRNAME/../lib"
    [ -x "$TOOLKIT" ] || skip "dispatcher not executable"
    export LAMBOOT_LIB_DIR="$LIB_DIR"
}

@test "dispatcher prints help without args" {
    run "$TOOLKIT" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-toolkit"* ]]
}

@test "dispatcher --help works" {
    run "$TOOLKIT" --help
    [ "$status" -eq 0 ]
}

@test "dispatcher version works" {
    run "$TOOLKIT" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"lamboot-toolkit"* ]]
}

@test "dispatcher --version works" {
    run "$TOOLKIT" --version
    [ "$status" -eq 0 ]
}

@test "dispatcher status runs" {
    run "$TOOLKIT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Core tools"* ]]
}

@test "dispatcher verify runs" {
    run "$TOOLKIT" verify
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" == *"shared library"* ]]
}

@test "dispatcher rejects unknown subcommand" {
    run "$TOOLKIT" thisisnotacommand
    [ "$status" -ne 0 ]
}

@test "dispatcher run with no tool name fails" {
    run "$TOOLKIT" run
    [ "$status" -ne 0 ]
}

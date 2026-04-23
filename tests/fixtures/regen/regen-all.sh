#!/bin/bash
# regen-all.sh — regenerate every fixture image
#
# All 11 fixtures are synthetic (no real distro installs). Total runtime on
# a modern host: ~2-5 minutes. Requires: root (for losetup/mount/cryptsetup),
# sgdisk, sfdisk, mkfs.fat, mkfs.ext4, cryptsetup, python3.
#
# After regen, tests/fixtures/download-fixtures.sh verifies checksums. If
# the fixtures are uploaded to fixtures.lamboot.dev for CI consumption,
# commit the updated fixtures.sha256 to reflect the new hashes.

set -uo pipefail

REGEN_DIR="$(cd "$(dirname "$0")" && pwd)"

FIXTURES=(
    clean-bios-mbr
    clean-uefi-gpt
    hybrid-mbr
    encrypted-root
    windows-mbr
    no-esp
    full-esp
    corrupted-esp-fat
    lamboot-installed
    grub-installed
    sdboot-installed
)

for fixture in "${FIXTURES[@]}"; do
    script="$REGEN_DIR/${fixture}.sh"
    if [[ ! -x "$script" ]]; then
        printf 'skip %s: regen script not present\n' "$fixture"
        continue
    fi
    printf '\n=== regenerating %s ===\n' "$fixture"
    if "$script"; then
        printf '  ok: %s regenerated\n' "$fixture"
    else
        printf '  fail: %s regen returned %d\n' "$fixture" "$?"
    fi
done

printf '\nregen-all complete. Re-run tests/fixtures/download-fixtures.sh to verify checksums.\n'

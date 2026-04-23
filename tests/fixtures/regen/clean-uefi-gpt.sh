#!/bin/bash
# clean-uefi-gpt.sh — 500 MB GPT image with ESP (FAT32) + ext4 root.
#
# Represents a minimal UEFI boot layout: ef00 ESP at sector 2048 (512 MiB),
# ext4 root afterwards. Empty ESP (no bootloader files). Used as the positive
# baseline for lamboot-diagnose (UEFI mode detection) and lamboot-esp
# (inventory of an empty-but-valid ESP).

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/clean-uefi-gpt.raw"

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sgdisk mkfs.fat mkfs.ext4; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not installed"
done
[[ $EUID -eq 0 ]] || fail "needs root for losetup"

dd if=/dev/zero of="$OUTPUT" bs=1M count=500 status=none || fail "dd failed"

sgdisk --clear "$OUTPUT" >/dev/null || fail "sgdisk --clear failed"
sgdisk --new=1:2048:+128M --typecode=1:ef00 --change-name=1:"EFI System" "$OUTPUT" >/dev/null \
    || fail "sgdisk ESP failed"
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"linux-root" "$OUTPUT" >/dev/null \
    || fail "sgdisk root failed"

LOOP=$(losetup --find --show --partscan "$OUTPUT") || fail "losetup failed"
trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT
# Allow kernel time to scan partitions
sleep 0.3
mkfs.fat -F 32 -n ESP "${LOOP}p1" >/dev/null || fail "mkfs.fat failed"
mkfs.ext4 -q -F -L ROOT "${LOOP}p2" >/dev/null || fail "mkfs.ext4 failed"

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "clean-uefi-gpt.raw built: 500 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  clean-uefi-gpt\.raw$/d' "$checksums"
    printf '%s  clean-uefi-gpt.raw\n' "$sha" >> "$checksums"
fi
exit 0

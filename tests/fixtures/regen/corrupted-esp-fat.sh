#!/bin/bash
# corrupted-esp-fat.sh — GPT image with ef00 ESP whose FAT is intentionally corrupted.
#
# Used to validate lamboot-diagnose's esp.fat_corrupt finding + the
# lamboot-repair esp.fsck action. Corrupts the FAT filesystem by zeroing a
# chunk of the reserved sector / FAT region after mkfs.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/corrupted-esp-fat.raw"

readonly RED=$'\033[0;31m'; readonly GREEN=$'\033[0;32m'; readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sgdisk mkfs.fat; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not installed"
done
[[ $EUID -eq 0 ]] || fail "needs root for losetup"

dd if=/dev/zero of="$OUTPUT" bs=1M count=200 status=none || fail "dd failed"
sgdisk --clear "$OUTPUT" >/dev/null || fail "sgdisk --clear"
sgdisk --new=1:2048:+100M --typecode=1:ef00 --change-name=1:"EFI System" "$OUTPUT" >/dev/null \
    || fail "sgdisk ESP"

LOOP=$(losetup --find --show --partscan "$OUTPUT") || fail "losetup failed"
trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT
sleep 0.3
mkfs.fat -F 32 -n ESP "${LOOP}p1" >/dev/null || fail "mkfs.fat failed"

# Corrupt a region of the primary FAT (starts around sector 32 on default mkfs.fat layout).
# Zero 16 KiB starting 32 sectors into the partition — this mangles FAT entries
# without removing the boot sector's magic, so lamboot-diagnose sees a partition
# that looks like FAT but fsck reports damage.
dd if=/dev/zero of="${LOOP}p1" bs=512 seek=32 count=32 conv=notrunc status=none

losetup -d "$LOOP"
trap - EXIT

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "corrupted-esp-fat.raw built: 200 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  corrupted-esp-fat\.raw$/d' "$checksums"
    printf '%s  corrupted-esp-fat.raw\n' "$sha" >> "$checksums"
fi
exit 0

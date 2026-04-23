#!/bin/bash
# full-esp.sh — 200 MB image with a 100 MB ESP filled to >95% capacity.
#
# Used to validate lamboot-esp's esp.free_space warning + lamboot-doctor's
# "ESP full" policy action. Fills the ESP with a few MB of filler files so
# the low-space threshold trips.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/full-esp.raw"

readonly RED=$'\033[0;31m'; readonly GREEN=$'\033[0;32m'; readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sgdisk mkfs.fat; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not installed"
done
[[ $EUID -eq 0 ]] || fail "needs root for losetup + mount"

dd if=/dev/zero of="$OUTPUT" bs=1M count=200 status=none || fail "dd failed"
sgdisk --clear "$OUTPUT" >/dev/null || fail "sgdisk --clear"
sgdisk --new=1:2048:+100M --typecode=1:ef00 --change-name=1:"EFI System" "$OUTPUT" >/dev/null \
    || fail "sgdisk ESP"

LOOP=$(losetup --find --show --partscan "$OUTPUT") || fail "losetup failed"
trap '{ umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }' EXIT
sleep 0.3
mkfs.fat -F 32 -n ESP "${LOOP}p1" >/dev/null || fail "mkfs.fat failed"

MNT=$(mktemp -d -t lamboot-fixture-full-esp.XXXXXX)
mount "${LOOP}p1" "$MNT" || fail "mount ESP failed"

# Create typical EFI layout + fill to ~96%
mkdir -p "$MNT/EFI/BOOT" "$MNT/EFI/test-bootloader"
# Write a small fake fallback binary (not a real EFI; stays under signature checks)
# Use dd rather than printf so arbitrary non-printable bytes from /dev/urandom
# don't trip printf's format-string parser.
{ printf 'MZ\0\0\0\0\0\0'; head -c 128 /dev/urandom; } > "$MNT/EFI/BOOT/BOOTX64.EFI"

# Fill ESP to ~96% with a large filler file
avail_kb=$(df -k --output=avail "$MNT" | tail -1 | tr -d ' ')
target_kb=$((avail_kb - 4096))  # leave 4 MiB free; well below the default 10 MiB threshold
dd if=/dev/urandom of="$MNT/filler.bin" bs=1K count="$target_kb" status=none || true
sync

umount "$MNT"
rmdir "$MNT"
losetup -d "$LOOP"
trap - EXIT

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "full-esp.raw built: 200 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  full-esp\.raw$/d' "$checksums"
    printf '%s  full-esp.raw\n' "$sha" >> "$checksums"
fi
exit 0

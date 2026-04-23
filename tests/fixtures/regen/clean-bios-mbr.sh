#!/bin/bash
# clean-bios-mbr.sh — 500 MB MBR-partitioned image with ext4 root (no ESP).
#
# Represents a vanilla BIOS-boot system: MBR partition table, one ext4 root
# partition, no EFI System Partition. Used as the positive baseline for
# lamboot-migrate to-uefi (the guardrails should pass; the conversion
# proceeds to lay down GPT + ESP).

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/clean-bios-mbr.raw"

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sfdisk mkfs.ext4; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not installed"
done

dd if=/dev/zero of="$OUTPUT" bs=1M count=500 status=none || fail "dd failed"

# MBR with one Linux partition (type 83) covering sectors 2048..end
sfdisk "$OUTPUT" >/dev/null 2>&1 <<'PART' || fail "sfdisk failed"
label: dos
start=2048, type=83, bootable
PART

# Find the partition offset + size (bytes) from sfdisk JSON
offset=$(sfdisk -J "$OUTPUT" | awk -F'[:,]' '/start/ {print $2; exit}' | tr -d ' ')
[[ -n "$offset" ]] || fail "could not read partition offset"
byte_offset=$((offset * 512))

# Format root partition inside the loop-mapped region. Use losetup -o to
# avoid needing a partition mapper (privileged).
if [[ $EUID -ne 0 ]]; then
    fail "clean-bios-mbr fixture needs root for losetup (run via sudo)"
fi
LOOP=$(losetup --find --show -o "$byte_offset" "$OUTPUT") || fail "losetup failed"
trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT

mkfs.ext4 -q -F -L BIOSROOT "$LOOP" >/dev/null || fail "mkfs.ext4 failed"

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "clean-bios-mbr.raw built: 500 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  clean-bios-mbr\.raw$/d' "$checksums"
    printf '%s  clean-bios-mbr.raw\n' "$sha" >> "$checksums"
fi
exit 0

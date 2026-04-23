#!/bin/bash
# hybrid-mbr.sh — build the hybrid-MBR refusal-test fixture
#
# Creates a synthetic disk image with BOTH a GPT partition table AND
# a non-protective MBR partition entry — the exact "flaky and dangerous"
# layout that lamboot-migrate to-uefi's guardrail refuses.
#
# This fixture takes seconds to build, unlike the full-install ones.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/hybrid-mbr.raw"

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'

fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

command -v sgdisk >/dev/null 2>&1 || fail "sgdisk not installed (install gdisk package)"

# 100 MB synthetic image — small enough to build/ship quickly
dd if=/dev/zero of="$OUTPUT" bs=1M count=100 status=none || fail "dd failed"

# Lay down GPT with one partition
sgdisk --clear "$OUTPUT" >/dev/null || fail "sgdisk --clear failed"
sgdisk --new=1:0:+50M --typecode=1:8300 --change-name=1:"linux-root" "$OUTPUT" >/dev/null \
    || fail "sgdisk --new failed"

# Now overlay a hybrid MBR: write a non-protective MBR partition entry
# referencing the GPT partition. This is the exact condition the guardrail
# refuses.
#
# MBR partition table entries start at offset 446, each is 16 bytes:
#   0x00: status (0x80 = active)
#   0x01-0x03: CHS start (ignored modern firmware)
#   0x04: partition type (0x83 = Linux native; DIFFERENT from 0xEE protective)
#   0x05-0x07: CHS end
#   0x08-0x0B: LBA start (little-endian u32)
#   0x0C-0x0F: LBA count (little-endian u32)
#
# Protective MBR normally has ONE entry at type 0xEE. Hybrid MBR has 0xEE
# PLUS one or more real-type partitions.

# Overwrite the second MBR entry (offset 446+16=462) with a fake 0x83 entry
# covering sectors 2048..100k (same range as our GPT partition 1):
python3 - <<'PY' "$OUTPUT"
import struct, sys
path = sys.argv[1]
with open(path, 'r+b') as f:
    f.seek(462)  # 446 + 16 (second partition slot)
    # Active (0x80), CHS ignored, type 0x83 Linux, CHS ignored, start 2048, size 100000
    entry = struct.pack('<BBBBBBBBLL',
        0x80,              # status: active (not required, but makes it "hybrid")
        0x00, 0x00, 0x00,  # CHS start (ignored)
        0x83,              # Linux native
        0x00, 0x00, 0x00,  # CHS end
        2048,              # LBA start
        100000             # LBA count
    )
    f.write(entry)
print('hybrid MBR layout written')
PY

# Compute SHA for the checksums file
sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
size=$(stat -c %s "$OUTPUT")
size_mb=$((size / 1024 / 1024))

ok "hybrid-mbr.raw built: ${size_mb} MB, sha256=${sha:0:16}..."

# Update checksums file (remove any stale entry first)
checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    # Remove existing uncommented hybrid-mbr line
    sed -i '/^[a-f0-9]\{64\}  hybrid-mbr\.raw$/d' "$checksums"
    # Append new line
    printf '%s  hybrid-mbr.raw\n' "$sha" >> "$checksums"
    ok "updated fixtures.sha256"
fi

exit 0

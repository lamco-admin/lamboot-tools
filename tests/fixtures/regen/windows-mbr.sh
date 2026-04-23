#!/bin/bash
# windows-mbr.sh — synthetic MBR image with a Windows-typed partition.
#
# Used to validate lamboot-migrate to-uefi's "Windows dual-boot" guardrail.
# A real Windows install would be ~20 GB; we don't build that. Instead, we
# create an MBR with a partition typed 0x07 (Windows NTFS) + filesystem
# signature bytes that mimic NTFS enough that blkid reports type=ntfs.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/windows-mbr.raw"

readonly RED=$'\033[0;31m'; readonly GREEN=$'\033[0;32m'; readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

command -v sfdisk >/dev/null 2>&1 || fail "sfdisk not installed"

dd if=/dev/zero of="$OUTPUT" bs=1M count=256 status=none || fail "dd failed"

# MBR with one Windows NTFS partition (type 0x07)
sfdisk "$OUTPUT" >/dev/null 2>&1 <<'PART' || fail "sfdisk failed"
label: dos
start=2048, size=500000, type=7
start=502048, type=83
PART

# Write NTFS boot sector signature at start of partition 1 (sector 2048).
# A real NTFS PBR begins with 0xEB 0x52 0x90, has "NTFS    " at offset 3,
# and ends with 0x55 0xAA. The toolkit's guardrail reads the first ~16 bytes
# via blkid heuristics and the partition type code via sfdisk; writing this
# small signature is enough.
python3 - <<'PY' "$OUTPUT"
import struct, sys
path = sys.argv[1]
# Partition 1 starts at sector 2048 = byte 2048*512
with open(path, 'r+b') as f:
    f.seek(2048*512)
    sig = b'\xeb\x52\x90' + b'NTFS    ' + b'\x00'*(512-11-2) + b'\x55\xaa'
    f.write(sig)
print('NTFS signature written to partition 1')
PY

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "windows-mbr.raw built: 256 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  windows-mbr\.raw$/d' "$checksums"
    printf '%s  windows-mbr.raw\n' "$sha" >> "$checksums"
fi
exit 0

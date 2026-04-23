#!/bin/bash
# lamboot-installed.sh — GPT image with ESP containing fake LamBoot binaries.
#
# Used to validate lamboot-diagnose's lamboot detection on the ESP. Writes
# decoy PE32+ files at /EFI/LamBoot/lambootx64.efi + /EFI/BOOT/BOOTX64.EFI
# with MZ/PE headers sufficient to pass lamboot-diagnose's PE32+ signature
# check.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/lamboot-installed.raw"

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
MNT=$(mktemp -d -t lamboot-fixture-lb.XXXXXX)
mount "${LOOP}p1" "$MNT" || fail "mount failed"

mkdir -p "$MNT/EFI/LamBoot" "$MNT/EFI/BOOT"

# Minimal PE32+ skeleton: MZ header at 0, PE offset at 0x3C = 0x40, PE header
# at 0x40 with signature PE\0\0, Machine 0x8664 (x86_64), Optional magic 0x020b.
# lamboot-diagnose's detector checks for MZ + PE + optional header magic.
python3 - <<'PY' "$MNT/EFI/LamBoot/lambootx64.efi" "$MNT/EFI/BOOT/BOOTX64.EFI"
import struct, sys
for path in sys.argv[1:]:
    buf = bytearray(4096)
    buf[0:2] = b'MZ'
    buf[0x3C:0x40] = struct.pack('<I', 0x80)        # e_lfanew → PE header offset 0x80
    buf[0x80:0x84] = b'PE\x00\x00'                  # PE signature
    buf[0x84:0x86] = struct.pack('<H', 0x8664)      # Machine: AMD64
    buf[0x86:0x88] = struct.pack('<H', 0x0003)      # NumberOfSections
    buf[0x98:0x9A] = struct.pack('<H', 240)         # SizeOfOptionalHeader
    buf[0x98+2:0x98+4] = struct.pack('<H', 0x0022)  # Characteristics: EXECUTABLE|LARGE_ADDR
    buf[0x98+2+22:0x98+2+24] = struct.pack('<H', 0x020b)  # Optional magic PE32+
    with open(path, 'wb') as f:
        f.write(buf)
print('wrote PE32+ skeletons')
PY

sync
umount "$MNT"
rmdir "$MNT"
losetup -d "$LOOP"
trap - EXIT

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "lamboot-installed.raw built: 200 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  lamboot-installed\.raw$/d' "$checksums"
    printf '%s  lamboot-installed.raw\n' "$sha" >> "$checksums"
fi
exit 0

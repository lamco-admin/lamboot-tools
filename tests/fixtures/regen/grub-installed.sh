#!/bin/bash
# grub-installed.sh — GPT image with ESP containing fake GRUB binaries.
#
# Used to validate lamboot-diagnose's cross-bootloader detection (GRUB on ESP)
# and lamboot-migrate --remove-grub's ESP-file cleanup logic.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/grub-installed.raw"

readonly RED=$'\033[0;31m'; readonly GREEN=$'\033[0;32m'; readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sgdisk mkfs.fat; do command -v "$t" >/dev/null 2>&1 || fail "$t not installed"; done
[[ $EUID -eq 0 ]] || fail "needs root"

dd if=/dev/zero of="$OUTPUT" bs=1M count=200 status=none || fail "dd failed"
sgdisk --clear "$OUTPUT" >/dev/null
sgdisk --new=1:2048:+100M --typecode=1:ef00 --change-name=1:"EFI System" "$OUTPUT" >/dev/null

LOOP=$(losetup --find --show --partscan "$OUTPUT") || fail "losetup"
trap '{ umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }' EXIT
sleep 0.3
mkfs.fat -F 32 -n ESP "${LOOP}p1" >/dev/null
MNT=$(mktemp -d -t lamboot-fixture-grub.XXXXXX)
mount "${LOOP}p1" "$MNT"

mkdir -p "$MNT/EFI/ubuntu" "$MNT/EFI/debian" "$MNT/EFI/BOOT" "$MNT/grub"

python3 - <<'PY' "$MNT/EFI/ubuntu/grubx64.efi" "$MNT/EFI/ubuntu/shimx64.efi" "$MNT/EFI/debian/grubx64.efi" "$MNT/EFI/BOOT/BOOTX64.EFI"
import struct, sys
for path in sys.argv[1:]:
    buf = bytearray(4096)
    buf[0:2] = b'MZ'
    buf[0x3C:0x40] = struct.pack('<I', 0x80)
    buf[0x80:0x84] = b'PE\x00\x00'
    buf[0x84:0x86] = struct.pack('<H', 0x8664)
    buf[0x86:0x88] = struct.pack('<H', 0x0003)
    buf[0x98:0x9A] = struct.pack('<H', 240)
    buf[0x98+2+22:0x98+2+24] = struct.pack('<H', 0x020b)
    with open(path, 'wb') as f:
        f.write(buf)
PY

# Grub config stub (used by diagnose's grub.cfg existence check)
cat > "$MNT/EFI/ubuntu/grub.cfg" <<'CFG'
# Minimal grub.cfg for fixture purposes
insmod ext2
set root='hd0,gpt1'
menuentry 'Fixture Linux' { linux /boot/vmlinuz root=/dev/sda2 ; initrd /boot/initrd.img }
CFG

sync; umount "$MNT"; rmdir "$MNT"; losetup -d "$LOOP"; trap - EXIT

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "grub-installed.raw built: 200 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  grub-installed\.raw$/d' "$checksums"
    printf '%s  grub-installed.raw\n' "$sha" >> "$checksums"
fi
exit 0

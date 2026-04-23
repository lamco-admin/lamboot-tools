#!/bin/bash
# sdboot-installed.sh — GPT image with ESP containing systemd-boot layout.
#
# Writes /EFI/systemd/systemd-bootx64.efi + /loader/loader.conf + /loader/entries/
# so lamboot-diagnose detects systemd-boot as the installed bootloader.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/sdboot-installed.raw"

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
MNT=$(mktemp -d -t lamboot-fixture-sdb.XXXXXX)
mount "${LOOP}p1" "$MNT"

mkdir -p "$MNT/EFI/systemd" "$MNT/EFI/BOOT" "$MNT/loader/entries"

python3 - <<'PY' "$MNT/EFI/systemd/systemd-bootx64.efi" "$MNT/EFI/BOOT/BOOTX64.EFI"
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

cat > "$MNT/loader/loader.conf" <<'CFG'
default fixture.conf
timeout 3
editor no
CFG

cat > "$MNT/loader/entries/fixture.conf" <<'ENT'
title   Fixture Linux
linux   /vmlinuz
initrd  /initrd.img
options root=UUID=deadbeef-dead-dead-dead-deadbeefbeef rw
ENT

sync; umount "$MNT"; rmdir "$MNT"; losetup -d "$LOOP"; trap - EXIT

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "sdboot-installed.raw built: 200 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  sdboot-installed\.raw$/d' "$checksums"
    printf '%s  sdboot-installed.raw\n' "$sha" >> "$checksums"
fi
exit 0

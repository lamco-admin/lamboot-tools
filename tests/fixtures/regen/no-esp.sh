#!/bin/bash
# no-esp.sh — 500 MB GPT image with root but NO ef00 ESP partition.
#
# A GPT disk that has no ESP at all — the user forgot to create one, or it
# was deleted. Used to validate lamboot-diagnose's esp.missing finding and
# lamboot-repair's "create fallback ESP" action preview.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/no-esp.raw"

readonly RED=$'\033[0;31m'; readonly GREEN=$'\033[0;32m'; readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sgdisk mkfs.ext4; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not installed"
done
[[ $EUID -eq 0 ]] || fail "needs root for losetup"

dd if=/dev/zero of="$OUTPUT" bs=1M count=500 status=none || fail "dd failed"
sgdisk --clear "$OUTPUT" >/dev/null || fail "sgdisk --clear failed"
sgdisk --new=1:2048:0 --typecode=1:8300 --change-name=1:"linux-root-no-esp" "$OUTPUT" >/dev/null \
    || fail "sgdisk new failed"

LOOP=$(losetup --find --show --partscan "$OUTPUT") || fail "losetup failed"
trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT
sleep 0.3
mkfs.ext4 -q -F -L ROOT "${LOOP}p1" >/dev/null || fail "mkfs.ext4 failed"

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "no-esp.raw built: 500 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  no-esp\.raw$/d' "$checksums"
    printf '%s  no-esp.raw\n' "$sha" >> "$checksums"
fi
exit 0

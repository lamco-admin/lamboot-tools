#!/bin/bash
# encrypted-root.sh — MBR image with a LUKS-encrypted root partition.
#
# Used to validate lamboot-migrate to-uefi's "encrypted root" guardrail.
# Formats a small LUKS container (passphrase: "fixture") so blkid reports
# TYPE=crypto_LUKS on the partition.

set -uo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$FIXTURES_DIR/encrypted-root.raw"

readonly RED=$'\033[0;31m'; readonly GREEN=$'\033[0;32m'; readonly RESET=$'\033[0m'
fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

for t in sfdisk cryptsetup; do
    command -v "$t" >/dev/null 2>&1 || fail "$t not installed"
done
[[ $EUID -eq 0 ]] || fail "needs root for losetup + cryptsetup"

dd if=/dev/zero of="$OUTPUT" bs=1M count=256 status=none || fail "dd failed"
sfdisk "$OUTPUT" >/dev/null 2>&1 <<'PART' || fail "sfdisk failed"
label: dos
start=2048, type=83
PART

LOOP=$(losetup --find --show --partscan "$OUTPUT") || fail "losetup failed"
trap 'losetup -d "$LOOP" 2>/dev/null || true' EXIT
sleep 0.3

# Minimal LUKS2 header — use a fixed passphrase for deterministic hash.
printf 'fixture' | cryptsetup luksFormat --batch-mode --type luks2 \
    --pbkdf argon2id --pbkdf-memory 32 --pbkdf-parallel 1 --pbkdf-force-iterations 4 \
    "${LOOP}p1" - || fail "cryptsetup luksFormat failed"

losetup -d "$LOOP"
trap - EXIT

sha=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
ok "encrypted-root.raw built: 256 MB, sha256=${sha:0:16}..."

checksums="$FIXTURES_DIR/fixtures.sha256"
if [[ -f "$checksums" ]]; then
    sed -i '/^[a-f0-9]\{64\}  encrypted-root\.raw$/d' "$checksums"
    printf '%s  encrypted-root.raw\n' "$sha" >> "$checksums"
fi
exit 0

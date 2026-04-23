#!/bin/bash
# download-fixtures.sh — fetch fixture disk images from hosting
#
# Fetches images from $FIXTURES_BASE_URL (default: https://fixtures.lamboot.dev/)
# and verifies against tests/fixtures/fixtures.sha256. Re-run is idempotent:
# already-present fixtures with matching SHA are skipped.
#
# Alternative sources (any one of these works):
#   - FIXTURES_BASE_URL=https://fixtures.lamboot.dev   (public hosting, TBD)
#   - FIXTURES_BASE_URL=rsync://pve.a.lamco.io/var/lib/lamboot-fixtures/  (internal)
#   - FIXTURES_LOCAL_DIR=/var/lib/lamboot-fixtures     (copy from local path)
#   - FIXTURES_SSH_HOST=pve.a.lamco.io + FIXTURES_SSH_PATH=/var/lib/lamboot-fixtures
#     (scp from an SSH-reachable host — the default within lamco infra)

set -uo pipefail

FIXTURES_BASE_URL="${FIXTURES_BASE_URL:-https://fixtures.lamboot.dev}"
FIXTURES_LOCAL_DIR="${FIXTURES_LOCAL_DIR:-}"
FIXTURES_SSH_HOST="${FIXTURES_SSH_HOST:-}"
FIXTURES_SSH_PATH="${FIXTURES_SSH_PATH:-/var/lib/lamboot-fixtures}"
FIXTURES_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKSUMS="$FIXTURES_DIR/fixtures.sha256"

readonly RED=$'\033[0;31m'
readonly YELLOW=$'\033[0;33m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'

fail() { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$1" >&2; }
ok()   { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }

[[ -f "$CHECKSUMS" ]] || fail "checksums file not found: $CHECKSUMS"

# Parse checksums: skip comments and empty lines
real_entries=$(grep -vE '^(#|$)' "$CHECKSUMS" | grep -cE '^[a-f0-9]{64}  ' || true)
real_entries="${real_entries:-0}"

if [[ "$real_entries" -eq 0 ]]; then
    warn "fixtures.sha256 has no real entries (all commented placeholders)"
    warn "fixtures have not been built and uploaded yet"
    warn "see tests/fixtures/README.md for regen + upload procedure"
    exit 0
fi

total=0
skipped=0
downloaded=0
failed=0

while read -r expected_sha filename; do
    [[ -z "$expected_sha" ]] && continue
    [[ "$expected_sha" == "#"* ]] && continue
    total=$((total + 1))

    local_path="$FIXTURES_DIR/$filename"

    if [[ -f "$local_path" ]]; then
        actual_sha=$(sha256sum "$local_path" | cut -d' ' -f1)
        if [[ "$actual_sha" == "$expected_sha" ]]; then
            ok "already present + valid: $filename"
            skipped=$((skipped + 1))
            continue
        else
            warn "sha mismatch on $filename — re-downloading"
        fi
    fi

    # Fetch priority: local dir > SSH > HTTP(S).
    fetched=0
    if [[ -n "$FIXTURES_LOCAL_DIR" ]] && [[ -f "$FIXTURES_LOCAL_DIR/$filename" ]]; then
        printf 'copying from local %s ... ' "$filename"
        cp "$FIXTURES_LOCAL_DIR/$filename" "$local_path" && fetched=1
    elif [[ -n "$FIXTURES_SSH_HOST" ]]; then
        printf 'fetching %s via SSH from %s ... ' "$filename" "$FIXTURES_SSH_HOST"
        scp -q "$FIXTURES_SSH_HOST:$FIXTURES_SSH_PATH/$filename" "$local_path" && fetched=1
    else
        info_url="${FIXTURES_BASE_URL}/$filename"
        printf 'downloading %s ... ' "$filename"
        curl -sfL "$info_url" -o "$local_path" && fetched=1
    fi

    if [[ $fetched -eq 1 ]]; then
        actual_sha=$(sha256sum "$local_path" | cut -d' ' -f1)
        if [[ "$actual_sha" == "$expected_sha" ]]; then
            printf '%sok%s\n' "$GREEN" "$RESET"
            downloaded=$((downloaded + 1))
        else
            printf '%sSHA mismatch%s\n' "$RED" "$RESET"
            warn "expected: $expected_sha"
            warn "got:      $actual_sha"
            rm -f "$local_path"
            failed=$((failed + 1))
        fi
    else
        printf '%sfetch failed%s\n' "$RED" "$RESET"
        failed=$((failed + 1))
    fi
done < <(grep -vE '^(#|$)' "$CHECKSUMS" | grep -E '^[a-f0-9]{64}  ')

printf '\n%sSummary:%s %d total, %d already valid, %d downloaded, %d failed\n' \
    "$GREEN" "$RESET" "$total" "$skipped" "$downloaded" "$failed"

[[ $failed -eq 0 ]] || exit 1
exit 0

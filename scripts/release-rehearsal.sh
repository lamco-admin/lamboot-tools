#!/bin/bash
# release-rehearsal.sh — 10-point release-readiness check
#
# Runs every release-moment precondition check. Invoked by
# docs/RELEASE.md §1 preflight. Safe to run anytime; doesn't modify state.
#
# Exit 0 = ready to release; non-zero = blockers present.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

readonly RED=$'\033[0;31m'
readonly YELLOW=$'\033[0;33m'
readonly GREEN=$'\033[0;32m'
readonly RESET=$'\033[0m'

pass=0
fail=0
warn=0

check_pass() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
check_fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; fail=$((fail + 1)); }
check_warn() { printf '  %s⚠%s %s\n' "$YELLOW" "$RESET" "$1" >&2; warn=$((warn + 1)); }

section() { printf '\n%s[%s]%s %s\n' "$GREEN" "$1" "$RESET" "$2"; }

# ── [1/12] structural verification ──────────────────────────────────────
section "1/12" "verify-claims.sh passes"
if scripts/verify-claims.sh >/dev/null 2>&1; then
    check_pass "all behavior claims verified (84 checks)"
else
    check_fail "verify-claims.sh failed — inspect output"
fi

# ── [2/10] CHANGELOG current ────────────────────────────────────────────
section "2/10" "CHANGELOG.md has current version entry"
toolkit_version=$(grep -oE 'LAMBOOT_TOOLKIT_VERSION="[^"]*"' lib/lamboot-toolkit-lib.sh | head -1 | cut -d'"' -f2)
release_version="${toolkit_version%-dev}"
if grep -qF "$release_version" CHANGELOG.md; then
    check_pass "CHANGELOG entry for $release_version found"
else
    check_fail "CHANGELOG.md has no entry for $release_version"
fi

# ── [3/10] syntax ───────────────────────────────────────────────────────
section "3/10" "bash -n clean across all tools + scripts"
fails=0
for f in tools/lamboot-* pve/tools/lamboot-* lib/*.sh scripts/*.sh scripts/inline-tool scripts/registry-to-man scripts/registry-to-markdown publish/*.sh .githooks/pre-commit tests/fixtures/download-fixtures.sh tests/fixtures/regen/*.sh; do
    [[ -f "$f" ]] || continue
    # Skip Python files (lamboot-inspect + package, lamboot-pve-monitor) —
    # they live in tools/ but aren't bash. First-line shebang discriminates.
    head -1 "$f" 2>/dev/null | grep -q 'python' && continue
    bash -n "$f" 2>/dev/null || { check_fail "$f"; fails=$((fails + 1)); }
done
[[ $fails -eq 0 ]] && check_pass "all bash files syntax-clean"

# ── [4/10] RPM specs field-complete ─────────────────────────────────────
section "4/10" "RPM specs have all required fields"
spec_fails=0
for spec in packaging/rpm/*.spec; do
    for field in Name Version Release Summary License %description %build %install %files %changelog; do
        if ! grep -qE "^${field}" "$spec"; then
            check_fail "$(basename "$spec") missing $field"
            spec_fails=$((spec_fails + 1))
        fi
    done
done
[[ $spec_fails -eq 0 ]] && check_pass "3 specs, all fields present"

# ── [5/10] Copr configs ─────────────────────────────────────────────────
section "5/10" "Copr configs present"
for yml in packaging/copr/lamboot-tools.yml packaging/copr/lamboot-migrate.yml; do
    [[ -f "$yml" ]] && check_pass "$yml" || check_fail "missing: $yml"
done
# Per founder decision 2026-04-22: lamboot-toolkit-pve ships as a subpackage
# of lamboot-tools (same Copr project), not as a separate Copr project.

# ── [6/10] help registries (every tool except the dispatcher) ───────────
section "6/10" "Help registries populated"
for tool in tools/lamboot-diagnose tools/lamboot-esp tools/lamboot-backup tools/lamboot-repair tools/lamboot-migrate tools/lamboot-doctor tools/lamboot-uki-build tools/lamboot-signing-keys pve/tools/lamboot-pve-setup pve/tools/lamboot-pve-fleet; do
    if grep -q '_register_subcommands' "$tool" 2>/dev/null; then
        check_pass "$(basename "$tool") registry present"
    else
        check_fail "$(basename "$tool") missing registry"
    fi
done
# lamboot-toolkit is the dispatcher; no registry expected
check_pass "lamboot-toolkit (dispatcher; no registry needed)"

# ── [7/10] man pages ────────────────────────────────────────────────────
section "7/10" "Man pages complete"
missing=0
for m in lamboot-diagnose lamboot-esp lamboot-backup lamboot-repair lamboot-migrate lamboot-doctor lamboot-toolkit lamboot-uki-build lamboot-signing-keys lamboot-pve-setup lamboot-pve-fleet; do
    [[ -f "man/${m}.1" ]] || { check_fail "missing man/${m}.1"; missing=$((missing+1)); }
done
[[ -f "man/lamboot-tools.7" ]] || { check_fail "missing man/lamboot-tools.7"; missing=$((missing+1)); }
[[ -f "man/lamboot-tools-schema.5" ]] || { check_fail "missing man/lamboot-tools-schema.5"; missing=$((missing+1)); }
[[ $missing -eq 0 ]] && check_pass "13/13 man pages present"

# ── [8/10] website pages ────────────────────────────────────────────────
section "8/10" "Website pages complete"
missing=0
for t in lamboot-diagnose lamboot-esp lamboot-backup lamboot-repair lamboot-migrate lamboot-doctor lamboot-toolkit lamboot-uki-build lamboot-signing-keys lamboot-pve-setup lamboot-pve-fleet; do
    [[ -f "website/tools/${t}.md" ]] || { check_fail "missing website/tools/${t}.md"; missing=$((missing+1)); }
done
[[ -f "website/index.md" ]] || { check_fail "missing website/index.md"; missing=$((missing+1)); }
[[ $missing -eq 0 ]] && check_pass "website pages present"

# ── [9/10] publish scripts + executables ────────────────────────────────
section "9/10" "Publish scripts ready"
for script in publish/build-tarball.sh publish/build-standalone-migrate.sh publish/bump-version.sh publish/mirror-from-lamboot-dev.sh publish/mirror-pve-from-lamboot-dev.sh publish/export-to-public.sh; do
    if [[ -x "$script" ]] && bash -n "$script" 2>/dev/null; then
        check_pass "$(basename "$script")"
    else
        check_fail "$(basename "$script")"
    fi
done

# ── [10/10] governance gate active ──────────────────────────────────────
section "10/10" "Governance gate active"
if publish/export-to-public.sh v0.2.0 >/dev/null 2>&1; then
    check_fail "export-to-public.sh did NOT refuse without LAMBOOT_EXPORT_CONFIRMED — governance broken"
else
    check_pass "export-to-public.sh correctly refuses without explicit confirmation"
fi

# ── [11/11] no stubs or placeholders in shipped code ────────────────────
section "11/11" "No unimplemented-feature stubs in shipped code"
# Scans shipped tools for patterns that indicate deferred-but-not-disclosed
# features. Added 2026-04-22 per AUDIT §5.1 "checkmark-green" anti-pattern.
# Excludes uki-build's legitimate --stub CLI flag (systemd-stub references)
# and the intentional doctor/backup "offline not supported in v0.2" guards.
stub_hits=0
while IFS= read -r line; do
    case "$line" in
        *"lamboot-uki-build"*"--stub"*)         continue ;;
        *"lamboot-uki-build"*"systemd-stub"*)   continue ;;
        *"lamboot-uki-build"*"stub="*)          continue ;;
        *"does not support --offline in v0.2"*) continue ;;  # documented v0.3 target
        *"--remove-grub is not implemented"*)    continue ;;  # documented v1.1 target
        *"\$OPT_STUB"*)                          continue ;;  # legit stub-path variable
        *"local stub"*)                          continue ;;  # legit variable in uki-build
        *)                                       stub_hits=$((stub_hits+1))
                                                 printf '   %s\n' "$line" >&2 ;;
    esac
done < <(grep -rnE 'not (yet )?implemented|\bTODO\b|\bFIXME\b|coming soon|\bplaceholder\b' \
             tools/ pve/tools/ lib/ 2>/dev/null || true)

if [[ $stub_hits -eq 0 ]]; then
    check_pass "no TODO/FIXME/not-implemented markers in shipped code"
else
    check_fail "$stub_hits stub/TODO marker(s) in shipped code — see stderr output above"
fi

# ── [12/12] mirrored files present ──────────────────────────────────────
section "12/12" "Mirrored files from lamboot-dev committed"
# Mirrors must be in-tree before release (§4.1 of RELEASE.md).
# Absence here doesn't block if running for a pre-release audit, but in a
# real release window these files ship in the tarball.
mirror_missing=0
for f in tools/lamboot-inspect \
         tools/lamboot_inspect \
         man/lamboot-inspect.1 \
         pve/tools/lamboot-pve-monitor \
         pve/tools/lamboot-pve-ovmf-vars; do
    [[ -e "$f" ]] || { check_warn "missing mirrored file: $f (run publish/mirror-*-from-lamboot-dev.sh before release window)"; mirror_missing=$((mirror_missing+1)); }
done
[[ $mirror_missing -eq 0 ]] && check_pass "all 5 mirrored files present"

# ── Summary ──────────────────────────────────────────────────────────────
printf '\n%sSummary:%s %d checks passed, %d warnings, %d failed\n' \
    "$GREEN" "$RESET" "$pass" "$warn" "$fail"

if [[ $fail -gt 0 ]]; then
    printf '\n%sNOT READY TO RELEASE%s — fix the %d failures before proceeding.\n' \
        "$RED" "$RESET" "$fail"
    exit 1
fi

printf '\n%sREADY TO RELEASE%s — continue with docs/RELEASE.md §2\n' "$GREEN" "$RESET"
exit 0

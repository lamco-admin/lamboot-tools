#!/bin/bash
# lamboot-toolkit-lib.sh — shared library for lamboot-tools
#
# Canonical source of truth for common operations across every tool.
# Sourced at startup by every tool:
#
#     source /usr/lib/lamboot-tools/lamboot-toolkit-lib.sh
#
# Or, in inlined-build form, concatenated at top of each tool.
#
# Governed by SPEC-LAMBOOT-TOOLKIT-V1.md §6.1. Changes to function signatures
# or semantics require spec amendment.

# ────────────────────────────────────────────────────────────────────────────
# Versioning — single source of truth for the toolkit version
# ────────────────────────────────────────────────────────────────────────────

readonly LAMBOOT_TOOLKIT_VERSION="0.2.0"
readonly LAMBOOT_TOOLKIT_SCHEMA_VERSION="v1"

# ────────────────────────────────────────────────────────────────────────────
# Exit codes — identical across every tool (spec §4.4)
# ────────────────────────────────────────────────────────────────────────────

readonly EXIT_OK=0
readonly EXIT_ERROR=1
readonly EXIT_PARTIAL=2
readonly EXIT_NOOP=3
readonly EXIT_UNSAFE=4
readonly EXIT_ABORT=5
readonly EXIT_NOT_APPLICABLE=6
readonly EXIT_PREREQUISITE=7

# ────────────────────────────────────────────────────────────────────────────
# State populated by parse_common_flags() — tools read these
# ────────────────────────────────────────────────────────────────────────────

LAMBOOT_DRY_RUN=0
LAMBOOT_VERBOSE=0
LAMBOOT_QUIET=0
LAMBOOT_JSON=0
LAMBOOT_NO_COLOR=0
LAMBOOT_YES=0
LAMBOOT_FORCE=0
LAMBOOT_AUTO=0
LAMBOOT_OFFLINE_DISK=""
LAMBOOT_SUGGEST_NEXT=0

LAMBOOT_TOOL_NAME="${LAMBOOT_TOOL_NAME:-unknown-tool}"
LAMBOOT_TOOL_VERSION="${LAMBOOT_TOOL_VERSION:-0.0.0}"

# Run ID correlates log lines, backup dirs, and JSON output from one invocation
LAMBOOT_RUN_ID=""

# JSON accumulator state
LAMBOOT_JSON_FINDINGS=""
LAMBOOT_JSON_ACTIONS=""
LAMBOOT_JSON_BACKUP_DIR=""

# Offline mode state — set by offline_setup(), torn down by offline_teardown()
LAMBOOT_OFFLINE_LOOP_DEV=""
LAMBOOT_OFFLINE_NBD_DEV=""
LAMBOOT_OFFLINE_ROOT=""
LAMBOOT_OFFLINE_ESP=""
LAMBOOT_OFFLINE_ACTIVE=0

# ────────────────────────────────────────────────────────────────────────────
# ANSI color — disabled on non-TTY stdout or when NO_COLOR is set
# ────────────────────────────────────────────────────────────────────────────

if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
    LAMBOOT_COLOR_ERROR=$'\033[0;31m'
    LAMBOOT_COLOR_WARN=$'\033[0;33m'
    LAMBOOT_COLOR_OK=$'\033[0;32m'
    LAMBOOT_COLOR_INFO=$'\033[0;36m'
    LAMBOOT_COLOR_RESET=$'\033[0m'
else
    LAMBOOT_COLOR_ERROR=""
    LAMBOOT_COLOR_WARN=""
    LAMBOOT_COLOR_OK=""
    LAMBOOT_COLOR_INFO=""
    LAMBOOT_COLOR_RESET=""
fi

# ────────────────────────────────────────────────────────────────────────────
# Run ID generation — deterministic format, random suffix
# ────────────────────────────────────────────────────────────────────────────

generate_run_id() {
    local ts
    ts=$(date -u +%Y-%m-%dT%H-%M-%S)
    local rand
    rand=$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || printf '%06x' $RANDOM$RANDOM)
    LAMBOOT_RUN_ID="${ts}-${rand}"
}

# ────────────────────────────────────────────────────────────────────────────
# Logging — stderr always; JSON mode suppresses human output from stdout
# ────────────────────────────────────────────────────────────────────────────

die() {
    printf '%serror:%s %s\n' "$LAMBOOT_COLOR_ERROR" "$LAMBOOT_COLOR_RESET" "$1" >&2
    if [[ $LAMBOOT_JSON -eq 1 ]] && [[ -n "$LAMBOOT_RUN_ID" ]]; then
        emit_finding "toolkit.fatal_error" "toolkit" "critical" "fail" \
            "Fatal error" "$1" "{}" "{}"
        emit_json "$EXIT_ERROR"
    fi
    exit "$EXIT_ERROR"
}

die_unsafe() {
    printf '%serror:%s %s\n' "$LAMBOOT_COLOR_ERROR" "$LAMBOOT_COLOR_RESET" "$1" >&2
    if [[ $LAMBOOT_JSON -eq 1 ]] && [[ -n "$LAMBOOT_RUN_ID" ]]; then
        emit_finding "toolkit.refused_unsafe" "toolkit" "critical" "fail" \
            "Operation refused by safety check" "$1" "{}" "{}"
        emit_json "$EXIT_UNSAFE"
    fi
    exit "$EXIT_UNSAFE"
}

die_noop() {
    printf '%sinfo:%s %s\n' "$LAMBOOT_COLOR_INFO" "$LAMBOOT_COLOR_RESET" "$1" >&2
    if [[ $LAMBOOT_JSON -eq 1 ]] && [[ -n "$LAMBOOT_RUN_ID" ]]; then
        emit_finding "toolkit.nothing_to_do" "toolkit" "info" "pass" \
            "Nothing to do" "$1" "{}" "{}"
        emit_json "$EXIT_NOOP"
    fi
    exit "$EXIT_NOOP"
}

die_prerequisite() {
    printf '%serror:%s %s\n' "$LAMBOOT_COLOR_ERROR" "$LAMBOOT_COLOR_RESET" "$1" >&2
    if [[ $LAMBOOT_JSON -eq 1 ]] && [[ -n "$LAMBOOT_RUN_ID" ]]; then
        emit_finding "toolkit.prerequisite_missing" "toolkit" "error" "fail" \
            "Prerequisite missing" "$1" "{}" "{}"
        emit_json "$EXIT_PREREQUISITE"
    fi
    exit "$EXIT_PREREQUISITE"
}

warn() {
    [[ $LAMBOOT_QUIET -eq 1 ]] && return 0
    printf '%swarning:%s %s\n' "$LAMBOOT_COLOR_WARN" "$LAMBOOT_COLOR_RESET" "$1" >&2
}

info() {
    [[ $LAMBOOT_QUIET -eq 1 ]] && return 0
    printf '%sinfo:%s %s\n' "$LAMBOOT_COLOR_INFO" "$LAMBOOT_COLOR_RESET" "$1" >&2
}

verbose() {
    [[ $LAMBOOT_VERBOSE -eq 1 ]] || return 0
    printf 'verbose: %s\n' "$1" >&2
}

success() {
    [[ $LAMBOOT_QUIET -eq 1 ]] && return 0
    printf '%sok:%s %s\n' "$LAMBOOT_COLOR_OK" "$LAMBOOT_COLOR_RESET" "$1" >&2
}

# ────────────────────────────────────────────────────────────────────────────
# Privilege + prerequisite checks
# ────────────────────────────────────────────────────────────────────────────

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die_prerequisite "this operation requires root; rerun with sudo"
    fi
}

require_tool() {
    local tool="$1"
    local hint="${2:-install $1 via your package manager}"
    if ! command -v "$tool" >/dev/null 2>&1; then
        die_prerequisite "required tool not found: $tool (hint: $hint)"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# User interaction — respects --yes / --auto / --force
# ────────────────────────────────────────────────────────────────────────────

confirm() {
    local question="$1"
    local expected_token="${2:-yes}"

    if [[ $LAMBOOT_YES -eq 1 ]] || [[ $LAMBOOT_AUTO -eq 1 ]] || [[ $LAMBOOT_FORCE -eq 1 ]]; then
        verbose "auto-confirmed: $question"
        return 0
    fi

    local reply
    printf '%s: type %q to proceed > ' "$question" "$expected_token"
    read -r reply
    if [[ "$reply" == "$expected_token" ]]; then
        return 0
    fi
    return 1
}

# ────────────────────────────────────────────────────────────────────────────
# Dry-run wrapper — print or execute based on LAMBOOT_DRY_RUN
# ────────────────────────────────────────────────────────────────────────────

lamboot_run() {
    if [[ $LAMBOOT_DRY_RUN -eq 1 ]]; then
        printf 'DRY-RUN: would exec: %s\n' "$*" >&2
        return 0
    fi
    verbose "exec: $*"
    "$@"
}

# ────────────────────────────────────────────────────────────────────────────
# ESP + disk detection
# ────────────────────────────────────────────────────────────────────────────

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        printf 'uefi'
    else
        printf 'bios'
    fi
}

detect_esp() {
    if [[ $LAMBOOT_OFFLINE_ACTIVE -eq 1 ]] && [[ -n "$LAMBOOT_OFFLINE_ESP" ]]; then
        printf '%s' "$LAMBOOT_OFFLINE_ESP"
        return 0
    fi

    local esp=""
    if mountpoint -q /boot/efi 2>/dev/null; then
        esp="/boot/efi"
    elif mountpoint -q /efi 2>/dev/null; then
        esp="/efi"
    elif mountpoint -q /boot 2>/dev/null; then
        local fstype
        fstype=$(findmnt -n -o FSTYPE /boot 2>/dev/null || true)
        if [[ "$fstype" == "vfat" ]]; then
            esp="/boot"
        fi
    fi

    if [[ -z "$esp" ]]; then
        return 1
    fi
    printf '%s' "$esp"
}

esp_mountpoint() {
    detect_esp
}

find_disk_for_mount() {
    local mount_point="$1"
    local source
    source=$(findmnt -n -o SOURCE --target "$mount_point" 2>/dev/null || true)
    if [[ -z "$source" ]]; then
        return 1
    fi
    lsblk -n -o PKNAME "$source" 2>/dev/null | head -1 | awk '{print "/dev/"$1}'
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        local id
        # shellcheck disable=SC1091  # dynamic source of well-known file
        id=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
        printf '%s' "$id"
    else
        printf 'unknown'
    fi
}

detect_distro_version() {
    if [[ -f /etc/os-release ]]; then
        local ver
        # shellcheck disable=SC1091
        ver=$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")
        printf '%s' "$ver"
    else
        printf 'unknown'
    fi
}

list_bootloaders() {
    local esp
    esp=$(detect_esp) || return 1

    local found=()

    [[ -f "$esp/EFI/LamBoot/lambootx64.efi" ]] && found+=("lamboot")
    [[ -d "$esp/EFI/systemd" ]] && found+=("systemd-boot")
    [[ -d "$esp/EFI/refind" ]] && found+=("refind")

    for grub_variant in "$esp"/EFI/{grub,GRUB,ubuntu,debian,fedora,redhat,centos,rocky,opensuse,arch,endeavouros,manjaro}; do
        if [[ -d "$grub_variant" ]]; then
            found+=("grub")
            break
        fi
    done

    [[ -f "$esp/EFI/Microsoft/Boot/bootmgfw.efi" ]] && found+=("windows-boot-manager")
    [[ -f "$esp/EFI/limine/limine.cfg" ]] && found+=("limine")

    if [[ ${#found[@]} -eq 0 ]]; then
        printf 'none\n'
    else
        printf '%s\n' "${found[@]}"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Backup discipline
# ────────────────────────────────────────────────────────────────────────────

backup_dir_new() {
    local tool="$1"
    [[ -n "$LAMBOOT_RUN_ID" ]] || generate_run_id
    local dir="/var/backups/lamboot-${tool}-${LAMBOOT_RUN_ID}"

    if [[ $LAMBOOT_DRY_RUN -eq 1 ]]; then
        printf 'DRY-RUN: would create backup dir: %s\n' "$dir" >&2
        LAMBOOT_JSON_BACKUP_DIR="$dir"
        printf '%s' "$dir"
        return 0
    fi

    mkdir -p "$dir" || die "failed to create backup dir: $dir"
    chmod 0700 "$dir"

    cat > "$dir/MANIFEST.json" <<EOF
{
  "schema_version": "${LAMBOOT_TOOLKIT_SCHEMA_VERSION}",
  "tool": "${tool}",
  "tool_version": "${LAMBOOT_TOOL_VERSION}",
  "toolkit_version": "${LAMBOOT_TOOLKIT_VERSION}",
  "run_id": "${LAMBOOT_RUN_ID}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "host": "$(hostname)",
  "command": "${0##*/} $*"
}
EOF

    LAMBOOT_JSON_BACKUP_DIR="$dir"
    printf '%s' "$dir"
}

backup_file_to() {
    local backup_dir="$1"
    local source_file="$2"
    local dest_name="${3:-$(basename "$source_file")}"

    if [[ ! -e "$source_file" ]]; then
        verbose "backup skipped (source not present): $source_file"
        return 0
    fi

    if [[ $LAMBOOT_DRY_RUN -eq 1 ]]; then
        printf 'DRY-RUN: would backup %s → %s/%s\n' "$source_file" "$backup_dir" "$dest_name" >&2
        return 0
    fi

    cp -a "$source_file" "$backup_dir/$dest_name" || die "backup failed: $source_file"
    verbose "backed up: $source_file → $backup_dir/$dest_name"
}

backup_success() {
    local backup_dir="$1"
    if [[ $LAMBOOT_DRY_RUN -eq 1 ]]; then
        printf 'DRY-RUN: would write success flag: %s/SUCCESS.flag\n' "$backup_dir" >&2
        return 0
    fi
    : > "$backup_dir/SUCCESS.flag"
}

backup_latest() {
    local tool="$1"
    local latest
    # shellcheck disable=SC2012  # ls + sort is intentional here; stat ordering differs across systems
    latest=$(ls -dt /var/backups/lamboot-"$tool"-* 2>/dev/null | head -1)
    [[ -n "$latest" ]] && printf '%s' "$latest"
}

# ────────────────────────────────────────────────────────────────────────────
# JSON emission — builds the unified envelope per spec §5
# ────────────────────────────────────────────────────────────────────────────

json_escape() {
    # Escape a string for safe inclusion as a JSON value
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

emit_finding() {
    local id="$1"
    local category="$2"
    local severity="$3"
    local status="$4"
    local title="$5"
    local message="$6"
    local context_json="${7:-\{\}}"
    local remediation_json="${8:-\{\}}"

    local esc_id esc_title esc_msg
    esc_id=$(json_escape "$id")
    esc_title=$(json_escape "$title")
    esc_msg=$(json_escape "$message")

    local finding
    finding=$(cat <<EOF
{"id":"${esc_id}","category":"${category}","severity":"${severity}","status":"${status}","title":"${esc_title}","message":"${esc_msg}","context":${context_json},"remediation":${remediation_json}}
EOF
)

    if [[ -z "$LAMBOOT_JSON_FINDINGS" ]]; then
        LAMBOOT_JSON_FINDINGS="$finding"
    else
        LAMBOOT_JSON_FINDINGS="${LAMBOOT_JSON_FINDINGS},${finding}"
    fi
}

record_action() {
    local action="$1"
    local target="$2"
    local result="$3"
    local reversible="${4:-false}"
    local details_json="${5:-\{\}}"
    local backup_ref="${6:-null}"

    [[ "$backup_ref" != "null" ]] && backup_ref="\"$(json_escape "$backup_ref")\""

    local entry
    entry=$(cat <<EOF
{"action":"$(json_escape "$action")","target":"$(json_escape "$target")","result":"${result}","reversible":${reversible},"backup_ref":${backup_ref},"dry_run":$([[ $LAMBOOT_DRY_RUN -eq 1 ]] && printf 'true' || printf 'false'),"details":${details_json}}
EOF
)

    if [[ -z "$LAMBOOT_JSON_ACTIONS" ]]; then
        LAMBOOT_JSON_ACTIONS="$entry"
    else
        LAMBOOT_JSON_ACTIONS="${LAMBOOT_JSON_ACTIONS},${entry}"
    fi
}

emit_json() {
    local exit_code="${1:-0}"
    [[ $LAMBOOT_JSON -eq 1 ]] || return 0
    [[ -n "$LAMBOOT_RUN_ID" ]] || generate_run_id

    local findings="[${LAMBOOT_JSON_FINDINGS}]"
    local actions="[${LAMBOOT_JSON_ACTIONS}]"
    local backup_dir="null"
    [[ -n "$LAMBOOT_JSON_BACKUP_DIR" ]] && backup_dir="\"$(json_escape "$LAMBOOT_JSON_BACKUP_DIR")\""

    local total=0
    local critical=0 error=0 warning=0 info_count=0
    if [[ -n "$LAMBOOT_JSON_FINDINGS" ]]; then
        # Findings are comma-joined; count by severity tokens (each finding
        # has exactly one "severity":"X" substring).
        critical=$(printf '%s' "$LAMBOOT_JSON_FINDINGS" | grep -oE '"severity":"critical"' | wc -l | tr -d ' ')
        error=$(printf '%s' "$LAMBOOT_JSON_FINDINGS" | grep -oE '"severity":"error"' | wc -l | tr -d ' ')
        warning=$(printf '%s' "$LAMBOOT_JSON_FINDINGS" | grep -oE '"severity":"warning"' | wc -l | tr -d ' ')
        info_count=$(printf '%s' "$LAMBOOT_JSON_FINDINGS" | grep -oE '"severity":"info"' | wc -l | tr -d ' ')
        total=$((critical + error + warning + info_count))
    fi

    local aggregate_status="pass"
    case "$exit_code" in
        0) [[ $warning -gt 0 ]] && aggregate_status="warn" || aggregate_status="pass" ;;
        2) aggregate_status="fail" ;;
        3) aggregate_status="noop" ;;
        4) aggregate_status="unsafe" ;;
        5) aggregate_status="abort" ;;
        *) aggregate_status="error" ;;
    esac

    cat <<EOF
{"schema_version":"${LAMBOOT_TOOLKIT_SCHEMA_VERSION}","tool":"$(json_escape "$LAMBOOT_TOOL_NAME")","version":"$(json_escape "$LAMBOOT_TOOL_VERSION")","toolkit_version":"$(json_escape "$LAMBOOT_TOOLKIT_VERSION")","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","host":"$(hostname)","run_id":"$(json_escape "$LAMBOOT_RUN_ID")","command":"$(json_escape "${0##*/}")","dry_run":$([[ $LAMBOOT_DRY_RUN -eq 1 ]] && printf 'true' || printf 'false'),"exit_code":${exit_code},"summary":{"status":"${aggregate_status}","findings_total":${total},"findings_by_severity":{"critical":${critical},"error":${error},"warning":${warning},"info":${info_count}}},"findings":${findings},"actions_taken":${actions},"backup_dir":${backup_dir}}
EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Offline mode — loopback / NBD setup for operating on disk images
# ────────────────────────────────────────────────────────────────────────────

offline_setup() {
    local disk="$1"
    [[ -n "$disk" ]] || die "offline_setup: disk argument required"
    require_root

    if [[ -b "$disk" ]]; then
        LAMBOOT_OFFLINE_LOOP_DEV="$disk"
        verbose "offline: using block device $disk directly"
    elif [[ -f "$disk" ]]; then
        local fmt
        fmt=$(file -b "$disk" 2>/dev/null || printf 'unknown')
        case "$fmt" in
            *QCOW*|*qcow*)
                require_tool qemu-nbd "install qemu-utils (Debian/Ubuntu) or qemu-img (Fedora)"
                modprobe nbd max_part=16 2>/dev/null || true
                local nbd
                for i in 0 1 2 3 4 5 6 7; do
                    if [[ ! -e "/sys/block/nbd${i}/pid" ]] || [[ -z "$(cat "/sys/block/nbd${i}/pid" 2>/dev/null || true)" ]]; then
                        nbd="/dev/nbd${i}"
                        break
                    fi
                done
                [[ -n "${nbd:-}" ]] || die "no free NBD device available"
                lamboot_run qemu-nbd --connect="$nbd" --read-only "$disk"
                sleep 1
                lamboot_run partprobe "$nbd" 2>/dev/null || true
                LAMBOOT_OFFLINE_NBD_DEV="$nbd"
                LAMBOOT_OFFLINE_LOOP_DEV="$nbd"
                ;;
            *)
                require_tool losetup "install util-linux"
                local loop
                loop=$(losetup --find --show --read-only --partscan "$disk") \
                    || die "losetup failed for $disk"
                LAMBOOT_OFFLINE_LOOP_DEV="$loop"
                sleep 1
                lamboot_run partprobe "$loop" 2>/dev/null || true
                ;;
        esac
    else
        die "offline_setup: $disk is neither a block device nor a file"
    fi

    LAMBOOT_OFFLINE_ACTIVE=1
    trap offline_teardown EXIT

    local mount_base
    mount_base=$(mktemp -d -t lamboot-offline.XXXXXX) || die "mktemp failed"

    local esp_found=""
    local root_found=""
    for part in "${LAMBOOT_OFFLINE_LOOP_DEV}"p* "${LAMBOOT_OFFLINE_LOOP_DEV}"[0-9]*; do
        [[ -b "$part" ]] || continue
        local fstype
        fstype=$(blkid -o value -s TYPE "$part" 2>/dev/null || true)
        case "$fstype" in
            vfat)
                if [[ -z "$esp_found" ]]; then
                    local mp="$mount_base/esp"
                    mkdir -p "$mp"
                    if mount -o ro "$part" "$mp" 2>/dev/null; then
                        if [[ -d "$mp/EFI" ]]; then
                            esp_found="$mp"
                        else
                            umount "$mp"
                        fi
                    fi
                fi
                ;;
            ext2|ext3|ext4|btrfs|xfs)
                if [[ -z "$root_found" ]]; then
                    local mp="$mount_base/root"
                    mkdir -p "$mp"
                    if mount -o ro "$part" "$mp" 2>/dev/null; then
                        if [[ -f "$mp/etc/os-release" ]] || [[ -f "$mp/etc/fstab" ]]; then
                            root_found="$mp"
                        else
                            umount "$mp"
                        fi
                    fi
                fi
                ;;
        esac
    done

    LAMBOOT_OFFLINE_ESP="$esp_found"
    LAMBOOT_OFFLINE_ROOT="$root_found"

    [[ -n "$esp_found" ]] && verbose "offline ESP detected at $esp_found"
    [[ -n "$root_found" ]] && verbose "offline rootfs detected at $root_found"
}

offline_teardown() {
    [[ $LAMBOOT_OFFLINE_ACTIVE -eq 1 ]] || return 0

    [[ -n "$LAMBOOT_OFFLINE_ESP" ]] && umount "$LAMBOOT_OFFLINE_ESP" 2>/dev/null || true
    [[ -n "$LAMBOOT_OFFLINE_ROOT" ]] && umount "$LAMBOOT_OFFLINE_ROOT" 2>/dev/null || true

    if [[ -n "$LAMBOOT_OFFLINE_NBD_DEV" ]]; then
        qemu-nbd --disconnect "$LAMBOOT_OFFLINE_NBD_DEV" 2>/dev/null || true
    elif [[ -n "$LAMBOOT_OFFLINE_LOOP_DEV" ]] && [[ "$LAMBOOT_OFFLINE_LOOP_DEV" == /dev/loop* ]]; then
        losetup --detach "$LAMBOOT_OFFLINE_LOOP_DEV" 2>/dev/null || true
    fi

    LAMBOOT_OFFLINE_ACTIVE=0
}

# ────────────────────────────────────────────────────────────────────────────
# Common flag parsing — tools opt in; returns consumed arg count to the caller
# ────────────────────────────────────────────────────────────────────────────

parse_common_flag() {
    case "$1" in
        --help|-h)    return 2 ;;
        --version)    return 3 ;;
        --json-schema) return 4 ;;
        --json)       LAMBOOT_JSON=1; return 1 ;;
        --verbose|-v) LAMBOOT_VERBOSE=1; return 1 ;;
        --quiet|-q)   LAMBOOT_QUIET=1; return 1 ;;
        --no-color)   LAMBOOT_NO_COLOR=1
                      LAMBOOT_COLOR_ERROR=""
                      LAMBOOT_COLOR_WARN=""
                      LAMBOOT_COLOR_OK=""
                      LAMBOOT_COLOR_INFO=""
                      LAMBOOT_COLOR_RESET=""
                      return 1 ;;
        --dry-run)    LAMBOOT_DRY_RUN=1; return 1 ;;
        --yes|-y)     LAMBOOT_YES=1; return 1 ;;
        --force)      LAMBOOT_FORCE=1; return 1 ;;
        --auto)       LAMBOOT_AUTO=1
                      LAMBOOT_YES=1
                      return 1 ;;
        --offline)    return 5 ;;
        --suggest-next-command) LAMBOOT_SUGGEST_NEXT=1; return 1 ;;
        *)            return 0 ;;
    esac
}

# ────────────────────────────────────────────────────────────────────────────
# Shell options — every tool inherits these by sourcing this library
# ────────────────────────────────────────────────────────────────────────────

set -u
set -o pipefail

# Generate a run ID on source — tools don't have to remember to
generate_run_id

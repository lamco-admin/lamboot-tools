#!/bin/bash
# lamboot-toolkit-help.sh — help registry driver for lamboot-tools
#
# Single source of truth for per-tool command metadata. Drives three surfaces:
#
#   1. --help (terse, clap-style + after-help summary)
#   2. <tool> help [<subcommand>] (structured deep help)
#   3. man pages (generated via bin/registry-to-man)
#
# Governed by SPEC-LAMBOOT-TOOLKIT-V1.md §10. Changes to the registry schema
# require spec amendment.
#
# Usage pattern in each tool:
#
#     source /usr/lib/lamboot-tools/lamboot-toolkit-help.sh
#
#     register_subcommand \
#         --name "check" \
#         --category "Diagnostics" \
#         --summary "Run ESP health check" \
#         --syntax "lamboot-esp check [--esp PATH]" \
#         --example "sudo lamboot-esp check" \
#         --example "sudo lamboot-esp check --esp /boot/efi --json" \
#         --offline-capable true \
#         --requires-root true \
#         --doc-url "https://lamboot.dev/tools/esp#check"
#
#     dispatch_help "$@"
#
# The registry lives in LAMBOOT_HELP_REGISTRY (newline-separated records,
# each record is tab-separated fields). Bash 3.2-compatible (no associative
# array requirement).

LAMBOOT_HELP_REGISTRY=""

# Record separator is ASCII 0x1F (US, Unit Separator). Tab cannot be used
# because bash `read` collapses consecutive whitespace IFS characters,
# which drops empty fields. 0x1F is non-whitespace, preserving empties.
readonly LAMBOOT_HELP_FS=$'\x1f'

# Field order in each registry record (0x1F-separated):
#   1. name
#   2. aliases (comma-separated; empty OK)
#   3. category
#   4. summary
#   5. syntax
#   6. args (pipe-separated "name:desc" pairs; empty OK)
#   7. examples (double-pipe-separated; empty OK)
#   8. notes
#   9. offline_capable (true/false)
#  10. requires_root (true/false)
#  11. see_also (comma-separated; empty OK)
#  12. doc_url
#  13. maturity (stable/beta/experimental)

register_subcommand() {
    local name="" aliases="" category="" summary="" syntax="" args=""
    local examples="" notes="" offline="false" root="false" see_also=""
    local doc_url="" maturity="stable"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)             name="$2"; shift 2 ;;
            --alias)            aliases="${aliases:+$aliases,}$2"; shift 2 ;;
            --category)         category="$2"; shift 2 ;;
            --summary)          summary="$2"; shift 2 ;;
            --syntax)           syntax="$2"; shift 2 ;;
            --arg)              args="${args:+$args|}$2"; shift 2 ;;
            --example)          examples="${examples:+$examples||}$2"; shift 2 ;;
            --notes)            notes="$2"; shift 2 ;;
            --offline-capable)  offline="$2"; shift 2 ;;
            --requires-root)    root="$2"; shift 2 ;;
            --see-also)         see_also="${see_also:+$see_also,}$2"; shift 2 ;;
            --doc-url)          doc_url="$2"; shift 2 ;;
            --maturity)         maturity="$2"; shift 2 ;;
            *)                  printf 'register_subcommand: unknown flag %s\n' "$1" >&2
                                return 1 ;;
        esac
    done

    [[ -z "$name" ]] && { printf 'register_subcommand: --name required\n' >&2; return 1; }
    [[ -z "$summary" ]] && { printf 'register_subcommand: --summary required\n' >&2; return 1; }
    [[ -z "$syntax" ]] && { printf 'register_subcommand: --syntax required\n' >&2; return 1; }

    local record
    record=$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' \
        "$name" "$aliases" "$category" "$summary" "$syntax" "$args" \
        "$examples" "$notes" "$offline" "$root" "$see_also" "$doc_url" "$maturity")

    if [[ -z "$LAMBOOT_HELP_REGISTRY" ]]; then
        LAMBOOT_HELP_REGISTRY="$record"
    else
        LAMBOOT_HELP_REGISTRY="${LAMBOOT_HELP_REGISTRY}"$'\n'"${record}"
    fi
}

_lookup_subcommand() {
    local target="$1"
    while IFS=$'\x1f' read -r name aliases _rest; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == "$target" ]]; then
            printf '%s' "$name"
            return 0
        fi
        IFS=',' read -ra alias_arr <<< "$aliases"
        for a in "${alias_arr[@]}"; do
            if [[ "$a" == "$target" ]]; then
                printf '%s' "$name"
                return 0
            fi
        done
    done <<< "$LAMBOOT_HELP_REGISTRY"
    return 1
}

_categories_in_order() {
    printf '%s\n' "$LAMBOOT_HELP_REGISTRY" \
        | awk -F$'\x1f' 'NF>0 {print $3}' \
        | awk '!seen[$0]++'
}

print_full_listing() {
    local tool_name="${LAMBOOT_TOOL_NAME:-lamboot-tool}"
    printf '%s — subcommand reference\n\n' "$tool_name"

    local cat
    while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        printf '%s:\n' "$cat"
        while IFS=$'\x1f' read -r name aliases category summary _syntax _args _examples _notes offline root _see_also _doc_url maturity; do
            [[ -z "$name" ]] && continue
            [[ "$category" != "$cat" ]] && continue

            local display="$name"
            [[ -n "$aliases" ]] && display="$name ($aliases)"

            local tags=""
            [[ "$offline" == "true" ]] && tags="${tags} [offline]"
            [[ "$root" == "true" ]] && tags="${tags} [root]"
            [[ "$maturity" == "beta" ]] && tags="${tags} [beta]"
            [[ "$maturity" == "experimental" ]] && tags="${tags} [experimental]"

            printf '  %-28s %s%s\n' "$display" "$summary" "$tags"
        done <<< "$LAMBOOT_HELP_REGISTRY"
        printf '\n'
    done < <(_categories_in_order)

    printf 'Global flags (every subcommand):\n'
    printf '  --help, -h             Show this help\n'
    printf '  --version              Print tool + toolkit version\n'
    printf '  --json                 Emit unified JSON output\n'
    printf '  --json-schema          Print the JSON schema this tool emits\n'
    printf '  --verbose, -v          Informational output beyond default\n'
    printf '  --quiet, -q            Only warnings and errors\n'
    printf '  --no-color             Disable ANSI color (auto on non-TTY)\n'
    printf '  --dry-run              Print planned actions without executing\n'
    printf '  --yes, -y              Answer yes to interactive prompts\n'
    printf '  --force                Skip safety checks (see per-command docs)\n'
    printf '  --auto                 Non-interactive full automation (implies --yes)\n'
    printf '  --offline DISK         Operate on an unmounted disk or image\n'
    printf '  --suggest-next-command Print the recommended follow-up command\n'
    printf '\nExit codes:\n'
    printf '  0 ok   1 error   2 partial   3 noop   4 unsafe\n'
    printf '  5 abort   6 not_applicable   7 prerequisite_missing\n'
}

print_subcommand_detail() {
    local target="$1"

    local resolved
    resolved=$(_lookup_subcommand "$target") || {
        printf 'error: unknown subcommand: %s\n' "$target" >&2
        printf 'try: %s help\n' "${LAMBOOT_TOOL_NAME:-tool}" >&2
        return 1
    }

    while IFS=$'\x1f' read -r name aliases category summary syntax args examples notes offline root see_also doc_url maturity; do
        [[ "$name" != "$resolved" ]] && continue

        printf '%s %s\n' "${LAMBOOT_TOOL_NAME:-tool}" "$name"
        [[ -n "$aliases" ]] && printf 'Aliases: %s\n' "$aliases"
        printf 'Category: %s\n' "$category"
        printf 'Maturity: %s\n' "$maturity"
        printf '\n  %s\n\n' "$summary"

        printf 'SYNTAX:\n  %s\n\n' "$syntax"

        if [[ -n "$args" ]]; then
            printf 'ARGUMENTS:\n'
            local max_name=0
            IFS='|' read -ra arg_arr <<< "$args"
            for a in "${arg_arr[@]}"; do
                local an="${a%%:*}"
                [[ ${#an} -gt $max_name ]] && max_name=${#an}
            done
            for a in "${arg_arr[@]}"; do
                local an="${a%%:*}"
                local ad="${a#*:}"
                printf '  %-*s  %s\n' "$max_name" "$an" "$ad"
            done
            printf '\n'
        fi

        if [[ -n "$examples" ]]; then
            printf 'EXAMPLES:\n'
            IFS='||' read -ra ex_arr <<< "$examples"
            for ex in "${ex_arr[@]}"; do
                [[ -z "$ex" ]] && continue
                printf '  %s\n' "$ex"
            done
            printf '\n'
        fi

        if [[ -n "$notes" ]]; then
            printf 'NOTES:\n'
            printf '%s\n' "$notes" | fold -s -w 76 | sed 's/^/  /'
            printf '\n'
        fi

        printf 'OFFLINE:\n  %s\n\n' "$([[ "$offline" == "true" ]] && printf 'Yes — supports --offline DISK' || printf 'No — requires online system')"
        printf 'PRIVILEGE:\n  %s\n\n' "$([[ "$root" == "true" ]] && printf 'Requires root (sudo)' || printf 'Runs unprivileged')"

        if [[ -n "$see_also" ]]; then
            printf 'SEE ALSO:\n  %s\n\n' "$see_also"
        fi

        [[ -n "$doc_url" ]] && printf 'DOCUMENTATION:\n  %s\n' "$doc_url"

        return 0
    done <<< "$LAMBOOT_HELP_REGISTRY"
}

print_after_help() {
    local tool_name="${LAMBOOT_TOOL_NAME:-lamboot-tool}"
    printf 'COMMANDS:\n'
    printf '  Commands and subcommands available under %s.\n' "$tool_name"
    printf '  Run `%s help` for full documentation or `%s help <cmd>` for details.\n\n' \
        "$tool_name" "$tool_name"

    local cat
    while IFS= read -r cat; do
        [[ -z "$cat" ]] && continue
        printf '  %s\n' "$cat"
        while IFS=$'\x1f' read -r name aliases category summary _rest; do
            [[ -z "$name" ]] && continue
            [[ "$category" != "$cat" ]] && continue
            local display="$name"
            [[ -n "$aliases" ]] && display="$name ($aliases)"
            printf '    %-32s %s\n' "$display" "$summary"
        done <<< "$LAMBOOT_HELP_REGISTRY"
        printf '\n'
    done < <(_categories_in_order)
}

dispatch_help() {
    if [[ $# -eq 0 ]]; then
        print_full_listing
        return 0
    fi
    print_subcommand_detail "$1"
}

dump_registry() {
    printf '%s\n' "$LAMBOOT_HELP_REGISTRY"
}

#!/usr/bin/env bash
#
# check_disk.sh — disk usage check for monitoring systems.
#
# Usage:
#   ./check_disk.sh [PATH] [WARN] [CRIT]
#   ./check_disk.sh -h | --help
#
# Arguments:
#   PATH   mount point or directory to check (default: /)
#   WARN   warning threshold in percent, integer 0..100 (default: 80)
#   CRIT   critical threshold in percent, integer 0..100 (default: 90)
#
# Exit codes (Nagios / monitoring-plugins convention):
#   0 — OK
#   1 — WARNING
#   2 — CRITICAL
#   3 — UNKNOWN (bad arguments / runtime failure)
#
# Examples:
#   ./check_disk.sh
#   ./check_disk.sh /var 75 90
#   ./check_disk.sh / 0 100

set -euo pipefail

readonly OK=0
readonly WARNING=1
readonly CRITICAL=2
readonly UNKNOWN=3

usage() {
    cat <<'EOF'
Usage: check_disk.sh [PATH] [WARN] [CRIT]
       check_disk.sh -h | --help

  PATH   mount point or directory to check (default: /)
  WARN   warning threshold in percent, integer 0..100 (default: 80)
  CRIT   critical threshold in percent, integer 0..100 (default: 90)

Exit codes: 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN
EOF
}

die_usage() {
    echo "UNKNOWN - $1" >&2
    usage >&2
    exit "$UNKNOWN"
}

# True only for a plain decimal integer with no leading zeros and no sign.
# "0" is allowed. "00", "08", "010", "+5", "-5", " 5", "" are not.
is_integer() {
    [[ "$1" =~ ^0$ || "$1" =~ ^[1-9][0-9]*$ ]]
}

# True only for a valid percentage threshold: decimal integer in 0..100.
# Length is bounded (<= 3 chars) BEFORE arithmetic so that values such as
# 2^64 (18446744073709551616) cannot wrap around to 0 inside $((...)).
in_range_percent() {
    is_integer "$1" || return 1
    (( ${#1} <= 3 )) || return 1
    local n=$((10#$1))
    (( n >= 0 && n <= 100 ))
}

# Prints the used-space percentage (digits only) for the given path.
# On failure prints nothing to stdout and returns non-zero.
# Note: set -e does NOT protect inside a function called from an `if`
# condition; the empty-output check below is what actually guards us.
get_usage_percent() {
    local path="$1"
    local raw
    raw="$(df --output=pcent "$path" | tail -n 1 | tr -dc '0-9')"
    if [[ -z "$raw" ]]; then
        return 1
    fi
    printf '%s\n' "$raw"
}

main() {
    # Help short-circuits before any argument validation.
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit "$OK"
    fi

    local path="${1:-/}"
    local warn="${2:-80}"
    local crit="${3:-90}"

    if ! is_integer "$warn"; then
        die_usage "WARN must be a decimal integer without leading zeros, got: '$warn'"
    fi
    if ! is_integer "$crit"; then
        die_usage "CRIT must be a decimal integer without leading zeros, got: '$crit'"
    fi
    if ! in_range_percent "$warn"; then
        die_usage "WARN must be within 0..100, got: $warn"
    fi
    if ! in_range_percent "$crit"; then
        die_usage "CRIT must be within 0..100, got: $crit"
    fi
    if (( warn > crit )); then
        die_usage "WARN ($warn) must not exceed CRIT ($crit)"
    fi
    if [[ ! -e "$path" ]]; then
        die_usage "path does not exist: '$path'"
    fi

    local used_pct
    if ! used_pct="$(get_usage_percent "$path")"; then
        echo "UNKNOWN - failed to read disk usage for $path" >&2
        exit "$UNKNOWN"
    fi

    if (( used_pct >= crit )); then
        echo "CRITICAL - $path usage ${used_pct}%"
        exit "$CRITICAL"
    elif (( used_pct >= warn )); then
        echo "WARNING - $path usage ${used_pct}%"
        exit "$WARNING"
    fi

    echo "OK - $path usage ${used_pct}%"
    exit "$OK"
}

main "$@"

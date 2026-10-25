#!/usr/bin/env bash
#
# check_disk.sh — проверка занятости диска для систем мониторинга.
#
# Использование:
#   ./check_disk.sh [путь] [warn%] [crit%]
#
# Аргументы:
#   путь   — точка монтирования или каталог (по умолчанию: /)
#   warn%  — порог предупреждения, целое число (по умолчанию: 80)
#   crit%  — критический порог, целое число (по умолчанию: 90)
#
# Коды выхода (соглашение Nagios/monitoring-plugins):
#   0 — OK
#   1 — WARNING
#   2 — CRITICAL
#   3 — UNKNOWN (ошибка аргументов / выполнения)
#
# Пример:
#   ./check_disk.sh /var 75 90

set -euo pipefail

readonly OK=0
readonly WARNING=1
readonly CRITICAL=2
readonly UNKNOWN=3

usage() {
    cat <<'EOF'
Usage: check_disk.sh [PATH] [WARN] [CRIT]

  PATH   mount point or directory to check (default: /)
  WARN   warning threshold in percent, integer (default: 80)
  CRIT   critical threshold in percent, integer (default: 90)

Exit codes: 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN
EOF
}

die_usage() {
    echo "UNKNOWN - $1" >&2
    usage >&2
    exit "$UNKNOWN"
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Возвращает процент занятости для заданного пути (только число).
get_usage_percent() {
    local path="$1"
    local raw
    raw="$(df --output=pcent "$path" | tail -n 1 | tr -dc '0-9')"
    if [[ -z "$raw" ]]; then
        echo "не удалось получить данные df для $path" >&2
        return 1
    fi
    printf '%s\n' "$raw"
}

main() {
    local path="${1:-/}"
    local warn="${2:-80}"
    local crit="${3:-90}"

    if ! is_integer "$warn"; then
        die_usage "WARN must be an integer, got: '$warn'"
    fi
    if ! is_integer "$crit"; then
        die_usage "CRIT must be an integer, got: '$crit'"
    fi
    if (( warn > crit )); then
        die_usage "WARN ($warn) must not exceed CRIT ($crit)"
    fi
    if [[ ! -e "$path" ]]; then
        die_usage "path does not exist: '$path'"
    fi

    local usage
    if ! usage="$(get_usage_percent "$path")"; then
        echo "UNKNOWN - failed to read disk usage for $path" >&2
        exit "$UNKNOWN"
    fi

    if (( usage >= crit )); then
        echo "CRITICAL - $path usage ${usage}%"
        exit "$CRITICAL"
    elif (( usage >= warn )); then
        echo "WARNING - $path usage ${usage}%"
        exit "$WARNING"
    fi

    echo "OK - $path usage ${usage}%"
    exit "$OK"
}

main "$@"

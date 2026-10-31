#!/usr/bin/env bash
#
# check_disk.sh — проверка занятости диска для систем мониторинга.
#
# Использование:
#   ./check_disk.sh [PATH] [WARN] [CRIT]
#   ./check_disk.sh -h | --help
#
# Коды выхода (соглашение Nagios / monitoring-plugins):
#   0 — OK, 1 — WARNING, 2 — CRITICAL, 3 — UNKNOWN
#
# Примеры:
#   ./check_disk.sh
#   ./check_disk.sh /var 75 90

# Строгий режим:
#   -e  остановить скрипт, если команда завершилась с ошибкой;
#   -u  считать ошибкой обращение к необъявленной переменной
#       (защита от опечаток вроде $pth вместо $path);
#   -o pipefail  конвейер "a | b | c" считается неудачным, если упала
#       ЛЮБАЯ его часть, а не только последняя.
set -euo pipefail

# Коды выхода вынесены в именованные константы: в коде видно смысл
# ("exit $CRITICAL"), а не магическое число. readonly запрещает
# случайно изменить значение дальше по скрипту.
readonly OK=0
readonly WARNING=1
readonly CRITICAL=2
readonly UNKNOWN=3

# Справка. Кавычки вокруг 'EOF' отключают подстановку переменных
# внутри текста: он выводится ровно так, как написан.
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

# Ошибка использования: сообщение и справка идут в stderr (>&2), чтобы
# не смешиваться с нормальным выводом, который читает система мониторинга.
# Код 3 (UNKNOWN) значит "проверку выполнить не удалось", а не "диск плохой".
die_usage() {
    echo "UNKNOWN - $1" >&2
    usage >&2
    exit "$UNKNOWN"
}

# Истина, только если аргумент — целое число от 0 до 100 без знака
# и без ведущих нулей. Разбор регулярки:
#   0            ровно ноль
#   [1-9][0-9]?  от 1 до 99 (первая цифра не ноль, вторая необязательна)
#   100          ровно сто
# Якоря ^ и $ обязательны: без них "abc5" или "1000" тоже совпали бы.
# Выражение лежит в переменной и используется БЕЗ кавычек: в кавычках
# Bash трактует его как обычный текст, и сопоставление не сработает.
# Побочный выигрыш: значения вроде "08" или огромных чисел до арифметики
# не доходят, поэтому проблемы восьмеричной системы и переполнения
# исключены по построению.
is_percent() {
    local -r re='^(0|[1-9][0-9]?|100)$'
    [[ "$1" =~ $re ]]
}

# Печатает процент занятости (только цифры) для указанного пути.
# Конвейер:
#   df --output=pcent -- "$path"  заголовок "Use%" и строка вида " 42%";
#                                 "--" значит "дальше только аргументы":
#                                 путь вида "-x" не примется за опцию;
#   tail -n 1                     оставляет последнюю строку (без заголовка);
#   tr -dc '0-9'                  удаляет всё, кроме цифр (пробелы, "%", "\n").
# set -e НЕ действует внутри функции, вызванной в условии if, поэтому
# от пустого результата нас защищает явная проверка -z.
get_usage_percent() {
    local path="$1"
    local raw
    raw="$(df --output=pcent -- "$path" | tail -n 1 | tr -dc '0-9')"
    if [[ -z "$raw" ]]; then
        return 1
    fi
    printf '%s\n' "$raw"
}

main() {
    # Справка обрабатывается раньше всего остального и завершается кодом 0.
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit "$OK"
    fi

    # $# — число аргументов. Лишние аргументы отвергаем явно:
    # молча проигнорированный ввод в мониторинге хуже понятной ошибки.
    if (( $# > 3 )); then
        die_usage "too many arguments (got $#, expected at most 3)"
    fi

    # ${N:-значение} подставляет умолчание, если аргумент не передан.
    local path="${1:-/}"
    local warn="${2:-80}"
    local crit="${3:-90}"

    if ! is_percent "$warn"; then
        die_usage "WARN must be an integer within 0..100 without leading zeros, got: '$warn'"
    fi
    if ! is_percent "$crit"; then
        die_usage "CRIT must be an integer within 0..100 without leading zeros, got: '$crit'"
    fi
    # Сравнение безопасно: после проверки выше это короткие десятичные числа.
    if (( warn > crit )); then
        die_usage "WARN ($warn) must not exceed CRIT ($crit)"
    fi
    if [[ ! -e "$path" ]]; then
        die_usage "path does not exist: '$path'"
    fi

    # Значение и код возврата получаем в одной конструкции: если функция
    # вернула ошибку, срабатывает ветка UNKNOWN.
    local used_pct
    if ! used_pct="$(get_usage_percent "$path")"; then
        echo "UNKNOWN - failed to read disk usage for $path" >&2
        exit "$UNKNOWN"
    fi

    # Порядок проверок важен: сначала более тяжёлое состояние (CRITICAL),
    # иначе значение выше crit попало бы в ветку WARNING.
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

# "$@" передаёт функции все аргументы скрипта с сохранением границ.
# Вызов main в самом конце означает, что Bash прочитает файл целиком
# до начала выполнения (безопаснее, если файл меняют на ходу).
main "$@"

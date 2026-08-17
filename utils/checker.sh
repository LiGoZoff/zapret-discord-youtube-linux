#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(readlink -f "$SCRIPT_DIR/..")"
STRATEGIES_DIR="$REPO_ROOT/linux-strategies"
RESULTS_FILE="$REPO_ROOT/results.txt"
NFQWS_BIN="/opt/zapret/binaries/linux-x86_64/nfqws"
ZAPRET_CONFIG="/opt/zapret/config"

declare -a RESULTS_ARRAY

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

CURRENT_PID=""
APPLIED_SUCCESSFULLY=0

if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: скрипт должен запускаться от root (sudo)." >&2
    exit 1
fi

cleanup() {
    if [ "$APPLIED_SUCCESSFULLY" -eq 1 ]; then
        exit 0
    fi

    if [ -n "$CURRENT_PID" ]; then
        kill -9 "$CURRENT_PID" 2>/dev/null || true
    fi
    if [ -n "${_CHECKER_BACKUP_FILE-}" ] && [ -f "${_CHECKER_BACKUP_FILE}" ]; then
        cp -a "${_CHECKER_BACKUP_FILE}" "${ZAPRET_CONFIG}" || true
        rm -f "${_CHECKER_BACKUP_FILE}" || true
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart zapret.service 2>/dev/null || systemctl restart zapret 2>/dev/null || true
        fi
    fi
    exit 1
}
trap cleanup INT TERM

check_http() {
    local url="$1"
    if curl -I -s -k -m 5 "$url" 2>/dev/null | grep -q -i "HTTP/"; then
        return 0
    else
        return 1
    fi
}

check_voice() {
    if curl -I -s -k -m 5 "https://gateway.discord.gg" 2>/dev/null | grep -q -i "HTTP/"; then
        return 0
    else
        return 1
    fi
}

print_table() {
    echo ""
    local max_len=25
    for result in "${RESULTS_ARRAY[@]}"; do
        IFS='|' read -r strat _ <<< "$result"
        local len=${#strat}
        if [ "$len" -gt "$max_len" ]; then max_len=$len; fi
    done
    local col1_width=$max_len

    local FORMAT="%-${col1_width}s | %-8s | %-14s | %-12s | %-14s\n"
    local HEADER_LINE=$(printf "$FORMAT" "Стратегия" "YouTube" "Discord Text" "Cloudflare" "Discord Voice")
    local sep_len=${#HEADER_LINE}

    : > "$RESULTS_FILE"
    printf '%*s\n' "$sep_len" '' | tr ' ' '-' | tee -a "$RESULTS_FILE"
    printf "%s" "$HEADER_LINE" | tee -a "$RESULTS_FILE"
    printf '%*s\n' "$sep_len" '' | tr ' ' '-' | tee -a "$RESULTS_FILE"

    for result in "${RESULTS_ARRAY[@]}"; do
        IFS='|' read -r strat yt ds cf vc <<< "$result"
        printf "$FORMAT" "$strat" "$yt" "$ds" "$cf" "$vc" | tee -a "$RESULTS_FILE"
    done

    printf '%*s\n' "$sep_len" '' | tr ' ' '-' | tee -a "$RESULTS_FILE"
    echo -e "\n${GREEN}Результаты сохранены в: $RESULTS_FILE${NC}"
}

if [ ! -d "$STRATEGIES_DIR" ]; then
    echo -e "${RED}Ошибка: Папка $STRATEGIES_DIR не найдена!${NC}"
    exit 1
fi

if [ ! -x "$NFQWS_BIN" ]; then
    if command -v nfqws >/dev/null 2>&1; then
        NFQWS_BIN="$(command -v nfqws)"
    else
        echo -e "${RED}Ошибка: бинарник не найден: $NFQWS_BIN${NC}" >&2
        exit 1
    fi
fi

if [ ! -e "$ZAPRET_CONFIG" ]; then
    read -rp "Не найден $ZAPRET_CONFIG. Введите путь до конфига zapret: " inp
    if [ -n "$inp" ]; then
        ZAPRET_CONFIG="$inp"
    fi
fi

_CHECKER_BACKUP_FILE="${ZAPRET_CONFIG}.checker.bak.$(date +%s)"
if [ -f "$ZAPRET_CONFIG" ]; then
    cp -a "$ZAPRET_CONFIG" "${_CHECKER_BACKUP_FILE}"
fi

shopt -s nullglob
mapfile -t STRATEGY_FILES < <(
    find "$STRATEGIES_DIR" -maxdepth 1 -type f -name 'general*.sh' -print0 \
    | xargs -0 -n1 printf '%s\n' \
    | sort -V
)
if [ ${#STRATEGY_FILES[@]} -eq 0 ]; then
    echo -e "${YELLOW}В папке $STRATEGIES_DIR пусто!${NC}"
    rm -f "${_CHECKER_BACKUP_FILE}"
    exit 1
fi

MODE="normal"
if [ "$#" -gt 0 ]; then
  case "$1" in
    interactive) MODE="interactive" ;;
    fast) MODE="fast" ;;
    *) MODE="$1" ;;
  esac
fi

draw_progress() {
    local cur=$1 total=$2 width=40 msg="${3-}"
    local percent=0
    if [ "$total" -gt 0 ]; then percent=$(( cur * 100 / total )); fi
    local filled=0
    if [ "$total" -gt 0 ]; then filled=$(( cur * width / total )); fi
    if [ "$filled" -gt "$width" ]; then filled=$width; fi
    local empty=$(( width - filled ))
    local bar_filled="" bar_empty=""
    for ((i=0;i<filled;i++)); do bar_filled+="#"; done
    for ((i=0;i<empty;i++)); do bar_empty+="-"; done
    local out
    if [ -n "$msg" ]; then
        out=$(printf "Progress: %3d%% [%s%s] (%d/%d) - %s" "$percent" "$bar_filled" "$bar_empty" "$cur" "$total" "$msg")
    else
        out=$(printf "Progress: %3d%% [%s%s] (%d/%d)" "$percent" "$bar_filled" "$bar_empty" "$cur" "$total")
    fi
    printf "\r%s" "$out"
    if [ -n "${_PROGRESS_PREV_LEN-}" ]; then
        local diff=$((_PROGRESS_PREV_LEN - ${#out}))
        if [ "$diff" -gt 0 ]; then
            printf "%${diff}s" ""
            printf "\r%s" "$out"
        fi
    fi
    _PROGRESS_PREV_LEN=${#out}
}

apply_and_exit() {
    local strat_path="$1"
    local strat_name="$(basename "$strat_path")"
    
    echo -e "\n\n${GREEN}Найдена идеальная стратегия: $strat_name${NC}"
    
    print_table

    echo "$strat_name" > "$REPO_ROOT/.active_strategy"
    
    if [ -f "${_CHECKER_BACKUP_FILE}" ]; then
        cp -a "${_CHECKER_BACKUP_FILE}" "$ZAPRET_CONFIG"
    fi

    if [ -f "$SCRIPT_DIR/service.sh" ]; then
        bash "$SCRIPT_DIR/service.sh" 
    fi

    rm -f "${_CHECKER_BACKUP_FILE}" 2>/dev/null || true
    APPLIED_SUCCESSFULLY=1
    echo -e "${GREEN}Готово! $strat_name активирована.${NC}"
    exit 0
}

checks_per_strategy=4
total=$(( ${#STRATEGY_FILES[@]} * checks_per_strategy ))
current=0
draw_progress $current $total

for file in "${STRATEGY_FILES[@]}"; do
    filename=$(basename "$file")
    draw_progress $current $total "$filename"

    if ! cp -a "$file" "$ZAPRET_CONFIG"; then
        current=$((current + checks_per_strategy))
        continue
    fi

    if [ -x "/opt/zapret/install_easy.sh" ]; then
        yes '' | bash "/opt/zapret/install_easy.sh" >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart zapret.service 2>/dev/null || systemctl restart zapret 2>/dev/null || true
    fi

    sleep 4

    draw_progress $current $total "$filename - YouTube"
    check_http "https://www.youtube.com" && res_yt="✅" || res_yt="❌"
    current=$((current+1)); draw_progress $current $total "$filename - YouTube"

    draw_progress $current $total "$filename - Discord Text"
    check_http "https://discord.com" && res_ds="✅" || res_ds="❌"
    current=$((current+1)); draw_progress $current $total "$filename - Discord"

    draw_progress $current $total "$filename - Cloudflare"
    check_http "https://cloudflare.com" && res_cf="✅" || res_cf="❌"
    current=$((current+1)); draw_progress $current $total "$filename - Cloudflare"

    draw_progress $current $total "$filename - Discord Voice"
    check_voice && res_vc="✅" || res_vc="❌"
    current=$((current+1)); draw_progress $current $total "$filename - Discord Voice"

    RESULTS_ARRAY+=("$filename|$res_yt|$res_ds|$res_cf|$res_vc")

    if [ "$MODE" = "fast" ]; then
        if [ "$res_yt" = "✅" ] && [ "$res_ds" = "✅" ] && [ "$res_cf" = "✅" ] && [ "$res_vc" = "✅" ]; then
            echo "$(date): Selected $filename via fast mode" >> "$RESULTS_FILE"
            apply_and_exit "$file"
        fi
    fi
done

if [ -f "${_CHECKER_BACKUP_FILE}" ]; then
    cp -a "${_CHECKER_BACKUP_FILE}" "$ZAPRET_CONFIG"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart zapret.service 2>/dev/null || systemctl restart zapret 2>/dev/null || true
    fi
fi

clear
print_table

if [ "$MODE" = "interactive" ]; then
    echo ""
    echo "Выберите номер стратегии для применения (0 - выход):"
    i=1
    for r in "${RESULTS_ARRAY[@]}"; do
        IFS='|' read -r s _ <<< "$r"
        printf "%3d) %s\n" "$i" "$s"
        ((i++))
    done
    read -rp "Номер: " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -gt 0 ] && [ "$sel" -le $((i-1)) ]; then
        chosen_index=$((sel-1))
        chosen_entry="${RESULTS_ARRAY[$chosen_index]}"
        IFS='|' read -r chosen_name _ <<< "$chosen_entry"
        apply_and_exit "$STRATEGIES_DIR/$chosen_name"
    fi
fi

rm -f "${_CHECKER_BACKUP_FILE}" 2>/dev/null || true

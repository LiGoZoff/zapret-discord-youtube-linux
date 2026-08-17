#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(readlink -f "$SCRIPT_DIR/..")"
STRATEGIES_DIR="$REPO_ROOT/linux-strategies"
RESULTS_FILE="$REPO_ROOT/results.txt"
NFQWS_BIN="/opt/zapret/binaries/linux-x86_64/nfqws"
ZAPRET_CONFIG="/opt/zapret/config"

declare -a RESULTS_ARRAY
declare -a NORMAL_ARRAY
declare -a ERROR_ARRAY

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
    NORMAL_ARRAY=()
    ERROR_ARRAY=()

    for result in "${RESULTS_ARRAY[@]}"; do
        IFS='|' read -r strat yt ds cf vc err <<< "$result"
        if [ -n "$err" ] && [ "$err" != "OK" ]; then
            ERROR_ARRAY+=("$strat|$err")
        else
            NORMAL_ARRAY+=("$result")
        fi
    done

    local max_len=9 # Длина слова "Стратегия"
    for result in "${NORMAL_ARRAY[@]}"; do
        IFS='|' read -r strat _ <<< "$result"
        local len=${#strat}
        if [ "$len" -gt "$max_len" ]; then max_len=$len; fi
    done
    local col1_width=$max_len

    local w_no=3
    local w_strat=$col1_width
    local w_yt=7
    local w_ds=12
    local w_cf=10
    local w_vc=13

    local FORMAT="%-3s | %-${w_strat}s | %-${w_yt}s | %-${w_ds}s | %-${w_cf}s | %-${w_vc}s\n"
    
    # Динамический расчет точной длины разделителя под суммарную ширину всех колонок и разделителей
    local sep_len=$((60 + w_strat))
    local sep_line
    printf -v sep_line '%*s' "$sep_len" ''
    sep_line="${sep_line// /-}"

    : > "$RESULTS_FILE"
    echo "$sep_line" | tee -a "$RESULTS_FILE"
    printf "$FORMAT" "№" "Стратегия" "YouTube" "Discord Text" "Cloudflare" "Discord Voice" | tee -a "$RESULTS_FILE"
    echo "$sep_line" | tee -a "$RESULTS_FILE"

    local idx=1
    for result in "${NORMAL_ARRAY[@]}"; do
        IFS='|' read -r strat yt ds cf vc err <<< "$result"
        printf "$FORMAT" "$idx" "$strat" "$yt" "$ds" "$cf" "$vc" | tee -a "$RESULTS_FILE"
        ((idx++))
    done

    echo "$sep_line" | tee -a "$RESULTS_FILE"
    echo -e "\n${GREEN}Результаты сохранены в: $RESULTS_FILE${NC}"

    if [ ${#ERROR_ARRAY[@]} -gt 0 ]; then
        echo -e "\n${RED}Стратегии с ошибками (не вошли в таблицу):${NC}" | tee -a "$RESULTS_FILE"
        for err_item in "${ERROR_ARRAY[@]}"; do
            IFS='|' read -r strat err <<< "$err_item"
            echo -e "${YELLOW}- $strat:${NC} $err" | tee -a "$RESULTS_FILE"
        done
    fi
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
    local skip_table="${2:-}"
    
    echo -e "\n\n${GREEN}Найдена идеальная стратегия: $strat_name${NC}"
    
    if [ "$MODE" = "fast" ]; then
        local has_errors=0
        for result in "${RESULTS_ARRAY[@]}"; do
            IFS='|' read -r strat yt ds cf vc err <<< "$result"
            if [ -n "$err" ] && [ "$err" != "OK" ]; then
                if [ "$has_errors" -eq 0 ]; then
                    echo -e "\n${RED}Во время поиска произошли ошибки в следующих стратегиях:${NC}"
                    has_errors=1
                fi
                echo -e "${YELLOW}- $strat:${NC} $err"
            fi
        done
    elif [ "$skip_table" != "skip" ]; then
        print_table
    fi

    echo "$strat_name" > "$REPO_ROOT/.active_strategy"
    
    echo -e "\nКак установить выбранную стратегию?"
    echo "1) С автозагрузкой"
    echo "2) Без автозагрузки"
    
    read -rp "Выберите (1 или 2): " autoh_choice < /dev/tty || autoh_choice="2"
    
    if [ "$autoh_choice" = "1" ]; then
        touch "$REPO_ROOT/.autorun_enabled"
        echo -e "${GREEN}Автозагрузка включена.${NC}"
    else
        rm -f "$REPO_ROOT/.autorun_enabled"
        echo -e "${YELLOW}Автозагрузка отключена.${NC}"
    fi

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

    INSTALL_OUT=""
    if [ -x "/opt/zapret/install_easy.sh" ]; then
        INSTALL_OUT=$(timeout 15s bash -c "yes '' | bash /opt/zapret/install_easy.sh" 2>&1)
    elif command -v systemctl >/dev/null 2>&1; then
        INSTALL_OUT=$(systemctl restart zapret.service 2>&1)
    fi

    sleep 4

    err_msg=""
    if ! systemctl is-active --quiet zapret.service 2>/dev/null; then
        err_msg=$(echo "$INSTALL_OUT" | grep -iE 'error|ошибка|not found|no such file|invalid|missing' | tail -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -z "$err_msg" ]; then
            err_msg=$(systemctl status zapret.service --no-pager | grep -iE 'error|ошибка|failed' | tail -n 1 | sed 's/^[[:space:]]*//')
        fi
        
        if [ -z "$err_msg" ]; then
            err_msg="Ошибка запуска (неверный параметр/отсутствует бинарник/отсутствует list)"
        fi

        if [ "$MODE" = "interactive" ] || [ "$MODE" = "fast" ]; then
            printf "\r\033[K"
            echo -e "${RED}Стратегия $filename не смогла запуститься!${NC}"
            echo -e "${YELLOW}Ошибка:${NC} $err_msg"
            _PROGRESS_PREV_LEN=0
        fi

        RESULTS_ARRAY+=("$filename|❌|❌|❌|❌|$err_msg")
        current=$((current + checks_per_strategy))
        continue
    fi

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

    RESULTS_ARRAY+=("$filename|$res_yt|$res_ds|$res_cf|$res_vc|")

    if [ "$MODE" = "fast" ]; then
        if [ "$res_yt" = "✅" ] && [ "$res_ds" = "✅" ] && [ "$res_cf" = "✅" ] && [ "$res_vc" = "✅" ]; then
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

if [ "$MODE" != "fast" ]; then
    print_table
else
    echo -e "\n${RED}Идеальная стратегия не найдена в быстром режиме.${NC}"
    has_errors_fast=0
    for result in "${RESULTS_ARRAY[@]}"; do
        IFS='|' read -r strat yt ds cf vc err <<< "$result"
        if [ -n "$err" ] && [ "$err" != "OK" ]; then
            if [ "$has_errors_fast" -eq 0 ]; then
                echo -e "\n${RED}Стратегии, которые завершились с ошибкой:${NC}"
                has_errors_fast=1
            fi
            echo -e "${YELLOW}- $strat:${NC} $err"
        fi
    done
fi

if [ "$MODE" = "interactive" ]; then
    echo ""
    read -rp "Выберите номер стратегии для применения (0 - выход): " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -gt 0 ] && [ "$sel" -le "${#NORMAL_ARRAY[@]}" ]; then
        chosen_index=$((sel-1))
        chosen_entry="${NORMAL_ARRAY[$chosen_index]}"
        IFS='|' read -r chosen_name _ <<< "$chosen_entry"
        
        apply_and_exit "$STRATEGIES_DIR/$chosen_name" "skip"
    fi
fi

rm -f "${_CHECKER_BACKUP_FILE}" 2>/dev/null || true
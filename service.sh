#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(readlink -f "$SCRIPT_DIR")"
BIN_DIR="$REPO_ROOT/bin"
CONVERT_SCRIPT="$REPO_ROOT/linux-strategies/convert-strategies.sh"
STRAT_DIR="$REPO_ROOT/linux-strategies"
GAMEFLAG_FILE="$REPO_ROOT/.gamefilter_mode"
AUTORUN_FLAG="$REPO_ROOT/.autorun_enabled"
LOCAL_VERSION_FILE="$REPO_ROOT/.service/version.txt"
LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE" 2>/dev/null || echo "unknown")

OPT_REPO="/opt/zapret"

clear_screen() { printf '\033c'; }

ensure_user_lists() {
  mkdir -p "$REPO_ROOT/lists"
  local list
  for list in ipset-exclude-user.txt list-general-user.txt list-exclude-user.txt; do
    if [ ! -f "$REPO_ROOT/lists/$list" ]; then
      case "$list" in
        ipset-exclude-user.txt)
          printf '203.0.113.113/32\n' > "$REPO_ROOT/lists/$list"
          ;;
        *)
          : > "$REPO_ROOT/lists/$list"
          ;;
      esac
    fi
  done
}

ensure_user_lists

ensure_convert() {
  if [ ! -x "$CONVERT_SCRIPT" ]; then
    if [ -f "$CONVERT_SCRIPT" ]; then
      sudo chmod +x "$CONVERT_SCRIPT"
    else
      echo "Конвертер не найден: $CONVERT_SCRIPT" >&2
      return 1
    fi
  fi
  return 0
}

toggle_gamefilter() {
  clear_screen
  echo "Выберите режим game filter:" 
  echo "  0. Отключить"
  echo "  1. TCP и UDP"
  echo "  2. Только TCP"
  echo "  3. Только UDP"
  echo ""
  
  local gf_choice="0"
  read -rp "Выберите опцию (0-3, по умолчанию: 0): " gf_choice
  [ -z "$gf_choice" ] && gf_choice="0"

  case "$gf_choice" in
    0)
      rm -f "$GAMEFLAG_FILE"
      ;;
    1)
      printf "all\n" > "$GAMEFLAG_FILE"
      ;;
    2)
      printf "tcp\n" > "$GAMEFLAG_FILE"
      ;;
    3)
      printf "udp\n" > "$GAMEFLAG_FILE"
      ;;
    *)
      echo "Неверный выбор."
      read -rp "Нажмите Enter для возврата в меню..."
      return
      ;;
  esac

  echo "Перезагрузите zapret для применения изменений"
  read -rp "Нажмите Enter для возврата в меню..."
}

toggle_autorun() {
  clear_screen
  if [ -f "$AUTORUN_FLAG" ]; then
    rm -f "$AUTORUN_FLAG"
    echo "Автозагрузка отключена."
  else
    touch "$AUTORUN_FLAG"
    echo "Автозагрузка включена."
  fi
  echo ""
  read -rp "Нажмите Enter для возврата в меню..."
}

check_for_updates() {
  clear_screen
  echo "Проверка обновлений..."

  local GITHUB_VERSION_URL="https://raw.githubusercontent.com/LiGoZoff/zapret-discord-youtube-linux/main/.service/version.txt"
  local GITHUB_RELEASE_URL="https://github.com/LiGoZoff/zapret-discord-youtube-linux/releases/tag/"
  local GITHUB_DOWNLOAD_URL="https://github.com/LiGoZoff/zapret-discord-youtube-linux/releases/latest"

  local GITHUB_VERSION
  if ! GITHUB_VERSION=$(curl -s --max-time 10 "$GITHUB_VERSION_URL" | tr -d '\n' | tr -d '\r'); then
    echo "Предупреждение: не удалось получить последнюю версию. Это не влияет на работу zapret."
    read -rp "Нажмите Enter для возврата в меню..."
    return
  fi

  if [ "$LOCAL_VERSION" = "$GITHUB_VERSION" ]; then
    echo "Установлена последняя версия: $LOCAL_VERSION"
    read -rp "Нажмите Enter для возврата в меню..."
    return
  fi

  echo "Текущая версия: $LOCAL_VERSION"
  echo "Доступна новая версия: $GITHUB_VERSION"
  echo "Страница релиза: $GITHUB_RELEASE_URL$GITHUB_VERSION"
  echo ""
  read -rp "Обновить сейчас? (y/N): " update_confirm
  if [[ ! "$update_confirm" =~ ^[Yy]$ ]]; then
    echo "Обновление отменено."
    read -rp "Нажмите Enter для возврата в меню..."
    return
  fi

  echo "Обновление..."
  if git -C "$REPO_ROOT" pull --rebase; then
    echo "Обновление завершено успешно."
    LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE" 2>/dev/null || echo "unknown")
    echo "Новая версия: $LOCAL_VERSION"
  else
    echo "Ошибка при обновлении. Попробуйте вручную."
  fi

  read -rp "Нажмите Enter для возврата в меню..."
}

delete_zapret() {
  clear_screen
  echo "ВНИМАНИЕ: Это действие полностью удалит zapret!"
  echo "Будут удалены:"
  echo "  - /opt/zapret"
  echo "  - Текущая директория zapret ($REPO_ROOT)"
  echo ""
  read -rp "Вы уверены? (y/N): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Удаление zapret..."

    if sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
      sudo systemctl stop zapret.service
      sudo systemctl disable zapret.service
    fi

    sudo rm -rf /opt/zapret

    cd /
    rm -rf "$REPO_ROOT"

    echo "Zapret полностью удален."
    echo "Выход."
    exit 0
  else
    echo "Удаление отменено."
    read -rp "Нажмите Enter для возврата в меню..."
  fi
}

service_status() {
  clear_screen
  echo "=== Status Service ==="
  echo ""
  
  sudo systemctl status zapret.service || true
  
  echo ""
  echo "=== Active Strategy ==="
  if sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
    if [ -f "$REPO_ROOT/.active_strategy" ]; then
      active_strategy=$(cat "$REPO_ROOT/.active_strategy")
      echo "Активная стратегия: $active_strategy"
    else
      echo "Активная стратегия: не установлена"
    fi
  else
    echo "Активная стратегия: сервис выключен"
  fi
  
  echo ""
  echo "=== Game Filter ==="
  local gf_mode="отключен"
  if [ -f "$GAMEFLAG_FILE" ]; then
    local gf_content=$(cat "$GAMEFLAG_FILE" | tr -d '\n' || echo "disabled")
    case "$gf_content" in
      all)
        gf_mode="включен (TCP и UDP)"
        ;;
      tcp)
        gf_mode="включен (только TCP)"
        ;;
      udp)
        gf_mode="включен (только UDP)"
        ;;
      *)
        gf_mode="отключен"
        ;;
    esac
  fi
  echo "Game Filter: $gf_mode"
  echo ""
  
  read -rp "Нажмите Enter для возврата в меню..."
}

manage_strategy() {
  clear_screen
  
  if [ ! -f "$REPO_ROOT/.active_strategy" ]; then
    echo "Активная стратегия не установлена."
    read -rp "Нажмите Enter..."
    return
  fi

  local active_strategy=$(cat "$REPO_ROOT/.active_strategy")
  local is_running=0
  
  if sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
    is_running=1
  fi
  
  if [ $is_running -eq 1 ]; then
    clear_screen
    echo "Выключаю стратегию: $active_strategy"
    _uninstall_strategy
  else
    clear_screen
    echo "Активная стратегия: $active_strategy"
    echo ""
    echo "Как включить стратегию?"
    echo "  1. С автозагрузкой"
    echo "  2. Без автозагрузки"
    echo ""
    
    local autorun_choice="2"
    read -rp "Выберите (1 или 2): " autorun_choice
    
    case "$autorun_choice" in
      1)
        touch "$AUTORUN_FLAG"
        _reinstall_strategy "$active_strategy"
        ;;
      2)
        rm -f "$AUTORUN_FLAG"
        _reinstall_strategy "$active_strategy"
        ;;
      *)
        echo "Неверный выбор."
        read -rp "Нажмите Enter..."
        return
        ;;
    esac
  fi
}

_reinstall_strategy() {
  local strategy="$1"
  local cfg_src="$STRAT_DIR/$strategy"

  if [ ! -f "$cfg_src" ]; then
    echo "Файл стратегии не найден: $cfg_src"
    read -rp "Нажмите Enter..."
    return
  fi

  if ! clone_opt_repo_if_needed; then
    echo "Не удалось подготовить /opt/zapret — отмена."
    read -rp "Нажмите Enter..."
    return
  fi

  echo "Переустанавливаю стратегию: $strategy"

  sudo cp -a "$cfg_src" "$OPT_REPO/config"
  sanitize_strategy_config "${OPT_REPO}/config"

  copy_missing_files_to_opt "${OPT_REPO}/config" || true
  apply_gamefilter_to_file "${OPT_REPO}/config" || true
  finalize_for_opt "${OPT_REPO}/config" || true

  if [ -x "$OPT_REPO/install_easy.sh" ]; then
    sudo bash "$OPT_REPO/install_easy.sh" || {
      echo "Ошибка при запуске install_easy.sh"
      read -rp "Нажмите Enter..."
      return
    }
  else
    echo "Предупреждение: install_easy.sh не найден или не исполняемый в $OPT_REPO"
  fi

  echo "Переустановка стратегии завершена."
  read -rp "Нажмите Enter для возврата в меню..."
}

_uninstall_strategy() {
  if [ -x "$OPT_REPO/uninstall_easy.sh" ]; then
    sudo bash "$OPT_REPO/uninstall_easy.sh"
    rm -f "$AUTORUN_FLAG"
    echo "Стратегия удалена."
    read -rp "Нажмите Enter для возврата в меню..."
  else
    echo "Предупреждение: uninstall_easy.sh не найден или не исполняемый в $OPT_REPO"
    read -rp "Нажмите Enter для возврата в меню..."
  fi
}

clone_opt_repo_if_needed() {
  if [ -d "$OPT_REPO" ]; then
    echo "/opt/zapret уже существует — распаковка не требуется."
    return 0
  fi

  local archive=""
  if [ -f "$REPO_ROOT/zapret.zip" ]; then
    archive="$REPO_ROOT/zapret.zip"
  elif [ -f "$REPO_ROOT/zapret.tar.gz" ]; then
    archive="$REPO_ROOT/zapret.tar.gz"
  elif [ -f "$REPO_ROOT/zapret.tar" ]; then
    archive="$REPO_ROOT/zapret.tar"
  else
    echo "Архив zapret не найден в $REPO_ROOT (ожидается zapret.zip, zapret.tar.gz или zapret.tar)" >&2
    return 1
  fi

  echo "Распаковываю $archive в /opt ..."
  sudo mkdir -p /opt
  cd /tmp

  case "$archive" in
    *.zip)
      sudo unzip -q "$archive" -d /opt
      if [ ! -d "$OPT_REPO" ] && [ -d "/opt/zapret-master" ]; then
        sudo mv /opt/zapret-master "$OPT_REPO"
      elif [ ! -d "$OPT_REPO" ] && [ -d "/opt/zapret-main" ]; then
        sudo mv /opt/zapret-main "$OPT_REPO"
      fi
      ;;
    *.tar.gz)
      sudo tar -xzf "$archive" -C /opt
      if [ ! -d "$OPT_REPO" ] && [ -d "/opt/zapret-master" ]; then
        sudo mv /opt/zapret-master "$OPT_REPO"
      fi
      ;;
    *.tar)
      sudo tar -xf "$archive" -C /opt
      if [ ! -d "$OPT_REPO" ] && [ -d "/opt/zapret-master" ]; then
        sudo mv /opt/zapret-master "$OPT_REPO"
      fi
      ;;
  esac

  if [ ! -d "$OPT_REPO" ]; then
    echo "Распаковка не создала директорию $OPT_REPO" >&2
    return 1
  fi

  echo "Запускаю скрипты установки..."
  if [ -x "$OPT_REPO/install_prereq.sh" ]; then
    echo "Запускаю install_prereq.sh ..."
    sudo bash "$OPT_REPO/install_prereq.sh" || true
  else
    echo "Предупреждение: install_prereq.sh не найден или не исполняемый"
  fi

  if [ -x "$OPT_REPO/install_bin.sh" ]; then
    echo "Запускаю install_bin.sh ..."
    sudo bash "$OPT_REPO/install_bin.sh" || true
  else
    echo "Предупреждение: install_bin.sh не найден или не исполняемый"
  fi

  if [ -x "$OPT_REPO/install_easy.sh" ]; then
    sudo chmod +x "$OPT_REPO/install_easy.sh" || true
  else
    echo "Предупреждение: install_easy.sh не найден"
  fi

  echo "Установка базовых компонентов завершена."
  return 0
}

apply_gamefilter_to_file() {
  local file="$1"
  [ -f "$file" ] || return 1

  local nfq_opt
  nfq_opt="$(awk '
    BEGIN{flag=0}
    /^NFQWS_OPT="/{
      flag=1
      sub(/^NFQWS_OPT="/,"")
      if(length($0)) print $0
      next
    }
    flag{
      if($0 ~ /"$/){
        sub(/"$/,"")
        if(length($0)) print $0
        exit
      } else {
        print
      }
    }
  ' "$file" )"

  [ -n "$nfq_opt" ] || return 0

  mapfile -t tcp_entries < <(printf '%s\n' "$nfq_opt" | grep -oE -- '--filter-tcp=[^ ]+' | sed -E 's/^--filter-tcp=//' || true)
  mapfile -t udp_entries < <(printf '%s\n' "$nfq_opt" | grep -oE -- '--filter-udp=[^ ]+' | sed -E 's/^--filter-udp=//' || true)

  # Also accept explicit NFQWS_PORTS_TCP / NFQWS_PORTS_UDP already present in config
  tcp_var_val=""
  udp_var_val=""
  if grep -q '^NFQWS_PORTS_TCP=' "$file" 2>/dev/null; then
    tcp_var_val=$(awk -F'=' '/^NFQWS_PORTS_TCP=/{s=$0; sub(/^NFQWS_PORTS_TCP="/,"",s); sub(/"$/,"",s); print s}' "$file" || true)
    [ -n "$tcp_var_val" ] && tcp_entries+=("$tcp_var_val")
  fi
  if grep -q '^NFQWS_PORTS_UDP=' "$file" 2>/dev/null; then
    udp_var_val=$(awk -F'=' '/^NFQWS_PORTS_UDP=/{s=$0; sub(/^NFQWS_PORTS_UDP="/,"",s); sub(/"$/,"",s); print s}' "$file" || true)
    [ -n "$udp_var_val" ] && udp_entries+=("$udp_var_val")
  fi

  normalize_list() {
    local s="$1"
    # remove any characters except digits, commas and dashes (strip TCP%/UDP% artifacts)
    s="$(printf '%s' "$s" | sed -E 's/[^0-9,-]//g')"
    s="$(printf '%s' "$s" | sed -E 's/,+/,/g; s/^,//; s/,$//')"
    printf '%s' "$s"
  }

  declare -A seen_tcp=()
  declare -A seen_udp=()
  local part
  for entry in "${tcp_entries[@]}"; do
    entry="$(normalize_list "$entry")"
    IFS=',' read -r -a parts <<< "$entry"
    for part in "${parts[@]}"; do
      part="$(printf '%s' "$part" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$part" ] && continue
      seen_tcp["$part"]=1
    done
  done

  for entry in "${udp_entries[@]}"; do
    entry="$(normalize_list "$entry")"
    IFS=',' read -r -a parts <<< "$entry"
    for part in "${parts[@]}"; do
      part="$(printf '%s' "$part" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$part" ] && continue
      seen_udp["$part"]=1
    done
  done

  local gf_mode="disabled"
  if [ -f "$GAMEFLAG_FILE" ]; then
    gf_mode=$(cat "$GAMEFLAG_FILE" | tr -d '\n' || echo "disabled")
  fi

  case "$gf_mode" in
    all)
      seen_tcp["1024-65535"]=1
      seen_udp["1024-65535"]=1
      ;;
    tcp)
      seen_tcp["1024-65535"]=1
      unset 'seen_udp[1024-65535]' 2>/dev/null || true
      ;;
    udp)
      unset 'seen_tcp[1024-65535]' 2>/dev/null || true
      seen_udp["1024-65535"]=1
      ;;
    *)
      unset 'seen_tcp[1024-65535]' 2>/dev/null || true
      unset 'seen_udp[1024-65535]' 2>/dev/null || true
      ;;
  esac

  build_list_from_assoc() {
    declare -n arr=$1
    local out=""
    for k in "${!arr[@]}"; do
      [ -z "$k" ] && continue
      if [ -z "$out" ]; then out="$k"; else out="$out,$k"; fi
    done

    if [ -n "$out" ]; then
      printf '%s' "$out" | awk -v RS=',' '
        {
          a[NR]=$0
        }
        END{
          PROCINFO["sorted_in"]="@ind_num_asc"
          for(i=1;i<=length(a);i++) print a[i]
        }' | paste -sd',' -
    else
      printf ''
    fi
  }

  local tcp_list udp_list
  tcp_list="$(build_list_from_assoc seen_tcp)"
  udp_list="$(build_list_from_assoc seen_udp)"

  if [ -z "$tcp_list" ]; then tcp_list=""; fi
  if [ -z "$udp_list" ]; then udp_list=""; fi

  tcp_list_esc="$(printf '%s' "$tcp_list" | sed 's/[\/&]/\\&/g')"
  udp_list_esc="$(printf '%s' "$udp_list" | sed 's/[\/&]/\\&/g')"

  if sudo grep -q '^NFQWS_PORTS_TCP=' "$file"; then
    sudo sed -i "s/^NFQWS_PORTS_TCP=.*/NFQWS_PORTS_TCP=\"${tcp_list_esc}\"/" "$file"
  else
    sudo sed -i "1iNFQWS_PORTS_TCP=\"${tcp_list_esc}\"" "$file"
  fi

  if sudo grep -q '^NFQWS_PORTS_UDP=' "$file"; then
    sudo sed -i "s/^NFQWS_PORTS_UDP=.*/NFQWS_PORTS_UDP=\"${udp_list_esc}\"/" "$file"
  else
    sudo sed -i "1iNFQWS_PORTS_UDP=\"${udp_list_esc}\"" "$file"
  fi

  return 0
}

finalize_for_opt() {
  local tmp="$1"

  # Remove TCP%/UDP% artifacts from converted Windows strategies
  sudo sed -i 's/--filter-tcp=\([0-9,-]*\)TCP%/--filter-tcp=\1/g' "$tmp"
  sudo sed -i 's/--filter-udp=\([0-9,-]*\)UDP%/--filter-udp=\1/g' "$tmp"

  sudo sed -i "s#\\\$ROOT_DIR/files#${OPT_REPO}/files#g" "$tmp"
  sudo sed -i "s#\\\$ROOT_DIR/lists#${OPT_REPO}/ipset#g" "$tmp"
  sudo sed -i "s#\\\$ROOT_DIR#${OPT_REPO}#g" "$tmp"
  sudo sed -i "s#/lists/#${OPT_REPO}/ipset/#g" "$tmp"
  sudo sed -i 's/NFQWS_PORTS_TCP=""/NFQWS_PORTS_TCP=""/g' "$tmp"
  sudo sed -i 's/NFQWS_PORTS_UDP=""/NFQWS_PORTS_UDP=""/g' "$tmp"
  sudo sed -i 's/NFQWS_PORTS_TCP="\([^"]\)/NFQWS_PORTS_TCP="\1/g' "$tmp"
  sudo sed -i 's/NFQWS_PORTS_UDP="\([^"]\)/NFQWS_PORTS_UDP="\1/g' "$tmp"
}

sanitize_strategy_config() {
  local cfg_file="$1"
  # Clean up TCP%/UDP% artifacts from converted Windows strategies
  if [ -f "$cfg_file" ]; then
    sudo sed -i 's/--filter-tcp=\([0-9,-]*\)TCP%/--filter-tcp=\1/g' "$cfg_file"
    sudo sed -i 's/--filter-udp=\([0-9,-]*\)UDP%/--filter-udp=\1/g' "$cfg_file"
  fi
}

load_binaries() {
  clear_screen

  if ! clone_opt_repo_if_needed; then
    echo "Не удалось подготовить /opt/zapret — отмена."
    read -rp "Нажмите Enter..."
    return
  fi

  copy_files_replace_to_opt || true

  local files_fake_dir="${OPT_REPO}/files/fake"
  local ipset_dir="${OPT_REPO}/ipset"
  local backup_suffix=".backup"

  sudo mkdir -p "$files_fake_dir" "$ipset_dir"

  # copy all lists
  if [ -d "${REPO_ROOT}/lists" ]; then
    for src_list in "${REPO_ROOT}/lists"/*.txt; do
      [ -f "$src_list" ] || continue
      lst_name=$(basename "$src_list")
      tgt="$ipset_dir/$lst_name"
      tgt_backup="${tgt}${backup_suffix}"
      if [ -f "$tgt" ]; then
        if ! sudo cmp -s "$src_list" "$tgt"; then
          if [ ! -f "$tgt_backup" ]; then
            sudo cp -a "$tgt" "$tgt_backup"
          fi
          sudo cp -a "$src_list" "$tgt"
        fi
      else
        sudo cp -a "$src_list" "$tgt"
      fi
    done
  fi

  # copy all .bin files
  if [ -d "${REPO_ROOT}/bin" ]; then
    for src_bin in "${REPO_ROOT}/bin"/*.bin; do
      [ -f "$src_bin" ] || continue
      bin_name=$(basename "$src_bin")
      tgt_bin="$files_fake_dir/$bin_name"
      tgt_bin_backup="${tgt_bin}${backup_suffix}"
      if [ -f "$tgt_bin" ]; then
        if ! sudo cmp -s "$src_bin" "$tgt_bin"; then
          if [ ! -f "$tgt_bin_backup" ]; then
            sudo cp -a "$tgt_bin" "$tgt_bin_backup"
          fi
          sudo cp -a "$src_bin" "$tgt_bin"
        fi
      else
        sudo cp -a "$src_bin" "$tgt_bin"
      fi
    done
  fi

  echo "Файлы ipset и бинари загружены в /opt/zapret." 
  read -rp "Нажмите Enter для возврата в меню..."
}

copy_files_replace_to_opt() {
  if ! clone_opt_repo_if_needed; then
    echo "Не удалось подготовить /opt/zapret — отмена."
    return 1
  fi

  local files_fake_dir="${OPT_REPO}/files/fake"
  local ipset_dir="${OPT_REPO}/ipset"

  sudo mkdir -p "$files_fake_dir" "$ipset_dir"

  if [ -d "${REPO_ROOT}/lists" ]; then
    for src_list in "${REPO_ROOT}/lists"/*.txt; do
      [ -f "$src_list" ] || continue
      lst_name=$(basename "$src_list")
      tgt="$ipset_dir/$lst_name"
      sudo cp -af "$src_list" "$tgt"
    done
  fi

  if [ -d "${REPO_ROOT}/bin" ]; then
    for src_bin in "${REPO_ROOT}/bin"/*.bin; do
      [ -f "$src_bin" ] || continue
      bin_name=$(basename "$src_bin")
      tgt_bin="$files_fake_dir/$bin_name"
      sudo cp -af "$src_bin" "$tgt_bin"
    done
  fi

  return 0
}

replace_placeholders() {
  local file="$1"
  sed -E -i 's/%BIN%/\$ROOT_DIR\/bin/g' "$file"
  sed -E -i 's/%LISTS%/\$ROOT_DIR\/lists/g' "$file"
}

copy_missing_files_to_opt() {
  local config_file="$1"
  local files_fake_dir="${OPT_REPO}/files/fake"
  local ipset_dir="${OPT_REPO}/ipset"
  local backup_suffix=".backup"

  sudo mkdir -p "$files_fake_dir" "$ipset_dir"

  mapfile -t lists < <(
    grep -oE '[%$A-Za-z0-9_./{}:-]+\.txt' "$config_file" \
      | sed -E -e 's@^.*/@@' -e 's/^%[^%]+%//' -e 's/^\$[A-Za-z_][A-Za-z0-9_]*\///' -e 's/^\$\{[^}]+\}\///' -e 's@^/opt/zapret/ipset/@@' \
      | sort -u || true
  )
  for lst in "${lists[@]}"; do
    local src="${REPO_ROOT}/lists/${lst}"
    local tgt="${ipset_dir}/${lst}"
    local tgt_backup="${tgt}${backup_suffix}"

    if [ ! -f "$src" ]; then
      continue
    fi

    if [ -f "$tgt" ]; then
      if ! sudo cmp -s "$src" "$tgt"; then
        if [ ! -f "$tgt_backup" ]; then
          sudo cp -a "$tgt" "$tgt_backup"
        fi
        sudo cp -a "$src" "$tgt"
      fi
    else
      sudo cp -a "$src" "$tgt"
    fi
  done

  mapfile -t bins < <(grep -oE "[^ \"'=]+\.bin" "$config_file" | sed -E 's@^.*/@@' | sort -u || true)
  for binfile in "${bins[@]}"; do

    [ -z "$binfile" ] && continue
    local src_bin="$REPO_ROOT/bin/$binfile"
    local tgt_bin="$files_fake_dir/$binfile"
    local tgt_bin_backup="${tgt_bin}${backup_suffix}"

    if [ ! -f "$src_bin" ]; then

      continue
    fi

    if [ -f "$tgt_bin" ]; then
      if ! sudo cmp -s "$src_bin" "$tgt_bin"; then
        if [ ! -f "$tgt_bin_backup" ]; then
          sudo cp -a "$tgt_bin" "$tgt_bin_backup"
        fi
        sudo cp -a "$src_bin" "$tgt_bin"
      fi
    else
      sudo cp -a "$src_bin" "$tgt_bin"
    fi
  done
}

manage_files() {
  while true; do
    clear_screen

    local local_hosts="$REPO_ROOT/.service/hosts"
    local hosts_status="(none)"
    if [ -f "$local_hosts" ]; then
      local ips=$(awk '{print $1}' "$local_hosts" | sort | uniq)
      local added=true
      for ip in $ips; do
        if ! grep -q "^$ip " /etc/hosts; then
          added=false
          break
        fi
      done
      if [ "$added" = true ]; then
        hosts_status="(loaded)"
      fi
    fi

    local list_file="$REPO_ROOT/lists/ipset-all.txt"
    local ipset_status="any"
    if [ -f "$list_file" ]; then
      local line_count=$(wc -l < "$list_file")
      if [ "$line_count" -eq 0 ]; then
        ipset_status="any"
      elif grep -q "^203\.0\.113\.113/32$" "$list_file"; then
        ipset_status="none"
      else
        ipset_status="loaded"
      fi
    fi

    echo "Updates:"
    echo "  1) Check for Updates"
    echo ""
    echo "Hosts:"
    echo "  2) Add/Remove records $hosts_status"
    echo "  3) Update locale file hosts"
    echo ""
    echo "IPSet:"
    echo "  4) Toggle IPSet Filter ($ipset_status)"
    echo "  5) Update IPSet List"
    echo ""
    echo "  6) Back"
    echo ""

    read -rp "Choose an option: " choice
    case "$choice" in
      0)
        check_for_updates
        ;;
      1)
        if [ ! -f "$local_hosts" ]; then
          echo "Local hosts file not found. Please update it first."
          read -rp "Press Enter..."
          continue
        fi
        local ips=$(awk '{print $1}' "$local_hosts" | sort | uniq)
        local added=true
        for ip in $ips; do
          if ! grep -q "^$ip " /etc/hosts; then
            added=false
            break
          fi
        done
        if [ "$added" = true ]; then
          for ip in $ips; do
            sudo sed -i "/^$ip /d" /etc/hosts
          done
          echo "Records removed from /etc/hosts"
        else
          sudo sh -c "cat '$local_hosts' >> /etc/hosts"
          echo "Records added to /etc/hosts"
        fi
        read -rp "Press Enter..."
        ;;
      2)
        mkdir -p "$REPO_ROOT/.service"
        local hosts_url="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts"
        if curl -L -o "$local_hosts" "$hosts_url"; then
          echo "Local hosts file updated: $local_hosts"
        else
          echo "Failed to download hosts file"
        fi
        read -rp "Press Enter..."
        ;;
      3)
        local backup_file="$list_file.backup"
        mkdir -p "$REPO_ROOT/lists"
        if [ "$ipset_status" = "loaded" ]; then
          echo "Switching to none..."
          if [ ! -f "$backup_file" ]; then
            mv "$list_file" "$backup_file"
          fi
          echo "203.0.113.113/32" > "$list_file"
          echo "Mode switched to none"
        elif [ "$ipset_status" = "none" ]; then
          echo "Switching to any..."
          > "$list_file"
          echo "Mode switched to any"
        elif [ "$ipset_status" = "any" ]; then
          echo "Switching to loaded..."
          if [ -f "$backup_file" ]; then
            mv "$backup_file" "$list_file"
            echo "Mode switched to loaded (from backup)"
          else
            echo "Error: No backup available for restoration. Please update the list first."
          fi
        fi
        read -rp "Press Enter..."
        ;;
      4)
        echo "Updating IPSet list..."
        local url="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"
        local backup_file="$list_file.backup"
        mkdir -p "$REPO_ROOT/lists"

        local mode_changed=false
        if [ "$ipset_status" != "loaded" ]; then
          if [ -f "$backup_file" ]; then
            mv "$backup_file" "$list_file"
          else
            : > "$list_file"
          fi
          mode_changed=true
        fi

        if curl -L -o "$list_file" "$url"; then
          if [ "$mode_changed" = true ]; then
            echo "Список IPSet обновлен. Режим переключен на loaded."
          else
            echo "Список IPSet обновлен."
          fi
        else
          echo "Не удалось скачать список IPSet"
        fi
        read -rp "Нажмите Enter..."
        ;;
      5)
        break
        ;;
      *)
        echo "Неверный выбор."
        read -rp "Нажмите Enter..."
        ;;
    esac
  done
}

show_menu() {
  clear_screen

  local gf_status="(отключен)"
  if [ -f "$GAMEFLAG_FILE" ]; then
    local gf_mode=$(cat "$GAMEFLAG_FILE" | tr -d '\n' || echo "disabled")
    case "$gf_mode" in
      all)
        gf_status="(TCP и UDP)"
        ;;
      tcp)
        gf_status="(только TCP)"
        ;;
      udp)
        gf_status="(только UDP)"
        ;;
      *)
        gf_status="(отключен)"
        ;;
    esac
  fi

  local ar_status="(выключена)"
  if [ -f "$AUTORUN_FLAG" ]; then ar_status="(включена)"; fi

  cat <<MENU
Выберите действие:
1) On/Off strategy
2) Install strategies
3) Convert strategies
4) Status service
5) Toggle autorun $ar_status
6) Toggle game filter $gf_status
7) Manage Files
8) Exit

0) Delete Zapret
MENU
  read -rp "Ваш выбор: " choice
  case "$choice" in
    1) manage_strategy ;;
    2) install_selected_strategy ;;
    3) convert_strategies ;;
    4) service_status ;;
    5) toggle_autorun ;;
    6) toggle_gamefilter ;;
    7) manage_files ;;
    8) clear_screen; echo "Выход."; exit 0 ;;
    0) delete_zapret ;;
    *) echo "Неверный выбор."; read -rp "Нажмите Enter...";;
  esac
}




convert_strategies() {
  clear_screen
  
  if ! ensure_convert; then
    echo "Конвертер отсутствует или не исполняем — отмена."
    read -rp "Нажмите Enter..."
    return
  fi

  echo "Конвертация стратегий..."
  if bash "$CONVERT_SCRIPT"; then
    echo "Конвертация стратегий завершена успешно."
  else
    echo "Конвертация стратегий завершилась с ошибкой."
  fi
  
  read -rp "Нажмите Enter для возврата в меню..."
}

install_selected_strategy() {
  clear_screen
  
  if ! clone_opt_repo_if_needed; then
    echo "Не удалось подготовить /opt/zapret — отмена."
    read -rp "Нажмите Enter..."
    return
  fi

  strategies=()
  for file in "$STRAT_DIR"/*.sh; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    [[ "$name" == "convert-strategies.sh" ]] && continue
    strategies+=("$name")
  done
  mapfile -t strategies < <(printf '%s\n' "${strategies[@]}" | sort)

  if [ "${#strategies[@]}" -eq 0 ]; then
    echo "Стратегии не найдены в $STRAT_DIR"
    read -rp "Нажмите Enter..."
    return
  fi

  clear_screen

  echo "Доступные стратегии:"
  echo ""

  local max_len=0
  for strat in "${strategies[@]}"; do
    len=${#strat}
    (( len > max_len )) && max_len=$len
  done
  local width=$((max_len + 5))

  local cols=3
  local rows=$(( (${#strategies[@]} + cols - 1) / cols ))

  for ((i=0; i<rows; i++)); do
    for ((j=0; j<cols; j++)); do
      local pos=$((j * rows + i))
      if [ $pos -lt ${#strategies[@]} ]; then
        local num=$((pos + 1))
        printf "%-${width}s" "$num) ${strategies[$pos]}"
      fi
    done
    echo ""
  done

  local idx=$((${#strategies[@]} + 1))
  echo ""
  echo "$idx) Отмена"
  echo ""
  
  while true; do
    read -rp "Выберите стратегию (номер): " strat_choice
    if [[ "$strat_choice" =~ ^[0-9]+$ ]] && [ "$strat_choice" -ge 1 ] && [ "$strat_choice" -le "$idx" ]; then
      break
    fi
    echo "Неверный выбор. Повторите ввод."
  done

  if [ "$strat_choice" -eq "$idx" ]; then
    return
  fi

  local selected_idx=$((strat_choice-1))
  local selected_strategy="${strategies[$selected_idx]}"
  local cfg_src="$STRAT_DIR/$selected_strategy"
  clear_screen
  echo "Как установить стратегию?"
  echo "1) С автозагрузкой"
  echo "2) Без автозагрузки"
  echo ""
  
  while true; do
    read -rp "Выберите (1 или 2): " autorun_choice
    if [[ "$autorun_choice" =~ ^[12]$ ]]; then
      break
    fi
    echo "Неверный выбор. Введите 1 или 2."
  done

  if [ "$autorun_choice" -eq 1 ]; then
    touch "$AUTORUN_FLAG"
  fi

  echo "$selected_strategy" > "$REPO_ROOT/.active_strategy"

  sudo cp -a "$cfg_src" "$OPT_REPO/config"
  sanitize_strategy_config "${OPT_REPO}/config"

  copy_missing_files_to_opt "${OPT_REPO}/config" || true
  apply_gamefilter_to_file "${OPT_REPO}/config" || true
  finalize_for_opt "${OPT_REPO}/config" || true

  if [ -x "$OPT_REPO/install_easy.sh" ]; then
    sudo bash "$OPT_REPO/install_easy.sh" || {
      echo "Ошибка при запуске install_easy.sh"
      read -rp "Нажмите Enter..."
      return
    }
  else
    echo "Предупреждение: install_easy.sh не найден или не исполняемый в $OPT_REPO"
  fi

  echo "Установка стратегии завершена."
  read -rp "Нажмите Enter для возврата в меню..."
}

while true; do
  show_menu
done

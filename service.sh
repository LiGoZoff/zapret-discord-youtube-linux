#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$REPO_ROOT/bin"
CONVERT_SCRIPT="$REPO_ROOT/linux-strategies/convert-strategies.sh"
STRAT_DIR="$REPO_ROOT/linux-strategies"
GAMEFLAG_FILE="$REPO_ROOT/.gamefilter_mode"
AUTORUN_FLAG="$REPO_ROOT/.autorun_enabled"
LOCAL_VERSION_FILE="$REPO_ROOT/.service/version.txt"
LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE" 2>/dev/null || echo "unknown")
OPT_REPO="/opt/zapret"

clear_screen() { printf '\033c'; }

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

ensure_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    if sudo -v 2>/dev/null; then
      clear_screen
    else
      clear_screen
    fi
  fi
}

ipset_get_status() {
  local lf="$REPO_ROOT/lists/ipset-all.txt"
  if [ ! -f "$lf" ]; then
    printf '%s' "any"
    return
  fi

  local cnt
  cnt=$(grep -v '^[[:space:]]*$' "$lf" | grep -v '^#' | wc -l 2>/dev/null || echo 0)

  cnt="$(printf '%s' "$cnt" | tr -cd '0-9')"
  if [ -z "$cnt" ]; then cnt=0; fi
  if [ "$cnt" -eq 0 ]; then
    printf '%s' "any"
    return
  fi
  if [ "$cnt" -eq 1 ]; then
    local first
    first=$(grep -v '^[[:space:]]*$' "$lf" | grep -v '^#' | head -n1 | tr -d '\r' || true)
    if [ "$first" = "203.0.113.113/32" ]; then
      printf '%s' "none"
      return
    fi
  fi
  
  if [ -f "$REPO_ROOT/lists/ipset-all.txt.backup" ]; then
  
    if grep -q "^203\.0\.113\.113/32$" "$lf" 2>/dev/null && [ $(grep -v '^[[:space:]]*$' "$lf" | grep -v '^#' | wc -l 2>/dev/null || echo 0) -le 1 ]; then
      printf '%s' "none"
      return
    fi
  fi
  printf '%s' "loaded"
}

check_update_available() {
  local local_v remote_v url
  local_v=$(cat "$REPO_ROOT/.service/version.txt" 2>/dev/null || echo "")
  local_v="$(printf '%s' "$local_v" | tr -d '\r\n')"

  url="https://raw.githubusercontent.com/LiGoZoff/zapret-discord-youtube-linux/refs/heads/main/.service/version.txt"
  remote_v=$(curl -fsSL "$url" 2>/dev/null || echo "")
  remote_v="$(printf '%s' "$remote_v" | tr -d '\r\n')"

  if [ -z "$remote_v" ]; then
    return 1
  fi

  if [ "$local_v" != "$remote_v" ]; then
    return 0
  fi
  return 1
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
    local install_out
    # Добавлен timeout чтобы отлавливать бесконечный луп ввода yes ''
    install_out=$(sudo timeout 15s bash -c "yes '' | bash '$OPT_REPO/install_easy.sh'" 2>&1)
    
    if ! sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
      clear_screen
      echo -e "\033[0;31mОшибка: Стратегия $strategy не смогла запуститься!\033[0m"
      
      local err_line=$(echo "$install_out" | grep -iE 'error|ошибка|not found|no such file|invalid|missing' | tail -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$err_line" ]; then
          err_line=$(sudo systemctl status zapret.service --no-pager | grep -iE 'error|ошибка|failed' | tail -n 1)
      fi
      if [ -z "$err_line" ]; then err_line="Проверьте правильность параметров или наличие бинарников/листов IPset."; fi
      
      echo -e "\n\033[1;33mПричина ошибки:\033[0m"
      echo "$err_line"
      echo ""
      read -rp "Нажмите Enter для возврата..."
      return
    fi
  else
    echo "Предупреждение: install_easy.sh не найден или не исполняемый в $OPT_REPO"
  fi

  echo "Переустановка стратегии завершена."
  read -rp "Нажмите Enter для возврата в меню..."
}

_uninstall_strategy() {
  if sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
    sudo systemctl stop zapret.service
    sudo systemctl disable zapret.service
    echo "Сервис zapret остановлен."
  else
    echo "Сервис уже выключен."
  fi
  rm -f "$AUTORUN_FLAG"
  read -rp "Нажмите Enter для возврата в меню..."
}

delete_zapret() {
  clear_screen
  read -rp "Вы уверены, что хотите полностью удалить Zapret и все изменения? (y/N): " confirm
  case "$confirm" in
    y|Y) ;;
    *) echo "Отмена."; read -rp "Нажмите Enter..."; return ;;
  esac

  echo "Останавливаю и отключаю службу zapret.service (если активна)..."
  if sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
    sudo systemctl stop zapret.service || true
  fi
  sudo systemctl disable zapret.service 2>/dev/null || true

  echo "Удаляю unit-файл и перезагружаю демон systemd..."
  sudo rm -f /etc/systemd/system/zapret.service || true
  sudo systemctl daemon-reload || true

  echo "Восстанавливаю /etc/hosts из бэкапа, если он есть..."
  if [ -f "/etc/hosts.zapret.bak" ]; then
    sudo cp -f /etc/hosts.zapret.bak /etc/hosts || true
    sudo rm -f /etc/hosts.zapret.bak || true
  fi

  echo "Удаляю локальные флаги и временные файлы..."
  sudo rm -f "$REPO_ROOT/.active_strategy" || true
  sudo rm -f "$AUTORUN_FLAG" || true
  sudo rm -f "$GAMEFLAG_FILE" || true
  sudo rm -f "$REPO_ROOT/results.txt" || true

  list_file="$REPO_ROOT/lists/ipset-all.txt"
  backup_file="$list_file.backup"
  mkdir -p "$(dirname "$list_file")"
  if [ -f "$list_file" ]; then
    if grep -q "^203\.0\.113\.113/32$" "$list_file" 2>/dev/null; then
      :
    else
      if [ ! -f "$backup_file" ]; then
        sudo mv -f "$list_file" "$backup_file" || sudo cp -a "$list_file" "$backup_file" || true
      else
        sudo cp -a "$list_file" "${backup_file}.$(date +%s)" || true
      fi
      printf '%s\n' "203.0.113.113/32" | sudo tee "$list_file" >/dev/null || true
    fi
  else
    printf '%s\n' "203.0.113.113/32" | sudo tee "$list_file" >/dev/null || true
  fi

  echo "Очищаю папку linux-strategies (оставляю пустой каталог)..."
  if [ -d "$STRAT_DIR" ]; then
    converter_name=$(basename "$CONVERT_SCRIPT")
    shopt -s nullglob dotglob
    for p in "$STRAT_DIR"/*; do
      [ -e "$p" ] || continue
      name=$(basename "$p")
      if [ "$name" != "$converter_name" ]; then
        sudo rm -rf "$p" || true
      fi
    done
    shopt -u nullglob dotglob || true
  fi

  echo "Удаляю каталог /opt/zapret (если есть)..."
  sudo rm -rf "$OPT_REPO" || true

  echo "Все связанные системные изменения удалены. Можно безопасно удалить локальную папку репозитория, если нужно."
  read -rp "Нажмите Enter..."
  exit 0
}

clone_opt_repo_if_needed() {
  if [ -d "$OPT_REPO" ]; then
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
     sudo bash -c "yes '' | bash '$OPT_REPO/install_prereq.sh'" || true
  else
    echo "Предупреждение: install_prereq.sh не найден или не исполняемый"
  fi

  if [ -x "$OPT_REPO/install_bin.sh" ]; then
    echo "Запускаю install_bin.sh ..."
     sudo bash -c "yes '' | bash '$OPT_REPO/install_bin.sh'" || true
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

utilities_menu() {
  while true; do
    clear_screen
    echo "Utilities:"
    echo "  1) Конвертация стратегий"
    echo "  2) Тест стратегий (полный)"
    echo "  3) Тест стратегий (быстрый)"
    echo "  4) Back"
    echo ""
    read -rp "Выберите опцию: " uchoice
    case "$uchoice" in
      1)
        convert_strategies ;;
      2)
        clear_screen
        if [ "$(id -u)" -ne 0 ]; then
          sudo bash "$REPO_ROOT/utils/checker.sh" interactive
        else
          bash "$REPO_ROOT/utils/checker.sh" interactive
        fi
        read -rp "Нажмите Enter для возврата..." ;;
      3)
        clear_screen
        if [ "$(id -u)" -ne 0 ]; then
          sudo bash "$REPO_ROOT/utils/checker.sh" fast
        else
          bash "$REPO_ROOT/utils/checker.sh" fast
        fi
        read -rp "Нажмите Enter для возврата..." ;;
      4) return ;;
      *) echo "Неверный выбор."; read -rp "Нажмите Enter..." ;;
    esac
  done
}

settings_menu() {
  while true; do
    clear_screen
    local autorun_state="(выключена)"
    if [ -f "$AUTORUN_FLAG" ]; then autorun_state="(включена)"; fi

    local gf_state="(отключен)"
    if [ -f "$GAMEFLAG_FILE" ]; then
      gf_content=$(cat "$GAMEFLAG_FILE" 2>/dev/null || echo "")
      case "$gf_content" in
        all) gf_state="(включен - TCP и UDP)" ;;
        tcp) gf_state="(включен - только TCP)" ;;
        udp) gf_state="(включен - только UDP)" ;;
        *) gf_state="(отключен)" ;;
      esac
    fi

    local ipset_state="($(ipset_get_status))"

    local hosts_state="(выключен)"
    if [ -f "$REPO_ROOT/.service/hosts" ]; then
      local ips=$(awk '{print $1}' "$REPO_ROOT/.service/hosts" | sort | uniq)
      local added=true
      for ip in $ips; do
        if ! grep -q "^$ip " /etc/hosts; then added=false; break; fi
      done
      if [ "$added" = true ]; then hosts_state="(включен)"; fi
    fi

    echo "Настройки:"
    echo "  1) Toggle autorun"
    echo "  2) Toggle game filter $gf_state"
    echo "  3) Toggle IPSet $ipset_state"
    echo "  4) Toggle Hosts $hosts_state"
    echo "  5) Back"
    echo ""
    read -rp "Выберите опцию: " sch
    case "$sch" in
      1) toggle_autorun ;;
      2) toggle_gamefilter ;;
      3) toggle_ipset ;;
      4) toggle_hosts ;;
      5) return ;;
      *) echo "Неверный выбор."; read -rp "Нажмите Enter..." ;;
    esac
  done
}

toggle_hosts() {
  local local_hosts="$REPO_ROOT/.service/hosts"
  local backup="/etc/hosts.zapret.bak"
  if [ ! -f "$local_hosts" ]; then
    echo "Локальный hosts не найден: $local_hosts"
    read -rp "Нажмите Enter..."; return
  fi
  if [ -f "$backup" ]; then
    echo "Восстанавливаю /etc/hosts из $backup";
    sudo cp -f "$backup" /etc/hosts || echo "Не удалось восстановить /etc/hosts"
    sudo rm -f "$backup" || true
    echo "Hosts восстановлен."
  else
    sudo cp -a /etc/hosts "$backup" || echo "Не удалось создать бэкап /etc/hosts"
    sudo sh -c "cat '$local_hosts' >> /etc/hosts" || echo "Не удалось применить локальный hosts"
    echo "Hosts применён."
  fi
}

toggle_gamefilter() {
  local mode=""
  if [ -f "$GAMEFLAG_FILE" ]; then
    mode=$(cat "$GAMEFLAG_FILE" 2>/dev/null | tr -d '\n' || echo "")
  fi

  case "$mode" in
    "")
      echo "all" > "$GAMEFLAG_FILE" && echo "Game filter set: включен (TCP и UDP)" || echo "Не удалось установить gamefilter" ;;
    all)
      echo "tcp" > "$GAMEFLAG_FILE" && echo "Game filter set: включен (только TCP)" || echo "Не удалось установить gamefilter" ;;
    tcp)
      echo "udp" > "$GAMEFLAG_FILE" && echo "Game filter set: включен (только UDP)" || echo "Не удалось установить gamefilter" ;;
    udp)
      rm -f "$GAMEFLAG_FILE" && echo "Game filter disabled" || echo "Не удалось отключить gamefilter" ;;
    *)
      rm -f "$GAMEFLAG_FILE" && echo "Game filter disabled" || echo "Не удалось отключить gamefilter" ;;
  esac
}

toggle_autorun() {
  if [ -f "$AUTORUN_FLAG" ]; then
    rm -f "$AUTORUN_FLAG" && echo "Autorun выключен." || echo "Не удалось удалить $AUTORUN_FLAG"
  else
    touch "$AUTORUN_FLAG" && echo "Autorun включен." || echo "Не удалось создать $AUTORUN_FLAG"
  fi
}

toggle_ipset() {
  local list_file="$REPO_ROOT/lists/ipset-all.txt"
  local backup="$list_file.backup"
  sudo mkdir -p "$REPO_ROOT/lists"
  if [ ! -f "$list_file" ]; then sudo tee "$list_file" </dev/null >/dev/null; fi

  local status
  status="$(ipset_get_status)"

  case "$status" in
    loaded)
      echo "Switching ipset -> none"
      if [ ! -f "$backup" ]; then sudo mv "$list_file" "$backup" || true; fi
      printf '%s\n' "203.0.113.113/32" | sudo tee "$list_file" >/dev/null || true
      ;;
    none)
      echo "Switching ipset -> any"
      sudo tee "$list_file" </dev/null >/dev/null || true
      ;;
    any)
      echo "Switching ipset -> loaded"
      if [ -f "$backup" ]; then sudo mv "$backup" "$list_file" || true; else echo "No backup available"; fi
      ;;
  esac
}

update_lists_and_hosts() {
  echo "Updating all lists and hosts from FlowSeal..."
  tmpzip="/tmp/flowseal_lists.zip"
  tmpd=$(mktemp -d)
  repo="https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip"

  if curl -fsSL "$repo" -o "$tmpzip"; then
    unzip -q "$tmpzip" -d "$tmpd" || true
    find "$tmpd" -type f -path "*/lists/*" -print0 | while IFS= read -r -d '' lf; do
      dest="$REPO_ROOT/lists/$(basename "$lf")"
      cp -af "$lf" "$dest" || echo "Failed copy $lf"
    done
    hs=$(find "$tmpd" -type f -path "*/.service/hosts" -print -quit || true)
    if [ -n "$hs" ]; then
      cp -af "$hs" "$REPO_ROOT/.service/hosts" || echo "Failed copy hosts"
    else
      curl -fsSL "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts" -o "$REPO_ROOT/.service/hosts" || true
    fi
  else
    echo "Failed to download repository zip for lists. Trying raw fetch..."
    curl -fsSL "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts" -o "$REPO_ROOT/.service/hosts" || true
  fi

  rm -f "$tmpzip"
  rm -rf "$tmpd"
  echo "Успех."
  read -rp "Нажмите Enter..."
}

check_for_updates() {
  clear_screen
  if ! command -v git >/dev/null 2>&1 || [ ! -d "$REPO_ROOT/.git" ]; then
    echo "Git не доступен или репозиторий не является git-рабочей копией. Обновляйте вручную или через zip." 
    read -rp "Нажмите Enter..."
    return
  fi

  echo "Подготовка обновления репозитория (git fetch)..."
  git -C "$REPO_ROOT" fetch --prune || true

  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  remote_ref="origin/$branch"

  mapfile -t local_untracked < <(git -C "$REPO_ROOT" ls-files -o --exclude-standard || true)
  mapfile -t remote_files < <(git -C "$REPO_ROOT" ls-tree -r --name-only "$remote_ref" 2>/dev/null || true)

  conflicted=()
  SAVED_CONFLICT_DIR=""
  if [ ${#local_untracked[@]} -gt 0 ] && [ ${#remote_files[@]} -gt 0 ]; then
    for f in "${local_untracked[@]}"; do
      for rf in "${remote_files[@]}"; do
        [ "$f" = "$rf" ] && conflicted+=("$f") && break
      done
    done
  fi

  if [ ${#conflicted[@]} -gt 0 ]; then
    echo "Обнаружены неотслеживаемые локальные файлы, которые конфликтуют с обновлением:" 
    for f in "${conflicted[@]:0:20}"; do echo "  $f"; done
    if [ ${#conflicted[@]} -gt 20 ]; then echo "  ... and ${#conflicted[@]} more"; fi
    echo "Выберите действие: (1) Перезаписать локальные файлы  (2) Сохранить их во временную папку и продолжить  (3) Отмена"
    read -rp "Ваш выбор [1/2/3]: " uchoice
    case "$uchoice" in
      1)
        echo "Перезапись локальных файлов..."
        for f in "${conflicted[@]}"; do rm -rf "$REPO_ROOT/$f" || true; done
        ;;
      2)
        tmpd=$(mktemp -d /tmp/zapret-local-backup-XXXX)
        SAVED_CONFLICT_DIR="$tmpd"
        echo "Копирование конфликтующих файлов в $tmpd"
        for f in "${conflicted[@]}"; do
          mkdir -p "$(dirname "$tmpd/$f")"
          mv "$REPO_ROOT/$f" "$tmpd/$f" || true
        done
        echo "Файлы сохранены в $tmpd и будут автоматически восстановлены после успешного обновления."
        ;;
      *)
        echo "Отмена обновления."
        read -rp "Нажмите Enter..."
        return
        ;;
    esac
  fi

  echo "Выполняю git pull..."
  if git -C "$REPO_ROOT" pull --rebase --autostash; then
    echo "Обновление завершено успешно."
    if [ -n "${SAVED_CONFLICT_DIR-}" ] && [ -d "$SAVED_CONFLICT_DIR" ]; then
      echo "Восстанавливаю сохранённые локальные файлы из $SAVED_CONFLICT_DIR ..."
      find "$SAVED_CONFLICT_DIR" -type f -print0 | while IFS= read -r -d '' sf; do
        rel=${sf#"$SAVED_CONFLICT_DIR"/}
        mkdir -p "$(dirname "$REPO_ROOT/$rel")"
        if [ -f "$REPO_ROOT/$rel" ]; then
          cp -a "$REPO_ROOT/$rel" "$REPO_ROOT/${rel}.gitremote_backup.$(date +%s)" || true
        fi
        mv "$sf" "$REPO_ROOT/$rel" || cp -a "$sf" "$REPO_ROOT/$rel" || true
      done
      rm -rf "$SAVED_CONFLICT_DIR"
      echo "Файлы восстановлены."
    fi
  else
    echo "git pull завершился с ошибкой. Проверьте вручную." 
  fi
  read -rp "Нажмите Enter..."
}

update_binaries() {
  echo "Updating binaries from FlowSeal..."
  tmp="/tmp/zapret_flowseal.zip"
  repo="https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip"
  if curl -fsSL "$repo" -o "$tmp"; then
    tmpd=$(mktemp -d)
    unzip -q "$tmp" -d "$tmpd" || true
    find "$tmpd" -type f -path "*/bin/*.bin" -exec cp -af {} "$REPO_ROOT/bin/" \; || true
    rm -rf "$tmpd"
  else
    echo "Failed to download repo"
  fi
  rm -f "$tmp"
  echo "Успех."
  read -rp "Нажмите Enter..."
}

update_strategies() {
  echo "Updating strategies (.bat) and running converter..."
  tmpd=$(mktemp -d)
  repo="https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip"
  zf="/tmp/flowseal_strats.zip"
  if curl -fsSL "$repo" -o "$zf"; then
    unzip -q "$zf" -d "$tmpd" || true
    find "$tmpd" -type f -path "*/windows-strategies/*.bat" -print0 | while IFS= read -r -d '' bat; do
      name=$(basename "$bat")
      dest="$STRAT_DIR/$name"
      mkdir -p "$STRAT_DIR"
      sed -e 's#set "BIN=%~dp0bin\\"#set "BIN=%~dp0..\\bin\\"#g' \
          -e 's#set "LISTS=%~dp0lists\\"#set "LISTS=%~dp0..\\lists\\"#g' "$bat" > "$dest"
      echo "Wrote $dest"
    done

    if [ -x "$CONVERT_SCRIPT" ]; then
      bash "$CONVERT_SCRIPT"
    fi
  else
    echo "Failed to download strategies"
  fi
  rm -f "$zf"
  rm -rf "$tmpd"
  echo "Успех."
  read -rp "Нажмите Enter..."
}

updates_menu() {
  while true; do
    clear_screen
    echo "Обновления:"
    echo "  1) Обновление запрета"
    echo "  2) Обновить Hosts и Lists"
    echo "  3) Обновление Binaries"
    echo "  4) Обновление Strategies"
    echo "  5) Back"
    echo ""
    read -rp "Выберите опцию: " ucho
    case "$ucho" in
      1) check_for_updates ;;
      2) update_lists_and_hosts ;;
      3) update_binaries ;;
      4) update_strategies ;;
      5) return ;;
      *) echo "Неверный выбор."; read -rp "Нажмите Enter..." ;;
    esac
  done
}

show_menu() {
  clear_screen

  if [ "${UPDATE_AVAILABLE-0}" = "1" ]; then
    cols=$(tput cols 2>/dev/null || echo 80)
    msg=$'\033[32mДоступно обновление\033[0m'
    plain_msg="Доступно обновление"
    pad=$(( (cols - ${#plain_msg}) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s%s\n' "$pad" "" "$msg"
    echo ""
  fi

  local svc_state="Выключено"
  if sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
    svc_state="Включено"
    local active_strategy="Нет"
    if [ -f "$REPO_ROOT/.active_strategy" ]; then
      active_strategy=$(cat "$REPO_ROOT/.active_strategy" 2>/dev/null || echo "Нет")
      [ -z "$active_strategy" ] && active_strategy="Нет"
    fi
  else
    svc_state="Выключено"
    local active_strategy="Нет"
  fi

  local autorun_state="Выключен"
  if [ -f "$AUTORUN_FLAG" ]; then autorun_state="Включен"; fi

  printf 'Состояние: %s\n' "$svc_state"
  printf 'Автозапуск: %s\n' "$autorun_state"
  printf 'Активная стратегия: %s\n\n' "$active_strategy"

  cat <<MENU
[ 1 ] 🚀 Вкл/Выкл стратегию
[ 2 ] 📁 Установить стратегию
[ 3 ] ⚙️  Настройки
[ 4 ] 🔄 Обновления
[ 5 ] 🛠  Утилиты
[ 6 ] ❌ Выход

[ 0 ] 🗑 Удалить Zapret
MENU
  read -rp "Ваш выбор: " choice
  case "$choice" in
    1) manage_strategy ;;
    2) install_selected_strategy ;;
    3) settings_menu ;;
    4) updates_menu ;;
    5) utilities_menu ;;
    6) clear_screen; echo "Выход."; exit 0 ;;
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

  local idx=${#strategies[@]}
  echo ""
  echo "0) Отмена"
  echo ""
  
  while true; do
    read -rp "Выберите стратегию (номер): " strat_choice
    if [[ "$strat_choice" =~ ^[0-9]+$ ]] && [ "$strat_choice" -ge 0 ] && [ "$strat_choice" -le "$idx" ]; then
      break
    fi
    echo "Неверный выбор. Повторите ввод."
  done

  if [ "$strat_choice" -eq 0 ]; then
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
  else
    rm -f "$AUTORUN_FLAG"
  fi

  echo "$selected_strategy" | sudo tee "$REPO_ROOT/.active_strategy" >/dev/null

  sudo cp -a "$cfg_src" "$OPT_REPO/config"
  sanitize_strategy_config "${OPT_REPO}/config"

  copy_missing_files_to_opt "${OPT_REPO}/config" || true
  apply_gamefilter_to_file "${OPT_REPO}/config" || true
  finalize_for_opt "${OPT_REPO}/config" || true

  if [ -x "$OPT_REPO/install_easy.sh" ]; then
    local install_out
    install_out=$(sudo timeout 15s bash -c "yes '' | bash '$OPT_REPO/install_easy.sh'" 2>&1)
    
    if ! sudo systemctl is-active --quiet zapret.service 2>/dev/null; then
      clear_screen
      echo -e "\033[0;31mОшибка: Стратегия $selected_strategy не смогла запуститься!\033[0m"
      
      local err_line=$(echo "$install_out" | grep -iE 'error|ошибка|not found|no such file|invalid|missing' | tail -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$err_line" ]; then
          err_line=$(sudo systemctl status zapret.service --no-pager | grep -iE 'error|ошибка|failed' | tail -n 1)
      fi
      if [ -z "$err_line" ]; then err_line="Проверьте правильность параметров или наличие бинарников/листов IPset."; fi
      
      echo -e "\n\033[1;33mПричина ошибки:\033[0m"
      echo "$err_line"
      echo ""
      read -rp "Нажмите Enter для возврата..."
      return
    fi
  else
    echo "Предупреждение: install_easy.sh не найден или не исполняемый в $OPT_REPO"
  fi

  echo "Установка стратегии завершена."
  read -rp "Нажмите Enter для возврата в меню..."
}

ensure_sudo

if [ ! -d "$OPT_REPO" ]; then
  clone_opt_repo_if_needed || true
fi

copy_files_replace_to_opt || true

if [ -d "$STRAT_DIR" ]; then
  converter_name=$(basename "$CONVERT_SCRIPT")
  have_other=0
  shopt -s nullglob dotglob
  for f in "$STRAT_DIR"/*; do
    [ -e "$f" ] || continue
    bn=$(basename "$f")
    if [ "$bn" != "$converter_name" ]; then
      have_other=1
      break
    fi
  done
  shopt -u nullglob dotglob
  if [ "$have_other" -eq 0 ]; then
    if ensure_convert; then
      bash "$CONVERT_SCRIPT" || true
    fi
  fi
fi

if check_update_available; then
  UPDATE_AVAILABLE=1
else
  UPDATE_AVAILABLE=0
fi

while true; do
  show_menu
done

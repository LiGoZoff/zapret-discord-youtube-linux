#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(readlink -f "$SCRIPT_DIR")"
BIN_DIR="$REPO_ROOT/bin"
CONVERT_SCRIPT="$REPO_ROOT/linux-strategies/convert-strategies.sh"
STRAT_DIR="$REPO_ROOT/linux-strategies"
GAMEFLAG_FILE="$REPO_ROOT/.gamefilter_enabled"
OPT_REPO="/opt/zapret"

IPSET_LIST_FILE="$REPO_ROOT/lists/ipset-all.txt"
IPSET_BACKUP_SUFFIX=".backup"

clear_screen() { printf '\033c'; }

ensure_convert() {
  if [ ! -x "$CONVERT_SCRIPT" ]; then
    echo "Конвертер не найден или не исполняемый: $CONVERT_SCRIPT" >&2
    return 1
  fi
  return 0
}

toggle_gamefilter() {
  clear_screen
  if [ -f "$GAMEFLAG_FILE" ]; then
    rm -f "$GAMEFLAG_FILE"
  else
    touch "$GAMEFLAG_FILE"
  fi
}

service_status() {
  clear_screen
  echo "=== Status Service ==="
  echo ""
  
  sudo systemctl status zapret.service
  
  echo ""
  echo "=== Active Strategy ==="
  if [ -f "$REPO_ROOT/.active_strategy" ]; then
    active_strategy=$(cat "$REPO_ROOT/.active_strategy")
    echo "Активная стратегия: $active_strategy"
  else
    echo "Активная стратегия: не установлена"
  fi
  echo ""
  
  read -rp "Нажмите Enter для возврата в меню..."
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

  local gf_enabled=0
  if [ -f "$GAMEFLAG_FILE" ]; then gf_enabled=1; fi

  if [ "$gf_enabled" -eq 1 ]; then
    seen_tcp["1024-65535"]=1
    seen_udp["1024-65535"]=1
  else
    unset 'seen_tcp[1024-65535]'
    unset 'seen_udp[1024-65535]'
  fi

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

  sudo sed -i "s#\\\$ROOT_DIR/files#${OPT_REPO}/files#g" "$tmp"
  sudo sed -i "s#\\\$ROOT_DIR/lists#${OPT_REPO}/ipset#g" "$tmp"
  sudo sed -i "s#\\\$ROOT_DIR#${OPT_REPO}#g" "$tmp"
  sudo sed -i "s#/lists/#${OPT_REPO}/ipset/#g" "$tmp"
  sudo sed -i 's/NFQWS_PORTS_TCP=""/NFQWS_PORTS_TCP=""/g' "$tmp"
  sudo sed -i 's/NFQWS_PORTS_UDP=""/NFQWS_PORTS_UDP=""/g' "$tmp"
  sudo sed -i 's/NFQWS_PORTS_TCP="\([^"]\)/NFQWS_PORTS_TCP="\1/g' "$tmp"
  sudo sed -i 's/NFQWS_PORTS_UDP="\([^"]\)/NFQWS_PORTS_UDP="\1/g' "$tmp"
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

  mapfile -t bins < <(grep -oE '[^ "=/]+\.bin' "$config_file" | sort -u || true)
  for bin in "${bins[@]}"; do
    local src=""
    if [ -f "$REPO_ROOT/files/$bin" ]; then
      src="$REPO_ROOT/files/$bin"
    elif [ -f "$REPO_ROOT/bin/$bin" ]; then
      src="$REPO_ROOT/bin/$bin"
    elif [ -f "$REPO_ROOT/$bin" ]; then
      src="$REPO_ROOT/$bin"
    fi
    if [ -n "$src" ] && [ -f "$src" ]; then
      if [ ! -f "${files_fake_dir}/${bin}" ]; then
        sudo cp -a "$src" "$files_fake_dir/"
      fi
    fi
  done

  mapfile -t lists < <(grep -oE '[^ "=/]+\.txt' "$config_file" | sed -E 's@^.*/@@' | sort -u || true)
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
}

ipset_switch() {
  local backup_suffix=".backup"
  ipset_status
  clear_screen

  declare -A files_map=()
  files_map["${REPO_ROOT}/lists/$(basename "$IPSET_LIST_FILE")"]=1

  if [ -d "${REPO_ROOT}/lists" ]; then
    for f in "${REPO_ROOT}/lists"/*.txt; do
      [ -f "$f" ] || continue
      files_map["$f"]=1
    done
  fi

  if [ -f "${OPT_REPO}/config" ]; then
    while IFS= read -r line; do
      for prefix in '--hostlist=' '--hostlist-exclude='; do
        if [[ "$line" == *"$prefix"* ]]; then
          val="${line#*$prefix}"
          val="${val%% *}"
          val="${val%\"}"
          val="${val#\"}"
          if [[ "$val" =~ ^/ ]]; then
            base="$(basename "$val")"
            files_map["${REPO_ROOT}/lists/$base"]=1
          else
            files_map["${REPO_ROOT}/lists/$val"]=1
          fi
        fi
      done
    done < "${OPT_REPO}/config"
  fi

  ipset_files=()
  for k in "${!files_map[@]}"; do
    ipset_files+=("$k")
  done

  if [ "${#ipset_files[@]}" -eq 0 ]; then
    read -rp "Нажмите Enter для возврата..."
    return
  fi

  if [ "$IPsetStatus" = "loaded" ]; then
    for lf in "${ipset_files[@]}"; do
      [ -z "$lf" ] && continue
      mkdir -p "$(dirname "$lf")"
      if [ -f "$lf" ]; then
        content="$(cat "$lf" 2>/dev/null || true)"
        if [ -n "$content" ] && ! printf '%s' "$content" | grep -q -x "203\.0\.113\.113/32"; then
          if [ ! -f "${lf}${backup_suffix}" ] || [ ! -s "${lf}${backup_suffix}" ]; then
            echo "$content" > "${lf}${backup_suffix}"
          fi
        fi
      fi
      printf '203.0.113.113/32\n' > "$lf"
    done

  elif [ "$IPsetStatus" = "none" ]; then
    for lf in "${ipset_files[@]}"; do
      [ -z "$lf" ] && continue
      mkdir -p "$(dirname "$lf")"
      backup="${lf}${backup_suffix}"
      if [ ! -f "$backup" ] || [ ! -s "$backup" ]; then
        content="$(cat "$lf" 2>/dev/null || true)"
        if [ -n "$content" ] && ! printf '%s' "$content" | grep -q -x "203\.0\.113\.113/32"; then
          echo "$content" > "$backup"
        fi
      fi
      : > "$lf"
    done

  else
    local restored=0
    for lf in "${ipset_files[@]}"; do
      [ -z "$lf" ] && continue
      backup="${lf}${backup_suffix}"
      if [ -f "$backup" ] && [ -s "$backup" ]; then
        cp -a "$backup" "$lf"
        restored=$((restored+1))
      fi
    done
  fi

}

show_menu() {
  clear_screen
  local gf_status="(выключен)"
  if [ -f "$GAMEFLAG_FILE" ]; then gf_status="(включён)"; fi
  ipset_status
  local ipset_disp="(unknown)"
  if [ "$IPsetStatus" = "loaded" ]; then ipset_disp="(loaded)"; fi
  if [ "$IPsetStatus" = "none" ]; then ipset_disp="(none)"; fi
  if [ "$IPsetStatus" = "any" ]; then ipset_disp="(any)"; fi

  cat <<MENU
Выберите действие:
1) Install strategies
2) Remove service
3) Status service
4) Toggle game filter $gf_status
5) Switch ipset $ipset_disp
6) Exit
MENU
  read -rp "Ваш выбор: " choice
  case "$choice" in
    1) install_selected_strategy ;;
    2) remove_service ;;
    3) service_status ;;
    4) toggle_gamefilter ;;
    5) ipset_switch ;;
    6) clear_screen; echo "Выход."; exit 0 ;;
    *) echo "Неверный выбор."; read -rp "Нажмите Enter...";;
  esac
}

ipset_status() {
  IPsetStatus="unknown"
  local any_loaded=0 any_none=0 any_empty=0
  for f in "$REPO_ROOT"/lists/*.txt; do
    [ -f "$f" ] || continue
    content="$(cat "$f" 2>/dev/null || true)"
    if [ -z "$content" ]; then
      any_empty=1
    elif printf '%s' "$content" | grep -q -x '203\.0\.113\.113/32'; then
      any_none=1
    else
      any_loaded=1
    fi
  done

  if [ "$any_loaded" -gt 0 ]; then
    IPsetStatus="loaded"
  elif [ "$any_none" -gt 0 ] && [ "$any_empty" -eq 0 ]; then
    IPsetStatus="none"
  elif [ "$any_empty" -gt 0 ] && [ "$any_none" -eq 0 ]; then
    IPsetStatus="any"
  else
    IPsetStatus="unknown"
  fi
}

remove_service() {
  clear_screen
  
  if [ -x "$OPT_REPO/uninstall_easy.sh" ]; then
    sudo bash "$OPT_REPO/uninstall_easy.sh"
  else
    echo "Предупреждение: uninstall_easy.sh не найден или не исполняемый в $OPT_REPO"
    read -rp "Нажмите Enter для возврата в меню..."
  fi
}

install_selected_strategy() {
  clear_screen
  
  if ! ensure_convert; then
    echo "Конвертер отсутствует или не исполняем — отмена."
    read -rp "Нажмите Enter..."
    return
  fi

  echo "Конвертация стратегий..."
  if ! bash "$CONVERT_SCRIPT" > /dev/null 2>&1; then
    echo "Конвертация стратегий завершилась с ошибкой, продолжу попытки."
  fi

  if ! clone_opt_repo_if_needed; then
    echo "Не удалось подготовить /opt/zapret — отмена."
    read -rp "Нажмите Enter..."
    return
  fi

  mapfile -t strategies < <(ls -1 "$STRAT_DIR"/*.sh 2>/dev/null | xargs -n1 basename | grep -v convert-strategies | sort || true)

  if [ "${#strategies[@]}" -eq 0 ]; then
    echo "Стратегии не найдены в $STRAT_DIR"
    read -rp "Нажмите Enter..."
    return
  fi

  clear_screen
  
  local cols=3
  local rows=$(( (${#strategies[@]} + cols - 1) / cols ))
  
  echo "Доступные стратегии:"
  echo ""
  
  local idx=1
  for ((i=0; i<rows; i++)); do
    for ((j=0; j<cols; j++)); do
      local pos=$((i + j * rows))
      if [ $pos -lt ${#strategies[@]} ]; then
        printf "%-35s" "$idx) ${strategies[$pos]}"
        idx=$((idx+1))
      fi
    done
    echo ""
  done
  
  echo ""
  echo "$idx) Отмена"
  echo ""
  
  read -rp "Выберите стратегию (номер): " strat_choice
  
  if [ "$strat_choice" -lt 1 ] || [ "$strat_choice" -gt "$idx" ]; then
    echo "Неверный выбор."
    read -rp "Нажмите Enter..."
    return
  fi

  if [ "$strat_choice" -eq "$idx" ]; then
    return
  fi

  local selected_idx=$((strat_choice-1))
  local selected_strategy="${strategies[$selected_idx]}"
  local cfg_src="$STRAT_DIR/$selected_strategy"

  echo "$selected_strategy" > "$REPO_ROOT/.active_strategy"

  sudo cp -a "$cfg_src" "$OPT_REPO/config"

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
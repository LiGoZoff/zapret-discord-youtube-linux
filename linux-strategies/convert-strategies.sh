#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

REPO_ROOT="$SCRIPT_DIR"
CURRENT="$SCRIPT_DIR"
while [ "$CURRENT" != "/" ]; do
  if [ -d "$CURRENT/windows-strategies" ]; then
    REPO_ROOT="$CURRENT"
    break
  fi
  CURRENT="$(dirname "$CURRENT")"
done

WINDOWS_DIR="$REPO_ROOT/windows-strategies"
OUT_DIR="$SCRIPT_DIR"
TEMPLATE="$REPO_ROOT/Exemple/config"

if [ ! -d "$WINDOWS_DIR" ]; then
  echo "ERROR: windows-strategies not found: $WINDOWS_DIR" >&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: Exemple template not found: $TEMPLATE" >&2
  exit 1
fi

shopt -s nullglob

safe_name() {
  local n="${1%.*}"
  n="$(echo "$n" | tr ' /()[],' '-----' | tr -s '-')"
  n="${n#-}"; n="${n%-}"
  echo "$n"
}

extract_args() {
  local f="$1"
  tr -d '\r' < "$f" \
    | sed -n '/[Ww][Ii][Nn][Ww][Ss]\.exe/,$p' \
    | sed '1s/.*[Ww][Ii][Nn][Ww][Ss]\.exe//' \
    | sed -E ':a; N; s/\^\n//g; ta; s/\n/ /g' \
    | tr -s '[:space:]' ' ' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed -E 's/[\x00-\x1F\x7F]//g' \
    | sed -E 's/[\^!]+//g'
}

convert_token() {
  local t="$1"
  t="${t#\"}"; t="${t%\"}"

  if [[ "$t" == "GameFilter" || "$t" == "%GameFilter%" || "$t" == "%GameFilter" || "$t" == "\$GameFilter" ]]; then
    printf '1024-65535'
    return 0
  fi

  t="${t//%BIN%/\$ROOT_DIR/bin/}"
  t="${t//%LISTS%/\$ROOT_DIR/lists/}"
  t="${t//\\//}"
  printf '%s' "$t"
}

sanitize_ports() {
  local v="$1"
  v="${v#\"}"; v="${v%\"}"
  v="${v//\$GameFilter/1024-65535}"
  v="${v//%GameFilter%/1024-65535}"
  v="${v//GameFilter/1024-65535}"
  v="$(printf '%s' "$v" | sed -E 's/[^0-9,\-]//g')"
  v="$(printf '%s' "$v" | sed -E 's/,+/,/g; s/^,+//; s/,+$//')"
  printf '%s' "$v"
}

write_with_replacements() {
  local template="$1"; local out="$2"
  local ports_tcp_line="$3"; local ports_udp_line="$4"
  local nfqblock="$5"

  local in_nfq=0
  local wrote_ports_tcp=0
  : > "$out"
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^NFQWS_PORTS_TCP ]]; then
      printf "%s\n" "$ports_tcp_line" >> "$out"
      wrote_ports_tcp=1
      continue
    fi
    if [[ "$line" =~ ^NFQWS_PORTS_UDP ]]; then
      printf "%s\n" "$ports_udp_line" >> "$out"
      continue
    fi
    if [ "$in_nfq" -eq 0 ] && [[ "$line" =~ ^NFQWS_OPT= ]]; then
      printf "%s\n" "$nfqblock" >> "$out"
      in_nfq=1
      continue
    fi
    if [ "$in_nfq" -eq 1 ]; then
      if [[ "$line" == *\" ]]; then
        in_nfq=0
      fi
      continue
    fi
    printf "%s\n" "$line" >> "$out"
  done < "$template"

  if [ "$wrote_ports_tcp" -eq 0 ]; then
    sed -i "1i$ports_udp_line\n$ports_tcp_line" "$out"
  fi
}

for bat in "$WINDOWS_DIR"/general*.bat; do
  [ -e "$bat" ] || continue
  echo "Converting $bat"
  name="$(basename "$bat")"
  safe="$(safe_name "$name")"
  out="$OUT_DIR/${safe}.sh"

  nfq_tcp=""
  nfq_udp=""
  blocks=()
  cur=()

  raw="$(extract_args "$bat")"
  echo "DEBUG [$safe] RAW: ${raw:0:400}" >/tmp/convert-"$safe".log
  if [ -z "$raw" ]; then
    echo "WARNING: no args parsed from $bat, skipping" >&2
    continue
  fi

  read -r -a toks <<< "$raw"
  toks_len=${#toks[@]}

  blocks=()
  cur=()

  nfq_tcp=""
  nfq_udp=""

  i=0
  while [ "$i" -lt "$toks_len" ]; do
    t="${toks[$i]}"

    if [[ "$t" == *"wf-tcp"* || "$t" == *"--wf-tcp"* ]]; then
      if [[ "$t" == *=* ]]; then
        val="${t#*=}"
      else
        val="${toks[$((i+1))]:-}"
        i=$((i+1))
      fi
      val="$(sanitize_ports "$val")"
      if [ -n "$val" ]; then
        if [ -n "$nfq_tcp" ]; then nfq_tcp="${nfq_tcp},${val}"; else nfq_tcp="$val"; fi
      fi
      i=$((i+1)); continue
    fi

    if [[ "$t" == *"wf-udp"* || "$t" == *"--wf-udp"* ]]; then
      if [[ "$t" == *=* ]]; then
        val="${t#*=}"
      else
        val="${toks[$((i+1))]:-}"
        i=$((i+1))
      fi
      val="$(sanitize_ports "$val")"
      if [ -n "$val" ]; then
        if [ -n "$nfq_udp" ]; then nfq_udp="${nfq_udp},${val}"; else nfq_udp="$val"; fi
      fi
      i=$((i+1)); continue
    fi

    if [[ "$t" == --ipset* ]] || [[ "$t" == --ipset-exclud* ]] || [[ "$t" == --ipset-exclude* ]]; then
      if [[ "$t" == "--ipset" || "$t" == "--ipset-exclude" ]]; then
        i=$((i+1))
      else
        :
      fi
      i=$((i+1)); continue
    fi

    if [[ "$t" == "--hostlist" || "$t" == "--hostlist-exclude" || "$t" == "--hostlist-auto" ]]; then
      next="${toks[$((i+1))]:-}"
      if [ -n "$next" ]; then
        p="$(convert_token "$next")"
        if [[ "$p" == /* ]]; then
          p="$p"
        else
          p="/opt/zapret/ipset/$(basename "$p")"
        fi
        cur+=("${t}=${p}")
        i=$((i+2)); continue
      else
        cur+=("$t"); i=$((i+1)); continue
      fi
    fi

    if [[ "$t" == *=* ]]; then
      key="${t%%=*}"; val_raw="${t#*=}"
      val_conv="$(convert_token "$val_raw")"
      if [[ "$val_conv" == /* || "$val_conv" == *".bin" || "$val_conv" == *".txt" || "$val_conv" == *list* || "$val_conv" == *ipset* ]]; then
        if [[ "$val_conv" != /* ]]; then
          if [[ "$val_conv" == *.bin ]]; then
            val_conv="/opt/zapret/files/fake/$(basename "$val_conv")"
          else
            val_conv="/opt/zapret/ipset/$(basename "$val_conv")"
          fi
        fi
      fi
      cur+=("${key}=${val_conv}")
      i=$((i+1)); continue
    fi

    if [[ "$t" == *"."* ]] && ( [[ "$t" == *.bin ]] || [[ "$t" == *.txt ]] || [[ "$t" == *list* ]] || [[ "$t" == *ipset* ]] ); then
      conv="$(convert_token "$t")"
      if [[ "$conv" == *.bin ]]; then
        conv="/opt/zapret/files/fake/$(basename "$conv")"
      else
        conv="/opt/zapret/ipset/$(basename "$conv")"
      fi
      cur+=("$conv"); i=$((i+1)); continue
    fi

    if [[ "$t" == "--new" ]]; then
      blocks+=("$(printf "%s " "${cur[@]}")")
      cur=()
      i=$((i+1)); continue
    fi

    cur+=("$(convert_token "$t")")
    i=$((i+1))
  done

  if [ "${#cur[@]}" -gt 0 ]; then
    blocks+=("$(printf "%s " "${cur[@]}")")
  fi

  content=""
  for idx in "${!blocks[@]}"; do
    line="${blocks[$idx]}"
    line="$(printf '%s' "$line" | sed -E 's/[[:space:]]+$//; s/\\,/,/g')"
    line="$(printf '%s' "$line" | sed -E 's@/opt/zapret/ipset//opt/zapret/ipset/@/opt/zapret/ipset/@g; s@/opt/zapret/ipset//@/opt/zapret/ipset/@g')"
    if [ "$idx" -lt "$((${#blocks[@]}-1))" ]; then
      content+="$line --new"$'\n'
    else
      content+="$line"$'\n'
    fi
  done
  content="$(printf '%s' "$content" | sed -E 's/%GameFilter%|%GameFilter|\\$GameFilter|\\$GameFilter|\\bGameFilter\\b/1024-65535/g')"
  content="${content//\\1/}" 
  content="${content//<HOSTLIST>/}"

  nfq="NFQWS_OPT=\""$'\n'"$content\""

  ports_tcp="NFQWS_PORTS_TCP=\""
  for p in $nfq_tcp; do
    ports_tcp+="$p,"
  done
  ports_tcp="${ports_tcp%,}\""

  ports_udp="NFQWS_PORTS_UDP=\""
  for p in $nfq_udp; do
    ports_udp+="$p,"
  done
  ports_udp="${ports_udp%,}\""

  write_with_replacements "$TEMPLATE" "$out" "$ports_tcp" "$ports_udp" "$nfq"

  chmod +x "$out"
  echo "Wrote $out"
done

echo "Conversion finished. Generated scripts are in $OUT_DIR"

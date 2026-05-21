#!/bin/bash
# Parse wifi-scan.swift JSON lines into networks.json and numbered networks.txt
# Usage: wifi-scan-parse.sh <json-lines-file> <out-dir>

set -euo pipefail

JSON_LINES="${1:-}"
OUT_DIR="${2:-}"

[[ -n "$JSON_LINES" && -f "$JSON_LINES" ]] || {
  echo "usage: wifi-scan-parse.sh <json-lines-file> <out-dir>" >&2
  exit 1
}
mkdir -p "$OUT_DIR"

NETWORKS_JSON="$OUT_DIR/networks.json"
NETWORKS_TXT="$OUT_DIR/networks.txt"

# Build JSON array from NDJSON (skip error lines)
{
  echo "["
  first=1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" == *'"error"'* ]] && continue
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      echo ","
    fi
    printf '%s' "$line"
  done < "$JSON_LINES"
  echo
  echo "]"
} > "$NETWORKS_JSON"

format_tsv() {
  if command -v jq &>/dev/null; then
    jq -r '.[] | [if (.bssid | length) > 0 then .bssid else "-" end, .channel, .security, .rssi, .ssid] | @tsv' "$NETWORKS_JSON"
  elif command -v python3 &>/dev/null; then
    python3 - "$NETWORKS_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    for n in json.load(f):
        print(f"{n.get('bssid','')}\t{n.get('channel',0)}\t{n.get('security','')}\t{n.get('rssi',0)}\t{n.get('ssid','')}")
PY
  else
    echo "jq or python3 required to format networks.txt" >&2
    exit 1
  fi
}

{
  printf '%-4s %-18s %-4s %-6s %-5s %s\n' '#' 'BSSID' 'CH' 'ENC' 'RSSI' 'SSID'
  n=0
  while IFS=$'\t' read -r bssid ch enc rssi ssid; do
    n=$((n + 1))
    bssid="${bssid:-unknown}"
    ssid="${ssid:-<hidden>}"
    printf '%-4s %-18s %-4s %-6s %-5s %s\n' "$n" "$bssid" "$ch" "$enc" "$rssi" "$ssid"
  done < <(format_tsv)
} > "$NETWORKS_TXT"

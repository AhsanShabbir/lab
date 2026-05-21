#!/bin/bash
# Allowlist helpers — source from run-wifi.sh after WIFI_ALLOWLIST is set

wifi_normalize_bssid() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' -'
}

wifi_normalize_ssid() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Returns 0 if ssid or bssid matches allowlist
wifi_allowlisted() {
  local ssid="${1:-}" bssid="${2:-}"
  local list="${WIFI_ALLOWLIST:-}"
  local line norm_ssid norm_bssid norm_line

  [[ -f "$list" ]] || return 1

  norm_ssid="$(wifi_normalize_ssid "$ssid")"
  norm_bssid="$(wifi_normalize_bssid "$bssid")"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue

    norm_line="$(wifi_normalize_ssid "$line")"
    if [[ "$norm_line" == *:* ]] || [[ ${#norm_line} -eq 12 ]]; then
      norm_line="$(wifi_normalize_bssid "$line")"
      [[ -n "$norm_bssid" && "$norm_line" == "$norm_bssid" ]] && return 0
    else
      [[ -n "$norm_ssid" && "$norm_line" == "$norm_ssid" ]] && return 0
    fi
  done < "$list"

  return 1
}

wifi_require_allowlisted() {
  local ssid="${1:-}" bssid="${2:-}"
  if wifi_allowlisted "$ssid" "$bssid"; then
    return 0
  fi
  echo "[-] Target not on allowlist ($WIFI_ALLOWLIST): SSID=${ssid:-?} BSSID=${bssid:-?}" >&2
  echo "[-] Add your lab SSID or BSSID to config/wifi-allowlist.txt" >&2
  return 1
}

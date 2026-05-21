#!/bin/bash
# Allowlist helpers — source from run-wifi.sh after WIFI_ALLOWLIST is set

wifi_normalize_bssid() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' -'
}

wifi_normalize_ssid() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# True if string looks like a MAC (with or without colons), not an SSID
wifi_looks_like_bssid() {
  local s
  s="$(wifi_normalize_bssid "$1")"
  [[ ${#s} -eq 12 ]] && [[ "$s" =~ ^[0-9a-f]{12}$ ]]
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

    if wifi_looks_like_bssid "$line"; then
      norm_line="$(wifi_normalize_bssid "$line")"
      [[ -n "$norm_bssid" && "$norm_line" == "$norm_bssid" ]] && return 0
    else
      norm_line="$(wifi_normalize_ssid "$line")"
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

# Enforce allowlist only when ONLY_ALLOWLIST=true (set by --only-allowlist)
wifi_enforce_allowlist() {
  local ssid="${1:-}" bssid="${2:-}"
  if [[ "${ONLY_ALLOWLIST:-false}" == "true" ]]; then
    wifi_require_allowlisted "$ssid" "$bssid"
    return $?
  fi
  return 0
}

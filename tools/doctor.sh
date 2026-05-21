#!/bin/bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=../scripts/lib/paths.sh
source "$LAB_ROOT/scripts/lib/paths.sh"

REQUIRED_BINS=(subfinder assetfinder httpx waybackurls gau katana dnsx naabu ffuf nuclei jq)
OPTIONAL_BINS=(findomain sqlmap go brew hashcat hcxpcapngtool swift)
WIFI_OPTIONAL_BINS=(hashcat hcxpcapngtool swift)

log() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }

main() {
  log "WISE lab root: $LAB_ROOT"
  ensure_lab_path

  local missing=()
  for bin in "${REQUIRED_BINS[@]}"; do
    if command -v "$bin" &>/dev/null; then
      log "OK  $bin -> $(command -v "$bin")"
    else
      missing+=("$bin")
      warn "MISSING $bin"
    fi
  done

  for bin in "${OPTIONAL_BINS[@]}"; do
    if command -v "$bin" &>/dev/null; then
      log "OK  $bin (optional)"
    else
      warn "optional missing: $bin"
    fi
  done

  [[ -f "$LAB_ROOT/config/recon.defaults" ]] && log "OK  config/recon.defaults" || warn "missing config/recon.defaults"
  [[ -f "$LAB_ROOT/config/third-party-domains.txt" ]] && log "OK  config/third-party-domains.txt" || warn "missing config/third-party-domains.txt"
  [[ -f "$LAB_ROOT/wordlists/common-dirs.txt" ]] && log "OK  wordlists/common-dirs.txt" || warn "missing wordlists/common-dirs.txt"
  [[ -x "$LAB_ROOT/scripts/run-recon.sh" ]] && log "OK  scripts/run-recon.sh" || warn "scripts/run-recon.sh not executable"

  log "--- WiFi lab (optional) ---"
  [[ -f "$LAB_ROOT/config/wifi.defaults" ]] && log "OK  config/wifi.defaults" || warn "missing config/wifi.defaults"
  [[ -f "$LAB_ROOT/config/wifi-allowlist.txt" ]] && log "OK  config/wifi-allowlist.txt" || warn "missing config/wifi-allowlist.txt"
  [[ -x "$LAB_ROOT/scripts/run-wifi.sh" ]] && log "OK  scripts/run-wifi.sh" || warn "scripts/run-wifi.sh not executable"
  [[ -x "$LAB_ROOT/wifi" ]] && log "OK  wifi wrapper" || warn "wifi wrapper not executable"
  [[ -f "$LAB_ROOT/tools/wifi-scan.swift" ]] && log "OK  tools/wifi-scan.swift" || warn "missing tools/wifi-scan.swift"
  local wbin
  for wbin in "${WIFI_OPTIONAL_BINS[@]}"; do
    if command -v "$wbin" &>/dev/null; then
      log "OK  $wbin (wifi)"
    else
      warn "wifi optional missing: $wbin — run $LAB_ROOT/setup-wifi-tools.sh"
    fi
  done

  if ((${#missing[@]} > 0)); then
    warn "Run: $LAB_ROOT/setup-recon-tools.sh"
    exit 1
  fi

  log "All required tools present"
}

main "$@"

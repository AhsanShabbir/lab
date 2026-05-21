#!/bin/bash
# Install WiFi lab tools (hashcat, hcxtools, jq) and verify macOS scan prerequisites
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=scripts/lib/paths.sh
source "$LAB_ROOT/scripts/lib/paths.sh"

BREW_FORMULAE=(hashcat hcxtools jq)
REQUIRED_BINS=(hashcat hcxpcapngtool jq swift)

log() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die() { echo "[-] $*" >&2; exit 1; }

check_prereqs() {
  command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install from https://brew.sh"
  ensure_lab_path
  if ! xcode-select -p &>/dev/null; then
    warn "Xcode Command Line Tools not found — required for wifi-scan.swift"
    warn "Run: xcode-select --install"
  fi
}

install_brew_packages() {
  for formula in "${BREW_FORMULAE[@]}"; do
    if brew list "$formula" &>/dev/null; then
      log "$formula already installed"
    else
      log "brew install $formula"
      brew install "$formula"
    fi
  done
}

verify_tools() {
  local missing=()
  for bin in "${REQUIRED_BINS[@]}"; do
    if command -v "$bin" &>/dev/null; then
      log "OK  $bin -> $(command -v "$bin")"
    else
      missing+=("$bin")
      warn "MISSING $bin"
    fi
  done

  [[ -f "$LAB_ROOT/config/wifi.defaults" ]] && log "OK  config/wifi.defaults" || warn "missing config/wifi.defaults"
  [[ -f "$LAB_ROOT/config/wifi-allowlist.txt" ]] && log "OK  config/wifi-allowlist.txt" || warn "missing config/wifi-allowlist.txt"
  [[ -x "$LAB_ROOT/scripts/run-wifi.sh" ]] && log "OK  scripts/run-wifi.sh" || warn "scripts/run-wifi.sh not executable"
  [[ -f "$LAB_ROOT/tools/wifi-scan.swift" ]] && log "OK  tools/wifi-scan.swift" || warn "missing tools/wifi-scan.swift"

  if ((${#missing[@]} > 0)); then
    die "Missing tools: ${missing[*]}"
  fi

  log "WiFi lab tools ready. Next:"
  echo "  1. Edit config/wifi-allowlist.txt with your lab SSID"
  echo "  2. ./wifi --scan"
}

main() {
  log "Setting up WiFi lab toolkit (Mac-first)"
  check_prereqs
  install_brew_packages
  ensure_lab_path
  chmod +x "$LAB_ROOT/wifi" "$LAB_ROOT/scripts/run-wifi.sh" 2>/dev/null || true
  verify_tools
}

main "$@"

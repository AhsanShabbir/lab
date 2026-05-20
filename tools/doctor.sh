#!/bin/bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REQUIRED_BINS=(subfinder assetfinder httpx waybackurls ffuf nuclei)
OPTIONAL_BINS=(jq go brew)

log() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }

ensure_go_path() {
  local go_bin="${GOPATH:-$HOME/go}/bin"
  if [[ ":$PATH:" != *":$go_bin:"* ]]; then
    export PATH="$go_bin:$PATH"
    warn "Added $go_bin to PATH for this check"
  fi
}

main() {
  log "Lab root: $LAB_ROOT"
  ensure_go_path

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
  [[ -f "$LAB_ROOT/wordlists/common-dirs.txt" ]] && log "OK  wordlists/common-dirs.txt" || warn "missing wordlists/common-dirs.txt"
  [[ -x "$LAB_ROOT/scripts/run-recon.sh" ]] && log "OK  scripts/run-recon.sh" || warn "scripts/run-recon.sh not executable"

  if ((${#missing[@]} > 0)); then
    warn "Run: $LAB_ROOT/setup-recon-tools.sh"
    exit 1
  fi

  log "All required tools present"
}

main "$@"

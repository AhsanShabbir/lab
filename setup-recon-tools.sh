#!/bin/bash
# Install pentest recon tools listed in tools/dashboard/recon.html
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/paths.sh
source "$LAB_ROOT/scripts/lib/paths.sh"

GO_TOOLS=(
  "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  "github.com/tomnomnom/assetfinder@latest"
  "github.com/projectdiscovery/httpx/cmd/httpx@latest"
  "github.com/tomnomnom/waybackurls@latest"
  "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
  "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  "github.com/projectdiscovery/katana/cmd/katana@latest"
  "github.com/lc/gau/v2/cmd/gau@latest"
  "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
)

BREW_FORMULAE=(ffuf jq findomain sqlmap)
BREW_CASKS=(burp-suite)

REQUIRED_BINS=(subfinder assetfinder httpx waybackurls gau katana dnsx naabu ffuf nuclei jq)

log() { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die() { echo "[-] $*" >&2; exit 1; }

check_prereqs() {
  command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install from https://brew.sh"
  command -v go >/dev/null 2>&1 || {
    log "Go not found; installing via Homebrew..."
    brew install go
  }
  ensure_lab_path
}

install_go_tools() {
  for module in "${GO_TOOLS[@]}"; do
    log "go install $module"
    go install "$module"
  done
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

  for cask in "${BREW_CASKS[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
      log "$cask already installed"
    else
      log "brew install --cask $cask"
      brew install --cask "$cask"
    fi
  done
}

update_nuclei_templates() {
  if command -v nuclei >/dev/null 2>&1; then
    log "Updating nuclei templates..."
    nuclei -update-templates
  fi
}

verify_tools() {
  local missing=()
  for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing+=("$bin")
    fi
  done

  if ((${#missing[@]} > 0)); then
    die "Missing from PATH: ${missing[*]}. Ensure \$HOME/go/bin is in your PATH and re-run."
  fi

  log "All CLI tools are available:"
  for bin in "${REQUIRED_BINS[@]}"; do
    echo "  $(command -v "$bin")"
  done

  if command -v findomain &>/dev/null; then
    log "findomain (optional): $(command -v findomain)"
  else
    warn "findomain not installed — subs stage will skip it (brew install findomain)"
  fi

  if command -v sqlmap &>/dev/null; then
    log "sqlmap: $(command -v sqlmap)"
  else
    warn "sqlmap not installed — sqli stage will fail (brew install sqlmap)"
  fi

  if [[ -d "/Applications/Burp Suite Community Edition.app" ]] \
     || [[ -d "/Applications/Burp Suite Professional.app" ]] \
     || brew list --cask burp-suite &>/dev/null; then
    log "Burp Suite: installed"
  else
    warn "Burp Suite cask may be installed but app path not detected; check /Applications."
  fi
}

main() {
  log "Setting up pentest recon toolkit (see tools/dashboard/recon.html)"
  check_prereqs
  install_go_tools
  install_brew_packages
  update_nuclei_templates
  ensure_lab_path
  verify_tools
  log "Setup complete. Open tools/dashboard/recon.html for command reference."
  log "Permanent PATH fix — add to ~/.zshrc:"
  echo "  source $LAB_ROOT/config/shell-path.sh"
}

main "$@"

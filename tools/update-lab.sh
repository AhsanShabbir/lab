#!/bin/bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

log() { echo "[+] $*"; }

ensure_go_path() {
  local go_bin="${GOPATH:-$HOME/go}/bin"
  export PATH="$go_bin:$PATH"
}

main() {
  log "Updating lab tools ($LAB_ROOT)"
  ensure_go_path

  if command -v go &>/dev/null; then
    for module in "${GO_TOOLS[@]}"; do
      log "go install $module"
      go install "$module"
    done
  else
    echo "[!] Go not found; skipping go tool updates" >&2
  fi

  if command -v nuclei &>/dev/null; then
    log "Updating nuclei templates..."
    nuclei -update-templates
  fi

  if command -v brew &>/dev/null; then
    for formula in ffuf jq findomain; do
      if brew list "$formula" &>/dev/null; then
        log "brew upgrade $formula"
        brew upgrade "$formula" 2>/dev/null || true
      fi
    done
  fi

  log "Update complete. Run: $LAB_ROOT/tools/doctor.sh"
}

main "$@"

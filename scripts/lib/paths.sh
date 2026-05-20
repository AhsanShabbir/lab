# Source from lab scripts to find go install and Homebrew binaries
ensure_lab_path() {
  local go_bin="${GOPATH:-$HOME/go}/bin"
  if [[ -d "$go_bin" ]] && [[ ":$PATH:" != *":$go_bin:"* ]]; then
    export PATH="$go_bin:$PATH"
  fi
  if [[ -d /opt/homebrew/bin ]] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
  fi
  if [[ -d /usr/local/bin ]] && [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    export PATH="/usr/local/bin:$PATH"
  fi
}

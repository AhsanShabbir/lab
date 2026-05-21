#!/bin/bash
# Staged WiFi lab pipeline — run from project wifi/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
ensure_lab_path

# shellcheck source=../config/wifi.defaults
source "$LAB_ROOT/config/wifi.defaults"

# shellcheck source=lib/wifi-allowlist.sh
source "$SCRIPT_DIR/lib/wifi-allowlist.sh"

WIFI_DIR="$(pwd)"
PROJECT_DIR="$(cd "$WIFI_DIR/.." && pwd)"
LOG_FILE="$WIFI_DIR/run.log"

SELECTED_INDEX=""
SELECTED_SSID=""
SELECTED_BSSID=""
ONLY_STAGE=""
FULL=false
RESUME=false
REQUIRE_CAPTURE=false
ONLY_ALLOWLIST=false
RUN_SCAN=false
RUN_CRACK=false
declare -a SKIP_STAGES=()

ALL_STAGES=(scan capture crack report)

log() { echo "[+] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!] $*" | tee -a "$LOG_FILE" >&2; }
die() { echo "[-] $*" | tee -a "$LOG_FILE" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: run-wifi.sh [options]

Options:
  --scan              Run scan stage only (alias for --only scan)
  --crack             Run crack stage (and report if --full)
  --target <N>        Select network by number from last scan (1-based)
  --ssid <name>       Select network by SSID
  --bssid <mac>       Select network by BSSID
  --only <stage>      scan|capture|crack|report
  --skip <stage>      Skip stage (repeatable)
  --full              scan → capture → crack → report
  --resume            Skip stage if primary output exists
  --require-capture   Fail capture stage if no inbox file
  --only-allowlist    Require target in config/wifi-allowlist.txt (default: off)

Run from: <project>/wifi/
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan) RUN_SCAN=true; shift ;;
    --crack) RUN_CRACK=true; shift ;;
    --target) SELECTED_INDEX="${2:-}"; shift 2 ;;
    --ssid) SELECTED_SSID="${2:-}"; shift 2 ;;
    --bssid) SELECTED_BSSID="${2:-}"; shift 2 ;;
    --only) ONLY_STAGE="${2:-}"; shift 2 ;;
    --skip) SKIP_STAGES+=("${2:-}"); shift 2 ;;
    --full) FULL=true; shift ;;
    --resume) RESUME=true; shift ;;
    --require-capture) REQUIRE_CAPTURE=true; shift ;;
    --only-allowlist) ONLY_ALLOWLIST=true; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

# --scan / --crack imply stages when --only not set
if [[ "$RUN_SCAN" == true && -z "$ONLY_STAGE" ]]; then
  ONLY_STAGE="scan"
fi
if [[ "$RUN_CRACK" == true && -z "$ONLY_STAGE" ]]; then
  ONLY_STAGE="crack"
fi

stage_skipped() {
  local stage="$1" s
  ((${#SKIP_STAGES[@]} == 0)) && return 1
  for s in "${SKIP_STAGES[@]}"; do
    [[ "$s" == "$stage" ]] && return 0
  done
  return 1
}

stage_enabled() {
  local stage="$1"
  stage_skipped "$stage" && return 1
  if [[ -n "$ONLY_STAGE" ]]; then
    [[ "$ONLY_STAGE" == "$stage" ]] && return 0
    return 1
  fi
  if [[ "$FULL" == true ]]; then
    return 0
  fi
  if [[ "$RUN_SCAN" == true ]]; then
    [[ "$stage" == "scan" ]] && return 0
    return 1
  fi
  if [[ "$RUN_CRACK" == true ]]; then
    [[ "$stage" == "crack" || "$stage" == "report" ]] && return 0
    return 1
  fi
  return 0
}

should_skip_resume() {
  local file="$1"
  [[ "$RESUME" == true && -f "$file" && -s "$file" ]]
}

run_stage() {
  local stage="$1"
  stage_enabled "$stage" || return 0
  log "=== Stage: $stage ==="
  "stage_${stage}"
}

resolve_selection() {
  local json="$WIFI_DIR/scan/networks.json"
  [[ -f "$json" ]] || die "No scan data — run scan stage first (./wifi --scan)"

  if [[ -n "$SELECTED_INDEX" ]]; then
    command -v jq &>/dev/null || die "jq required for --target"
    local idx="$SELECTED_INDEX"
    [[ "$idx" =~ ^[0-9]+$ ]] || die "Invalid --target: $idx"
    SELECTED_SSID="$(jq -r ".[$((idx - 1))].ssid // empty" "$json")"
    SELECTED_BSSID="$(jq -r ".[$((idx - 1))].bssid // empty" "$json")"
    [[ -n "$SELECTED_SSID" ]] || die "No network at index $idx"
    return 0
  fi

  if [[ -n "$SELECTED_SSID" && -z "$SELECTED_BSSID" ]] && command -v jq &>/dev/null; then
    SELECTED_BSSID="$(jq -r --arg s "$SELECTED_SSID" '.[] | select(.ssid == $s) | .bssid' "$json" | head -1)"
  fi
  if [[ -n "$SELECTED_BSSID" && -z "$SELECTED_SSID" ]] && command -v jq &>/dev/null; then
    SELECTED_SSID="$(jq -r --arg b "$SELECTED_BSSID" '.[] | select(.bssid == $b) | .ssid' "$json" | head -1)"
  fi
  if [[ -n "$SELECTED_SSID" || -n "$SELECTED_BSSID" ]]; then
    return 0
  fi

  # Default: first network (or first allowlisted when --only-allowlist)
  if command -v jq &>/dev/null; then
    local i count
    count="$(jq 'length' "$json")"
    for ((i = 0; i < count; i++)); do
      local ssid bssid
      ssid="$(jq -r ".[$i].ssid // empty" "$json")"
      bssid="$(jq -r ".[$i].bssid // empty" "$json")"
      if [[ "${ONLY_ALLOWLIST:-false}" == "true" ]]; then
        wifi_allowlisted "$ssid" "$bssid" || continue
        SELECTED_SSID="$ssid"
        SELECTED_BSSID="$bssid"
        log "Auto-selected allowlisted: $ssid ($bssid)"
        return 0
      fi
      SELECTED_SSID="$ssid"
      SELECTED_BSSID="$bssid"
      log "Auto-selected: $ssid ($bssid)"
      return 0
    done
  fi
  die "No target selected. Use --target N, --ssid, or --bssid after scan"
}

bins_for_stage() {
  case "$1" in
    scan) echo "swift jq" ;;
    capture) echo "hcxpcapngtool" ;;
    crack) echo "hashcat" ;;
    report) echo "jq" ;;
  esac
}

check_bins() {
  local -a stages_to_check=()
  local stage bin missing=() seen=() s x already

  if [[ -n "$ONLY_STAGE" ]]; then
    stages_to_check=("$ONLY_STAGE")
  elif [[ "$FULL" == true ]]; then
    stages_to_check=("${ALL_STAGES[@]}")
  elif [[ "$RUN_SCAN" == true ]]; then
    stages_to_check=(scan)
  elif [[ "$RUN_CRACK" == true ]]; then
    stages_to_check=(capture crack report)
  else
    stages_to_check=("${ALL_STAGES[@]}")
  fi

  for stage in "${stages_to_check[@]}"; do
    for bin in $(bins_for_stage "$stage"); do
      already=0
      for x in "${seen[@]+"${seen[@]}"}"; do
        [[ "$x" == "$bin" ]] && already=1 && break
      done
      ((already)) && continue
      seen+=("$bin")
      command -v "$bin" &>/dev/null || missing+=("$bin")
    done
  done

  if ((${#missing[@]} > 0)); then
    die "Missing tools: ${missing[*]}. Run: $LAB_ROOT/setup-wifi-tools.sh"
  fi
}

stage_scan() {
  if should_skip_resume "$WIFI_DIR/scan/networks.txt"; then
    warn "Resume: skipping scan (networks.txt exists)"
    return
  fi

  local raw="$WIFI_DIR/scan/scan-raw.jsonl"
  mkdir -p "$WIFI_DIR/scan"

  log "Scanning Wi-Fi networks (CoreWLAN)..."
  if ! swift "$LAB_ROOT/tools/wifi-scan.swift" > "$raw" 2>"$WIFI_DIR/scan/scan.err"; then
    if [[ -s "$WIFI_DIR/scan/scan.err" ]]; then
      cat "$WIFI_DIR/scan/scan.err" >&2
    fi
    die "Scan failed. Install Xcode CLT: xcode-select --install"
  fi

  if [[ ! -s "$raw" ]]; then
    die "Scan returned no networks"
  fi

  # shellcheck source=lib/wifi-scan-parse.sh
  bash "$SCRIPT_DIR/lib/wifi-scan-parse.sh" "$raw" "$WIFI_DIR/scan"

  log "Networks found: $(jq 'length' "$WIFI_DIR/scan/networks.json" 2>/dev/null || echo '?')"
  echo ""
  cat "$WIFI_DIR/scan/networks.txt"
  echo ""
  log "Use --target N to select a network for capture/crack"
}

stage_capture() {
  resolve_selection
  wifi_enforce_allowlist "$SELECTED_SSID" "$SELECTED_BSSID" || die "Capture blocked by allowlist"

  if should_skip_resume "$WIFI_DIR/crack/handshake.22000"; then
    warn "Resume: skipping capture (handshake.22000 exists)"
    return
  fi

  local inbox="$WIFI_DIR/${CAPTURE_INBOX:-capture/inbox}"
  mkdir -p "$inbox" "$WIFI_DIR/crack"

  local cap_file=""
  for ext in pcapng pcap cap; do
    local f
    f="$(find "$inbox" -maxdepth 1 -type f -name "*.${ext}" 2>/dev/null | head -1)"
    if [[ -n "$f" ]]; then
      cap_file="$f"
      break
    fi
  done

  if [[ -z "$cap_file" ]]; then
    warn "No capture in $inbox — manual step required:"
    echo "  1. Wireless Diagnostics → Sniffer (match lab AP channel)" >&2
    echo "  2. Save .pcapng to: $inbox/" >&2
    echo "  3. Re-run: ./wifi --only capture" >&2
    if [[ "$REQUIRE_CAPTURE" == true ]]; then
      die "No capture file (--require-capture)"
    fi
    return 0
  fi

  log "Converting capture: $cap_file"
  rm -f "$WIFI_DIR/crack/handshake.22000"
  hcxpcapngtool -o "$WIFI_DIR/crack/handshake.22000" "$cap_file" \
    >>"$LOG_FILE" 2>&1 || die "hcxpcapngtool failed — check capture has WPA handshake or PMKID"

  if [[ ! -s "$WIFI_DIR/crack/handshake.22000" ]]; then
    die "handshake.22000 empty — capture may lack EAPOL/PMKID"
  fi
  log "Hash file: crack/handshake.22000 ($(wc -c < "$WIFI_DIR/crack/handshake.22000" | tr -d ' ') bytes)"
}

stage_crack() {
  resolve_selection
  wifi_enforce_allowlist "$SELECTED_SSID" "$SELECTED_BSSID" || die "Crack blocked by allowlist"

  if should_skip_resume "$WIFI_DIR/crack/result.txt"; then
    warn "Resume: skipping crack (result.txt exists)"
    return
  fi

  local hashfile="$WIFI_DIR/crack/handshake.22000"
  [[ -s "$hashfile" ]] || die "No handshake.22000 — run capture stage or add file to capture/inbox/"

  [[ -f "${WORDLIST:-}" ]] || die "Wordlist not found: $WORDLIST"

  log "Cracking with hashcat (mode ${HASHCAT_MODE:-22000})..."
  mkdir -p "$WIFI_DIR/crack"

  local pot="$WIFI_DIR/crack/hashcat.potfile"
  rm -f "$WIFI_DIR/crack/result.txt"

  hashcat -m "${HASHCAT_MODE:-22000}" -a 0 -w "${HASHCAT_WORKLOAD:-3}" \
    --potfile-path "$pot" \
    -o "$WIFI_DIR/crack/hashcat.out" \
    "$hashfile" "$WORDLIST" \
    >>"$WIFI_DIR/crack/hashcat.log" 2>&1 || true

  if [[ -s "$WIFI_DIR/crack/hashcat.out" ]]; then
    {
      echo "status=cracked"
      echo "ssid=$SELECTED_SSID"
      echo "bssid=$SELECTED_BSSID"
      cat "$WIFI_DIR/crack/hashcat.out"
    } >"$WIFI_DIR/crack/result.txt"
    log "Password recovered — see crack/result.txt"
  else
    {
      echo "status=not_found"
      echo "ssid=$SELECTED_SSID"
      echo "bssid=$SELECTED_BSSID"
    } >"$WIFI_DIR/crack/result.txt"
    warn "No password in wordlist — see crack/hashcat.log"
  fi
}

stage_report() {
  local summary="$WIFI_DIR/report/summary.md"
  mkdir -p "$WIFI_DIR/report"
  local ts status ssid bssid
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  status="unknown"
  ssid="${SELECTED_SSID:-}"
  bssid="${SELECTED_BSSID:-}"
  if [[ -f "$WIFI_DIR/crack/result.txt" ]]; then
    status="$(grep '^status=' "$WIFI_DIR/crack/result.txt" 2>/dev/null | cut -d= -f2- | head -1)"
    ssid="$(grep '^ssid=' "$WIFI_DIR/crack/result.txt" 2>/dev/null | cut -d= -f2- | head -1)"
    bssid="$(grep '^bssid=' "$WIFI_DIR/crack/result.txt" 2>/dev/null | cut -d= -f2- | head -1)"
    status="${status:-unknown}"
  fi

  {
    echo "## WiFi lab run — $ts"
    echo ""
    echo "- SSID: ${ssid:-n/a}"
    echo "- BSSID: ${bssid:-n/a}"
    echo "- Status: $status"
    echo ""
  } >>"$summary"
  log "Report appended: report/summary.md"
}

main() {
  mkdir -p "$WIFI_DIR"/{scan,capture/inbox,crack,report}
  : >>"$LOG_FILE"

  check_bins

  if [[ "$FULL" == true ]]; then
    ONLY_STAGE=""
    for stage in "${ALL_STAGES[@]}"; do
      run_stage "$stage"
    done
    exit 0
  fi

  if [[ -n "$ONLY_STAGE" ]]; then
    run_stage "$ONLY_STAGE"
    # --crack also wants report when not only crack? Plan says --crack runs crack; optional report on full only
    if [[ "$RUN_CRACK" == true && "$ONLY_STAGE" == "crack" ]]; then
      stage_enabled report || run_stage report
    fi
    exit 0
  fi

  for stage in "${ALL_STAGES[@]}"; do
    run_stage "$stage"
  done
}

main "$@"

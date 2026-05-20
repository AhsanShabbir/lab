#!/bin/bash
# Staged recon pipeline — run from project recon/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/paths.sh
source "$SCRIPT_DIR/lib/paths.sh"
ensure_lab_path

# shellcheck source=config/recon.defaults
source "$LAB_ROOT/config/recon.defaults"

RECON_DIR="$(pwd)"
PROJECT_DIR="$(cd "$RECON_DIR/.." && pwd)"
LOG_FILE="$RECON_DIR/run.log"

TARGET=""
ONLY_STAGE=""
FULL=false
RESUME=false
declare -a SKIP_STAGES=()

ALL_STAGES=(subs live urls fuzz scan summary)
DEFAULT_STAGES=(subs live urls scan summary)

REQUIRED_BINS=(subfinder assetfinder httpx waybackurls nuclei)
REQUIRED_BINS_FUZZ=(ffuf)

log() { echo "[+] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!] $*" | tee -a "$LOG_FILE" >&2; }
die() { echo "[-] $*" | tee -a "$LOG_FILE" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: run-recon.sh [options]

Options:
  --target <domain>   Target domain (or set in ../meta.json)
  --only <stage>      Run single stage: subs|live|urls|fuzz|scan|summary
  --skip <stage>      Skip stage (repeatable)
  --full              Include fuzz stage
  --resume            Skip stage if primary output exists and is non-empty

Run from: <project>/recon/
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --only) ONLY_STAGE="${2:-}"; shift 2 ;;
    --skip) SKIP_STAGES+=("${2:-}"); shift 2 ;;
    --full) FULL=true; shift ;;
    --resume) RESUME=true; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

resolve_target() {
  if [[ -n "$TARGET" ]]; then
    return
  fi
  if [[ -f "$PROJECT_DIR/meta.json" ]]; then
    if command -v jq &>/dev/null; then
      TARGET="$(jq -r '.target // empty' "$PROJECT_DIR/meta.json")"
    else
      TARGET="$(grep -o '"target"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_DIR/meta.json" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    fi
  fi
  [[ -n "$TARGET" ]] || die "Target required: --target <domain> or ../meta.json with target field"
}

bins_for_stage() {
  case "$1" in
    subs) echo "subfinder assetfinder" ;;
    live) echo "httpx" ;;
    urls) echo "waybackurls" ;;
    fuzz) echo "ffuf" ;;
    scan) echo "nuclei" ;;
    summary) echo "" ;;
  esac
}

check_bins() {
  local -a stages_to_check=()
  local stage bin missing=() seen=() s

  if [[ -n "$ONLY_STAGE" ]]; then
    stages_to_check=("$ONLY_STAGE")
  else
    for stage in "${ALL_STAGES[@]}"; do
      stage_enabled "$stage" && stages_to_check+=("$stage")
    done
  fi

  for stage in "${stages_to_check[@]}"; do
    for bin in $(bins_for_stage "$stage"); do
      local x already=0
      for x in "${seen[@]+"${seen[@]}"}"; do
        [[ "$x" == "$bin" ]] && already=1 && break
      done
      ((already)) && continue
      seen+=("$bin")
      command -v "$bin" &>/dev/null || missing+=("$bin")
    done
  done

  if ((${#missing[@]} > 0)); then
    die "Missing tools: ${missing[*]}. Run: $LAB_ROOT/setup-recon-tools.sh — then: source $LAB_ROOT/config/shell-path.sh (add to ~/.zshrc)"
  fi
}

stage_skipped() {
  local stage="$1"
  local s
  ((${#SKIP_STAGES[@]} == 0)) && return 1
  for s in "${SKIP_STAGES[@]}"; do
    [[ "$s" == "$stage" ]] && return 0
  done
  return 1
}

stage_enabled() {
  local stage="$1"
  if stage_skipped "$stage"; then
    return 1
  fi
  if [[ "$stage" == "fuzz" ]] && [[ "$FULL" != true ]]; then
    return 1
  fi
  if [[ -n "$ONLY_STAGE" ]] && [[ "$ONLY_STAGE" != "$stage" ]]; then
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

stage_subs() {
  if should_skip_resume subs.txt; then
    warn "Resume: skipping subs (subs.txt exists)"
    return
  fi
  local sf="$RECON_DIR/subs.subfinder.tmp"
  local af="$RECON_DIR/subs.assetfinder.tmp"
  : > "$sf"
  : > "$af"
  subfinder -d "$TARGET" -silent > "$sf" &
  assetfinder "$TARGET" > "$af" &
  wait
  cat "$sf" "$af" | sed '/^$/d' | sort -u > "$RECON_DIR/subs.txt"
  rm -f "$sf" "$af"
  log "Subdomains: $(wc -l < "$RECON_DIR/subs.txt" | tr -d ' ')"
}

stage_live() {
  if should_skip_resume live.txt; then
    warn "Resume: skipping live (live.txt exists)"
    return
  fi
  [[ -s "$RECON_DIR/subs.txt" ]] || die "subs.txt empty — run subs stage first"
  httpx -l "$RECON_DIR/subs.txt" -silent -status-code -title -tech-detect \
    -rate-limit "$HTTPX_RATE" -json -o "$RECON_DIR/live.json"
  if command -v jq &>/dev/null; then
    jq -r 'select(.url != null) | .url' "$RECON_DIR/live.json" > "$RECON_DIR/live.txt"
  else
    grep -oE '"url"\s*:\s*"[^"]+"' "$RECON_DIR/live.json" | sed 's/.*"url"\s*:\s*"//;s/"$//' > "$RECON_DIR/live.txt" || true
  fi
  [[ -s "$RECON_DIR/live.txt" ]] || cp "$RECON_DIR/subs.txt" "$RECON_DIR/live.txt"
  log "Live hosts: $(wc -l < "$RECON_DIR/live.txt" | tr -d ' ')"
}

stage_urls() {
  if should_skip_resume urls.txt; then
    warn "Resume: skipping urls (urls.txt exists)"
    return
  fi
  [[ -s "$RECON_DIR/subs.txt" ]] || die "subs.txt empty — run subs stage first"
  local tmp="$RECON_DIR/urls.tmp"
  : > "$tmp"
  while IFS= read -r sub; do
    [[ -z "$sub" ]] && continue
    echo "$sub" | waybackurls >> "$tmp" 2>/dev/null || true
  done < "$RECON_DIR/subs.txt"
  sort -u "$tmp" -o "$RECON_DIR/urls.txt"
  rm -f "$tmp"
  log "URLs collected: $(wc -l < "$RECON_DIR/urls.txt" | tr -d ' ')"
}

stage_fuzz() {
  [[ -s "$RECON_DIR/live.txt" ]] || die "live.txt empty — run live stage first"
  [[ -f "$WORDLIST" ]] || die "Wordlist not found: $WORDLIST"
  mkdir -p "$RECON_DIR/fuzz"
  local url host out base
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    base="${url%/}"
    host="$(echo "$base" | sed -E 's#^https?://##' | tr '/:' '_')"
    out="$RECON_DIR/fuzz/${host}.json"
    if [[ "$RESUME" == true && -f "$out" && -s "$out" ]]; then
      warn "Resume: skipping ffuf for $url"
      continue
    fi
    log "ffuf: $base"
    ffuf -u "${base}/FUZZ" -w "$WORDLIST" -of json -o "$out" \
      -t "$FFUF_THREADS" -s -noninteractive 2>/dev/null || warn "ffuf finished with errors for $url"
  done < "$RECON_DIR/live.txt"
  log "Fuzz outputs: $(find "$RECON_DIR/fuzz" -name '*.json' 2>/dev/null | wc -l | tr -d ' ') files"
}

stage_scan() {
  local jsonl="$RECON_DIR/nuclei/results.jsonl"
  if should_skip_resume "$jsonl"; then
    warn "Resume: skipping scan (results.jsonl exists)"
    return
  fi
  [[ -s "$RECON_DIR/live.txt" ]] || die "live.txt empty — run live stage first"
  mkdir -p "$RECON_DIR/nuclei"
  nuclei -l "$RECON_DIR/live.txt" -severity "$NUCLEI_SEVERITY" \
    -jsonl-export "$jsonl" \
    -o "$RECON_DIR/nuclei/summary.txt" || true
  log "Nuclei scan complete"
}

count_lines() {
  local f="$1"
  [[ -f "$f" && -s "$f" ]] && wc -l < "$f" | tr -d ' ' || echo "0"
}

nuclei_severity_counts() {
  local jsonl="$RECON_DIR/nuclei/results.jsonl"
  local crit=0 high=0 medium=0 low=0 info=0 total=0
  if [[ ! -f "$jsonl" ]]; then
    echo "0 0 0 0 0 0"
    return
  fi
  if command -v jq &>/dev/null; then
    total="$(wc -l < "$jsonl" | tr -d ' ')"
    crit="$(jq -rs '[.[] | select(.info.severity=="critical")] | length' "$jsonl" 2>/dev/null || echo 0)"
    high="$(jq -rs '[.[] | select(.info.severity=="high")] | length' "$jsonl" 2>/dev/null || echo 0)"
    medium="$(jq -rs '[.[] | select(.info.severity=="medium")] | length' "$jsonl" 2>/dev/null || echo 0)"
    low="$(jq -rs '[.[] | select(.info.severity=="low")] | length' "$jsonl" 2>/dev/null || echo 0)"
    info="$(jq -rs '[.[] | select(.info.severity=="info")] | length' "$jsonl" 2>/dev/null || echo 0)"
  else
    total="$(wc -l < "$jsonl" | tr -d ' ')"
    crit="$(grep -ci '"severity":"critical"' "$jsonl" 2>/dev/null || echo 0)"
    high="$(grep -ci '"severity":"high"' "$jsonl" 2>/dev/null || echo 0)"
    medium="$(grep -ci '"severity":"medium"' "$jsonl" 2>/dev/null || echo 0)"
    low="$(grep -ci '"severity":"low"' "$jsonl" 2>/dev/null || echo 0)"
    info="$(grep -ci '"severity":"info"' "$jsonl" 2>/dev/null || echo 0)"
  fi
  echo "$total $crit $high $medium $low $info"
}

httpx_status_summary() {
  local json="$RECON_DIR/live.json"
  if [[ ! -f "$json" ]]; then
    echo "(no live.json)"
    return
  fi
  if command -v jq &>/dev/null; then
    jq -rs '[.[] | .status_code // empty] | group_by(.) | map({code: .[0], count: length}) | .[] | "\(.code): \(.count)"' "$json" 2>/dev/null | head -10
  else
    grep -o '"status_code":[0-9]*' "$json" 2>/dev/null | sort | uniq -c | head -10
  fi
}

stage_summary() {
  local subs live urls nuc_line total crit high medium low info
  subs="$(count_lines "$RECON_DIR/subs.txt")"
  live="$(count_lines "$RECON_DIR/live.txt")"
  urls="$(count_lines "$RECON_DIR/urls.txt")"
  read -r total crit high medium low info <<< "$(nuclei_severity_counts)"

  local generated
  generated="$(date -u +"%Y-%m-%d %H:%M UTC")"

  cat > "$RECON_DIR/summary.md" <<EOF
# Recon Summary — $TARGET

Generated: $generated

## Counts

- Subdomains: $subs
- Live hosts: $live
- URLs collected: $urls
- Nuclei findings: $total (critical: $crit, high: $high, medium: $medium, low: $low, info: $info)

## HTTP status codes (top)

$(httpx_status_summary)

## Outputs

- \`subs.txt\`, \`live.txt\`, \`live.json\`, \`urls.txt\`
- \`nuclei/results.jsonl\`, \`nuclei/summary.txt\`
- \`fuzz/\` (when run with \`--full\`)
- \`run.log\`

## Next steps

1. Manual Burp testing using \`live.txt\`
2. Review nuclei results in \`nuclei/\`
3. Optional: \`../../scripts/run-recon.sh --target $TARGET --full\` for ffuf
EOF

  # Update notes README with summary link
  local notes="$PROJECT_DIR/notes/README.md"
  if [[ -f "$notes" ]]; then
    if ! grep -q "recon/summary.md" "$notes" 2>/dev/null; then
      echo "" >> "$notes"
      echo "Last recon summary: ../recon/summary.md ($generated)" >> "$notes"
    else
      sed -i.bak "s|Last recon summary:.*|Last recon summary: ../recon/summary.md ($generated)|" "$notes" 2>/dev/null || true
      rm -f "${notes}.bak"
    fi
  fi

  log "Summary written to summary.md"
}

main() {
  resolve_target
  : > "$LOG_FILE"
  log "Recon pipeline — target: $TARGET"
  log "Lab root: $LAB_ROOT"
  log "Recon dir: $RECON_DIR"

  if [[ -n "$ONLY_STAGE" ]]; then
    case "$ONLY_STAGE" in
      subs|live|urls|fuzz|scan|summary) ;;
      *) die "Invalid --only stage: $ONLY_STAGE" ;;
    esac
    check_bins
    run_stage "$ONLY_STAGE"
    exit 0
  fi

  check_bins

  local stage
  for stage in "${ALL_STAGES[@]}"; do
    run_stage "$stage"
  done

  log "Pipeline complete"
}

main "$@"

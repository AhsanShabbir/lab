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

# shellcheck source=lib/filter-scope.sh
source "$SCRIPT_DIR/lib/filter-scope.sh"

RECON_DIR="$(pwd)"
PROJECT_DIR="$(cd "$RECON_DIR/.." && pwd)"
LOG_FILE="$RECON_DIR/run.log"

TARGET=""
ONLY_STAGE=""
FULL=false
RESUME=false
declare -a SKIP_STAGES=()

ALL_STAGES=(subs dns live network urls crawl fuzz scan sqli summary)

log() { echo "[+] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[!] $*" | tee -a "$LOG_FILE" >&2; }
die() { echo "[-] $*" | tee -a "$LOG_FILE" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: run-recon.sh [options]

Options:
  --target <domain>   Target domain (or set in ../meta.json)
  --only <stage>      Run single stage: subs|dns|live|network|urls|crawl|fuzz|scan|sqli|summary
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

require_jq() {
  command -v jq &>/dev/null || die "jq is required. Install: brew install jq"
}

bins_for_stage() {
  case "$1" in
    subs) echo "subfinder assetfinder" ;;
    dns) echo "dnsx" ;;
    live) echo "httpx jq" ;;
    network) echo "naabu jq" ;;
    urls) echo "gau waybackurls" ;;
    crawl) echo "katana" ;;
    fuzz) echo "ffuf" ;;
    scan) echo "nuclei jq" ;;
    sqli) echo "sqlmap" ;;
    summary) echo "jq" ;;
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
  if [[ "$stage" == "dns" ]] && [[ "${ENABLE_DNS_STAGE:-true}" != "true" ]]; then
    return 1
  fi
  if [[ "$stage" == "network" ]] && [[ "${ENABLE_NETWORK_STAGE:-true}" != "true" ]]; then
    return 1
  fi
  if [[ "$stage" == "sqli" ]] && [[ "${ENABLE_SQLMAP_STAGE:-true}" != "true" ]]; then
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
  local ff="$RECON_DIR/subs.findomain.tmp"
  : > "$sf"
  : > "$af"
  : > "$ff"

  if [[ "${SUBFINDER_ALL:-true}" == "true" ]]; then
    subfinder -d "$TARGET" -all -silent > "$sf" &
  else
    subfinder -d "$TARGET" -silent > "$sf" &
  fi
  assetfinder "$TARGET" > "$af" &
  if command -v findomain &>/dev/null; then
    findomain -t "$TARGET" -q > "$ff" 2>/dev/null &
  else
    warn "findomain not installed — skipping (brew install findomain)"
  fi
  wait

  cat "$sf" "$af" "$ff" | sed '/^$/d' | sort -u > "$RECON_DIR/subs.txt"
  rm -f "$sf" "$af" "$ff"
  apply_scope_filter "subdomains" "$RECON_DIR/subs.txt" host
  log "Subdomains: $(wc -l < "$RECON_DIR/subs.txt" | tr -d ' ')"
}

stage_dns() {
  if should_skip_resume dns.json; then
    warn "Resume: skipping dns (dns.json exists)"
    return
  fi
  [[ -s "$RECON_DIR/subs.txt" ]] || die "subs.txt empty — run subs stage first"
  dnsx -l "$RECON_DIR/subs.txt" -json -o "$RECON_DIR/dns.json" -a -cname -mx -resp -silent 2>/dev/null || \
    warn "dnsx finished with errors"
  if [[ -f "$RECON_DIR/dns.json" ]] && command -v jq &>/dev/null; then
    jq -r '.host // empty' "$RECON_DIR/dns.json" 2>/dev/null | sed '/^$/d' | sort -u > "$RECON_DIR/dns.txt" || : > "$RECON_DIR/dns.txt"
  else
    cp "$RECON_DIR/subs.txt" "$RECON_DIR/dns.txt"
  fi
  apply_scope_filter "DNS hosts" "$RECON_DIR/dns.txt" host
  log "DNS records: $(wc -l < "$RECON_DIR/dns.json" 2>/dev/null | tr -d ' ' || echo 0) lines in dns.json"
}

stage_live() {
  if should_skip_resume live.txt; then
    warn "Resume: skipping live (live.txt exists)"
    return
  fi
  [[ -s "$RECON_DIR/subs.txt" ]] || die "subs.txt empty — run subs stage first"
  require_jq
  httpx -l "$RECON_DIR/subs.txt" -silent -status-code -title -tech-detect \
    -rate-limit "$HTTPX_RATE" -json -o "$RECON_DIR/live.json"
  jq -r 'select(.url != null) | .url' "$RECON_DIR/live.json" > "$RECON_DIR/live.txt"
  if [[ ! -s "$RECON_DIR/live.txt" ]]; then
    warn "httpx found no live hosts — live.txt left empty (subs are not copied)"
    : > "$RECON_DIR/live.txt"
  fi
  filter_live_outputs
  log "Live hosts: $(wc -l < "$RECON_DIR/live.txt" | tr -d ' ')"
}

stage_network() {
  local net_dir="$RECON_DIR/network"
  local hosts_file="$net_dir/hosts.txt"
  local naabu_json="$net_dir/naabu.json"
  local open_ports="$net_dir/open-ports.txt"
  local hosts_with_ports="$net_dir/hosts-with-ports.txt"

  if should_skip_resume "$open_ports"; then
    warn "Resume: skipping network (open-ports.txt exists)"
    return
  fi

  [[ -s "$RECON_DIR/subs.txt" ]] || die "subs.txt empty — run subs stage first"

  mkdir -p "$net_dir"
  head -n "${NETWORK_MAX_HOSTS:-50}" "$RECON_DIR/subs.txt" > "$hosts_file"
  apply_scope_filter "network hosts" "$hosts_file" host

  if [[ ! -s "$hosts_file" ]]; then
    warn "No hosts for network scan after scope filter — skipping network stage"
    : > "$open_ports"
    : > "$hosts_with_ports"
    return
  fi

  require_jq
  log "Port scan (naabu): $(wc -l < "$hosts_file" | tr -d ' ') host(s), top ${NAABU_TOP_PORTS:-1000} ports"
  local rc=0
  naabu -list "$hosts_file" -json -o "$naabu_json" \
    -top-ports "${NAABU_TOP_PORTS:-1000}" -rate "${NAABU_RATE:-1000}" -silent 2>/dev/null || rc=$?
  if ((rc != 0)); then
    warn "naabu exited $rc"
  fi

  : > "$open_ports"
  : > "$hosts_with_ports"
  if [[ -f "$naabu_json" && -s "$naabu_json" ]]; then
    jq -r 'select(.host != null and .port != null) | "\(.host):\(.port)"' "$naabu_json" 2>/dev/null \
      | sed '/^$/d' | sort -u > "$open_ports" || : > "$open_ports"
    jq -r 'select(.host != null and .port != null) | .host' "$naabu_json" 2>/dev/null \
      | sed '/^$/d' | sort -u > "$hosts_with_ports" || : > "$hosts_with_ports"
  fi

  if [[ -s "$open_ports" ]]; then
    apply_scope_filter "open ports" "$open_ports" host
    cut -d: -f1 "$open_ports" | sort -u > "$hosts_with_ports"
  else
    warn "No open ports found (or naabu produced no parseable JSON)"
  fi

  log "Open ports: $(wc -l < "$open_ports" | tr -d ' ') (hosts with ports: $(wc -l < "$hosts_with_ports" | tr -d ' '))"
}

stage_urls() {
  if should_skip_resume urls-archive.txt; then
    warn "Resume: skipping urls (urls-archive.txt exists)"
    merge_url_outputs
    return
  fi
  [[ -s "$RECON_DIR/subs.txt" ]] || die "subs.txt empty — run subs stage first"
  local tmp="$RECON_DIR/urls-archive.tmp"
  : > "$tmp"

  if command -v gau &>/dev/null; then
    log "Collecting archive URLs (gau)"
    gau --subs "$TARGET" >> "$tmp" 2>/dev/null || warn "gau --subs finished with errors"
    while IFS= read -r sub; do
      [[ -z "$sub" ]] && continue
      gau "$sub" >> "$tmp" 2>/dev/null || true
    done < "$RECON_DIR/subs.txt"
  else
    warn "gau not found — using waybackurls only"
  fi

  log "Collecting archive URLs (waybackurls fallback)"
  echo "$TARGET" | waybackurls >> "$tmp" 2>/dev/null || true
  while IFS= read -r sub; do
    [[ -z "$sub" ]] && continue
    echo "$sub" | waybackurls >> "$tmp" 2>/dev/null || true
  done < "$RECON_DIR/subs.txt"

  sort -u "$tmp" -o "$RECON_DIR/urls-archive.txt"
  rm -f "$tmp"
  apply_scope_filter "archive URLs" "$RECON_DIR/urls-archive.txt" url
  merge_url_outputs
  log "Archive URLs: $(wc -l < "$RECON_DIR/urls-archive.txt" | tr -d ' ')"
}

filter_static_urls() {
  local infile="$1" outfile="$2"
  grep -viE '\.(css|png|jpe?g|gif|svg|ico|woff2?|ttf|eot|map|webp|avif)(\?|$)' "$infile" 2>/dev/null | \
    grep -viE '^[[:space:]]*$' > "$outfile" || : > "$outfile"
}

merge_url_outputs() {
  local merged="$RECON_DIR/urls.txt"
  local archive="$RECON_DIR/urls-archive.txt"
  local live_urls="$RECON_DIR/urls-live.txt"
  : > "$merged"
  [[ -f "$archive" ]] && cat "$archive" >> "$merged"
  [[ -f "$live_urls" ]] && cat "$live_urls" >> "$merged"
  if [[ -s "$merged" ]]; then
    sort -u "$merged" -o "$merged"
  fi
  log "Merged URLs (urls.txt): $(wc -l < "$merged" | tr -d ' ')"
}

build_urls_scan() {
  local out="$RECON_DIR/urls-scan.txt"
  local tmp="$RECON_DIR/urls-scan.tmp"
  local max="${URLS_SCAN_MAX:-3000}"
  : > "$tmp"

  if [[ -f "$RECON_DIR/urls-live.txt" && -s "$RECON_DIR/urls-live.txt" ]]; then
    filter_static_urls "$RECON_DIR/urls-live.txt" "$tmp"
  fi

  if [[ -f "$RECON_DIR/urls-archive.txt" && -s "$RECON_DIR/urls-archive.txt" ]]; then
    local archive_filtered="$RECON_DIR/urls-archive.filtered.tmp"
    filter_static_urls "$RECON_DIR/urls-archive.txt" "$archive_filtered"
    local current
    current="$(wc -l < "$tmp" | tr -d ' ')"
    if ((current < max)); then
      head -n "$((max - current))" "$archive_filtered" >> "$tmp" 2>/dev/null || true
    fi
    rm -f "$archive_filtered"
  fi

  sort -u "$tmp" -o "$out"
  if [[ -s "$out" ]]; then
    head -n "$max" "$out" > "${out}.cap" && mv "${out}.cap" "$out"
  fi
  rm -f "$tmp"
  apply_scope_filter "scan URLs" "$out" url
  log "URLs for nuclei pass 2: $(wc -l < "$out" | tr -d ' ')"
}

stage_crawl() {
  if should_skip_resume urls-live.txt; then
    warn "Resume: skipping crawl (urls-live.txt exists)"
    merge_url_outputs
    return
  fi
  [[ -s "$RECON_DIR/live.txt" ]] || die "live.txt empty — run live stage first"

  local hosts_file="$RECON_DIR/crawl-hosts.txt"
  head -n "${CRAWL_MAX_HOSTS:-30}" "$RECON_DIR/live.txt" > "$hosts_file"
  local crawl_out="$RECON_DIR/urls-live.tmp"
  : > "$crawl_out"

  log "Crawling up to ${CRAWL_MAX_HOSTS:-30} live hosts (katana)"
  katana -list "$hosts_file" -depth "${KATANA_DEPTH:-2}" -rate-limit "${KATANA_RATE_LIMIT:-50}" \
    -silent -json -o "$RECON_DIR/katana.json" 2>/dev/null || warn "katana finished with errors"

  if [[ -f "$RECON_DIR/katana.json" ]] && command -v jq &>/dev/null; then
    jq -r '.request.endpoint // .url // empty' "$RECON_DIR/katana.json" 2>/dev/null | sed '/^$/d' >> "$crawl_out" || true
  fi
  if [[ ! -s "$crawl_out" ]]; then
    katana -list "$hosts_file" -depth "${KATANA_DEPTH:-2}" -rate-limit "${KATANA_RATE_LIMIT:-50}" \
      -silent -o "$crawl_out" 2>/dev/null || warn "katana plain output failed"
  fi

  sort -u "$crawl_out" -o "$RECON_DIR/urls-live.txt"
  rm -f "$crawl_out" "$hosts_file"
  apply_scope_filter "crawl URLs" "$RECON_DIR/urls-live.txt" url
  merge_url_outputs
  log "Crawl URLs: $(wc -l < "$RECON_DIR/urls-live.txt" | tr -d ' ')"
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

nuclei_common_args() {
  NUCLEI_EXCLUDE_FILE="$RECON_DIR/nuclei/exclude-hosts.txt"
  nuclei_exclude_hosts_file "$NUCLEI_EXCLUDE_FILE"
}

nuclei_run_pass() {
  local input="$1" severity="$2" tags="$3" jsonl_out="$4" summary_out="$5"
  local -a args=(
    -l "$input"
    -severity "$severity"
    -exclude-hosts "$NUCLEI_EXCLUDE_FILE"
    -jsonl-export "$jsonl_out"
    -o "$summary_out"
    -rl "${NUCLEI_RATE_LIMIT:-100}"
    -c "${NUCLEI_CONCURRENCY:-25}"
    -timeout "${NUCLEI_TIMEOUT:-10m}"
  )
  if [[ -n "$tags" ]]; then
    args+=(-tags "$tags")
  fi
  local rc=0
  nuclei "${args[@]}" || rc=$?
  if ((rc != 0)); then
    warn "nuclei exited $rc (input: $input, output: $jsonl_out)"
  fi
  return 0
}

merge_nuclei_results() {
  local merged="$RECON_DIR/nuclei/results.jsonl"
  local live_jsonl="$RECON_DIR/nuclei/results-live.jsonl"
  local urls_jsonl="$RECON_DIR/nuclei/results-urls.jsonl"
  : > "$merged"
  [[ -f "$live_jsonl" && -s "$live_jsonl" ]] && cat "$live_jsonl" >> "$merged"
  [[ -f "$urls_jsonl" && -s "$urls_jsonl" ]] && cat "$urls_jsonl" >> "$merged"
  log "Merged nuclei results: $(wc -l < "$merged" | tr -d ' ') findings"
}

stage_scan() {
  local merged="$RECON_DIR/nuclei/results.jsonl"
  local live_jsonl="$RECON_DIR/nuclei/results-live.jsonl"
  local urls_jsonl="$RECON_DIR/nuclei/results-urls.jsonl"

  if should_skip_resume "$merged"; then
    warn "Resume: skipping scan (results.jsonl exists)"
    return
  fi
  [[ -s "$RECON_DIR/live.txt" ]] || die "live.txt empty — run live stage first"
  filter_live_outputs
  mkdir -p "$RECON_DIR/nuclei"
  nuclei_common_args

  if ! should_skip_resume "$live_jsonl"; then
    log "Nuclei pass 1: live hosts ($NUCLEI_SEVERITY_LIVE)"
    nuclei_run_pass "$RECON_DIR/live.txt" "${NUCLEI_SEVERITY_LIVE:-high,critical}" "" \
      "$live_jsonl" "$RECON_DIR/nuclei/summary.txt"
  else
    warn "Resume: skipping nuclei live pass (results-live.jsonl exists)"
  fi

  build_urls_scan
  if [[ -s "$RECON_DIR/urls-scan.txt" ]]; then
    if ! should_skip_resume "$urls_jsonl"; then
      log "Nuclei pass 2: URLs ($NUCLEI_SEVERITY_URLS, tags: $NUCLEI_TAGS_URLS)"
      nuclei_run_pass "$RECON_DIR/urls-scan.txt" "${NUCLEI_SEVERITY_URLS:-medium,high,critical}" \
        "${NUCLEI_TAGS_URLS:-cve,exposure,misconfig}" \
        "$urls_jsonl" "$RECON_DIR/nuclei/summary-urls.txt"
    else
      warn "Resume: skipping nuclei URL pass (results-urls.jsonl exists)"
    fi
  else
    warn "urls-scan.txt empty — skipping nuclei URL pass"
    : > "$urls_jsonl"
  fi

  merge_nuclei_results
  log "Nuclei scan complete"
}

build_sqlmap_candidates() {
  mkdir -p "$RECON_DIR/sqlmap"
  local out="$RECON_DIR/sqlmap/candidates.txt"
  local tmp="$RECON_DIR/sqlmap/candidates.tmp"
  local src="$RECON_DIR/urls-scan.txt"
  : > "$tmp"

  if [[ -f "$src" && -s "$src" ]]; then
    filter_static_urls "$src" "$RECON_DIR/sqlmap/from-scan.tmp"
    cat "$RECON_DIR/sqlmap/from-scan.tmp" >> "$tmp"
    rm -f "$RECON_DIR/sqlmap/from-scan.tmp"
  fi
  if [[ -f "$RECON_DIR/urls-live.txt" && -s "$RECON_DIR/urls-live.txt" ]]; then
    filter_static_urls "$RECON_DIR/urls-live.txt" "$RECON_DIR/sqlmap/from-live.tmp"
    cat "$RECON_DIR/sqlmap/from-live.tmp" >> "$tmp"
    rm -f "$RECON_DIR/sqlmap/from-live.tmp"
  fi
  if [[ ! -s "$tmp" && -f "$RECON_DIR/urls.txt" ]]; then
    filter_static_urls "$RECON_DIR/urls.txt" "$RECON_DIR/sqlmap/from-all.tmp"
    cat "$RECON_DIR/sqlmap/from-all.tmp" >> "$tmp"
    rm -f "$RECON_DIR/sqlmap/from-all.tmp"
  fi

  grep -E '\?' "$tmp" 2>/dev/null | grep -E '[?&][^=&]+=' | sort -u | head -n "${SQLMAP_MAX_URLS:-50}" > "$out"
  rm -f "$tmp"
  apply_scope_filter "sqlmap candidates" "$out" url
}

parse_sqlmap_output() {
  local outdir="$RECON_DIR/sqlmap/output"
  local vulnerable="$RECON_DIR/sqlmap/vulnerable.txt"
  local findings="$RECON_DIR/sqlmap/findings.json"
  : > "$vulnerable"
  : > "$findings"
  [[ -d "$outdir" ]] || {
    echo "[]" > "$findings"
    return 0
  }

  require_jq
  local entries="[]"
  local target_file log_file url param inject_type

  while IFS= read -r target_file; do
    [[ -f "$target_file" ]] || continue
    url="$(tr -d '\r' < "$target_file" | head -1)"
    [[ -z "$url" ]] || [[ "$url" != http* ]] && continue
    log_file="$(dirname "$target_file")/log"
    [[ -f "$log_file" ]] || continue
    if ! grep -qE 'appears to be injectable|is vulnerable|sqlmap identified the following injection|Type:.+(based|UNION|stacked)' "$log_file" 2>/dev/null; then
      continue
    fi
    param="$(grep -m1 'Parameter:' "$log_file" 2>/dev/null | sed -E "s/.*Parameter: ([^ (]+).*/\1/" || echo "unknown")"
    inject_type="$(grep -m1 '^Type:' "$log_file" 2>/dev/null | sed 's/^Type: //' || echo "unknown")"
    echo "$url" >> "$vulnerable"
    entries="$(jq -nc --arg url "$url" --arg param "$param" --arg type "$inject_type" \
      '$entries + [{url: $url, parameter: $param, injectionType: $type}]' --argjson entries "$entries")"
  done < <(find "$outdir" -name 'target.txt' 2>/dev/null)

  sort -u "$vulnerable" -o "$vulnerable"
  echo "$entries" | jq '.' > "$findings"
}

sqli_summary_section() {
  local findings="$RECON_DIR/sqlmap/findings.json"
  local candidates="$RECON_DIR/sqlmap/candidates.txt"
  local vuln="$RECON_DIR/sqlmap/vulnerable.txt"
  local n_cand n_vuln

  n_cand="$(count_lines "$candidates")"
  n_vuln="$(count_lines "$vuln")"

  if [[ ! -f "$findings" ]]; then
    echo "_SQLmap stage not run._"
    return
  fi

  if ((n_vuln == 0)); then
    echo "Tested **${n_cand}** parameterized URL(s); **no confirmed SQL injection** in automated sqlmap pass."
    return
  fi

  echo "**${n_vuln}** potentially injectable URL(s) (sqlmap) — verify manually:"
  echo ""
  if command -v jq &>/dev/null; then
    jq -r '.[] | "- `\(.url)` — parameter `\(.parameter)` (\(.injectionType))"' "$findings" 2>/dev/null
  else
    sed 's/^/- `/' "$vuln" | sed 's/$/`/'
  fi
  echo ""
  echo "Full details: \`sqlmap/findings.json\`, logs in \`sqlmap/output/\`."
}

stage_sqli() {
  local findings="$RECON_DIR/sqlmap/findings.json"
  if should_skip_resume "$findings"; then
    warn "Resume: skipping sqli (findings.json exists)"
    return
  fi

  command -v sqlmap &>/dev/null || die "sqlmap not found. Install: brew install sqlmap"

  if [[ ! -f "$RECON_DIR/urls-scan.txt" ]]; then
    build_urls_scan 2>/dev/null || true
  fi
  build_sqlmap_candidates

  local candidates="$RECON_DIR/sqlmap/candidates.txt"
  if [[ ! -s "$candidates" ]]; then
    warn "No parameterized URLs for sqlmap — skipping sqli stage"
    echo "[]" > "$findings"
    : > "$RECON_DIR/sqlmap/vulnerable.txt"
    return
  fi

  mkdir -p "$RECON_DIR/sqlmap/output"
  log "SQLmap: testing $(wc -l < "$candidates" | tr -d ' ') candidate URL(s) (--smart, level ${SQLMAP_LEVEL:-1})"

  local rc=0
  sqlmap -m "$candidates" --batch --smart \
    --output-dir="$RECON_DIR/sqlmap/output" \
    --threads="${SQLMAP_THREADS:-2}" \
    --level="${SQLMAP_LEVEL:-1}" \
    --risk="${SQLMAP_RISK:-1}" \
    --random-agent \
    2>&1 | tee -a "$RECON_DIR/sqlmap/run.log" || rc=$?

  if ((rc != 0)); then
    warn "sqlmap exited $rc (partial results may exist under sqlmap/output/)"
  fi

  parse_sqlmap_output
  local n_vuln
  n_vuln="$(count_lines "$RECON_DIR/sqlmap/vulnerable.txt")"
  if ((n_vuln > 0)); then
    log "SQLmap: ${n_vuln} potentially injectable URL(s) — see sqlmap/vulnerable.txt and summary.md"
  else
    log "SQLmap: no injectable parameters confirmed"
  fi
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
  require_jq
  total="$(wc -l < "$jsonl" | tr -d ' ')"
  crit="$(jq -rs '[.[] | select(.info.severity=="critical")] | length' "$jsonl" 2>/dev/null || echo 0)"
  high="$(jq -rs '[.[] | select(.info.severity=="high")] | length' "$jsonl" 2>/dev/null || echo 0)"
  medium="$(jq -rs '[.[] | select(.info.severity=="medium")] | length' "$jsonl" 2>/dev/null || echo 0)"
  low="$(jq -rs '[.[] | select(.info.severity=="low")] | length' "$jsonl" 2>/dev/null || echo 0)"
  info="$(jq -rs '[.[] | select(.info.severity=="info")] | length' "$jsonl" 2>/dev/null || echo 0)"
  echo "$total $crit $high $medium $low $info"
}

httpx_status_summary() {
  local json="$RECON_DIR/live.json"
  if [[ ! -f "$json" ]]; then
    echo "(no live.json)"
    return
  fi
  require_jq
  jq -rs '[.[] | .status_code // empty] | group_by(.) | map({code: .[0], count: length}) | .[] | "\(.code): \(.count)"' "$json" 2>/dev/null | head -10
}

network_top_ports_section() {
  local json="$RECON_DIR/network/naabu.json"
  if [[ ! -f "$json" || ! -s "$json" ]]; then
    echo "_Network stage not run or no naabu output._"
    return
  fi
  require_jq
  jq -rs '
    [.[] | select(.port != null) | .port | tonumber] |
    group_by(.) | map({port: .[0], count: length}) |
    sort_by(-.count) | .[:10][] |
    "- Port \(.port): \(.count) host(s)"
  ' "$json" 2>/dev/null || echo "(could not parse naabu.json for port stats)"
}

stage_summary() {
  local subs live net_hosts net_ports net_hosts_open urls archive crawl scan_urls sqli_cand sqli_vuln nuc_line total crit high medium low info
  subs="$(count_lines "$RECON_DIR/subs.txt")"
  live="$(count_lines "$RECON_DIR/live.txt")"
  net_hosts="$(count_lines "$RECON_DIR/network/hosts.txt")"
  net_ports="$(count_lines "$RECON_DIR/network/open-ports.txt")"
  net_hosts_open="$(count_lines "$RECON_DIR/network/hosts-with-ports.txt")"
  urls="$(count_lines "$RECON_DIR/urls.txt")"
  archive="$(count_lines "$RECON_DIR/urls-archive.txt")"
  crawl="$(count_lines "$RECON_DIR/urls-live.txt")"
  scan_urls="$(count_lines "$RECON_DIR/urls-scan.txt")"
  sqli_cand="$(count_lines "$RECON_DIR/sqlmap/candidates.txt")"
  sqli_vuln="$(count_lines "$RECON_DIR/sqlmap/vulnerable.txt")"
  read -r total crit high medium low info <<< "$(nuclei_severity_counts)"

  local generated sqli_block net_ports_block
  generated="$(date -u +"%Y-%m-%d %H:%M UTC")"
  sqli_block="$(sqli_summary_section)"
  net_ports_block="$(network_top_ports_section)"

  cat > "$RECON_DIR/summary.md" <<EOF
# Recon Summary — $TARGET

Generated: $generated

## Counts

- Subdomains: $subs
- Live hosts: $live
- Network hosts scanned: $net_hosts
- Open ports (host:port): $net_ports
- Hosts with open ports: $net_hosts_open
- Archive URLs: $archive
- Crawl URLs (live): $crawl
- Merged URLs (urls.txt): $urls
- URLs scanned (nuclei pass 2): $scan_urls
- Nuclei findings: $total (critical: $crit, high: $high, medium: $medium, low: $low, info: $info)
- SQLmap candidates tested: $sqli_cand
- **SQL injection (sqlmap): $sqli_vuln potentially vulnerable**

## Network (naabu)

$net_ports_block

## SQL injection (sqlmap)

$sqli_block

## HTTP status codes (top)

$(httpx_status_summary)

## Outputs

- \`subs.txt\`, \`dns.json\`, \`dns.txt\`
- \`live.txt\`, \`live.json\`
- \`network/hosts.txt\`, \`network/naabu.json\`, \`network/open-ports.txt\`, \`network/hosts-with-ports.txt\`
- \`urls-archive.txt\`, \`urls-live.txt\`, \`urls-scan.txt\`, \`urls.txt\`
- \`nuclei/results.jsonl\` (merged), \`results-live.jsonl\`, \`results-urls.jsonl\`
- \`nuclei/summary.txt\`, \`nuclei/summary-urls.txt\`
- \`sqlmap/candidates.txt\`, \`sqlmap/vulnerable.txt\`, \`sqlmap/findings.json\`
- \`fuzz/\` (when run with \`--full\`)
- \`run.log\`

## Next steps

1. Manual Burp testing using \`live.txt\`
2. Review open ports in \`network/open-ports.txt\`
3. Review nuclei results in \`nuclei/\`
4. **Confirm sqlmap hits** in \`sqlmap/vulnerable.txt\` before reporting
5. Optional: \`../../scripts/run-recon.sh --target $TARGET --full\` for ffuf
EOF

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

append_log_banner() {
  {
    echo ""
    echo "--- Run $(date -u +"%Y-%m-%d %H:%M:%S UTC") — target: $TARGET ---"
  } >> "$LOG_FILE"
}

main() {
  resolve_target
  append_log_banner
  log "Recon pipeline — target: $TARGET"
  log "WISE lab root: $LAB_ROOT"
  log "Recon dir: $RECON_DIR"

  local valid_stages="subs dns live network urls crawl fuzz scan sqli summary"

  if [[ -n "$ONLY_STAGE" ]]; then
    case " $valid_stages " in
      *" $ONLY_STAGE "*) ;;
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

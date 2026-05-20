#!/bin/bash
# Scope and third-party filtering for the recon pipeline.
# Requires: TARGET, PROJECT_DIR, LAB_ROOT

filter_scope_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER_AWK="$filter_scope_lib_dir/filter-hosts.awk"
THIRD_PARTY_LIST="${LAB_ROOT}/config/third-party-domains.txt"

filter_build_blocklist() {
  local outfile="$1"
  : > "$outfile"
  if [[ -f "$THIRD_PARTY_LIST" ]]; then
    grep -v '^[[:space:]]*#' "$THIRD_PARTY_LIST" | grep -v '^[[:space:]]*$' >> "$outfile" || true
  fi
  if [[ -f "$PROJECT_DIR/scope/out-of-scope.txt" ]]; then
    grep -v '^[[:space:]]*#' "$PROJECT_DIR/scope/out-of-scope.txt" | grep -v '^[[:space:]]*$' >> "$outfile" || true
  fi
  sort -u -o "$outfile" "$outfile"
}

count_nonempty_lines() {
  local f="$1"
  [[ -f "$f" && -s "$f" ]] && grep -cve '^[[:space:]]*$' "$f" || echo 0
}

filter_hosts_file() {
  local infile="$1" outfile="$2" blocklist="$3"
  local before after
  before="$(count_nonempty_lines "$infile")"
  awk -v scope_root="$TARGET" -v blockfile="$blocklist" -v mode=host -f "$FILTER_AWK" "$infile" > "$outfile"
  after="$(count_nonempty_lines "$outfile")"
  echo $((before - after))
}

filter_urls_file() {
  local infile="$1" outfile="$2" blocklist="$3"
  local before after
  before="$(count_nonempty_lines "$infile")"
  awk -v scope_root="$TARGET" -v blockfile="$blocklist" -v mode=url -f "$FILTER_AWK" "$infile" > "$outfile"
  after="$(count_nonempty_lines "$outfile")"
  echo $((before - after))
}

apply_scope_filter() {
  local label="$1" infile="$2" mode="${3:-host}"
  local blocklist tmp removed=0

  [[ -f "$infile" ]] || return 0
  blocklist="$(mktemp)"
  filter_build_blocklist "$blocklist"

  tmp="${infile}.scope-filtered"
  if [[ "$mode" == "url" ]]; then
    removed="$(filter_urls_file "$infile" "$tmp" "$blocklist")"
  else
    removed="$(filter_hosts_file "$infile" "$tmp" "$blocklist")"
  fi
  mv "$tmp" "$infile"
  rm -f "$blocklist"

  if ((removed > 0)); then
    log "Scope filter ($label): removed $removed out-of-scope / third-party entries"
  fi
}

filter_live_json() {
  [[ -f "$RECON_DIR/live.json" ]] || return 0
  command -v jq &>/dev/null || {
    warn "jq not found — live.json not scope-filtered"
    return 0
  }

  local blocklist allowed tmp
  blocklist="$(mktemp)"
  allowed="$(mktemp)"
  filter_build_blocklist "$blocklist"

  jq -r '.host // empty' "$RECON_DIR/live.json" 2>/dev/null | sort -u \
    | awk -v scope_root="$TARGET" -v blockfile="$blocklist" -v mode=host -f "$FILTER_AWK" > "$allowed"

  tmp="${RECON_DIR}/live.json.scope-filtered"
  jq -c --argfile allowed <(jq -R . "$allowed" 2>/dev/null) '
    . as $row | ($row.host // "") as $h | select($h != "" and ([$allowed[] | . == $h] | any))
  ' "$RECON_DIR/live.json" > "$tmp" 2>/dev/null && mv "$tmp" "$RECON_DIR/live.json"

  rm -f "$blocklist" "$allowed"
}

filter_live_outputs() {
  apply_scope_filter "live hosts" "$RECON_DIR/live.txt" host
  filter_live_json
}

nuclei_exclude_hosts_file() {
  filter_build_blocklist "$1"
}

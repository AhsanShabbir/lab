#!/bin/bash

LAB_ROOT="$(cd "$(dirname "$0")" && pwd)"

RUN_RECON=false
FULL=false
RESUME=false
TARGET=""
ONLY_STAGE=""
declare -a SKIP_STAGES=()
declare -a RECON_ARGS=()

usage() {
  cat <<EOF
Usage: start-project.sh [options] <target-domain>

Options:
  --recon           Run recon pipeline after creating project
  --full            Include ffuf stage (passes --full to run-recon.sh)
  --resume          Skip stages with existing output
  --only <stage>    Run single pipeline stage (subs|live|urls|fuzz|scan|summary)
  --skip <stage>    Skip stage (repeatable)

Examples:
  ./start-project.sh client.com
  ./start-project.sh --recon client.com
  ./start-project.sh --recon --full client.com
  ./start-project.sh --recon --only scan client.com
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recon) RUN_RECON=true; shift ;;
    --full) FULL=true; shift ;;
    --resume) RESUME=true; shift ;;
    --only) ONLY_STAGE="${2:-}"; shift 2 ;;
    --skip) SKIP_STAGES+=("${2:-}"); shift 2 ;;
    -h|--help) usage ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        usage
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

[[ -n "$TARGET" ]] || usage

BASE="$LAB_ROOT/projects/$TARGET"
TEMPLATE_DIR="$LAB_ROOT/templates/project"
DATE="$(date -u +"%Y-%m-%d")"

substitute_template() {
  local src="$1" dest="$2"
  sed "s/__TARGET__/$TARGET/g; s/__DATE__/$DATE/g" "$src" > "$dest"
}

copy_template_file() {
  local rel="$1"
  local src="$TEMPLATE_DIR/$rel"
  local dest="$BASE/$rel"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    return 0
  fi
  substitute_template "$src" "$dest"
}

echo "[+] Creating project for $TARGET..."

mkdir -p "$BASE"/{recon,exploits,notes,reports,screenshots,scope}

# Copy template tree (skip existing files)
while IFS= read -r -d '' src_file; do
  rel="${src_file#"$TEMPLATE_DIR/"}"
  copy_template_file "$rel"
done < <(find "$TEMPLATE_DIR" -type f -print0)

# Symlink shared wordlists
if [[ ! -e "$BASE/wordlists" ]]; then
  ln -s "$LAB_ROOT/wordlists" "$BASE/wordlists"
fi

# Ensure meta.json exists
if [[ ! -f "$BASE/meta.json" ]]; then
  substitute_template "$TEMPLATE_DIR/meta.json" "$BASE/meta.json"
fi

echo "[+] Project created at $BASE"

if [[ "$RUN_RECON" != true ]]; then
  echo "[+] Next step:"
  echo "  cd $BASE/recon && $LAB_ROOT/scripts/run-recon.sh --target $TARGET"
  echo "  Or: $LAB_ROOT/start-project.sh --recon $TARGET"
  exit 0
fi

RECON_ARGS=(--target "$TARGET")
[[ "$FULL" == true ]] && RECON_ARGS+=(--full)
[[ "$RESUME" == true ]] && RECON_ARGS+=(--resume)
[[ -n "$ONLY_STAGE" ]] && RECON_ARGS+=(--only "$ONLY_STAGE")
for s in "${SKIP_STAGES[@]}"; do
  RECON_ARGS+=(--skip "$s")
done

echo "[+] Running recon pipeline..."
(cd "$BASE/recon" && "$LAB_ROOT/scripts/run-recon.sh" "${RECON_ARGS[@]}")

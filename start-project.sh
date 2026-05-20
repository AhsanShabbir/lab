#!/bin/bash

RUN_RECON=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --recon)
      RUN_RECON=true
      ;;
    -*)
      echo "Unknown option: $arg"
      echo "Usage: start-project.sh [--recon] <target-domain>"
      exit 1
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "Usage: start-project.sh [--recon] <target-domain>"
        exit 1
      fi
      TARGET="$arg"
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: start-project.sh [--recon] <target-domain>"
  exit 1
fi

BASE="$HOME/lab/projects/$TARGET"

echo "[+] Creating project for $TARGET..."

mkdir -p "$BASE"/{recon,exploits,notes,reports,screenshots,wordlists}

# Create starter files
cat > "$BASE/notes/README.md" <<EOF
# Target: $TARGET

## Notes
- Initial recon pending
EOF

cat > "$BASE/recon/commands.sh" <<EOF
# Recon commands for $TARGET

subfinder -d $TARGET -silent > subs.txt
assetfinder $TARGET >> subs.txt
sort -u subs.txt -o subs.txt

cat subs.txt | httpx -silent > live.txt

cat subs.txt | waybackurls > urls.txt

echo "[+] Recon complete"
EOF

cat > "$BASE/reports/findings.md" <<EOF
# Findings Report - $TARGET

## Vulnerabilities:
- TBD

## Notes:
- TBD
EOF

echo "[+] Project created at $BASE"

if [ "$RUN_RECON" = true ]; then
  echo "[+] Running recon..."
  (cd "$BASE/recon" && bash commands.sh)
else
  echo "[+] Next step:"
  echo "cd $BASE/recon && bash commands.sh"
  echo "Or re-run with: start-project.sh --recon $TARGET"
fi

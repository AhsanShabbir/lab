#!/bin/bash

TARGET=$1

if [ -z "$TARGET" ]; then
  echo "Usage: start <target-domain>"
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
echo "[+] Next step:"
echo "cd $BASE/recon && bash commands.sh"

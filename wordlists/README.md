# Wordlists

Default directory fuzzing list: `common-dirs.txt` (~50 paths for fast lab runs).

## Use a larger list

**Homebrew (macOS):**

```bash
brew install seclists
# Then in config/recon.defaults:
# WORDLIST="/opt/homebrew/share/seclists/Discovery/Web-Content/common.txt"
```

**Manual clone:**

```bash
git clone https://github.com/danielmiessler/SecLists.git ~/SecLists
```

Update `WORDLIST` in [config/recon.defaults](../config/recon.defaults) to point at your preferred file.

# WISE lab — Guidelines

WISE lab is a local pentest workspace for managing targets, automated recon, findings, and a web dashboard.

## Prerequisites

Install tools and verify the environment:

```bash
cd ~/lab
./setup-recon-tools.sh
source ~/lab/config/shell-path.sh   # add this line to ~/.zshrc for persistence
./tools/doctor.sh
```

---

## Project layout

Each target lives under `projects/<domain>/`:

| Path | Purpose |
|------|---------|
| `meta.json` | Target name, created date, engagement type |
| `scope/in-scope.txt` | Assets allowed for testing |
| `scope/out-of-scope.txt` | Assets that must not be tested |
| `recon/` | Automated pipeline outputs |
| `reports/findings.md` | Vulnerability report (manual) |
| `notes/` | Engagement notes |
| `exploits/` | PoCs and exploit notes |
| `screenshots/` | Evidence images |

---

## New project

Create folders and templates (safe to re-run; existing files are not overwritten):

```bash
./target example.com
```

Create and run full recon in one step:

```bash
./target --recon example.com
```

Or via Make:

```bash
make project TARGET=example.com
make recon TARGET=example.com
```

---

## Recon pipeline

Stages run in order:

```
subs → dns → live → urls → crawl → scan → sqli → summary
                              ↘ fuzz (optional, only with --full)
```

| Stage | Output | Requires |
|-------|--------|----------|
| `subs` | `subs.txt` | — (subfinder -all, assetfinder, findomain) |
| `dns` | `dns.json`, `dns.txt` | `subs.txt` (skip if `ENABLE_DNS_STAGE=false`) |
| `live` | `live.txt`, `live.json` | `subs.txt` |
| `urls` | `urls-archive.txt` | `subs.txt` (gau + waybackurls) |
| `crawl` | `urls-live.txt`, `urls.txt` | `live.txt` (katana, capped hosts) |
| `fuzz` | `fuzz/*.json` | `live.txt` and `--full` |
| `scan` | `nuclei/results*.jsonl`, summaries | `live.txt`; builds `urls-scan.txt` |
| `sqli` | `sqlmap/vulnerable.txt`, `sqlmap/findings.json` | parameterized URLs from crawl/archive |
| `summary` | `summary.md` | prior stage outputs |

**Dual-pass nuclei:** pass 1 on `live.txt` (high/critical); pass 2 on `urls-scan.txt` (medium+, tag-limited). Merged into `nuclei/results.jsonl`.

**SQLmap (`sqli` stage):** tests up to `SQLMAP_MAX_URLS` parameterized URLs (`--smart`, level/risk from config). Hits are listed in `summary.md` and highlighted in the dashboard. Set `ENABLE_SQLMAP_STAGE=false` to skip. Requires `sqlmap` (`brew install sqlmap`).

Tune caps and scanners in `config/recon.defaults` (`CRAWL_MAX_HOSTS`, `URLS_SCAN_MAX`, `NUCLEI_*`, `SQLMAP_*`, etc.).

Run from the project recon directory:

```bash
cd ~/lab/projects/example.com/recon
~/lab/scripts/run-recon.sh --target example.com
```

Or from lab root:

```bash
./target --recon example.com
```

Edit scope before recon if needed (`scope/in-scope.txt`, `scope/out-of-scope.txt`). Out-of-scope and third-party domains are filtered during the pipeline.

---

## Running a project you already started

You do **not** need to create the project again. If `projects/<domain>/` exists, go straight to recon or manual testing.

### Continue after a partial run (recommended)

Use `--resume` to skip stages whose output files already exist and are non-empty:

```bash
./target --recon --resume example.com
```

```bash
cd ~/lab/projects/example.com/recon
~/lab/scripts/run-recon.sh --target example.com --resume
```

`make recon TARGET=example.com` does **not** pass `--resume`. Use `make recon-resume TARGET=example.com`, `./target --recon --resume`, or `run-recon.sh --resume` when continuing a partial run.

### Run a single stage

Use when you know what is left (e.g. scan failed, subs/live already done):

```bash
cd ~/lab/projects/example.com/recon
~/lab/scripts/run-recon.sh --target example.com --only scan
~/lab/scripts/run-recon.sh --target example.com --only summary
```

From lab root:

```bash
./target --recon --only scan example.com
```

### Re-run from scratch (refresh data)

Run **without** `--resume` to overwrite stage outputs:

```bash
cd ~/lab/projects/example.com/recon
~/lab/scripts/run-recon.sh --target example.com
```

To refresh only one stage, delete its output file(s), then use `--resume` so other stages stay skipped:

- Re-scan: `rm nuclei/results.jsonl nuclei/results-live.jsonl nuclei/results-urls.jsonl` then `--only scan` or `--resume`
- Re-fetch subs: `rm subs.txt` (and usually `live.txt`, `urls-archive.txt`, `urls-live.txt` if you want those refreshed too)
- Re-crawl only: `rm urls-live.txt` then `--only crawl --resume`

### Directory fuzzing (ffuf)

Not included in the default pipeline. Add `--full`:

```bash
./target --recon --resume --full example.com
```

### Recon already complete

When `run.log` ends with `Pipeline complete`, automated recon is done. Next steps:

1. Review `recon/live.txt`, `recon/urls.txt`, `recon/nuclei/`, `recon/summary.md`
2. Record issues in `reports/findings.md`
3. Open `./dashboard` and select the project (Recon / Findings tabs)

To refresh nuclei or summary only:

```bash
cd ~/lab/projects/example.com/recon
rm -f nuclei/results.jsonl          # optional: force new scan
~/lab/scripts/run-recon.sh --target example.com --only scan
~/lab/scripts/run-recon.sh --target example.com --only summary
```

---

## Dashboard

Start the WISE lab UI (opens in your browser):

```bash
./dashboard
```

Default URL: `http://127.0.0.1:7331/`

Optional: `DASHBOARD_PORT=7331` `DASHBOARD_HOST=127.0.0.1`

The recon toolkit command reference is linked from the dashboard (`tools/dashboard/recon.html`).

---

## Quick reference

| Goal | Command |
|------|---------|
| New project | `./target <domain>` |
| New project + recon | `./target --recon <domain>` |
| Resume recon | `make recon-resume TARGET=<domain>` or `run-recon.sh --target <domain> --resume` |
| One stage | `run-recon.sh --target <domain> --only <stage>` |
| Full recon (overwrite) | `run-recon.sh --target <domain>` |
| Include ffuf | add `--full` |
| Check tools | `./tools/doctor.sh` |
| View projects | `./dashboard` |
| Watch pipeline | `tail -f projects/<domain>/recon/run.log` |

**Stages:** `subs` | `dns` | `live` | `urls` | `crawl` | `fuzz` | `scan` | `sqli` | `summary`

**Skip stages:** `--skip <stage>` (repeatable)

Target is read from `--target` or `projects/<domain>/meta.json` when omitted.

---

## Makefile shortcuts

```bash
make setup              # install recon tools
make doctor             # health check
make project TARGET=x   # create project
make recon TARGET=x     # create (if needed) + full recon
make recon-resume TARGET=x  # continue partial run
make dashboard          # open WISE lab UI
```

---

## Tips

- Always `source ~/lab/config/shell-path.sh` in new shells so `subfinder`, `httpx`, `nuclei`, etc. are on `PATH`.
- Keep `scope/out-of-scope.txt` up to date before long runs (e.g. third-party login domains).
- Large `urls-archive.txt` / `urls.txt` files are normal; focus manual testing on `live.txt` and `urls-live.txt` first.
- `run.log` appends each run (banner per run) — use `tail` on the last section for the current job.
- Findings live in markdown under `reports/`; the dashboard renders them but does not edit them.

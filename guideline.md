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
subs → live → urls → scan → summary
              ↘ fuzz (optional, only with --full)
```

| Stage | Output | Requires |
|-------|--------|----------|
| `subs` | `subs.txt` | — |
| `live` | `live.txt`, `live.json` | `subs.txt` |
| `urls` | `urls.txt` | `subs.txt` |
| `fuzz` | `fuzz/*.json` | `live.txt` and `--full` |
| `scan` | `nuclei/results.jsonl`, `nuclei/summary.txt` | `live.txt` |
| `summary` | `summary.md` | prior stage outputs |

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

`make recon TARGET=example.com` does **not** pass `--resume`; use `./target` or `run-recon.sh` directly when resuming.

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

- Re-scan: `rm nuclei/results.jsonl` then `--only scan` or `--resume`
- Re-fetch subs: `rm subs.txt` (and usually `live.txt`, `urls.txt` if you want those refreshed too)

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
| Resume recon | `run-recon.sh --target <domain> --resume` (from `recon/`) |
| One stage | `run-recon.sh --target <domain> --only <stage>` |
| Full recon (overwrite) | `run-recon.sh --target <domain>` |
| Include ffuf | add `--full` |
| Check tools | `./tools/doctor.sh` |
| View projects | `./dashboard` |
| Watch pipeline | `tail -f projects/<domain>/recon/run.log` |

**Stages:** `subs` | `live` | `urls` | `fuzz` | `scan` | `summary`

**Skip stages:** `--skip <stage>` (repeatable)

Target is read from `--target` or `projects/<domain>/meta.json` when omitted.

---

## Makefile shortcuts

```bash
make setup              # install recon tools
make doctor             # health check
make project TARGET=x   # create project
make recon TARGET=x     # create (if needed) + full recon
make dashboard          # open WISE lab UI
```

---

## Tips

- Always `source ~/lab/config/shell-path.sh` in new shells so `subfinder`, `httpx`, `nuclei`, etc. are on `PATH`.
- Keep `scope/out-of-scope.txt` up to date before long runs (e.g. third-party login domains).
- Large `urls.txt` files are normal after wayback collection; focus manual testing on `live.txt` first.
- Findings live in markdown under `reports/`; the dashboard renders them but does not edit them.

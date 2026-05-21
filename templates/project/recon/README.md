# Recon — __TARGET__

From WISE lab root:

```bash
../../target --recon __TARGET__
../../target --recon --resume __TARGET__
../../target --recon --only scan __TARGET__
../../target --recon --full __TARGET__   # includes ffuf
```

Or from this directory:

```bash
../../scripts/run-recon.sh --target __TARGET__
../../scripts/run-recon.sh --target __TARGET__ --resume
../../scripts/run-recon.sh --target __TARGET__ --only scan
../../scripts/run-recon.sh --target __TARGET__ --full
```

## Pipeline stages

`subs` → `dns` → `live` → `network` → `urls` → `crawl` → `scan` → `sqli` → `summary` (optional: `fuzz` with `--full`)

## Outputs

| File | Stage |
|------|--------|
| `subs.txt` | subs |
| `dns.json`, `dns.txt` | dns |
| `live.txt`, `live.json` | live |
| `network/hosts.txt`, `network/naabu.json`, `network/open-ports.txt`, `network/hosts-with-ports.txt` | network |
| `urls-archive.txt` | urls |
| `urls-live.txt` | crawl |
| `urls-scan.txt` | scan (input for nuclei pass 2) |
| `urls.txt` | merged archive + crawl |
| `nuclei/results.jsonl` | scan (merged) |
| `nuclei/results-live.jsonl`, `results-urls.jsonl` | scan |
| `nuclei/summary.txt`, `summary-urls.txt` | scan |
| `sqlmap/candidates.txt`, `vulnerable.txt`, `findings.json` | sqli |
| `summary.md`, `run.log` | summary |

Passive DNS noise is dropped via scope filtering and `config/third-party-domains.txt`. Add project-specific exclusions in `../scope/out-of-scope.txt`.

Tune caps and nuclei settings in `~/lab/config/recon.defaults`.

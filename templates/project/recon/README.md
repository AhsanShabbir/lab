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

Outputs: `subs.txt`, `live.txt`, `live.json`, `urls.txt`, `nuclei/`, `fuzz/` (with `--full`), `summary.md`, `run.log`

Passive DNS noise (e.g. `twitter.com` under your target) is dropped automatically via scope filtering and `config/third-party-domains.txt`. Add project-specific exclusions in `../scope/out-of-scope.txt`.

# Recon — __TARGET__

Automated pipeline (from lab root):

```bash
../../scripts/run-recon.sh --target __TARGET__
```

Resume / single stage:

```bash
../../scripts/run-recon.sh --target __TARGET__ --resume
../../scripts/run-recon.sh --target __TARGET__ --only scan
../../scripts/run-recon.sh --target __TARGET__ --full   # includes ffuf
```

Outputs: `subs.txt`, `live.txt`, `live.json`, `urls.txt`, `nuclei/`, `fuzz/` (with `--full`), `summary.md`, `run.log`

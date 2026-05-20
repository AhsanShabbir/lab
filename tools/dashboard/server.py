#!/usr/bin/env python3
"""WISE lab dashboard — serves static UI and JSON API over local projects/."""

from __future__ import annotations

import json
import mimetypes
import os
import re
import sys
from collections import defaultdict
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

LAB_ROOT = Path(__file__).resolve().parents[2]
PROJECTS_DIR = LAB_ROOT / "projects"
STATIC_DIR = Path(__file__).resolve().parent
ALLOWED_EXTENSIONS = {
    ".md", ".txt", ".json", ".jsonl", ".log", ".html", ".csv",
}


def count_lines(path: Path) -> int:
    if not path.is_file():
        return 0
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            return sum(1 for line in fh if line.strip())
    except OSError:
        return 0


def read_text(path: Path, limit: int | None = None) -> str | None:
    if not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        if limit is not None and len(text) > limit:
            return text[:limit] + "\n\n… (truncated)"
        return text
    except OSError:
        return None


def nuclei_severity_counts(jsonl: Path) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    if not jsonl.is_file():
        return {}
    try:
        with jsonl.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                sev = (
                    row.get("info", {}).get("severity")
                    or row.get("severity")
                    or "unknown"
                )
                counts[str(sev).lower()] += 1
    except OSError:
        return {}
    return dict(counts)


def parse_findings_sections(md: str | None) -> dict[str, list[str]]:
    if not md:
        return {}
    sections: dict[str, list[str]] = {}
    current = "_intro"
    sections[current] = []
    for raw in md.splitlines():
        m = re.match(r"^##\s+(.+)$", raw.strip())
        if m:
            current = m.group(1).strip().lower()
            sections[current] = []
            continue
        if raw.strip().startswith("# ") and not sections[current]:
            continue
        sections.setdefault(current, []).append(raw)
    return {
        k: [ln for ln in v if ln.strip() and not ln.strip().startswith("- TBD")]
        for k, v in sections.items()
        if any(ln.strip() for ln in v)
    }


def recon_run_status(log_path: Path) -> dict[str, str | None]:
    text = read_text(log_path, limit=8000)
    if not text:
        return {"status": "not_started", "lastLine": None}
    lines = [ln for ln in text.splitlines() if ln.strip()]
    last = lines[-1] if lines else None
    if last and "Pipeline complete" in last:
        status = "complete"
    elif last and "===" in last:
        status = "running"
    else:
        status = "partial"
    return {"status": status, "lastLine": last}


def project_dir(name: str) -> Path | None:
    if not name or "/" in name or "\\" in name or name in (".", ".."):
        return None
    path = (PROJECTS_DIR / name).resolve()
    try:
        path.relative_to(PROJECTS_DIR.resolve())
    except ValueError:
        return None
    if not path.is_dir():
        return None
    return path


def safe_file(project: Path, rel: str) -> Path | None:
    rel = unquote(rel).lstrip("/")
    if not rel or ".." in Path(rel).parts:
        return None
    target = (project / rel).resolve()
    try:
        target.relative_to(project.resolve())
    except ValueError:
        return None
    if not target.is_file():
        return None
    if target.suffix.lower() not in ALLOWED_EXTENSIONS:
        return None
    return target


def build_project_summary(name: str) -> dict | None:
    root = project_dir(name)
    if root is None:
        return None

    meta: dict = {}
    meta_path = root / "meta.json"
    if meta_path.is_file():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            meta = {}

    recon = root / "recon"
    nuclei = nuclei_severity_counts(recon / "nuclei" / "results.jsonl")
    nuc_total = sum(nuclei.values())

    findings_path = root / "reports" / "findings.md"
    findings_text = read_text(findings_path, limit=4000)
    sections = parse_findings_sections(findings_text)

    return {
        "id": name,
        "target": meta.get("target", name),
        "created": meta.get("created"),
        "engagement": meta.get("engagement"),
        "paths": {
            "root": str(root),
            "findings": str(findings_path) if findings_path.is_file() else None,
            "reconSummary": str(recon / "summary.md") if (recon / "summary.md").is_file() else None,
        },
        "recon": {
            "subs": count_lines(recon / "subs.txt"),
            "live": count_lines(recon / "live.txt"),
            "urls": count_lines(recon / "urls.txt"),
            "nuclei": {
                "total": nuc_total,
                "bySeverity": nuclei,
            },
            "hasSummary": (recon / "summary.md").is_file(),
            "run": recon_run_status(recon / "run.log"),
        },
        "findings": {
            "hasReport": findings_path.is_file(),
            "sections": {k: v[:8] for k, v in sections.items()},
            "preview": (findings_text or "")[:500] or None,
        },
        "scope": {
            "inScope": read_text(root / "scope" / "in-scope.txt"),
            "outOfScope": read_text(root / "scope" / "out-of-scope.txt"),
        },
    }


def build_project_detail(name: str) -> dict | None:
    summary = build_project_summary(name)
    if summary is None:
        return None

    root = project_dir(name)
    assert root is not None
    recon = root / "recon"

    live_preview = None
    live_path = recon / "live.txt"
    if live_path.is_file():
        try:
            with live_path.open("r", encoding="utf-8", errors="replace") as fh:
                live_preview = [ln.strip() for ln in fh if ln.strip()][:40]
        except OSError:
            live_preview = []

    files: list[dict] = []
    for rel in (
        "reports/findings.md",
        "recon/summary.md",
        "recon/run.log",
        "recon/README.md",
        "notes/README.md",
        "recon/nuclei/summary.txt",
        "scope/in-scope.txt",
        "scope/out-of-scope.txt",
    ):
        fp = root / rel
        if fp.is_file():
            files.append({
                "path": rel,
                "size": fp.stat().st_size,
                "modified": fp.stat().st_mtime,
            })

    return {
        **summary,
        "content": {
            "findings": read_text(root / "reports" / "findings.md"),
            "reconSummary": read_text(recon / "summary.md"),
            "runLog": read_text(recon / "run.log", limit=12000),
            "notes": read_text(root / "notes" / "README.md"),
            "nucleiSummary": read_text(recon / "nuclei" / "summary.txt", limit=20000),
        },
        "liveHosts": live_preview,
        "files": files,
    }


class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def log_message(self, fmt: str, *args) -> None:
        if os.environ.get("DASHBOARD_QUIET"):
            return
        super().log_message(fmt, *args)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/projects":
            self._json_response(self._list_projects())
            return

        m = re.match(r"^/api/projects/([^/]+)$", path)
        if m:
            detail = build_project_detail(m.group(1))
            if detail is None:
                self._json_error(404, "Project not found")
                return
            self._json_response(detail)
            return

        m = re.match(r"^/api/projects/([^/]+)/file$", path)
        if m:
            self._serve_project_file(m.group(1), parse_qs(parsed.query))
            return

        if path in ("", "/"):
            self.path = "/index.html"
        return super().do_GET()

    def _list_projects(self) -> dict:
        projects = []
        if PROJECTS_DIR.is_dir():
            for entry in sorted(PROJECTS_DIR.iterdir()):
                if entry.is_dir() and not entry.name.startswith("."):
                    row = build_project_summary(entry.name)
                    if row:
                        projects.append(row)
        return {"labRoot": str(LAB_ROOT), "projects": projects}

    def _serve_project_file(self, name: str, query: dict) -> None:
        rel_list = query.get("path", [])
        if not rel_list:
            self._json_error(400, "Missing path query")
            return
        root = project_dir(name)
        if root is None:
            self._json_error(404, "Project not found")
            return
        target = safe_file(root, rel_list[0])
        if target is None:
            self._json_error(404, "File not found or not allowed")
            return
        body = target.read_bytes()
        ctype = mimetypes.guess_type(str(target))[0] or "text/plain"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json_response(self, payload: dict) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json_error(self, code: int, message: str) -> None:
        body = json.dumps({"error": message}).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> int:
    port = int(os.environ.get("DASHBOARD_PORT", "7331"))
    host = os.environ.get("DASHBOARD_HOST", "127.0.0.1")
    server = ThreadingHTTPServer((host, port), DashboardHandler)
    print(f"WISE lab: http://{host}:{port}/", flush=True)
    print(f"Projects dir: {PROJECTS_DIR}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.", flush=True)
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())

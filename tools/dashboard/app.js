const $ = (sel, root = document) => root.querySelector(sel);

let allProjects = [];
let selectedId = null;
let activeTab = "overview";

async function fetchJSON(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

function renderMarkdown(text) {
  if (!text) return '<p class="empty">No content yet.</p>';
  return marked.parse(text, { breaks: true });
}

function renderSqliPanel(sqli) {
  const total = sqli?.total ?? 0;
  const candidates = sqli?.candidates ?? 0;
  if (!candidates && !total) {
    return '<p class="empty">No sqlmap run yet (sqli stage).</p>';
  }
  if (!total) {
    return `<p class="sqli-ok">Tested <strong>${candidates}</strong> parameterized URL(s); no confirmed SQL injection in automated pass.</p>`;
  }
  const rows = (sqli.items || [])
    .map(
      (item) => `
      <div class="sqli-hit">
        <a href="${escapeAttr(item.url)}" target="_blank" rel="noopener">${escapeHtml(item.url)}</a>
        <span class="sqli-meta">parameter <code>${escapeHtml(item.parameter || "?")}</code> — ${escapeHtml(item.injectionType || "unknown")}</span>
      </div>`
    )
    .join("");
  return `
    <p class="sqli-alert"><strong>${total}</strong> potentially injectable URL(s) — confirm manually before reporting.</p>
    <div class="sqli-list">${rows}</div>`;
}

function formatNuclei(nuclei) {
  const total = nuclei?.total ?? 0;
  if (!total) return "0 findings";
  const parts = Object.entries(nuclei.bySeverity || {})
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${k}: ${v}`);
  return `${total} (${parts.join(", ")})`;
}

function statusClass(status) {
  return `status-badge status-${status || "not_started"}`;
}

function renderProjectList(filter = "") {
  const list = $("#projectList");
  const q = filter.trim().toLowerCase();
  const items = allProjects.filter((p) => {
    if (!q) return true;
    return (
      p.id.toLowerCase().includes(q) ||
      (p.target || "").toLowerCase().includes(q) ||
      (p.engagement || "").toLowerCase().includes(q)
    );
  });

  if (!items.length) {
    list.innerHTML = '<p class="empty">No projects match. Run <code>./target target.com</code></p>';
    return;
  }

  list.innerHTML = items
    .map((p) => {
      const r = p.recon || {};
      const nuc = r.nuclei?.total || 0;
      const active = p.id === selectedId ? " active" : "";
      return `
        <button type="button" class="project-card${active}" data-id="${escapeAttr(p.id)}">
          <div class="engagement">${escapeHtml(p.engagement || "—")}</div>
          <h3>${escapeHtml(p.target || p.id)}</h3>
          <div class="stats-row">
            <span class="chip live">${r.live ?? 0} live</span>
            <span class="chip">${r.subs ?? 0} subs</span>
            ${nuc ? `<span class="chip nuc warn">${nuc} nuclei</span>` : ""}
            ${(r.sqli?.total || 0) > 0 ? `<span class="chip sqli">${r.sqli.total} sqli</span>` : ""}
          </div>
        </button>`;
    })
    .join("");

  list.querySelectorAll(".project-card").forEach((btn) => {
    btn.addEventListener("click", () => selectProject(btn.dataset.id));
  });
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeAttr(s) {
  return escapeHtml(s).replace(/'/g, "&#39;");
}

async function loadProjects() {
  const data = await fetchJSON("/api/projects");
  allProjects = data.projects || [];
  $("#labMeta").textContent = `WISE lab · ${allProjects.length} project(s)`;
  renderProjectList($("#search").value);
  if (selectedId && !allProjects.find((p) => p.id === selectedId)) {
    selectedId = null;
    showPlaceholder();
  }
}

async function selectProject(id) {
  selectedId = id;
  activeTab = "overview";
  renderProjectList($("#search").value);
  const pane = $("#detailPane");
  pane.innerHTML = '<p class="empty">Loading…</p>';
  try {
    const p = await fetchJSON(`/api/projects/${encodeURIComponent(id)}`);
    renderDetail(p);
  } catch (err) {
    pane.innerHTML = `<p class="empty">Failed to load: ${escapeHtml(err.message)}</p>`;
  }
}

function showPlaceholder() {
  $("#detailPane").innerHTML = `
    <div class="placeholder">
      <h2>Select a project</h2>
      <p>Overview, findings, recon stats, scope, and notes appear here.</p>
    </div>`;
}

function renderDetail(p) {
  const pane = $("#detailPane");
  const r = p.recon || {};
  const run = r.run || {};

  pane.innerHTML = `
    <div class="detail-header">
      <h2>${escapeHtml(p.target || p.id)}</h2>
      <span class="sub">Created ${escapeHtml(p.created || "—")} · ${escapeHtml(p.engagement || "")}</span>
      <span class="${statusClass(run.status)}">${escapeHtml(run.status || "not_started")}</span>
    </div>

    <div class="tabs" role="tablist">
      ${tabBtn("overview", "Overview")}
      ${tabBtn("findings", "Findings")}
      ${tabBtn("recon", "Recon")}
      ${tabBtn("scope", "Scope")}
      ${tabBtn("files", "Files")}
    </div>

    <div id="tabContent"></div>
  `;

  pane.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      activeTab = btn.dataset.tab;
      pane.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === activeTab));
      renderTabContent(p);
    });
  });

  pane.querySelector(`.tab[data-tab="${activeTab}"]`)?.classList.add("active");
  renderTabContent(p);
}

function tabBtn(id, label) {
  const active = id === activeTab ? " active" : "";
  return `<button type="button" class="tab${active}" data-tab="${id}">${label}</button>`;
}

function renderTabContent(p) {
  const el = $("#tabContent");
  const r = p.recon || {};
  const run = r.run || {};
  const c = p.content || {};

  switch (activeTab) {
    case "findings":
      el.innerHTML = `
        <div class="panel">
          <h3>Findings report</h3>
          <div class="md-content">${renderMarkdown(c.findings)}</div>
        </div>`;
      break;

    case "recon":
      el.innerHTML = `
        <div class="panel">
          <h3>Recon metrics</h3>
          <div class="metric-grid">
            ${metric("Subdomains", r.subs)}
            ${metric("Live hosts", r.live)}
            ${metric("URLs", r.urls)}
            ${metric("Nuclei", r.nuclei?.total ?? 0)}
          </div>
          ${renderNucleiBreakdown(r.nuclei)}
        </div>
        <div class="panel panel-sqli">
          <h3>SQL injection (sqlmap)</h3>
          ${renderSqliPanel(r.sqli)}
        </div>
        <div class="panel">
          <h3>Recon summary</h3>
          <div class="md-content">${renderMarkdown(c.reconSummary)}</div>
        </div>
        <div class="panel">
          <h3>Live hosts (preview)</h3>
          <div class="host-list">${(p.liveHosts || []).map((h) => `<div>${escapeHtml(h)}</div>`).join("") || '<span class="empty">No live hosts yet.</span>'}</div>
        </div>
        <div class="panel">
          <h3>Pipeline log</h3>
          <div class="md-content"><pre>${escapeHtml(c.runLog || "(empty)")}</pre></div>
        </div>
        ${c.nucleiSummary ? `<div class="panel"><h3>Nuclei summary</h3><div class="md-content"><pre>${escapeHtml(c.nucleiSummary)}</pre></div></div>` : ""}`;
      break;

    case "scope":
      el.innerHTML = `
        <div class="panel scope-block">
          <h3>In scope</h3>
          <pre>${escapeHtml(p.scope?.inScope || "(not defined)")}</pre>
        </div>
        <div class="panel scope-block">
          <h3>Out of scope</h3>
          <pre>${escapeHtml(p.scope?.outOfScope || "(not defined)")}</pre>
        </div>`;
      break;

    case "files":
      el.innerHTML = `
        <div class="panel">
          <h3>Project files</h3>
          <ul class="file-list">
            ${(p.files || [])
              .map(
                (f) => `
              <li>
                <button type="button" data-path="${escapeAttr(f.path)}">${escapeHtml(f.path)}</button>
                <span class="muted">${formatSize(f.size)}</span>
              </li>`
              )
              .join("")}
          </ul>
          <div id="filePreview" class="md-content" style="margin-top:16px"></div>
        </div>`;
      el.querySelectorAll(".file-list button").forEach((btn) => {
        btn.addEventListener("click", () => previewFile(p.id, btn.dataset.path));
      });
      break;

    default:
      el.innerHTML = `
        <div class="panel">
          <h3>At a glance</h3>
          <div class="metric-grid">
            ${metric("Subdomains", r.subs)}
            ${metric("Live hosts", r.live)}
            ${metric("URLs", r.urls)}
            ${metric("Nuclei", r.nuclei?.total ?? 0)}
            ${metric("SQLi", r.sqli?.total ?? 0)}
          </div>
          <p style="margin-top:12px;color:var(--muted);font-size:0.85rem">
            Nuclei: ${escapeHtml(formatNuclei(r.nuclei))}
            ${(r.sqli?.total || 0) > 0 ? ` · <span class="sqli-inline">${r.sqli.total} sqlmap hit(s)</span>` : ""}
            ${run.lastLine ? ` · Last log: ${escapeHtml(run.lastLine)}` : ""}
          </p>
        </div>
        <div class="panel">
          <h3>Findings preview</h3>
          <div class="md-content">${renderMarkdown(c.findings?.slice(0, 1500) || p.findings?.preview)}</div>
        </div>
        <div class="panel">
          <h3>Notes</h3>
          <div class="md-content">${renderMarkdown(c.notes)}</div>
        </div>
        <div class="panel">
          <h3>Path</h3>
          <pre style="margin:0;font-size:0.85rem;color:var(--green)">${escapeHtml(p.paths?.root || "")}</pre>
        </div>`;
  }
}

function metric(label, value) {
  return `<div class="metric"><div class="value">${Number(value).toLocaleString()}</div><div class="label">${escapeHtml(label)}</div></div>`;
}

function renderNucleiBreakdown(nuclei) {
  const by = nuclei?.bySeverity;
  if (!by || !Object.keys(by).length) return "";
  return `<div class="severity-grid" style="margin-top:12px">${Object.entries(by)
    .map(([k, v]) => `<span class="sev ${escapeAttr(k)}">${escapeHtml(k)}: ${v}</span>`)
    .join("")}</div>`;
}

function formatSize(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

async function previewFile(projectId, relPath) {
  const box = $("#filePreview");
  box.innerHTML = '<p class="empty">Loading…</p>';
  try {
    const url = `/api/projects/${encodeURIComponent(projectId)}/file?path=${encodeURIComponent(relPath)}`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(res.statusText);
    const text = await res.text();
    if (relPath.endsWith(".md")) {
      box.innerHTML = `<h4>${escapeHtml(relPath)}</h4>${renderMarkdown(text)}`;
    } else {
      box.innerHTML = `<h4>${escapeHtml(relPath)}</h4><pre>${escapeHtml(text)}</pre>`;
    }
  } catch (err) {
    box.innerHTML = `<p class="empty">${escapeHtml(err.message)}</p>`;
  }
}

$("#search").addEventListener("input", (e) => renderProjectList(e.target.value));
$("#refreshBtn").addEventListener("click", () => {
  loadProjects().then(() => {
    if (selectedId) selectProject(selectedId);
  });
});

loadProjects().catch((err) => {
  $("#projectList").innerHTML = `<p class="empty">API error: ${escapeHtml(err.message)}. Is the server running?</p>`;
});

// Auto-refresh every 45s when viewing a running recon
setInterval(() => {
  if (!selectedId) return;
  const card = allProjects.find((p) => p.id === selectedId);
  if (card?.recon?.run?.status === "running") {
    selectProject(selectedId);
  }
}, 45000);

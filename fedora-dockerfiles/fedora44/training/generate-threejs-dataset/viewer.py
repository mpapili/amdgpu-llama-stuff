#!/usr/bin/env python3
"""
Train.jsonl Review Viewer.

A single-file, stdlib-only local web app for reviewing the Three.js training
set in `train.jsonl`. Each sample's HTML is extracted and rendered live in an
iframe; you mark rows good/bad (stored in a SQLite DB) and can export a pruned
train-pruned.jsonl (good rows only).

Usage:
    python3 viewer.py [path/to/train.jsonl] [port]

Then open http://localhost:8000
"""

import json
import os
import sqlite3
import sys
import urllib.parse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TRAIN = os.path.join(HERE, "train.jsonl")
DB_PATH = os.path.join(HERE, "labels.db")
PRUNED_PATH = os.path.join(HERE, "train-pruned.jsonl")


# --------------------------------------------------------------------------- #
# Data layer
# --------------------------------------------------------------------------- #
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS labels (
            idx         INTEGER PRIMARY KEY,
            label       TEXT NOT NULL,
            updated_at  TEXT NOT NULL
        )
        """
    )
    conn.commit()
    return conn


def load_samples(path):
    """Read train.jsonl lazily into a list of raw line strings."""
    samples = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                samples.append(line)
    return samples


def extract_html(assistant_content):
    """Pull the first ```html ... ``` fenced block out of the assistant text."""
    start = assistant_content.find("```html")
    if start == -1:
        start = assistant_content.find("```")
        if start == -1:
            return ""
        start += 3
    else:
        start += len("```html")
    end = assistant_content.find("```", start)
    if end == -1:
        return assistant_content[start:].strip()
    return assistant_content[start:end].strip()


def get_message(sample_line):
    obj = json.loads(sample_line)
    messages = obj.get("messages", [])
    user_msg = next((m for m in messages if m.get("role") == "user"), {})
    asst_msg = next((m for m in messages if m.get("role") == "assistant"), {})
    return user_msg.get("content", ""), asst_msg.get("content", "")


def get_label(conn, idx):
    row = conn.execute("SELECT label FROM labels WHERE idx=?", (idx,)).fetchone()
    return row[0] if row else None


def set_label(conn, idx, label):
    if label in (None, "none", ""):
        conn.execute("DELETE FROM labels WHERE idx=?", (idx,))
    else:
        now = datetime.now(timezone.utc).isoformat()
        conn.execute(
            "INSERT INTO labels(idx, label, updated_at) VALUES(?,?,?) "
            "ON CONFLICT(idx) DO UPDATE SET label=excluded.label, "
            "updated_at=excluded.updated_at",
            (idx, label, now),
        )
    conn.commit()


def get_stats(conn, total):
    good = conn.execute("SELECT COUNT(*) FROM labels WHERE label='good'").fetchone()[0]
    bad = conn.execute("SELECT COUNT(*) FROM labels WHERE label='bad'").fetchone()[0]
    return {"good": good, "bad": bad, "total": total, "unlabeled": total - good - bad}


# --------------------------------------------------------------------------- #
# HTTP layer
# --------------------------------------------------------------------------- #
class Handler(BaseHTTPRequestHandler):
    train_path = DEFAULT_TRAIN
    samples = []

    @classmethod
    def reload(cls):
        cls.samples = load_samples(cls.train_path)

    def log_message(self, *args):
        # Quieter logging.
        pass

    def _send(self, status, body, content_type="application/json"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html):
        self._send(200, html, "text/html; charset=utf-8")

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        if path in ("/", "/index.html"):
            self._send_html(PAGE_HTML)
            return

        if path == "/api/sample":
            try:
                idx = int(qs.get("i", ["0"])[0])
            except ValueError:
                idx = 0
            total = len(self.samples)
            if total == 0:
                self._send(200, json.dumps({"error": "no samples"}))
                return
            idx = max(0, min(idx, total - 1))
            sample = self.samples[idx]
            prompt, asst = get_message(sample)
            html = extract_html(asst)
            with get_db() as conn:
                label = get_label(conn, idx)
                stats = get_stats(conn, total)
            payload = {
                "index": idx,
                "total": total,
                "prompt": prompt,
                "html": html,
                "raw": asst,
                "label": label,
                "stats": stats,
            }
            self._send(200, json.dumps(payload))
            return

        if path == "/api/next-unlabeled":
            try:
                idx = int(qs.get("i", ["0"])[0])
            except ValueError:
                idx = 0
            total = len(self.samples)
            if total == 0:
                self._send(200, json.dumps({"error": "no samples"}))
                return
            idx = max(0, min(idx, total - 1))
            with get_db() as conn:
                labeled = {r[0] for r in conn.execute("SELECT idx FROM labels")}
            # Smallest index > idx that is unlabeled, else wrap to the first
            # unlabeled index overall. Falls back to the next index if every
            # row is labeled.
            nxt = None
            for i in range(idx + 1, total):
                if i not in labeled:
                    nxt = i
                    break
            if nxt is None:
                for i in range(0, idx + 1):
                    if i not in labeled:
                        nxt = i
                        break
            if nxt is None:
                nxt = min(idx + 1, total - 1)
            self._send(200, json.dumps({"index": nxt, "total": total}))
            return

        if path == "/download/train-pruned.jsonl":
            self.export_pruned(download=True)
            return

        self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/label":
            body = self._read_body()
            try:
                idx = int(body.get("i"))
            except (TypeError, ValueError):
                self._send(400, json.dumps({"error": "bad index"}))
                return
            label = body.get("label", "none")
            if label not in ("good", "bad", "none"):
                self._send(400, json.dumps({"error": "bad label"}))
                return
            total = len(self.samples)
            idx = max(0, min(idx, total - 1))
            with get_db() as conn:
                set_label(conn, idx, label)
                stats = get_stats(conn, total)
            self._send(200, json.dumps({"ok": True, "stats": stats}))
            return

        if path == "/api/export":
            self.export_pruned(download=False)
            return

        self._send(404, json.dumps({"error": "not found"}))

    def export_pruned(self, download=False):
        total = len(self.samples)
        with get_db() as conn:
            good_rows = conn.execute(
                "SELECT idx FROM labels WHERE label='good' ORDER BY idx"
            ).fetchall()
        good_idx = [r[0] for r in good_rows]
        lines = []
        for idx in good_idx:
            if 0 <= idx < total:
                lines.append(self.samples[idx])
        with open(PRUNED_PATH, "w", encoding="utf-8") as fh:
            for line in lines:
                fh.write(line + "\n")
        if download:
            data = "\n".join(lines).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/jsonl")
            self.send_header(
                "Content-Disposition",
                'attachment; filename="train-pruned.jsonl"',
            )
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self._send(
                200,
                json.dumps(
                    {"ok": True, "count": len(lines), "path": PRUNED_PATH}
                ),
            )


# --------------------------------------------------------------------------- #
# UI
# --------------------------------------------------------------------------- #
PAGE_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Train.jsonl Review Viewer</title>
<style>
  * { box-sizing: border-box; }
  body { margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
         background:#16161a; color:#e6e6e6; }
  header { position:sticky; top:0; z-index:10; background:#1e1e24; border-bottom:1px solid #2e2e36;
           padding:10px 16px; display:flex; align-items:center; gap:16px; flex-wrap:wrap; }
  h1 { font-size:15px; margin:0; font-weight:600; }
  .pos { font-variant-numeric: tabular-nums; color:#9fd0ff; }
  .stats { font-size:13px; color:#9a9aa4; display:flex; gap:12px; }
  .stats span b { color:#fff; }
  .progress { flex:1; min-width:120px; height:6px; background:#2e2e36; border-radius:3px; overflow:hidden; }
  .progress > div { height:100%; background:linear-gradient(90deg,#3b82f6,#22c55e); width:0; transition:width .2s; }
  main { display:grid; grid-template-columns: 1fr 1fr; gap:1px; background:#2e2e36; height:calc(100vh - 58px); }
  .pane { background:#16161a; overflow:auto; padding:16px; }
  .pane h2 { font-size:12px; text-transform:uppercase; letter-spacing:.08em; color:#7a7a84;
             margin:0 0 8px; font-weight:600; }
  .prompt { white-space:pre-wrap; font-size:14px; line-height:1.5; background:#1e1e24;
            padding:12px; border-radius:8px; border:1px solid #2e2e36; }
  .raw { white-space:pre-wrap; word-break:break-word; font-family:ui-monospace,Menlo,Consolas,monospace;
         font-size:12px; line-height:1.5; margin-top:8px; }
  iframe { width:100%; height:calc(100% - 30px); border:1px solid #2e2e36; border-radius:8px; background:#fff; }
  .toolbar { position:sticky; bottom:0; background:#1e1e24; border-top:1px solid #2e2e36;
             padding:10px 16px; display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
  button { font:inherit; padding:8px 14px; border:1px solid #2e2e36; background:#2a2a32; color:#e6e6e6;
           border-radius:6px; cursor:pointer; }
  button:hover { background:#34343e; }
  button.active.good { background:#16a34a; border-color:#16a34a; color:#fff; }
  button.active.bad  { background:#dc2626; border-color:#dc2626; color:#fff; }
  .spacer { flex:1; }
  .hint { font-size:11px; color:#6a6a74; }
  .empty { color:#6a6a74; font-style:italic; }
  details summary { cursor:pointer; color:#7a7a84; font-size:12px; }
  #flash { position:fixed; bottom:64px; left:50%; transform:translateX(-50%);
           background:#2a2a32; border:1px solid #2e2e36; color:#e6e6e6;
           padding:6px 14px; border-radius:6px; font-size:13px; opacity:0;
           transition:opacity .2s; pointer-events:none; z-index:20; }
</style>
</head>
<body>
<div id="flash"></div>
<header>
  <h1>Train Review</h1>
  <div class="pos"><span id="cur">0</span> / <span id="tot">0</span></div>
  <div class="progress"><div id="bar"></div></div>
  <div class="stats">
    <span>good: <b id="gc">0</b></span>
    <span>bad: <b id="bc">0</b></span>
    <span>unlabeled: <b id="uc">0</b></span>
  </div>
</header>

<main>
  <div class="pane">
    <h2>Prompt</h2>
    <div class="prompt" id="prompt"></div>
    <details>
      <summary>Show raw assistant content (c)</summary>
      <div class="raw" id="raw"></div>
    </details>
  </div>
  <div class="pane">
    <h2>Live render (iframe)</h2>
    <iframe id="render" sandbox="allow-scripts allow-same-origin"></iframe>
  </div>
</main>

<div class="toolbar">
  <button id="prev">◀ Prev (p)</button>
  <button id="good">✓ Good (g)</button>
  <button id="bad">✗ Bad (b)</button>
  <button id="unset">Unset</button>
  <button id="next">Next (n) ▶</button>
  <button id="jump">⤵ Next unmarked (j)</button>
  <div class="spacer"></div>
  <span class="hint">g/b saves &amp; advances</span>
  <button id="export">⬇ Export pruned (good only)</button>
</div>

<script>
const state = { index: 0, total: 0, label: null };

async function load(i){
  const r = await fetch('/api/sample?i=' + i);
  const d = await r.json();
  if (d.error){ return; }
  state.index = d.index; state.total = d.total; state.label = d.label;
  document.getElementById('cur').textContent = d.index + 1;
  document.getElementById('tot').textContent = d.total;
  document.getElementById('prompt').textContent = d.prompt || '(no prompt)';
  document.getElementById('raw').textContent = d.raw || '';
  const frame = document.getElementById('render');
  frame.srcdoc = d.html || '<body style="font-family:sans-serif;color:#888">No HTML found</body>';
  updateStats(d.stats);
  updateButtons();
  if (window.location.hash !== '#' + d.index){
    history.replaceState(null, '', '#' + d.index);
  }
}

function updateStats(s){
  document.getElementById('gc').textContent = s.good;
  document.getElementById('bc').textContent = s.bad;
  document.getElementById('uc').textContent = s.unlabeled;
  const pct = s.total ? ((s.good + s.bad) / s.total) * 100 : 0;
  document.getElementById('bar').style.width = pct + '%';
}

function updateButtons(){
  const g = document.getElementById('good');
  const b = document.getElementById('bad');
  g.classList.toggle('active', state.label === 'good');
  g.classList.toggle('good', state.label === 'good');
  b.classList.toggle('active', state.label === 'bad');
  b.classList.toggle('bad', state.label === 'bad');
}

async function label(l){
  const r = await fetch('/api/label', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({ i: state.index, label: l })
  });
  const d = await r.json();
  if (d.stats) updateStats(d.stats);
  state.label = l;
  updateButtons();
  if (l === 'good' || l === 'bad'){
    next();
  }
}

function next(){ go(Math.min(state.index + 1, state.total - 1)); }
function prev(){ go(Math.max(state.index - 1, 0)); }
function go(i){ load(i); }

async function jumpUnmarked(){
  const r = await fetch('/api/next-unlabeled?i=' + state.index);
  const d = await r.json();
  if (d.error){ return; }
  if (d.index === state.index){
    // Nothing unmarked after us — we're already on the last unlabeled row.
    flash('All rows marked');
  } else {
    load(d.index);
  }
}

function flash(msg){
  const el = document.getElementById('flash');
  if (!el) return;
  el.textContent = msg;
  el.style.opacity = '1';
  clearTimeout(flash._t);
  flash._t = setTimeout(() => { el.style.opacity = '0'; }, 1200);
}

document.getElementById('prev').onclick = prev;
document.getElementById('next').onclick = next;
document.getElementById('jump').onclick = jumpUnmarked;
document.getElementById('good').onclick = () => label('good');
document.getElementById('bad').onclick  = () => label('bad');
document.getElementById('unset').onclick = () => label('none');

document.getElementById('export').onclick = async () => {
  const r = await fetch('/api/export', { method:'POST' });
  const d = await r.json();
  if (d.ok){
    alert('Exported ' + d.count + ' good rows to\n' + d.path);
  } else {
    alert('Export failed');
  }
};

document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
  const k = e.key.toLowerCase();
  if (k === 'g') label('good');
  else if (k === 'b') label('bad');
  else if (k === 'n') next();
  else if (k === 'p') prev();
  else if (k === 'j') jumpUnmarked();
  else if (k === 'c') {
    const d = document.querySelector('details');
    d.open = !d.open;
  }
});

const startIdx = parseInt(location.hash.replace('#','')) || 0;
load(startIdx);
</script>
</body>
</html>
"""


def main():
    args = sys.argv[1:]
    train_path = args[0] if len(args) >= 1 else DEFAULT_TRAIN
    port = int(args[1]) if len(args) >= 2 else 8000
    Handler.train_path = os.path.abspath(train_path)
    Handler.reload()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"Train path : {Handler.train_path}")
    print(f"DB         : {DB_PATH}")
    print(f"Pruned out : {PRUNED_PATH}")
    print(f"Serving on : http://localhost:{port}  ({len(Handler.samples)} samples)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.")
        server.shutdown()


if __name__ == "__main__":
    main()

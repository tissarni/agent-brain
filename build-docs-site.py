#!/usr/bin/env python3
"""Build the docs site: a human-readable mirror of the vault's state.

For every main project (02-projects/<main>/context.md) it renders the brain-state page with /doc-build's build.js — context, ADRs, specs, current/summary —
straight into the site. It copies every other .html page of the vault (team docs, /md-html
pages, specs, design canvases) with the local assets they load, keeping vault paths. Then
it writes index.html: one dropdown per main with its brain-state page, then one row per sub
with its team doc (or the gap) and its other pages, in the same design as the pages (CSS and logo come from
build.js, never restated here).

Output goes OUTSIDE the repo: DOCS_SITE_DIR in brain.env, default
~/.local/share/<brain directory name>-docs/site, updated in place because a server may
bind-mount it. Serve that folder with any static server — never the brain's root, which
holds far more than pages; DOCS_URL is the address it is served at. The builder refuses a
DOCS_SITE_DIR that is the brain's root, lies inside it or contains it: prune() deletes
every file there that this run did not write.

Runs from auto-commit.sh on every Stop; safe to run by hand. docs-exclude.txt opts pages
out (globs on vault-relative paths; a main's brain-state page is <main>/doc.html).
"""
import fnmatch
import html
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

VAULT = Path(__file__).resolve().parent


def brain_env(key):
    """The value after the first `KEY=` in brain.env, "" when absent. Read, never sourced."""
    try:
        lines = (VAULT / "brain.env").read_text().splitlines()
    except OSError:
        return ""
    for line in lines:
        if line.startswith(key + "="):
            return line[len(key) + 1:].rstrip("\r")
    return ""


def site_dir():
    v = brain_env("DOCS_SITE_DIR")
    if not v:
        return Path.home() / f".local/share/{VAULT.name}-docs/site"
    if v == "~" or v.startswith("~/"):
        return Path.home() / v[2:]
    return VAULT / v


OUT = site_dir().resolve()
BUILD_JS = VAULT / ".agents/skills/doc-build/build.js"
ROOTS = ("02-projects", "03-knowledge")
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)
REF_RE = re.compile(r'''(?:src|href)=["']([^"'#?:]+)["']''', re.I)
STATUSES = ("active", "blocked", "impl-done", "done", "paused")
esc = html.escape


def excluded(rel, pats):
    return any(fnmatch.fnmatch(rel, p) for p in pats)


def excludes():
    f = VAULT / "docs-exclude.txt"
    if not f.exists():
        return []
    return [l.strip() for l in f.read_text().splitlines() if l.strip() and not l.startswith("#")]


def node_json(script, *args):
    out = subprocess.run(["node", "-e", script, str(BUILD_JS), *map(str, args)],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def projects():
    """Mains then their subs, with the frontmatter build.js itself parses."""
    ctx = sorted(VAULT.glob("02-projects/*/context.md")) + sorted(VAULT.glob("02-projects/*/subprojects/*/context.md"))
    ctx = [c for c in ctx if not c.parent.name.startswith(("_", "."))]
    metas = node_json(
        "const b=require(process.argv[1]);"
        "console.log(JSON.stringify(process.argv.slice(2).map(f=>b.parseFrontmatter(b.readFile(f)).meta)))",
        *ctx)
    out = []
    for c, meta in zip(ctx, metas):
        rel = c.parent.relative_to(VAULT).as_posix()
        parts = rel.split("/")
        out.append({"rel": rel, "name": c.parent.name, "main": parts[1],
                    "kind": "sub" if len(parts) == 4 else "main",
                    "status": str(meta.get("status", "")).strip(),
                    "summary": " ".join(str(meta.get("summary", "")).split()),
                    "opt_out": str(meta.get("team_doc", "")).strip().lower().startswith("none")})
    return out


SKIPPED_RE = re.compile(r"^Coworker doc: none", re.M)


def team_doc_state(p, rels):
    """(html path or "", state): reviewed | draft | none | missing.

    none = the user decided this sub needs no team doc: `team_doc: none` in its context.md, or
    /ship's "Coworker doc: none" line in summary.md. A doc that exists wins over the flag.
    """
    html_rel = f'{p["rel"]}/{p["name"]}-team-doc.html'
    md = VAULT / p["rel"] / f'{p["name"]}-team-doc.md'
    if html_rel in rels:
        reviewed = ""
        if md.exists():
            m = re.search(r"^reviewed:\s*(.+)$", md.read_text(errors="replace").split("\n---", 1)[0], re.M)
            reviewed = m.group(1).strip().strip("'\"") if m else ""
        return html_rel, "draft" if reviewed in ("", "no") else "reviewed"
    summary = VAULT / p["rel"] / "summary.md"
    if p["opt_out"] or (summary.exists() and SKIPPED_RE.search(summary.read_text(errors="replace"))):
        return "", "none"
    return "", "missing"


def pages(pats):
    """Vault .html pages to copy. doc.html is skipped: the site renders its own, fresh."""
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(VAULT / root):
            # Hidden dirs hold worktrees and tool state; _templates is scaffolding.
            dirnames[:] = sorted(d for d in dirnames if not d.startswith(".") and d != "_templates")
            for name in sorted(filenames):
                if name.endswith(".html") and name != "doc.html":
                    rel = (Path(dirpath) / name).relative_to(VAULT).as_posix()
                    if not excluded(rel, pats):
                        yield rel


def assets_of(rel):
    """Local files a page loads (support.js, images...). Notes (.md) stay in the vault."""
    page = VAULT / rel
    for ref in REF_RE.findall(page.read_text(errors="replace")):
        target = (page.parent / ref).resolve()
        if (target.is_file() and target.suffix not in (".md", ".html") and VAULT in target.parents
                and not any(p.startswith(".") for p in target.relative_to(VAULT).parts)):
            yield target.relative_to(VAULT).as_posix()


def title_of(path):
    m = TITLE_RE.search(path.read_text(errors="replace")[:20000])
    return html.unescape(" ".join(m.group(1).split())) if m and m.group(1).strip() else path.stem


def owner_of(rel, project_rels):
    """Deepest project folder containing the page."""
    best = ""
    for p in project_rels:
        if rel.startswith(p + "/") and len(p) > len(best):
            best = p
    return best


def copy_pages(rels):
    for rel in rels:
        src, dst = VAULT / rel, OUT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists() or src.stat().st_mtime != dst.stat().st_mtime or src.stat().st_size != dst.stat().st_size:
            shutil.copy2(src, dst)


def render_brain_states(projs):
    """Mains only: a sub's raw state is noise for a teammate — its page is the team doc."""
    for p in projs:
        p["doc"] = False
        if p["kind"] != "main":
            continue
        dst = OUT / p["rel"] / "doc.html"
        dst.parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(["node", str(BUILD_JS), str(VAULT / p["rel"]), str(dst)],
                           capture_output=True, text=True)
        p["doc"] = r.returncode == 0
        if not p["doc"]:
            print(f"doc-build failed for {p['rel']}: {r.stderr.strip()}", file=sys.stderr)


def prune(keep):
    for dirpath, _, filenames in os.walk(OUT, topdown=False):
        for name in filenames:
            rel = (Path(dirpath) / name).relative_to(OUT).as_posix()
            if rel not in keep:
                (Path(dirpath) / name).unlink()
        if Path(dirpath) != OUT and not os.listdir(dirpath):
            os.rmdir(dirpath)


INDEX_CSS = """
.filter { width: 100%; padding: 0.6rem 0.85rem; font: inherit; color: var(--text); background: var(--surface);
  border: 1px solid var(--border); border-radius: 10px; margin: 0 0 0.5rem; }
.coverage { list-style: none; padding: 0; margin: 1.2rem 0 0; font-size: 0.9rem; }
.coverage li { margin: 0.35rem 0; }
.coverage strong { font-size: 1.05rem; }
.bar { display: flex; gap: 0.5rem; align-items: center; margin: 0 0 1.2rem; }
.bar .filter { flex: 1; margin: 0; }
.bar button { font: inherit; font-size: 0.85rem; padding: 0.55rem 0.8rem; border: 1px solid var(--border);
  border-radius: 10px; background: var(--surface); color: var(--text); cursor: pointer; white-space: nowrap; }
.bar button:hover { background: var(--surface-2); }
.proj { background: var(--surface); border: 1px solid var(--border); border-left: 4px solid var(--brand);
  border-radius: 10px; margin: 0 0 0.9rem; padding: 0.95rem 1.1rem; box-shadow: var(--shadow); scroll-margin-top: 1rem; }
.proj-head { display: flex; flex-wrap: wrap; align-items: center; gap: 0.4rem 0.75rem; margin: 0 0 0.35rem; }
.btn { display: inline-block; padding: 0.3rem 0.8rem; border: 1px solid var(--border); border-radius: 8px;
  background: var(--surface-2); text-decoration: none; font-size: 0.88rem; font-weight: 600; }
.btn:hover { border-color: var(--brand); }
details.subs { margin-top: 0.8rem; }
details.subs > summary { display: flex; align-items: center; gap: 0.5rem; cursor: pointer; list-style: none;
  font-size: 0.9rem; font-weight: 600; padding: 0.4rem 0; color: var(--text); }
details.subs > summary::-webkit-details-marker { display: none; }
details.subs > summary::before { content: "▸"; color: var(--text-muted); transition: transform 0.15s ease; }
details.subs[open] > summary::before { transform: rotate(90deg); }
details.subs > summary:hover { color: var(--accent); }
details.subs .table-wrap { margin-top: 0.4rem; }
.proj-name { font-size: 1.2rem; font-weight: 700; flex: 1; min-width: 10rem; }
.proj-count { font-size: 0.82rem; font-weight: 400; color: var(--text-muted); white-space: nowrap; }
.proj .links { align-items: center; }
.status-pill { margin: 0; white-space: nowrap; }
.main-summary { color: var(--text-muted); margin: 0 0 0.7rem; }
.links { display: flex; flex-wrap: wrap; gap: 0.35rem 0.9rem; font-size: 0.92rem; }
.missing { color: #a4222b; font-size: 0.85rem; }
.td-note { font-size: 0.82rem; color: var(--text-muted); }
.draft { display: inline-block; margin-left: 0.4rem; padding: 0 0.5em; border-radius: 999px; font-size: 0.72rem;
  font-weight: 700; text-transform: uppercase; letter-spacing: 0.03em; background: #fbedd0; color: #8a5f00; vertical-align: 1px; }
td:last-child { width: 1%; white-space: nowrap; }
td .links { flex-direction: column; gap: 0.15rem; }
td .links a, td .missing, td .td-note { display: block; line-height: 1.45; }
.sub-name { font-weight: 600; }
a.sub-name { text-decoration: none; }
a.sub-name::after { content: " →"; color: var(--brand); }
tr[data-href] { cursor: pointer; }
tr[data-href]:hover a.sub-name { text-decoration: underline; }
.sub-summary { display: block; color: var(--text-muted); font-size: 0.82rem; font-weight: 400; }
.hide { display: none; }
"""


def status_pill(s):
    cls = f"status-{s}" if s in STATUSES else ""
    return f'<span class="status-pill {cls}">{esc(s or "?")}</span>'


def render_index(projs, extra, css, logo):
    by_main = {p["main"]: p for p in projs if p["kind"] == "main"}
    subs = [p for p in projs if p["kind"] == "sub"]
    def tally(ps):
        return {k: sum(1 for p in ps if p["td_state"] == k) for k in ("reviewed", "draft", "none", "missing")}
    t = tally(subs)
    done_subs = [p for p in subs if p["status"] in ("done", "impl-done")]
    td_done = tally(done_subs)

    def links(p):
        out = []
        if p["doc"]:
            out.append(f'<a class="btn" href="{esc(p["rel"])}/doc.html">Brain state</a>')
        for rel, title in extra.get(p["rel"], []):
            out.append(f'<a href="{esc(rel)}">{esc(title)}</a>')
        return f'<span class="links">{"".join(out)}</span>'

    body = []
    for main in sorted({p["main"] for p in projs}):
        m = by_main.get(main)
        if not m:
            continue
        msubs = sorted((p for p in subs if p["main"] == main), key=lambda p: (STATUSES.index(p["status"]) if p["status"] in STATUSES else 9, p["name"]))
        hay = esc(f'{main} {m["summary"]} ' + " ".join(f'{p["name"]} {p["status"]}' for p in msubs).lower())
        mt = tally(msubs)
        count = (f'{len(msubs)} sub{"s" if len(msubs) > 1 else ""} · {len(msubs) - mt["missing"]}/{len(msubs)} covered'
                 + (f' · {mt["draft"]} draft' if mt["draft"] else "")) if msubs else "no subs"
        body.append(f'<section class="proj" id="{esc(main)}" data-q="{hay}"><div class="proj-head">'
                    f'<span class="proj-name">{esc(main)}</span>{status_pill(m["status"])}</div>')
        if m["summary"]:
            body.append(f'<p class="main-summary">{esc(m["summary"])}</p>')
        body.append(links(m))
        if msubs:
            rows = []
            for p in msubs:
                tag = {"reviewed": " team-doc reviewed", "draft": " team-doc draft", "none": " not-needed", "missing": " no-team-doc"}[p["td_state"]]
                q = esc(f'{main} {p["name"]} {p["status"]} {p["summary"]}'.lower() + tag)
                gap = {"missing": '<span class="missing">no team doc</span>',
                       "none": '<span class="td-note">no team doc needed</span>'}.get(p["td_state"], "")
                badge = '<span class="draft" title="Not reviewed yet: written from the code and the vault, unchecked">draft</span>' if p["td_state"] == "draft" else ""
                name = (f'<a class="sub-name" href="{esc(p["team_doc"])}">{esc(p["name"])}</a>{badge}' if p["team_doc"]
                        else f'<span class="sub-name">{esc(p["name"])}</span>')
                href = f' data-href="{esc(p["team_doc"])}"' if p["team_doc"] else ""
                rows.append(f'<tr data-q="{q}"{href}><td>{name}'
                            f'<span class="sub-summary">{esc(p["summary"])}</span></td>'
                            f'<td>{status_pill(p["status"])}</td><td>{links(p)}{gap}</td></tr>')
            body.append(f'<details class="subs"><summary>Sub-projects <span class="proj-count">{count}</span></summary>'
                        '<div class="table-wrap"><table><thead><tr><th>Sub-project</th><th>Status</th>'
                        f'<th>Pages</th></tr></thead><tbody>{"".join(rows)}</tbody></table></div></details>')
        body.append("</section>")

    if extra.get(""):
        items = "".join(f'<li><a href="{esc(r)}">{esc(t)}</a></li>' for r, t in extra[""])
        body.append(f'<section class="proj" id="other" data-q="knowledge other"><div class="proj-head">'
                    f'<span class="proj-name">Other pages</span></div><ul>{items}</ul></section>')

    built = datetime.now().strftime("%Y-%m-%d %H:%M")
    toc = "".join(f'<li><a href="#{esc(m)}">{esc(m)}</a></li>' for m in sorted(by_main))
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(VAULT.name)} docs</title>
<style>{css}{INDEX_CSS}</style></head><body>
<aside class="sidebar">
{logo}
<div class="kicker">{esc(VAULT.name)}</div>
<h1>Docs</h1>
<p class="summary">The vault's state, readable: each project's brain-state page, and the team docs written for coworkers.</p>
<ul class="coverage">
<li><strong>{len(by_main)}</strong> projects · <strong>{len(subs)}</strong> sub-projects</li>
<li><strong>{len(subs) - t["missing"]}/{len(subs)}</strong> subs covered</li>
<li>{t["reviewed"]} reviewed · {t["draft"]} draft · {t["none"]} not needed · <span class="missing">{t["missing"]} missing</span></li>
<li><strong>{len(done_subs) - td_done["missing"]}/{len(done_subs)}</strong> of the done / impl-done ones</li>
</ul>
<nav class="toc" style="margin-top:1.2rem"><strong>Projects</strong><ul>{toc}</ul></nav>
</aside>
<div class="content-wrap"><main class="content">
<div class="bar"><input id="q" class="filter" type="search" placeholder="Filter: project, status, draft, no-team-doc, not-needed…" autofocus>
<button type="button" data-all="1">Open all subs</button><button type="button" data-all="0">Close all subs</button></div>
{"".join(body)}
<footer>Rebuilt {built} from the vault on every session Stop · {len(by_main)} brain-state pages</footer>
</main></div>
<script>
// A sub with a team doc: the whole row opens it. Links inside the row keep their own target.
document.querySelectorAll('tr[data-href]').forEach(r=>r.addEventListener('click',e=>{{
if(e.target.closest('a'))return;const u=r.dataset.href;
(e.ctrlKey||e.metaKey)?window.open(u,'_blank'):location.assign(u);}}));
const q=document.getElementById('q'), projs=[...document.querySelectorAll('section.proj')];
q.addEventListener('input',()=>{{const t=q.value.toLowerCase().trim();
projs.forEach(sec=>{{const subs=sec.querySelector('details.subs'), rows=[...sec.querySelectorAll('tr[data-q]')];
rows.forEach(r=>r.classList.toggle('hide',!!t&&!r.dataset.q.includes(t)));
const rowHit=rows.some(r=>!r.classList.contains('hide'));
if(t&&!rowHit&&sec.dataset.q.includes(t))rows.forEach(r=>r.classList.remove('hide'));
sec.classList.toggle('hide',!(!t||rowHit||sec.dataset.q.includes(t)));
if(subs)subs.open=!!t&&rowHit;}});}});
document.querySelectorAll('[data-all]').forEach(b=>b.addEventListener('click',()=>
document.querySelectorAll('details.subs').forEach(d=>d.open=b.dataset.all==='1')));
</script></body></html>
"""


def main():
    if OUT == VAULT or VAULT in OUT.parents or OUT in VAULT.parents:
        sys.exit(f"refusing DOCS_SITE_DIR {OUT}: it is, lies inside or contains the brain {VAULT}")
    pats = excludes()
    projs = [p for p in projects() if not excluded(p["rel"] + "/doc.html", pats)]
    rels = list(pages(pats))
    assets = sorted({a for rel in rels for a in assets_of(rel)})
    OUT.mkdir(parents=True, exist_ok=True)
    copy_pages(rels + assets)
    render_brain_states(projs)

    project_rels = [p["rel"] for p in projs]
    extra = {}
    for p in projs:
        p["team_doc"], p["td_state"] = team_doc_state(p, set(rels)) if p["kind"] == "sub" else ("", "")
    team_docs = {p["team_doc"] for p in projs}
    for rel in rels:
        if rel not in team_docs:
            extra.setdefault(owner_of(rel, project_rels), []).append((rel, title_of(VAULT / rel)))

    css, logo = node_json("const b=require(process.argv[1]);console.log(JSON.stringify([b.CSS,b.LOGO_HTML]))")
    tmp = OUT / ".index.html.tmp"
    tmp.write_text(render_index(projs, extra, css, logo))
    tmp.replace(OUT / "index.html")
    prune(set(rels) | set(assets) | {"index.html"} | {p["rel"] + "/doc.html" for p in projs if p["doc"]})
    print(f"{sum(p['doc'] for p in projs)} brain-state pages, {len(rels)} copied pages -> {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()

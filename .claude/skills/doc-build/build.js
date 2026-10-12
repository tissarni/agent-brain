#!/usr/bin/env node
// Deterministic vault -> standalone HTML compiler for one project (main or sub).
//
// Usage: node build.js <project-dir> [output-path]
//
// This performs a pure structural transform: frontmatter + markdown in, one HTML
// file out. No LLM pass, no summarizing, no paraphrasing — the same source files
// always produce the same document, because the writing already happened when the
// project's context.md/ADRs/specs were authored. This script's only job is to
// render that existing text faithfully for a reader who has no vault, no Obsidian,
// and no access to the paths it references (see AGENTS.md's vault-boundary rule).
'use strict';

const fs = require('fs');
const path = require('path');

// ---------- generic helpers ----------

function readFile(p) {
  return fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
}

// Single escape pass, used everywhere raw source text enters the page (both
// element content and attribute values) so nothing downstream ever re-escapes it.
function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function slugify(s) {
  return (
    String(s)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'section'
  );
}

// ---------- frontmatter (hand-rolled: no YAML lib available offline) ----------

function parseFrontmatter(raw) {
  if (!raw.startsWith('---\n')) return { meta: {}, body: raw };
  const end = raw.indexOf('\n---', 4);
  if (end === -1) return { meta: {}, body: raw };
  const block = raw.slice(4, end);
  const body = raw.slice(end + 4).replace(/^\n/, '');
  const lines = block.split('\n');
  const meta = {};
  let i = 0;
  while (i < lines.length) {
    const m = /^([A-Za-z_][\w-]*):\s?(.*)$/.exec(lines[i]);
    if (!m) {
      i++;
      continue;
    }
    const key = m[1];
    const rawValue = m[2];
    // Folded/literal block scalar (`>-`, `|-`, `>`, `|`): match the whole token,
    // never by stripping characters -- `repo: -` is a real value ("no repo"),
    // not the start of a block scalar.
    if (rawValue === '>-' || rawValue === '|-' || rawValue === '>' || rawValue === '|') {
      const parts = [];
      i++;
      while (i < lines.length && /^\s+\S/.test(lines[i])) {
        parts.push(lines[i].trim());
        i++;
      }
      meta[key] = parts.join(' ');
      continue;
    }
    const value = rawValue.trim();
    if (/^\[.*\]$/.test(value)) {
      meta[key] = value
        .slice(1, -1)
        .split(',')
        .map((v) => v.trim())
        .filter(Boolean);
    } else if (/^".*"$/.test(value) || /^'.*'$/.test(value)) {
      meta[key] = value.slice(1, -1);
    } else {
      meta[key] = value;
    }
    i++;
  }
  return { meta, body };
}

// ---------- markdown -> HTML ----------
// Not a full CommonMark implementation -- covers exactly the subset this vault's
// files actually use (checked against real context.md/ADR/spec files): headers,
// paragraphs, bold/italic/strikethrough/code, fenced code blocks, blockquotes,
// GFM pipe tables, ordered/unordered lists (with nesting and multi-line items),
// horizontal rules, markdown links, [[wikilinks]] and block images.

function renderMarkdown(md, opts) {
  const lines = md.replace(/\t/g, '    ').split('\n');
  return renderBlocks(lines, opts);
}

function renderBlocks(lines, opts) {
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];

    if (line.trim() === '') {
      i++;
      continue;
    }

    const fence = /^(```+|~~~+)\s*([\w+-]*)\s*$/.exec(line);
    if (fence) {
      const marker = fence[1];
      const lang = fence[2];
      const codeLines = [];
      i++;
      while (i < lines.length && lines[i].trim() !== marker) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // skip closing fence
      const cls = lang ? ` class="language-${escapeHtml(lang)}"` : '';
      out.push(`<pre><code${cls}>${escapeHtml(codeLines.join('\n'))}</code></pre>`);
      continue;
    }

    const image = /^!\[([^\]]*)\]\(([^)\s]+)\)\s*$/.exec(line.trim());
    if (image) {
      out.push(renderFigure(image[1], image[2], opts));
      i++;
      continue;
    }

    if (/^(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
      out.push('<hr>');
      i++;
      continue;
    }

    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      const level = Math.max(1, Math.min(6, heading[1].length + (opts.headingOffset || 0)));
      const text = heading[2].trim();
      out.push(`<h${level} id="${slugify(text)}">${renderInline(text)}</h${level}>`);
      i++;
      continue;
    }

    if (/^>\s?/.test(line)) {
      const quoteLines = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        quoteLines.push(lines[i].replace(/^>\s?/, ''));
        i++;
      }
      out.push(`<blockquote>${renderBlocks(quoteLines, opts)}</blockquote>`);
      continue;
    }

    if (
      /^\s*\|/.test(line) &&
      i + 1 < lines.length &&
      /^\s*\|?[\s:|-]+\|?\s*$/.test(lines[i + 1]) &&
      lines[i + 1].includes('-')
    ) {
      const headerCells = splitTableRow(line);
      const aligns = splitTableRow(lines[i + 1]).map((c) => {
        const t = c.trim();
        if (/^:-+:$/.test(t)) return 'center';
        if (/^-+:$/.test(t)) return 'right';
        if (/^:-+$/.test(t)) return 'left';
        return null;
      });
      i += 2;
      const rows = [];
      while (i < lines.length && /^\s*\|/.test(lines[i])) {
        rows.push(splitTableRow(lines[i]));
        i++;
      }
      out.push(renderTable(headerCells, aligns, rows));
      continue;
    }

    if (/^(\s*)([-*+]|\d+\.)\s+/.test(line)) {
      const { html, next } = renderList(lines, i, opts);
      out.push(html);
      i = next;
      continue;
    }

    const paraLines = [];
    while (
      i < lines.length &&
      lines[i].trim() !== '' &&
      !/^(```+|~~~+)/.test(lines[i]) &&
      !/^(#{1,6})\s+/.test(lines[i]) &&
      !/^>\s?/.test(lines[i]) &&
      !/^(\s*)([-*+]|\d+\.)\s+/.test(lines[i]) &&
      !/^(-{3,}|\*{3,}|_{3,})\s*$/.test(lines[i])
    ) {
      paraLines.push(lines[i].trim());
      i++;
    }
    if (paraLines.length) {
      out.push(`<p>${renderInline(paraLines.join(' '))}</p>`);
    } else {
      i++; // never loop forever on a line we didn't recognize
    }
  }
  return out.join('\n');
}

function splitTableRow(line) {
  let t = line.trim();
  if (t.startsWith('|')) t = t.slice(1);
  if (t.endsWith('|')) t = t.slice(0, -1);
  const cells = [];
  let cur = '';
  for (let j = 0; j < t.length; j++) {
    if (t[j] === '\\' && t[j + 1] === '|') {
      cur += '|';
      j++;
      continue;
    }
    if (t[j] === '|') {
      cells.push(cur);
      cur = '';
      continue;
    }
    cur += t[j];
  }
  cells.push(cur);
  return cells.map((c) => c.trim());
}

function renderTable(header, aligns, rows) {
  const alignStyle = (idx) => (aligns[idx] ? ` style="text-align:${aligns[idx]}"` : '');
  const th = header.map((c, idx) => `<th${alignStyle(idx)}>${renderInline(c)}</th>`).join('');
  const body = rows
    .map((r) => `<tr>${r.map((c, idx) => `<td${alignStyle(idx)}>${renderInline(c || '')}</td>`).join('')}</tr>`)
    .join('\n');
  return `<div class="table-wrap"><table><thead><tr>${th}</tr></thead><tbody>\n${body}\n</tbody></table></div>`;
}

function renderList(lines, start, opts) {
  const baseIndent = lines[start].match(/^(\s*)/)[1].length;
  const ordered = /^\s*\d+\./.test(lines[start]);
  const markerRe = ordered ? /^(\s*)(\d+)\.\s+(.*)$/ : /^(\s*)([-*+])\s+(.*)$/;
  const items = [];
  let i = start;

  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === '') {
      const next = lines[i + 1];
      if (next && markerRe.test(next) && next.match(/^(\s*)/)[1].length === baseIndent) {
        i++;
        continue;
      }
      break;
    }
    const m = markerRe.exec(line);
    const indent = line.match(/^(\s*)/)[1].length;
    if (!m || indent !== baseIndent) {
      if (m && indent > baseIndent) {
        const nested = renderList(lines, i, opts);
        items[items.length - 1].sub += nested.html;
        i = nested.next;
        continue;
      }
      if (indent > baseIndent && items.length) {
        items[items.length - 1].text += ' ' + line.trim();
        i++;
        continue;
      }
      break;
    }
    items.push({ text: m[3], sub: '' });
    i++;
  }

  const tag = ordered ? 'ol' : 'ul';
  const html =
    `<${tag}>\n` +
    items.map((it) => `<li>${renderInline(it.text)}${it.sub ? '\n' + it.sub : ''}</li>`).join('\n') +
    `\n</${tag}>`;
  return { html, next: i };
}

// A line holding only `![caption](file)` becomes a figure. A local file is
// embedded as a data URI, resolved against opts.baseDir (the source file's
// folder), so the page stays one offline file; a URL is linked as is. The alt
// text doubles as the caption.
const IMAGE_TYPES = { '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp' };

function renderFigure(alt, src, opts) {
  let url = src;
  if (!/^(https?:|data:)/i.test(src)) {
    const file = path.resolve((opts && opts.baseDir) || process.cwd(), decodeURIComponent(src));
    const type = IMAGE_TYPES[path.extname(file).toLowerCase()];
    if (!type || !fs.existsSync(file)) {
      console.error(`image not embedded (missing or unsupported type): ${src}`);
      return `<p class="missing-image">[image: ${escapeHtml(alt || src)}]</p>`;
    }
    url = `data:${type};base64,${fs.readFileSync(file).toString('base64')}`;
  }
  const caption = alt ? `<figcaption>${escapeHtml(alt)}</figcaption>` : '';
  return `<figure class="doc-figure"><img src="${escapeHtml(url)}" alt="${escapeHtml(alt)}">${caption}</figure>`;
}

function renderInline(text) {
  let s = escapeHtml(text);

  const codeStore = [];
  s = s.replace(/`([^`]+)`/g, (_, code) => {
    codeStore.push(code);
    return ` CODE${codeStore.length - 1} `;
  });

  // Obsidian-style cross-references. `target`/`label` below are already
  // HTML-escaped (this whole string was escaped above) -- do not escape again.
  s = s.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_, target, label) =>
    resolveWikilink(target.trim(), label ? label.trim() : null)
  );

  s = s.replace(
    /\[([^\]]+)\]\(([^)\s]+)\)/g,
    (_, txt, url) => `<a href="${url}" target="_blank" rel="noopener">${txt}</a>`
  );

  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/__([^_]+)__/g, '<strong>$1</strong>');
  s = s.replace(/~~([^~]+)~~/g, '<del>$1</del>');
  s = s.replace(/(^|[^*])\*([^*\s][^*]*?)\*(?!\*)/g, '$1<em>$2</em>');
  s = s.replace(/(^|[^_\w])_([^_\s][^_]*?)_(?!_)/g, '$1<em>$2</em>');

  s = s.replace(/ CODE(\d+) /g, (_, idx) => `<code>${codeStore[idx]}</code>`);

  return s;
}

// Turn an Obsidian-style [[target]] or [[target|label]] reference into safe
// inline HTML. `target` is the raw vault path inside the brackets (already
// HTML-escaped -- e.g. "02-projects/web-app/context"), `label` is the text after
// `|`, or null if there wasn't one.
//
// The reader of this document has no vault, no Obsidian, and generally no
// filesystem access to what `target` points at -- see AGENTS.md's "vault is
// personal memory, not team-shared" boundary rule. A real hyperlink back into
// the vault would be both broken for that reader and a path-structure leak.
// Decide what to actually show them instead: how much of `target` survives,
// whether it's ever a real, clickable link (e.g. to a sibling doc-build output
// that happens to sit alongside this file), and how it's visually distinguished
// from a normal link so nobody clicks it expecting a working page.
//
// Must return a string of inline HTML (e.g. a <span>...</span>), safe to splice
// directly into the page.
//
// Decision: never a real <a href> -- the target is a vault-relative path with
// nothing on the other end for this reader, and a link that looks clickable but
// goes nowhere is worse than plain text. Render inert, styled text (the .wikiref
// class already in the stylesheet marks it visually as "internal reference, not
// a link" -- dashed underline, no pointer cursor) with the full path kept only
// in a title tooltip, for the rare reader who does have vault access.
//
// The visible label is kept short rather than dumping the full path inline,
// since a context.md body can carry a dozen of these and a wall of
// "02-projects/web-app/subprojects/login-timeout/context" fragments would bury
// the actual prose:
//   - an explicit `|label` always wins (the author chose it on purpose)
//   - a `.../decisions/ADR-003-slug` or `.../decisions/0003-slug` target
//     collapses to "ADR-003" -- consistent with how this doc lists decisions
//     elsewhere. The bare-numeric form is accepted ONLY inside `decisions/`, and
//     never for a date-shaped prefix: every spec in this vault is named
//     `YYYY-MM-DD-slug`, so an unguarded `\d{4}-` rule labelled all of them
//     "ADR-2026" -- a wrong label pointing at the wrong kind of document
//   - a `YYYY-MM-DD-slug` target (the spec naming convention) drops the date and
//     shows the slug; the date is noise, and the slug is what the prose means
//   - a trailing `/context`, `/current`, `/summary` or `/README` segment (the
//     vault's fixed per-project filenames, not content) is dropped in favor of
//     the project/sub folder name above it
//   - otherwise, just the last path segment
function resolveWikilink(target, label) {
  const withoutPrefix = target.replace(/^02-projects\//, '');
  const segments = withoutPrefix.split('/').filter(Boolean);
  const last = segments[segments.length - 1] || withoutPrefix;
  const knownFilenames = new Set(['context', 'current', 'summary', 'readme']);

  let derived;
  const datePrefixed = /^(\d{4}-\d{2}-\d{2})-(.+)$/.exec(last);
  const inDecisions = segments[segments.length - 2] === 'decisions';
  const adrPattern = (inDecisions && !datePrefixed) ? /^(ADR-\d+|\d{4})-/i : /^(ADR-\d+)-/i;
  const adrMatch = adrPattern.exec(last);
  if (adrMatch) {
    derived = /^ADR-/i.test(adrMatch[1]) ? adrMatch[1].toUpperCase() : `ADR-${adrMatch[1]}`;
  } else if (datePrefixed) {
    derived = datePrefixed[2];
  } else if (knownFilenames.has(last.toLowerCase()) && segments.length > 1) {
    derived = segments[segments.length - 2];
  } else {
    derived = last;
  }

  const text = label || derived;
  return `<span class="wikiref" title="vault reference: ${target}">${text}</span>`;
}

// ---------- project-level rendering ----------

function listAdrFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isFile() && /\.md$/i.test(d.name))
    .map((d) => {
      const m = /^(?:ADR-)?(\d+)-/i.exec(d.name);
      return { name: d.name, num: m ? parseInt(m[1], 10) : Number.MAX_SAFE_INTEGER };
    })
    .sort((a, b) => a.num - b.num || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
    .map((x) => path.join(dir, x.name));
}

function listMdFilesSorted(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isFile() && /\.md$/i.test(d.name))
    .map((d) => d.name)
    .sort()
    .map((name) => path.join(dir, name));
}

function listExtraTopLevelFiles(dir, known) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isFile() && /\.md$/i.test(d.name) && !known.has(d.name.toLowerCase()))
    .map((d) => d.name)
    .sort()
    .map((name) => path.join(dir, name));
}

// The vault has two ADR shapes in the wild: older files carry `status`/`date`/
// `superseded_by` in frontmatter; newer ones (matching the current /adr skill
// template) have no frontmatter at all and put `Date:`/`Status:` as plain body
// lines instead. Read whichever is present rather than assuming one shape.
function extractAdrMeta(filePath, raw) {
  const { meta, body } = parseFrontmatter(raw);
  let status = meta.status || null;
  let date = meta.date || null;
  const supersededBy = meta.superseded_by || null;

  for (const l of body.split('\n').slice(0, 8)) {
    const dM = /^Date:\s*(.+)$/i.exec(l.trim());
    if (dM && !date) date = dM[1].trim();
    const sM = /^Status:\s*(.+)$/i.exec(l.trim());
    if (sM && !status) status = sM[1].trim();
  }

  let title = path.basename(filePath, '.md');
  const hM = /^#\s+(.+)$/m.exec(body);
  if (hM) title = hM[1].replace(/^ADR-\d+\s*[:—-]\s*/i, '').trim();

  return { title, status: status || 'unknown', date, supersededBy, body };
}

function classifyStatus(status) {
  const s = (status || 'unknown').toLowerCase();
  return s.includes('supersed')
    ? 'superseded'
    : s.includes('reject')
    ? 'rejected'
    : s.includes('propos') || s.includes('draft')
    ? 'proposed'
    : s.includes('accept')
    ? 'accepted'
    : 'unknown';
}

function statusBadge(status) {
  return `<span class="badge badge-${classifyStatus(status)}">${escapeHtml(status || 'unknown')}</span>`;
}

function projectStatusEmoji(status) {
  return { active: '🟢', blocked: '🔴', 'impl-done': '🟡', done: '⚪', paused: '⏸' }[status] || '•';
}

function projectStatusClass(status) {
  return (
    { active: 'status-active', blocked: 'status-blocked', 'impl-done': 'status-impl-done', done: 'status-done', paused: 'status-paused' }[
      status
    ] || 'status-unknown'
  );
}

function renderAdrSection(adrPaths, opts) {
  return adrPaths
    .map((p) => {
      const info = extractAdrMeta(p, readFile(p));
      const bodyHtml = renderMarkdown(info.body, { headingOffset: (opts.headingOffset || 0) + 1 });
      const supersededNote = info.supersededBy
        ? ` <span class="badge badge-superseded">superseded by ${escapeHtml(info.supersededBy)}</span>`
        : '';
      const dateNote = info.date ? ` <span class="adr-date">${escapeHtml(info.date)}</span>` : '';
      return `<details class="adr" data-status="${classifyStatus(info.status)}" open>
<summary><span class="adr-file">${escapeHtml(path.basename(p))}</span> <span class="adr-title">${renderInline(
        info.title
      )}</span> ${statusBadge(info.status)}${supersededNote}${dateNote}</summary>
<div class="adr-body">
${bodyHtml}
</div>
</details>`;
    })
    .join('\n');
}

function renderSpecSection(specPaths, opts) {
  return specPaths
    .map((p) => {
      const { meta, body } = parseFrontmatter(readFile(p));
      const bodyHtml = renderMarkdown(body, { headingOffset: (opts.headingOffset || 0) + 1 });
      const statusNote = meta.status ? ` ${statusBadge(meta.status)}` : '';
      const updatedNote = meta.updated ? ` <span class="adr-date">${escapeHtml(meta.updated)}</span>` : '';
      return `<details class="adr" data-status="${classifyStatus(meta.status)}" open>
<summary><span class="adr-file">${escapeHtml(path.basename(p, '.md'))}</span>${statusNote}${updatedNote}</summary>
<div class="adr-body">
${bodyHtml}
</div>
</details>`;
    })
    .join('\n');
}

// brain.env is read, never sourced: the value is everything after the first `=`.
// A leading `~/` is the home directory; a relative path is relative to the brain's root.
function brainEnv(key) {
  try {
    const root = path.resolve(__dirname, '..', '..', '..');
    for (const line of fs.readFileSync(path.join(root, 'brain.env'), 'utf8').split('\n')) {
      if (line.startsWith(key + '=')) {
        const v = line.slice(key.length + 1).replace(/\r$/, '');
        if (!v) return '';
        if (v === '~' || v.startsWith('~/')) return path.join(require('os').homedir(), v.slice(1));
        return path.resolve(root, v);
      }
    }
  } catch (e) { /* no brain.env: defaults */ }
  return '';
}

// The theme directory named by HTML_THEME holds theme.css and optionally logo.svg or
// logo.png. Any of them missing gives the neutral look, never an error.
const THEME_DIR = brainEnv('HTML_THEME');
const THEME_FILE = (name) => {
  const f = THEME_DIR && path.join(THEME_DIR, name);
  return f && fs.existsSync(f) ? f : '';
};
const LOGO_FILE = THEME_FILE('logo.svg') || THEME_FILE('logo.png');
const LOGO_HTML = LOGO_FILE
  ? `<img class="brand-logo" alt="" src="data:${IMAGE_TYPES[path.extname(LOGO_FILE)]};base64,${fs.readFileSync(LOGO_FILE).toString('base64')}">`
  : '';
const THEME_CSS = THEME_FILE('theme.css') ? fs.readFileSync(THEME_FILE('theme.css'), 'utf8') : '';

const BASE_CSS = `
:root {
  /* Neutral defaults; a theme's theme.css overrides any of them. */
  color-scheme: light;
  --bg: #fafafa; --surface: #ffffff; --surface-2: #f4f4f5;
  --text: #18181b; --text-muted: #71717a; --border: rgba(0, 0, 0, 0.1);
  --accent: #1d4ed8; --accent-soft: #eef2ff; --brand: #1d4ed8;
  --shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
}
* { box-sizing: border-box; }
body {
  font-family: Arial, Helvetica, sans-serif;
  line-height: 1.6; margin: 0; color: var(--text); background: var(--bg); font-size: 16.5px;
}
a { color: var(--accent); }
.sidebar {
  position: fixed; top: 0; left: 0; bottom: 0; width: 280px; overflow-y: auto;
  padding: 2.5rem 1.75rem; background: var(--surface); border-right: 1px solid var(--border);
  border-top: 4px solid var(--brand);
}
.brand-logo { display: block; width: 56px; height: 56px; margin: 0 0 1.25rem; }
.content-wrap { margin-left: 280px; padding: 3rem 2rem 6rem; }
.content { max-width: 760px; margin: 0 auto; min-width: 0; }
.kicker { font-size: 0.76rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em; color: var(--accent); margin-bottom: 0.5rem; }
.sidebar h1 { font-size: 1.6rem; margin: 0 0 0.6rem; }
.summary { color: var(--text-muted); margin: 0 0 1rem; }
h1, h2, h3, h4, h5, h6 { line-height: 1.3; scroll-margin-top: 1.5rem; font-weight: 700; }
h2 { font-size: 1.5rem; margin: 2.8rem 0 1rem; padding-bottom: 0.5rem; border-bottom: 2px solid var(--border); }
h3 { font-size: 1.15rem; margin-top: 2rem; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: var(--surface-2); padding: 0.15em 0.4em; border-radius: 5px; font-size: 0.88em; }
pre { background: var(--surface-2); border: 1px solid var(--border); padding: 1rem 1.1rem; border-radius: 10px; overflow-x: auto; }
pre code { background: none; padding: 0; border-radius: 0; }
blockquote { border-left: 3px solid var(--brand); margin: 1.2rem 0; padding: 0.3rem 1.2rem; color: var(--text-muted); background: var(--accent-soft); border-radius: 0 8px 8px 0; }
hr { border: none; border-top: 1px solid var(--border); margin: 2.5rem 0; }
.table-wrap { overflow-x: auto; margin: 1.2rem 0; border: 1px solid var(--border); border-radius: 10px; }
table { border-collapse: collapse; width: 100%; font-size: 0.92rem; }
th, td { border-bottom: 1px solid var(--border); padding: 0.55rem 0.85rem; text-align: left; vertical-align: top; }
tr:last-child td { border-bottom: none; }
th { background: var(--surface-2); font-weight: 600; }
tbody tr:hover { background: var(--surface-2); }
details.adr { background: var(--surface); border: 1px solid var(--border); border-left: 4px solid var(--border); border-radius: 10px; margin: 1.1rem 0; padding: 0.9rem 1.2rem; box-shadow: var(--shadow); }
details.adr[data-status="accepted"] { border-left-color: #2f9e56; }
details.adr[data-status="proposed"] { border-left-color: #c98a12; }
details.adr[data-status="rejected"] { border-left-color: #d1414b; }
details.adr[data-status="superseded"] { border-left-color: var(--border); opacity: 0.82; }
details.adr[data-status="extra"] { border-left-color: var(--accent); }
details.adr summary { cursor: pointer; font-weight: 600; display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: baseline; list-style: none; }
details.adr summary::-webkit-details-marker { display: none; }
details.adr summary::before { content: "▸"; display: inline-block; color: var(--text-muted); transition: transform 0.15s ease; }
details.adr[open] summary::before { transform: rotate(90deg); }
.adr-file { font-family: ui-monospace, monospace; font-size: 0.82rem; opacity: 0.6; font-weight: 400; }
.adr-date { font-weight: 400; opacity: 0.6; font-size: 0.85rem; }
.adr-body { margin-top: 1rem; }
.badge { display: inline-block; padding: 0.15em 0.65em; border-radius: 999px; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.03em; }
.badge-accepted { background: #d9f5e3; color: #0f7a3d; }
.badge-proposed { background: #fbedd0; color: #8a5f00; }
.badge-rejected { background: #fbdadd; color: #a4222b; }
.badge-superseded { background: var(--surface-2); color: var(--text-muted); text-decoration: line-through; }
.badge-unknown { background: var(--surface-2); color: var(--text-muted); }
.status-pill { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.3em 0.8em; border-radius: 999px; font-size: 0.82rem; font-weight: 600; background: var(--surface-2); margin: 0 0 1.2rem; }
.status-active { background: #d9f5e3; color: #0f7a3d; }
.status-blocked { background: #fbdadd; color: #a4222b; }
.status-impl-done { background: #fbedd0; color: #8a5f00; }
.status-done { background: var(--surface-2); color: var(--text-muted); }
.status-paused { background: var(--accent-soft); color: var(--accent); }
.meta-table { border-collapse: collapse; margin: 0 0 1.3rem; font-size: 0.85rem; width: 100%; }
.meta-table td { border: none; padding: 0.2rem 0; }
.meta-table td:first-child { opacity: 0.55; white-space: nowrap; padding-right: 0.8rem; width: 1%; }
.toc { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 1rem 1.3rem; }
.toc strong { font-size: 0.76rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-muted); }
.toc ul { list-style: none; margin: 0.6rem 0 0; padding: 0; }
.toc li { margin: 0.4rem 0; }
.toc a { text-decoration: none; font-size: 0.92rem; }
.toc a:hover { text-decoration: underline; }
.wikiref { border-bottom: 1px dashed var(--text-muted); opacity: 0.85; cursor: default; }
footer { margin-top: 4rem; padding-top: 1.4rem; border-top: 1px solid var(--border); font-size: 0.8rem; color: var(--text-muted); }
footer ul { padding-left: 1.2rem; }
.doc-figure { margin: 1.6rem 0; }
.doc-figure img { display: block; max-width: 100%; height: auto; margin: 0 auto; }
.doc-figure figcaption { margin-top: 0.5rem; font-size: 0.85rem; color: var(--text-muted); text-align: center; }
.missing-image { color: var(--text-muted); font-style: italic; }
@media (max-width: 860px) {
  .sidebar { position: static; width: auto; height: auto; border-right: none; border-bottom: 1px solid var(--border); padding: 1.75rem 1.25rem; }
  .content-wrap { margin-left: 0; padding: 1.75rem 1.25rem 4rem; }
  .content { max-width: none; }
}
`;

const CSS = THEME_CSS ? `${BASE_CSS}\n${THEME_CSS}` : BASE_CSS;

function renderDocument(meta, folderName, sections, manifest, generatedAt) {
  const title = meta.project || folderName;
  const summary = meta.summary || '';
  const emoji = projectStatusEmoji(meta.status);
  const kicker = meta.kind ? (meta.parent ? `${meta.kind} of ${meta.parent}` : meta.kind) : '';

  const metaRows = [
    ['created', meta.created],
    ['updated', meta.updated],
    ['repo', meta.repo],
    ['branch', meta.branch],
    ['related', Array.isArray(meta.related) ? meta.related.join(', ') : meta.related],
    ['blocker', meta.blocker],
  ].filter(([, v]) => v);

  const metaHtml = metaRows
    .map(([k, v]) => `<tr><td>${escapeHtml(k)}</td><td>${escapeHtml(v)}</td></tr>`)
    .join('\n');

  const statusPill = meta.status
    ? `<div class="status-pill ${projectStatusClass(meta.status)}">${emoji} ${escapeHtml(meta.status)}</div>`
    : '';

  const tocHtml = sections.map((s) => `<li><a href="#${s.id}">${escapeHtml(s.title)}</a></li>`).join('\n');

  const sectionsHtml = sections
    .map((s) => `<section id="${s.id}">\n<h2>${escapeHtml(s.title)}</h2>\n${s.html}\n</section>`)
    .join('\n');

  const manifestHtml = manifest.map((f) => `<li><code>${escapeHtml(f)}</code></li>`).join('\n');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} — project documentation</title>
<style>${CSS}</style>
</head>
<body>
<!-- GENERATED by doc-build from vault source files — do not hand-edit; rerun to refresh -->
<aside class="sidebar">
${LOGO_HTML}
${kicker ? `<div class="kicker">${escapeHtml(kicker)}</div>` : ''}
<h1>${escapeHtml(title)}</h1>
${summary ? `<p class="summary">${escapeHtml(summary)}</p>` : ''}
${statusPill}
${metaHtml ? `<table class="meta-table">${metaHtml}</table>` : ''}
<nav class="toc"><strong>Contents</strong><ul>${tocHtml}</ul></nav>
</aside>
<div class="content-wrap">
<main class="content">
${sectionsHtml}
<footer>
Built ${escapeHtml(generatedAt)} by doc-build from ${manifest.length} source file(s) in the vault:
<ul>${manifestHtml}</ul>
This is a structural render of those files, not a summary — if something reads oddly, the
source file does too. Regenerate after the vault changes; this file does not update itself.
</footer>
</main>
</div>
</body>
</html>
`;
}

// ---------- CLI ----------

function main() {
  const projectDir = process.argv[2];
  if (!projectDir) {
    console.error('usage: node build.js <project-dir> [output-path]');
    process.exit(1);
  }
  const resolvedDir = path.resolve(projectDir);
  const contextPath = path.join(resolvedDir, 'context.md');
  if (!fs.existsSync(contextPath)) {
    console.error(`no context.md in ${resolvedDir} — resolve the project path first (AGENTS.md § Project path resolution)`);
    process.exit(1);
  }
  const outPath = process.argv[3] ? path.resolve(process.argv[3]) : path.join(resolvedDir, 'doc.html');

  const { meta, body: contextBody } = parseFrontmatter(readFile(contextPath));
  const manifest = ['context.md'];
  const opts = { headingOffset: 1 };

  const known = new Set(['context.md', 'current.md', 'summary.md', 'readme.md', '_index.md']);
  const adrPaths = listAdrFiles(path.join(resolvedDir, 'decisions'));
  const specPaths = listMdFilesSorted(path.join(resolvedDir, 'specs'));
  const summaryPath = path.join(resolvedDir, 'summary.md');
  const currentPath = path.join(resolvedDir, 'current.md');
  const extraPaths = listExtraTopLevelFiles(resolvedDir, known);

  const sections = [{ id: 'overview', title: 'Overview', html: renderMarkdown(contextBody, opts) }];

  if (adrPaths.length) {
    sections.push({ id: 'decisions', title: `Key Decisions (${adrPaths.length})`, html: renderAdrSection(adrPaths, opts) });
    adrPaths.forEach((p) => manifest.push(path.relative(resolvedDir, p)));
  }

  if (specPaths.length) {
    sections.push({ id: 'specs', title: `Design Specs (${specPaths.length})`, html: renderSpecSection(specPaths, opts) });
    specPaths.forEach((p) => manifest.push(path.relative(resolvedDir, p)));
  }

  if (fs.existsSync(summaryPath)) {
    const { body } = parseFrontmatter(readFile(summaryPath));
    sections.push({ id: 'outcome', title: 'Outcome', html: renderMarkdown(body, opts) });
    manifest.push('summary.md');
  } else if (fs.existsSync(currentPath)) {
    const { body } = parseFrontmatter(readFile(currentPath));
    sections.push({ id: 'current', title: 'Current State', html: renderMarkdown(body, opts) });
    manifest.push('current.md');
  }

  if (extraPaths.length) {
    // Loose operational docs (cookbooks, runbooks, guides) render COLLAPSED —
    // a project can carry several long ones, and expanding them all made
    // doc.html an unreadable wall. The reader opens what they need; the page
    // stays a concise overview. Same <details> pattern as ADRs above.
    const html = extraPaths
      .map((p) => {
        const { body } = parseFrontmatter(readFile(p));
        const name = path.basename(p, '.md');
        return `<details class="adr" data-status="extra">\n<summary><span class="adr-file">${escapeHtml(
          name
        )}</span></summary>\n<div class="adr-body">\n${renderMarkdown(
          body,
          { headingOffset: 1 }
        )}\n</div>\n</details>`;
      })
      .join('\n');
    sections.push({ id: 'notes', title: `Additional Notes (${extraPaths.length} — click to expand)`, html });
    extraPaths.forEach((p) => manifest.push(path.relative(resolvedDir, p)));
  }

  const generatedAt = new Date().toISOString().slice(0, 16).replace('T', ' ') + ' UTC';
  const html = renderDocument(meta, path.basename(resolvedDir), sections, manifest, generatedAt);
  fs.writeFileSync(outPath, html, 'utf8');

  console.log(`built ${outPath}`);
  console.log(`source files (${manifest.length}):`);
  manifest.forEach((f) => console.log(`  - ${f}`));
}

module.exports = {
  readFile,
  parseFrontmatter,
  renderMarkdown,
  renderInline,
  slugify,
  escapeHtml,
  CSS,
  LOGO_HTML,
};

// CLI entry — only when run directly (`node build.js ...`), not when required
// as a module by another skill (e.g. md-html reuses the renderer).
if (require.main === module) main();

---
name: md-html
description: Render any single vault .md (cookbook, guide, runbook) into a standalone HTML page in the same design as doc-build. Use when the user says "make an HTML of this doc/cookbook", or when a standalone page of one file is wanted.
---

Arguments: a path to a `.md` file (vault-relative or absolute).

## Why this exists
Everything is written as `.md` in the vault. `doc-build` renders a whole
*project* (context + ADRs + specs + current) into one `doc.html`. But sometimes
one file deserves its own page — a cookbook, an ops guide, a migration runbook —
without dragging the whole project along, and in the **same visual design** so
all HTML artifacts in the vault look alike.

`md-html` is that single-file path: it reuses `doc-build`'s renderer and CSS
directly (imports `build.js` as a module — no copy of the design exists here),
so the two skills can never drift apart visually.

## Steps
1. Resolve the `.md` path; confirm it exists and ends in `.md`.
2. Run:
   ```
   node .agents/skills/md-html/build.js <path-to-file.md> [output-path]
   ```
   Output defaults to `<file>.html` **next to the source .md**.
3. Report the output path and source file, verbatim from the script's stdout.
   Do not paste the HTML into chat — it's built to be read as a page.
4. Offer to open/send it.

## Relationship to doc-build
- `doc-build` = full subproject doc (`doc.html`), reads the project folder.
- `md-html` = one `.md` → one `.html`, same design.
- For the base subproject doc, `doc-build` remains the default; run `md-html`
  on individual files only when a standalone page of that file is wanted
  (e.g. a cookbook shared on its own).
- Both are deterministic: never hand-edit the output — fix `build.js` and
  rerun. Never copy doc-build's CSS into this skill; import it.

## What it renders
- Frontmatter `title`, `summary`, `kind` feed the sidebar (same layout as
  doc-build); first `# heading` is the fallback title.
- The body's `#` is the page `h1` (styled as the page title); `##` stay `h2` so
  sections look like doc-build pages. No frontmatter needed: `summary` falls back
  to the first paragraph, `kind` to `readme` for a README.md. Sidebar TOC lists h2.
- Same markdown subset as doc-build (tables, fenced code, wikilinks, ADR-style
  details blocks are NOT used here — plain sections only).
- A line holding only `![caption](file.svg)` becomes a figure, the alt text its
  caption. The file is resolved next to the `.md` and embedded (svg, png, jpg, gif,
  webp), so the page stays one offline file; a missing file prints a warning.

## Re-running
Idempotent — rerunning after the `.md` changes overwrites the `.html`. Only the
`Built <timestamp>` footer line differs between runs over an unchanged source.

Last, apply the rules filed under `### /md-html` in `AGENTS.local.md` § Local rules, if there are any.

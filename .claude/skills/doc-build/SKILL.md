---
name: doc-build
description: Build a standalone HTML documentation page for a project from its vault files — deterministic, for sharing with a teammate who has no vault access. Use when user says "document this subproject", "build docs for X", "make an onboarding doc", "generate a handoff doc".
---

Arguments: a main or sub project name.

## Why this exists
A freehand "write an HTML summary of this session" prompt re-derives its own structure
and wording every time it runs, because it's really asking the model to redo judgment
calls that are already made and written down — in `context.md`, the ADRs, the specs.
Run it twice on an unchanged subproject and the two documents can disagree.

This skill runs a build instead: `build.js` renders those existing files structurally
and faithfully, with no summarizing pass. Same source files in, same document out.
When the output changes, it's because the vault files changed — not because the model
phrased it differently this time.

## Steps
1. Resolve the project folder with the rule in AGENTS.md (§ Project path resolution).
2. Confirm its `context.md` exists — `build.js` refuses to run without one.
3. Run:
   ```
   node .agents/skills/doc-build/build.js <resolved-project-dir>
   ```
   This writes `doc.html` inside the project folder and prints the exact list of
   source files it read.
4. Report the output path and the source-file manifest to the user, verbatim from
   the script's stdout. Do not add your own summary of what the project is about —
   the HTML already contains that; narrating it again in chat just reintroduces
   the variance this skill exists to remove.
5. Offer to open it or send it (e.g. via SendUserFile). Do not paste its content
   into the chat — it's built to be read as a page, not as a message.

## What it reads
`context.md`, every `decisions/ADR-*.md` (sorted numerically, not alphabetically —
`ADR-10` sorts after `ADR-9`, not before), every `specs/*.md`, then `summary.md` if
present else `current.md`, then any other loose `.md` file directly in the project
folder (e.g. `friction-log.md`, `implementation-plan.md`). Never `_archive/`, never
`README.md`, never `_index.md` — same exclusions as everywhere else in this vault.

## What it does not do
- No LLM pass over the content, ever. Do not hand-edit `doc.html` to fix a rendering
  problem — fix `build.js`. A one-off manual patch is exactly the kind of drift this
  skill exists to prevent.
- No cross-subproject rollup. One project in, one HTML file out. "What's the state of
  everything under X" is `/rollup`'s `_index.md`, not this.
- Touches nothing outside the project folder, and nothing in git. `doc.html` is a
  local build artifact (gitignored) — regenerate it, don't hand-edit it.

## The docs site already has it
There is a docs site only when `brain.env` sets `DOCS_URL`, its address. Then
`build-docs-site.py` (run on every Stop) renders this same page for every main (not subs: their page is the team doc) into
the site; to share a project's state with a teammate, send that link, and build a local
`doc.html` only for a one-off file to attach. Without `DOCS_URL`, build a local `doc.html` to share.
The theme directory that `brain.env` names with `HTML_THEME` (its `theme.css`, and `logo.svg` or `logo.png`) styles every page, the site's index included. A change to `build.js` (renderer, `CSS`, `LOGO_HTML`) restyles the whole site too.

## Re-running
Safe and idempotent — rerunning after the vault changes overwrites `doc.html` with the
new state. The `Built <timestamp>` line in the footer is the only part expected to
differ between two runs over unchanged source files; everything above it should not.

Last, apply the rules filed under `### /doc-build` in `AGENTS.local.md` § Local rules, if there are any.

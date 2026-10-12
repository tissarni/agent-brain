---
name: ship
description: Close out a finished sub-project — write its summary.md, mark it done, refresh the parent index. Use when user says "ship [sub]", "close [sub]", "[sub] is done", "mark [sub] as shipped".
---

Arguments: a sub-project name.

Resolve it with the rule in AGENTS.md (§ Project path resolution) and confirm its
`context.md` has `kind: sub`. A main is never shipped — only its subs are.

## Why this exists
`summary.md` is the **only** thing anyone reads about this sub ever again — AGENTS.md
§ Level 4 forbids reading a `done` sub's body. Write it as the replacement for the
folder, not as a footnote to it.

## Token budget
This is the one time reading the sub's body is correct: you are closing it.
Read its `current.md` and `context.md` in full, plus ADR **filenames** in `decisions/`
— the Key decisions section of `context.md` already summarises them, so do not open
the ADR files themselves.

## Gate: the coworker doc comes first
Shipping archives the specs and reports `/team-doc` reads, so the doc is written and
reviewed **before** anything below runs. Check `<sub-folder>/<sub>-team-doc.md`:
- missing → run `/team-doc <sub>`, then stop: "Review `<sub>-team-doc.md`, then re-run /ship."
- `reviewed: no` → give its path and ask once: "Reviewed? (yes/edit)". On yes, set
  `reviewed: YYYY-MM-DD` (today) in its frontmatter and continue; on edit, stop.
- `reviewed: <date>` → continue.

The only ways past without a doc are the user saying so in the request ("ship X, no team doc"),
or `team_doc: none` already set in the sub's `context.md` (the user's earlier, durable decision).
Then write `Coworker doc: none — skipped by the user.` under `## Detail` in `summary.md`.
Never skip it on your own judgment.

## Steps

1. Read the sub's `current.md` and `context.md`. List `decisions/ADR-*.md` filenames.
2. Draft `summary.md` in the shape below — 8 of the 9 existing summaries use it exactly,
   so match it rather than improving on it.
3. Show the draft and ask once: "Ship it? (yes/edit)". One confirmation, not an interview.
4. On yes:
   - write `summary.md`
   - set `status: done` in the sub's `context.md` frontmatter, and remove `blocker:`
   - keep `summary:` accurate — it is what the parent `_index.md` displays
   - offer to move `current.md`, `specs/`, `plans/` into that sub's `_archive/` —
     `<sub>-team-doc.md` and `.html` stay in the sub folder, they are the coworker-facing files
5. Run `/rollup <main>`. **Not optional** — the parent index still shows it as active
   until you do, and `/rollup` validates exactly this: `status: done` with no `summary.md`.
6. Check whether the sub's `repo:` is a linked worktree: it is one when
   `git -C <repo> rev-parse --path-format=absolute --git-dir` differs from
   `git -C <repo> rev-parse --path-format=absolute --git-common-dir`. If it is, print
   `git -C <main checkout> worktree remove <repo>`, where the main checkout is the parent
   directory of the `--git-common-dir`. Never run it: a worktree can hold work nobody pushed.
7. Last, apply the rules filed under `### /ship` in `AGENTS.local.md` § Local rules, if there are any.

No need to log it anywhere else: `/day-log` classifies a new `summary.md` as **Shipped**,
so it lands in the day's note on its own.

## Template — match this exactly
```markdown
---
project: <sub>
kind: summary
status: done
closed: YYYY-MM-DD
tags: [summary]
---

# <sub> — what shipped

## Outcome
<one or two lines: what exists now that did not before>

## What changed
- <bullets, concrete>

## Why it still matters
<The future-you section, and the reason this file is worth writing. What breaks if
someone changes it, what downstream depends on it, what is non-obvious. Link across
mains with [[02-projects/<other-main>/context]] where a dependency crosses.>

## Decisions
- [[ADR-NNN-slug]] — one line
<or: "None beyond the initial setup note.">

## Detail
Working notes in `_archive/`. Coworker doc: `<sub>-team-doc.md`.
```

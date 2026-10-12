---
name: team-doc
description: Write a sub-project's coworker doc — one .md stating the problem, the solution, the measurements, the implementation details a teammate must know and what the release must do, and nothing else. Use when user says "team doc", "write the doc for the team", "explain [sub] to my coworkers", "coworker doc for [sub]".
---

Arguments: a sub-project name (any status).

## Why this exists
A teammate who was not there needs five things: what was wrong, what was done about it,
what it measurably changed, what will bite them if they touch it, and what the release
must do so production does not break. `/doc-build` renders
every vault file as-is, deliberation and process included; `/ship`'s `summary.md` is written
for future-me, with vault links. Neither is something you can hand to a coworker. This skill
is the curated one: judgment applied, every line earning its place.

**The line test.** Before keeping any line: *would a coworker act wrongly, or waste time,
without it?* No → cut it. A short doc is the goal, not a side effect.

## Sources
Resolve the sub with AGENTS.md § Project path resolution and confirm `kind: sub`. If its
`context.md` says `team_doc: none`, the user decided it needs none: say so and stop, unless they
asked for this doc by name.

Vault (read in full — this skill is an explicit request, so the Level 4 exception applies to
a `done` sub; for one, read `summary.md` and its `_archive/` reports, nothing else archived):
- `context.md` — Why it exists, Scope, Key decisions. Open an ADR only when Key decisions
  lacks the *why* of a decision the doc must state.
- `current.md` or `summary.md`, every `specs/*.md` that is not a brief, any loose `.md` in the
  folder that holds measurements (e.g. a bench or recon note).
- `specs/*.report.md` and `_archive/**/*.report.md` — only for numbers and for DIVERGED /
  BRIEF WAS WRONG entries that changed what shipped. Most of a report is process; skip it.

Repo (`repo:` and `branch:` from the frontmatter):
- Resolve the path: as written if it exists on this host; else `<CODE_ROOT>/<basename>`, with `CODE_ROOT` from `brain.env` (default `~/projects`);
  else no repo — say so in the final report and mark repo-dependent claims unverified.
- Read from the remote ref, never the working tree (checkouts here lag origin):
  `git -C <repo> fetch -q`, then `git show origin/<branch>:<path>`, `git grep … origin/<branch>`,
  `git log origin/<dev-or-main> --grep`. Fall back to `origin/main` if the branch is merged
  or gone. Never `cd`.
- Delegate both the report sweep and the repo reading to **one read-only `Explore` subagent**
  (pre-approved, AGENTS.md § Level 5). Give it the sub's problem statement and the list of
  implementation claims you intend to make, and ask back, compactly: every measured number
  with its conditions and method (hardware, data size, date, ref, what stood in for what,
  which clock); signatures and contracts of anything another repo calls or provides; the
  exact log lines the code emits on success and on each failure; confirmation or correction of each
  claim with `file:symbol` at the ref; PR numbers and head commits; how far the local
  checkout is behind. It returns facts, not prose.
- For the Deployment section, have the same subagent sweep the branch diff against its
  base (`git diff origin/<base>...origin/<branch>`, `--first-parent` log): env/config files
  (`.env*`, `settings*`, compose files, Helm/Ansible vars), every `os.environ`/`getenv`/
  `import.meta.env` read added or changed, migrations, dependency pins, public API
  routes/serializers/schemas, CHANGELOG or PR-body release notes. Each hit back as
  `file:line — what changed`; an empty sweep is reported as empty, explicitly.

## Output
`<sub-folder>/<sub>-team-doc.md`, in English, rendered to `<sub-folder>/<sub>-team-doc.html` (step 5). If one exists, read it first — it may be hand-edited —
keep what still holds, and show the diff in chat before overwriting.

`reviewed:` is always written as `no` — a regenerated doc is an unreviewed doc, even if the
old one carried a date. Only the user's yes (asked by `/ship`'s gate, or said directly) sets a date.

The body is for a reader with repo access and no vault: never `[[wikilinks]]`, `02-projects/`
paths, ADR numbers, the words "vault", "brief", "handoff", "run", "review", status emoji or
`verified YYYY-MM-DD` stamps. Name code by repo, path and symbol; name changes by PR and
commit.

The doc is read in layers: the top 15 lines give the outcome, each section opens with its
own summary, detail comes after. A reader who stops at any layer has the whole picture
at that depth.

```markdown
---
title: <Feature name, plain words>
summary: <one line: what it does and for whom>
kind: team-doc
project: <sub>
updated: YYYY-MM-DD
reviewed: no
artifact: <private page URL, kept across re-runs; omit until step 6 first publishes>
---

# <Feature name>

Scope: <repo(s), PR(s) with state and base, head commit; where and when measured>.

## In short
| What | Result |
|---|---|
<4–7 rows, the takeaway a reader keeps if they read nothing else: the headline numbers
in bold with their unit, where it runs, what it replaces, the one release action that
matters most. Cells are fragments, not sentences.>

## Problem
<What was wrong or missing, observed how, and who it hurt. Concrete: the symptom, the
number, the incident, each fault as one bullet. No history of how it was discovered.>

## <Contract heading, e.g. "What web-app #127 adds"> — only when the work spans repos or exposes an API
| Addition | Where | Contract |
|---|---|---|
<One row per function/endpoint/event the other side codes against: signature, who owns
what (files, retries, cleanup), what it must never do, how errors surface. This is the
table a teammate on the other repo reads; it is the one place cells may be sentences.>

## How it works
<Open with the parties (threads, services, boxes) and the one design idea that makes it
work, in two sentences — e.g. "custody moves by rename on the main thread, so the
rollover never waits on compression or the network".
Then an overview table, one row per step: When | <one column per party> | — cells of a
few words, so the whole flow reads in one glance.
Then one `### N. <step>: <what> (<party>)` subsection per row: what happens, the
invariant it keeps, how it fails and what the failure looks like (verbatim log line in
backticks, so it can be grepped). Each subsection ends with
`Code: <path> <symbol>, <symbol>`.
No steps or parties → prose, no table.>

## Decisions a reviewer might question
- **<The ruling, as a sentence.>** <Why, in one or two lines. The rejected alternative
  only when a teammate would otherwise try it, and what ruled it out (a number, a limit).>

## Measurements
<First the method, one paragraph: hardware, what stood in for what (and why the real
thing was not possible), what was timed and with which clock, the code ref measured.
Then one table per question the reader asks ("what does it cost?", "what does the user/
main loop feel?"), each with units, ranges for repeated runs, normal vs worst case.
Then "How to read these numbers": bold-led bullets — what the scenario represents vs a
real day, outliers and their cause, how the number extrapolates to production (link,
data, volume). End with "Not covered:" and the check that would cover it.
No measured number anywhere → drop the section, never write "not measured".>

## Known limits
<Bold-led bullets: what this change deliberately does not handle, and latent issues
that do not bite today — each with the condition that would make it bite and where the
fix belongs. Empty → drop the section.>

## Implementation notes
<Code caveats only, for whoever edits it next: invariants, ownership, surprising
behaviour of a dependency, repo hygiene traps. Bold-led bullets: the fact, then the
consequence. Release actions are never here — they go to Deployment.>

## Deployment
<What the person releasing it must do so production does not break. Always present.
In order of execution, bold-led bullets per target (per box type, per server, per repo),
each concrete enough to act on without asking:
- Breaking changes: API/payload/schema/contract changes, who consumes them, what they
  must change and whether that must ship first.
- Config: every env var / setting added, renamed or removed — name, where it is set
  (service, file, secret store), value or how to get it, default if unset, and what
  happens when it is missing.
- Order: migrations, cross-repo order (e.g. library release + pin bump before the app),
  services to restart or remove, feature flags and their default.
- Check after release: the one observation that proves it works (log line, endpoint, metric).
- Rollback: how to undo, and anything that cannot be undone (data migration, deleted files).
Nothing to do → one line: "No deployment action: ships with the normal release." — only
once the repo diff confirms it, never by default.>
```

## Writing rules
- **Bold the claim, then the consequence.** Every bullet leads with a bold sentence that
  stands alone, followed by why it matters in operational terms ("a box without it ships
  nothing", "the old cron deletes the new outbox tree") — never "be careful".
- **Short table cells.** A cell that needs "then" or a second clause is a subsection. The
  contract table is the only exception.
- **Every behaviour points to code** (`Code:` line or `path` `symbol` inline), every
  observable is quoted verbatim (log line, error text, endpoint path).
- **Numbers carry their conditions**: unit, input size, hardware, ranges over runs. Say
  which case is normal and which is the worst.
- **One bucket per fact.** A fact appears once, in the section a reader would look for it
  in: a release action in Deployment, a latent bug in Known limits, a code trap in
  Implementation notes. The In short table may repeat a headline, nothing else repeats.
- **Plain register.** Present tense, active voice, no adjectives that grade ("robust",
  "clean", "simple"), no "we".

## Cut, always
- How we got here: session history, dead ends nobody would retry, dates of work, who did what.
- Process: briefs, reviews, revisions, audits, agent runs, test-repair noise, test counts.
- What the diff already shows: file lists, renames, line counts.
- The parent system's architecture — one line of context at most, the team knows it.
- State that is true this week only (open PR checklists, blockers) — except the Scope line.
- Hedges. A claim the repo did not confirm is either removed or kept and listed as
  unverified in the chat report — never softened in the doc.

## Steps
1. Resolve the sub, read the vault sources above, list the claims the doc will make.
2. Run the subagent; correct the claims from its answer.
3. Write `<sub>-team-doc.md` in one pass (diff first if it existed).
4. Report in chat, briefly: the path, the ref the repo facts came from (and checkout lag),
   any claim left unverified, and sections dropped for lack of material. No repo on this
   host → say Deployment is unverified and needs the user's check. Do not paste the doc.
5. Always render it: `node .agents/skills/md-html/build.js <sub-folder>/<sub>-team-doc.md`
   (writes `<sub>-team-doc.html` next to it), then hand the user the **HTML**, not the .md — via
   SendUserFile with `display: render` when available, else its path. The user reviews the
   page; the .md stays the source. Say it is `reviewed: no` until they have read it — `/ship`
   will not archive the sub before then.
6. Always publish the HTML as a private page, when the host has an Artifact tool (Claude
   Code does; other agents skip this step and say so):
   - frontmatter has `artifact: <url>` → `read` that URL first (the tool refuses a publish
     to an artifact this conversation has not read), then publish `<sub>-team-doc.html`
     with `url: <that url>`, so the link the user already shared keeps working;
   - no `artifact:` → publish it new with `icon: doc` and the frontmatter `summary` as
     `description`, then write the returned URL into the .md frontmatter as `artifact:`.
   Give the user the link and one line: the page is private until they add people from its
   Share menu, and they should share it only once they have reviewed it.

Last, apply the rules filed under `### /team-doc` in `AGENTS.local.md` § Local rules, if there are any.

## What it does not do
- No frontmatter changes on the sub, no `/rollup`, no commit, nothing in the repo.
- No main projects — a main's coworker view is its own subs' docs.

---
name: day-log
description: Write the day's note from what actually changed in the vault. Runs unattended from the brain's timers, which pass the date; also on demand when user says "day log", "log today", "what changed today".
---

Arguments: optional date `YYYY-MM-DD`. Default: today.

## Contract
Runs unattended. **Never ask a question** — nobody is there to answer.
Everything in the note comes from files, never from memory.
**Write nothing on a day with no changes.** An empty daily note is the exact failure
this skill exists to avoid.

## Token budget
Reads: the day's changed *paths*, plus **frontmatter only** of each touched
`context.md`. Never a body. Never `_archive/`.

## Steps

### 1. Collect what changed
```
find 02-projects 03-knowledge 00-inbox -name "*.md" \
  -newermt "<date>" ! -newermt "<date> 23:59:59" -not -path "*_archive*"
```
Then drop:
- `_index.md` — `/rollup` regenerates all of them on every run. Noise, not work.
- anything under `01-daily/`, `05-weekly/`

Also check the vault's own tooling, same date window:
```
find .agents/skills AGENTS.md SKILLS.md *.sh -newermt "<date>" ! -newermt "<date> 23:59:59"
```
Never scan `.claude/skills/` — it is a generated mirror of `.agents/skills/`, so counting
it reports every change twice. A day spent on skills, the constitution or the sync scripts
is real work; without this it produces an empty note. Report it under **Vault tooling**.

Empty list → stop. Report "no vault activity on `<date>`" and write nothing.

### 2. Group by owner
Path shape decides it, per AGENTS.md § Project path resolution:
- `02-projects/<main>/subprojects/<sub>/…` → **`<sub>`** — always the most specific
- `02-projects/<main>/…` → **`<main>`**
- `03-knowledge/…`, `00-inbox/…` → ungrouped, list under Elsewhere

### 3. Read state — frontmatter only
For each touched sub or main, read the frontmatter of its `context.md` and stop at
the closing `---`. Take `status`, `summary`, `blocker`. Never open the body.

### 4. Classify each path
| Path | Reads as |
|---|---|
| `decisions/ADR-*.md` | decision |
| `summary.md` | **shipped — but only if it closed today, see below** |
| `current.md` | task moved |
| `specs/`, `plans/`, `runbook*` | planning |
| `context.md` | scope or status changed |
| anything else | note |

**A touched file is not an event.** Two gates, because a bulk edit — a restructure, a
template sweep, a find-and-replace — touches hundreds of files that nothing happened to:

- **Shipped** requires `closed: <date>` in that `summary.md` to equal the log date.
  A `summary.md` modified for any other reason shipped nothing. Without this gate a
  restructuring day reports eight things shipped that actually closed months earlier.
- **Blocked** requires `status: blocked` in the sub's `context.md`. A `blocker:` string
  on an `active` sub is standing friction, not today's news — and counting those made
  this section say 12 on a day `/rollup` said 🔴 1, from the same frontmatter.

### 4b. Cap a bulk-edit day
If more than 12 projects were touched, do not enumerate them. Write the counts, the
project names as a plain list, and one line naming the likely cause (restructure,
template sweep, mass rename). A 260-line daily note is not a daily note.
Shipped, Blocked and Decisions stay fully itemised at any size — they are already
gated above, so they stay short on their own.

On a capped day set `projects: []` and add `bulk: <cause>` to the frontmatter, then say
in the body why it is empty. Listing all of them is worse than listing none:
`/project-status` keeps the 3 most recent notes whose `projects:` names its target, so a
note claiming 44 projects becomes "recent activity" for every one of them and pushes the
real recent activity out of the window — for every project at once.

Decisions get the same scepticism: an ADR file with today's mtime may be reformatting,
not a decision. Git only separates the two once the repo has history older than the day
being logged — on the day a repo is initialised, `--diff-filter=A` reports every file as
added. When you cannot tell, say how many were touched and name only the unambiguous ones.

### 5. Write `01-daily/<date>.md`
```markdown
---
date: YYYY-MM-DD
tags: [daily]
projects: [<names touched, most specific level>]
decisions: [<ADR filenames written today, slug only>]
generated: day-log
---

# YYYY-MM-DD

## Shipped
- [[02-projects/<main>/subprojects/<sub>/summary|<sub>]] — <summary>

## Moved
### [[02-projects/<main>/subprojects/<sub>/context|<sub>]] 🟢
<summary from frontmatter>
- decision · [[ADR-NNN-<slug>]]
- planning · plans/YYYY-MM-DD-<slug>.md

## Blocked
- <sub> — <blocker from frontmatter>

## Vault tooling
- <what changed in .agents/skills/, AGENTS.md, SKILLS.md or the scripts>

## Elsewhere
- 03-knowledge/tools/<note>.md

---
## Notes
<!-- Yours. day-log never writes below this line. -->
```
Omit any section that would be empty. Legend: 🟢 active · 🔴 blocked · 🟡 impl-done · ⚪ done · ⏸ paused.

`decisions:` holds ADR **filename slugs** (`ADR-004-retry-backoff-policy`), not
`ADR-NNN` — that is what makes the `[[wikilink]]` resolve.

### 5b. One follow-on
- **Inbox.** If `00-inbox/` holds triageable `.md` files, add an `## Inbox` line naming
  them and their age. **Report only — never move, rename or file anything.**
  This run is unattended: there is nobody to confirm a move with, and silently filing
  someone's notes is worse than leaving them.
  Empty inbox → omit the section entirely.

### 6. Rerun safely
If the file already exists, replace everything **above** the `## Notes` marker and
leave everything below it untouched. Anything hand-written survives a rerun.

## Unattended runs — the date is passed, then backfill
The scheduled run passes the date (the timers run in the evening, and the runner picks the
day the run is about), so it needs no guess. With no argument, the date is today — also what
a person asking "what changed today" means.

Then **backfill**, on every unattended run, whether or not a date is given: for each of the
previous 7 days, if that date has activity by the step-1 rule but no `01-daily/<date>.md`,
run for that date too.

This exists because a timer missed while the machine slept or was off runs at the next
start, and the days in between would otherwise be lost. Report one line per date: written,
or skipped.

Last, apply the rules filed under `### /day-log` in `AGENTS.local.md` § Local rules, if there are any.

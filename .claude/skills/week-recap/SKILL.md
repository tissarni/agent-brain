---
name: week-recap
description: Write one recap note for the week that just ended, from that week's daily notes. Runs unattended on a schedule; also on demand when user says "week recap", "weekly", "what happened last week".
---

Arguments: optional ISO week `YYYY-WNN`.

Default: **the most recent Mon→Sun week that has fully ended.** Never the week in progress
— a week is only complete once its Sunday is over, and a recap written before then silently
omits the last day. Run on Monday, that is the seven days just finished.

## Contract
Runs unattended. **Never ask a question.**
**Write nothing if the week has no daily notes.** No empty weeklies.

## Token budget
Reads: that week's `01-daily/*.md` in full — they are short and already summaries —
plus **one** `_index.md` per touched main. Never a project body, never an ADR file,
never `_archive/`.

## Steps

1. Resolve the Mon→Sun range. Skip missing dates silently; none exist → stop.
2. Read each daily note. From frontmatter take `projects` and `decisions`; from the
   body take the Shipped / Moved / Blocked entries.
   **Read the `## Notes` section too.** Anything hand-written there is the part no
   generator could have produced, so it carries the most signal in the file.
3. One read per touched main: `02-projects/<main>/_index.md`. That single file is the
   **end state** of every sub in the cluster (AGENTS.md § Level 1). This is what turns
   "what moved" into "where it landed" — do not reconstruct it from sub-project files.
4. List the mains in `02-projects/` with no activity all week. Absence is information.
5. Run the reconciler once — read-only, no questions, safe unattended, from the vault
   root:
   ```
   bash reconcile-repos.sh < <repo-list>
   ```
   Report disagreements between `blocker:`/`branch:` and the repos under `## Vault drift`.
   **Report only — never edit frontmatter here.** The user fixes drift by hand,
   because "0 unpushed" does not distinguish shipped from abandoned. If the reconciler
   cannot run, omit the section rather than guessing.
6. Write `05-weekly/<YYYY-WNN>.md`.

Last, apply the rules filed under `### /week-recap` in `AGENTS.local.md` § Local rules, if there are any.

## Unattended runs — backfill
Called with no argument, do the week that just ended **and then backfill**: for each of
the previous 4 weeks, if it has daily notes but no `05-weekly/<YYYY-WNN>.md`, write it too.

Without this a week is lost permanently, and it has already happened once: W30 ran, found
no daily notes, correctly wrote nothing — and `/day-log`'s own backfill then created
`2026-07-23.md` and `2026-07-24.md`, both inside W30. The data arrived after the only run
that would ever have read it. A missed week must stay recoverable.

## Output
```markdown
---
week: YYYY-WNN
range: YYYY-MM-DD → YYYY-MM-DD
tags: [weekly]
projects: [<all names touched>]
decisions: [<ADR slugs written this week>]
generated: week-recap
---

# Week YYYY-WNN

## The week in one line
<one sentence — what this week was actually about>

## Shipped
- [[02-projects/<main>/subprojects/<sub>/summary|<sub>]] — <summary>

## By main
### [[02-projects/<main>/_index|<main>]] — 🟢N 🔴N 🟡N ⚪N
**<sub>** 🟢 — <where it landed, from _index.md>
- <what moved during the week, from the dailies>

## Decisions
- [[ADR-NNN-<slug>]] (<sub>) — <one line>

## Still blocked
- <sub> — <blocker>

## Vault drift
- <sub> — vault says "<blocker>", repo shows <what git actually reports> → fix by hand

## Quiet this week
<main> · <main> · <main>

---
## Notes
<!-- Yours. week-recap never writes below this line. -->
```
Omit any section that would be empty. Same rerun rule as `/day-log`: replace above the
`## Notes` marker, never below it.

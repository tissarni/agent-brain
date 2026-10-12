---
name: supersede
description: Mark an ADR replaced by a newer decision, in both files and in context.md. Use when user says "supersede", "that ADR is obsolete", "we changed our mind about", "this replaces ADR-NNN".
---

Arguments: the ADR being replaced, and the decision replacing it.

## Why this exists
**The convention already exists and is correct**: the old record carries
`status: superseded` + `superseded_by:` naming the new one, and the project's
`## Key decisions` marks the old line *superseded* and the new one **current**. Copy that.
Do not invent a new shape.

This skill is not filling a gap. It exists so the same thing happens every time without
being remembered — done once by hand in four months means the next reversal probably
goes unmarked, and an unmarked reversal is invisible to `/project-status` forever.

## Steps

1. Resolve the project per AGENTS.md § Project path resolution. Find the old ADR by number.
2. Read the old ADR — this is one of the few times reading an ADR body is right, because
   you have to say *what* was reversed, not just that something was.
3. In the **old** ADR, set the frontmatter — all 93 ADRs use frontmatter, never a
   `Status:` body line or a `**Status:**` bold line:
   ```yaml
   status: superseded
   superseded_by: ADR-NNN
   ```
   `status: superseded` alone is not enough — it says the decision is dead without saying
   what replaced it, which leaves the reader no way forward.
   Leave the rest of the body untouched. A superseded ADR is a record of what was believed
   at the time; rewriting it destroys the only reason to keep it.
4. In the **new** ADR, add under `## Context`:
   `Supersedes [[ADR-NNN-slug]] — <one line on what changed and why>.`
   If the new ADR does not exist yet, write it first with `/adr` or `/decision-needed`.
5. In that project's `## Key decisions`, mark the old line and the new one — this exact shape:
   ```
   - [[ADR-001-old-slug]] — *superseded* — <what it used to say>
   - [[ADR-002-new-slug]] — **current** — <what it says now>
   ```
   This is the load-bearing step. `/project-status` reads that section and never opens the
   ADRs, so an unmarked line there means the reversal is invisible to every future session.
6. If the reversal changes the sub's `status`/`summary`/`blocker`, update it and run
   `/rollup <main>`.

Last, apply the rules filed under `### /supersede` in `AGENTS.local.md` § Local rules, if there are any.

## Status vocabulary — frontmatter, lowercase
`accepted` · `proposed` · `draft` · `rejected` · `superseded` (+ `superseded_by:`).
Stay inside this set. A one-off value like `investigated-deferred` reads fine to a human
and is invisible to every filter; put that nuance in the body instead.

Do not delete a superseded ADR, and do not renumber around it.

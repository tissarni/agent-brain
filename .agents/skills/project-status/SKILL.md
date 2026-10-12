---
name: project-status
description: Load context for a project before a work session. Use when user says "status of [project]", "brief me on [project]", "what's the state of [project]".
---

Arguments: a main or sub project name. Resolve it with the rule in `AGENTS.md`
(§ Project path resolution). If the name is ambiguous, say so and pick the main.

## Token budget
Never read `decisions/`, `specs/`, `plans/` or `_archive/` — `context.md`'s
**Key decisions** section already summarises them. Only open an ADR if the user
explicitly asks for its full reasoning.
Never read the body of a `done` sub — read its `summary.md` if anything.

## If the target is a MAIN
1. Read `02-projects/<main>/_index.md` — **this single file is the state of every sub**.
2. Read `02-projects/<main>/context.md`.
3. Read `02-projects/<main>/current.md` if it exists.
4. Do **not** open any sub-project file. The index is the answer.

Output:
```
## <main> — main project
[one-paragraph what-this-is + stack from context.md]

### Sub-projects (N active · N blocked · N impl-done · N done)
[the _index.md Active and Paused tables, verbatim-ish; collapse Done to a count + names]

### Open risks
[Open risks section from context.md]

### Main-level task
[current.md, or "none — all work is in sub-projects"]
```

## If the target is a SUB
1. Read `02-projects/<main>/subprojects/<sub>/current.md` — the live task.
2. Read that sub's `context.md`.
3. Read the parent's `context.md` **Stack + Constraints sections only** — skip if the
   sub's own context already answers the question at hand.
4. Do not read sibling sub-projects. If `related:` matters, read only the named
   sub's frontmatter.

Output:
```
## <sub> — sub-project of <main>

### Current task
[current.md]

### Scope + key decisions
[from the sub's context.md — do not re-read ADRs]

### Inherited from <main>
[only the parent constraints that actually bind this work]

### Blocker
[frontmatter blocker:, or "none"]
```

## Daily note pass (both cases)
1. List the last 14 daily-note filenames, newest first.
2. Read **frontmatter only**; keep the 3 most recent whose `projects:` includes the
   target — or, for a main, includes the main *or any of its subs*.
3. Read the bodies of those 3 only.
4. Append a `### Recent activity` section.

## Finally
If `_index.md` contradicts what you read in a sub's `current.md`, say so and offer
to run `/rollup <main>`. A stale index is worse than no index.

Print to terminal only. Do not write to the vault.

Last, apply the rules filed under `### /project-status` in `AGENTS.local.md` § Local rules, if there are any.

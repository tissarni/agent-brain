---
name: handoff-split
description: Cut an oversized implementation brief into phases that each leave a working system. Use when user says "split the brief", "this brief is too big", "phase this", or when /handoff produces a brief over ~400 lines.
---

Arguments: sub-project name, or a path to a brief.

A brief bigger than one session's room does not fail cleanly. It gets truncated by
context rather than by choice, and stops wherever the window ran out — which is
usually halfway through a change that only works once both halves land.

## 1. Decide whether to split at all

Split if any hold:

- over ~400 lines, or over ~6 top-level tasks in §7
- it touches two sides that must move together *more than once* — several backend
  endpoints each paired with a frontend rewiring
- it contains a verification phase whose result could change what the later tasks are

Do **not** split merely because it is long. A 300-line brief with one coherent task is
fine, and cutting it invents a handoff that costs more than it saves. Say so and stop.

## 2. Find the cuts

The rule is not size, it is: **stopping after part N leaves a system that works.**

Walk §7 and mark each task boundary as a candidate. A boundary is real when, with
everything before it done and nothing after it, the app boots, the tests pass, and
nothing is half-migrated. A route moved server-side but not yet called by the frontend
is *not* a boundary — that is the failure this rule exists to prevent.

Where no such boundary exists across a stretch of tasks, those tasks are one part, even
if that part is large. Say that in the part's own size warning rather than cutting
through the middle.

Verification-first: if the brief contains checks whose outcome could change later
tasks, they belong at the **front of the part that depends on them**, not in a part of
their own. Verifying facts in one run that the next run then depends on is ceremony —
and it has already been collapsed by hand once in this vault, for the same reason.

## 3. Write the parts

`YYYY-MM-DD-brief-N-<slug>.md`, one per part, each standing completely alone:

```yaml
---
updated: YYYY-MM-DD
tags: [spec, brief]
handoff: draft
revision: YYYY-MM-DD-r1
brief: N
of: M
repo: <repo>
branch: <branch>
---
```

Each part carries **every** mandated section, not a subset. In particular:

- **§2 State** — written as it will be *when this part starts*, i.e. assuming parts
  1..N-1 landed. Describe that state in full. Do not name the earlier briefs: the
  runner is a fresh session and has never seen them.
- **§3 Settled** — repeat what this part needs. Duplication across parts is correct;
  each part is read by a session that has read nothing else.
- **§4 Done when** — this part's own machine-checkable criterion. "Part 2 is done when
  part 3 passes" is not one.
- **§7** — ends with what the next part will pick up, described as work, never as a
  file reference.

Every part's revision counter is independent. Part 3 can reach `r4` while part 1 is
still `r1`.

## 4. Sweep and report

Run §5b of `/handoff`, then the check, on **every** part, from the vault root — splitting
is the single most likely moment to introduce a cross-brief reference:

```
brief-check <each part>
```

Every `FAIL` line is a defect: fix it by inlining, as `/handoff` §5 says. A `WARN` line
is a lead. A later part names files an earlier part creates, and those `WARN` lines are
expected. A later part's DOES NOT HOLD rows about what an earlier part creates are
expected too, like its `WARN` lines.

Then print the part list with, for each: its goal in one line, its Done-when, and
whether stopping there leaves a working system. If any part does not, say so
explicitly — an honest warning beats a cut that pretends to be safe.

Only part 1 gets a launch command. Print it as `/handoff` does, with the review
wrapper. The rest wait: each part's §2 is written against a state that does not exist
yet, and a part launched early is a brief describing a world that has not happened.

Last, apply the rules filed under `### /handoff-split` in `AGENTS.local.md` § Local rules, if there are any.

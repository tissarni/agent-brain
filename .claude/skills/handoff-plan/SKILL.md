---
name: handoff-plan
description: Brainstorm a sub-project's work into phases of briefs, write the plan file, and draft every brief of the current phase so handoff-orchestrate can run them unattended. Use when user says "plan the phases", "handoff-plan [sub]", "orchestrate this feature", "write the next phase", "phase 1 closed, what next".
---

Arguments: sub-project name, plus an optional note (backend, model, what the plan should
cover, or "next phase").

Writes **one plan** and **every brief of one phase**. A phase is the longest run of
briefs that can all be written today and executed one after the other with no human
decision between them. The orchestrator crosses each brief's review gate by rule and
stops only on a major finding; the human boundary is the phase boundary, and this skill
is where that boundary gets drawn. Nothing here launches anything.

## 1. Resolve and gate

Resolve the project with AGENTS.md § Project path resolution. A plan belongs to a
**sub**; if given a main, say so and ask which sub.

Refuse, before reading anything expensive, if:

- the sub's `context.md` has no `## Key decisions` **and** `specs/` is empty — a phase of
  briefs written from an unsettled design hands the driver your open questions as if
  they were answers, several times over. Offer `/decision-needed` first.
- `repo:` or `branch:` is missing or `-` in the sub's frontmatter.
- a plan for this sub is `orchestration: running`, `paused` or `broken` — it owns the repo;
  a second plan would race it. Say which one and offer `/handoff-orchestrate status`.
- a brief for this sub is `handoff: running` — same reason, one level down.

**Which form.** `specs/*-plan-*.md` also matches a plan's own `.status.md` file and any
debrief note whose name happens to carry `-plan-`; only a real plan has an
`orchestration:` key, so list this sub's plans with:

```
/usr/bin/grep -l '^orchestration:' 02-projects/<main>/subprojects/<sub>/specs/*-plan-*.md
```

No match means the sub has no plan:

- none, or all `done` → **new plan**, §2–§6.
- one with `orchestration: phase-done` → **next phase**, §7, then §4–§6 for that phase.
- one with `broken` → not this skill. The status file names the break; the human fixes
  it and runs `/handoff-orchestrate resume`. Say so.

## 2. Read, cheapest first

`current.md`, then `context.md` `## Key decisions`. Then the one spec the plan is
implementing, if the user named it or `current.md` points at one — this is the one read
that pays for itself here, because phase boundaries come from the design's dependency
structure and a summary line does not show that.

Then verify the perishable claims once, for the whole plan, the way `/handoff` §3 does:

```bash
git -C <repo> status -sb && git -C <repo> log --oneline -8 && git -C <repo> branch --show-current && git -C <repo> rev-list --count origin/<branch>..HEAD
```

The plan's branch is a feature branch (never `dev` or `main` themselves — the
orchestrator refuses those). **It does not have to exist yet, and the user is never
asked to create it or to open a PR**: `handoff-orchestrate start` cuts it from
`origin/<base>` and pushes it when it is missing, checks it out when the repo is on
another branch, and the run opens the draft PR after its first commit with the driver as
backstop. If the branch exists, origin must be an ancestor: local may be
ahead, never behind. The dirty set is the baseline the driver will hold every brief to. A dirty set the vault does not know about
is a finding to tell the user now, not a fact to write into five §2 paragraphs.

## 3. Brainstorm the phases — with the user, briefly

Lay out the work as an ordered list of candidate briefs, each with:

- one line of goal (what lands, in words a `git log` would confirm)
- its **precondition**: the repo facts its §2 *State* and §3 *Settled* would have to
  state — names, counts, shapes, files that exist
- whether that precondition is **known today** or **produced by an earlier brief's run**

Then apply the one test, from the first brief onward: *can this brief's §2 be written
honestly right now, assuming every earlier brief in the list landed whole?* `/handoff-split`
already writes part N's §2 "as it will be when this part starts", and that is exactly the
bar. The first brief that fails it starts phase 2, and the fact it was missing is that
phase's `why-cut-here`.

Rules of thumb that decide most cases:

- A brief that reads a *name* the previous run chooses (a column, a route, a component)
  can still be in the same phase if the plan **fixes the name now** and the earlier brief
  is told to use it. Preferring a fixed name over a cut is usually right: the deferred
  review will catch a drift anyway.
- A brief that depends on a *measurement* the previous run produces (a count, a timing,
  whether a migration is reversible) cannot. Cut there.
- A brief whose Done-when needs the human (a visual gate, a dev-stack pass, a prod
  deploy) ends the phase. Put it last in its phase and say the phase's finish is that
  human check, not the orchestrator's `phase-done`.
- Two or three briefs per phase is normal. Six is a plan that should be looked at again.
  One is fine when the second genuinely depends on it.

Show the user the list with the cut marked and one line of why. Ask **once**: is the cut
right, and which backend. Offer `brain.env`'s `DEFAULT_BACKEND` (one key, never sourced;
`claude` when absent) as the default answer, but the backend is never inferred — the user
names it, the same way `--backend` is always spelled out on a launch command. Model stays empty unless they name
one, because a plan-level model overrides every stage of every brief.

## 4. Write the plan file

Path: `02-projects/<main>/subprojects/<sub>/specs/YYYY-MM-DD-plan-<slug>.md`, from
`02-projects/_templates/plan.md`. Fill every field; stamp resolved values, never a
reference to the defaults file:

- `backend:` what the user said. `model:` `''` unless they named one.
- `branch:` the sub's `branch:`. A phase that must work elsewhere gets a `branch:` under
  its own `phases[]` entry, with the reason on the line.
- `base:` `''` unless the PR must land somewhere other than `dev` (or `main` on a repo
  with no `dev`). The run pushes every commit and opens one draft PR to the base; the
  driver backstops both after each brief.
- `setup:` `''` unless the repo needs an install in a fresh checkout: one command, e.g.
  `(cd frontend && npm ci)`. §4b runs it, once, only when it makes a worktree.
- `budgets:` from `02-projects/_templates/handoff-defaults.yml` `orchestration.budgets`,
  one small read. Raise `run:` only when a brief's §7 is honestly long; say so in the log.
- `notify:` `brain.env`'s `NOTIFY` (one key, never sourced) if `~/.config/handoff/notify.env`
  exists and the key is set, else `''` and
  a line telling the user what that costs (no message on a break).
- `phases:` every phase you can name, in order. Only the current phase has `briefs:`
  filled; every later phase has `briefs: []`, a `name`, and a `why-cut-here` naming the
  fact its first brief waits for. A later phase with no `why-cut-here` is a phase nobody
  can explain.

Body: Goal (one paragraph, with the whole plan's decidable done), the Phases table, the
Run block with the real plan path and backend, and one dated Log line.

## 4b. The checkout — a worktree only when another plan holds it

`start` refuses a plan whose checkout another running, paused or broken plan holds,
because two plans on one checkout move each other's branch. Settle it here, before §5
measures anything.

1. List the plans:
   `/usr/bin/grep -l '^orchestration:' 02-projects/*/subprojects/*/specs/*-plan-*.md`.
   Drop this plan and every one at `orchestration: done`. A plan at `phase-done` stays on
   purpose: its checkout is still in use between phases, so a new plan on it gets a
   worktree. For each plan left, compare `readlink -f` of its **first brief's** `repo:`
   (what the engine locks) with `readlink -f` of this sub's `context.md` `repo:`. Both must
   be non-empty: a `/home/<another user>/…` path gives an empty string, which is never a match. Count the
   checkout as held, too, when it is the one the kit runs from: when
   `git -C "$(dirname "$(readlink -f "$(command -v handoff-orchestrate)")")" rev-parse --show-toplevel`
   prints the same path as `git -C <repo> rev-parse --show-toplevel`, `start` refuses the
   plan with `preflight:kit`, so it needs the worktree of step 3 even when no other plan
   targets it.
2. **No match:** keep the sub's `repo:`. Its installed dependencies and dev-stack paths
   keep working, and most plans end here.
3. **A match:** the checkout is held. Make a sibling worktree. It sits next to the repo
   and is named after the repo plus `-<sub>`, with a leading `<repo basename, lowercased>-`
   dropped from the sub. So `~/projects/WebApp` with `webapp-login-timeout` gives
   `~/projects/WebApp-login-timeout`.
   - Run
     `git -C <repo> fetch -q origin && git -C <repo> worktree add --detach <sibling> origin/<base>`.
     Reuse an existing sibling only when no plan left in step 1 points at it, and skip the
     `worktree add` for it. When the sibling exists and a plan left in step 1 points at it,
     stop and ask the operator for another name.
   - With a `setup:`, run it there once:
     `set -o pipefail; (cd <sibling> && <setup>) 2>&1 | tail -n 40`. If it fails, stop
     before writing any brief, show the tail, and leave the worktree for the retry.
   - Set the sub's `repo:` to the sibling. `/handoff` reads that field, so §5 measures
     each brief's §2 in the tree it will run in.
4. Say which case applied in the plan's Log line.

## 5. Write the briefs of the current phase

For each brief of the phase, in order, run `/handoff <sub>` with a note that says: which
plan and phase it belongs to, its one-line goal from §3, and *write §2 as the repo will be
when this brief starts, assuming the earlier briefs of the phase landed whole; the plan
fixes these names: …*. `/handoff` resolves the session blocks, numbers the file one past
the highest existing brief, sweeps for cross-references and sets `handoff: draft`. Keep
its output; do **not** print its launch commands — the plan's Run block replaces them.

Two things `/handoff` cannot know, so check them yourself:

- **The stacked §2.** Brief k's §2 describes the tree after brief k-1, not today's. Read
  each §2 once, in order, and make sure the counts and names it states are the ones the
  previous brief's §4 *Done when* promises. A §2 written from today's tree is the most
  common defect here and the deferred review will flag every line of it as `WRONG`.
- **No brief names another.** The self-containment sweep bans it, and the plan is the
  only place the order lives. If a brief needs something an earlier one produces, it
  states the fact, not the file.

Then fill `phases[<current>].briefs` with the file names, in order, and run the check
on all of them, from the vault root:

```bash
brief-check <each brief>
```

Every `FAIL` line is a defect. Do not report the phase as written while one remains.

When a brief's repo may be public, run `./publish-guard.sh guarded <the repo>` from the
brain root. On exit 0 (guarded, so public), check the plan and every brief of the phase
in one call: `./publish-guard.sh files <plan> <each brief>`. Treat each hit as a `FAIL`:
reword until the word is gone, and never quote it. The plan is in the call because its
file name becomes a PR's slug, and the gate checks names too. If `files` exits 2, the
check did not run: fix the setup it names, and never treat it as a pass. Exit 1 from
`guarded`: nothing more to do. Exit 2: the repo is not on this host, say so.

A later brief's `WARN` lines about files and branches an earlier brief of the phase
creates are expected: check each against that brief's §4 instead.

## 6. Hand over

Set `orchestration: planned`, `phase:` to the phase just written, and print:

1. the phase table — brief, goal, Done-when in one line each, and the cut reason;
2. the one command the user runs next, as a **`bash`-tagged block**:

```bash
handoff-orchestrate start <plan path relative to vault> --backend <backend>
```

`/handoff-orchestrate start` runs pre-flight, installs the watchdog and prints the same
command.

Do not run it. Starting a phase is the user's decision; this skill's output is the plan
and its briefs.

Last, apply the rules filed under `### /handoff-plan` in `AGENTS.local.md` § Local rules, if there are any.

## 7. Next phase (`orchestration: phase-done`)

The previous phase's run produced the facts the cut was waiting for. Read, in this order
and nothing more:

1. `<plan>.status.md` — the **phase summary** at its end: briefs closed, every `DIVERGED`
   and `BRIEF WAS WRONG` line, ADR drafts the debriefs wrote, `PAIN POINTS`, the branch
   head. This is the input; it exists so you do not have to read the reports.
2. The plan's `why-cut-here` for the phase about to be written — the question the summary
   should answer. If it does not, the summary's `NOT DONE` or `BRIEF WAS WRONG` lines
   usually say why, and that is a finding for the user before any brief is written.
3. Each ADR draft the summary lists: a draft is a decision nobody made. Offer
   `/decision-needed` or `/adr` for each **before** writing briefs that depend on it, or
   the next phase silently ratifies it.

Then §3 again for the remaining phases (the cut may move now that the facts are in).
Then §4 to update the plan — `phase:` bumped, the finished phase `status: done`, the new
phase's `briefs:` filled, `orchestration: planned`, a dated Log line naming what the
summary changed, §4b for the checkout, and §5–§6 for the new briefs. The old phase's briefs stay `closed` and
are never edited.

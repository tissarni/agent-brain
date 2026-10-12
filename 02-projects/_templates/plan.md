---
updated: YYYY-MM-DD
tags: [spec, plan]
project: <sub>
orchestration: planned          # planned -> running -> paused -> broken -> phase-done -> done
backend: <claude|hermes|devin>  # forwarded to every stage as --backend; never auto-detected
model: ''                       # '' = each stage's own default (brief block / hermes profile /
                                # devin account default). Set only to override every stage.
phase: 1                        # the phase being run, or the next to run
branch: <from the sub, or feat/<slug>>   # feature branch cut from base; every commit of every phase
                                #   is pushed here as committed; one draft PR for the plan
base: ''                        # PR target: '' = dev when origin has it, else main. Never the plan branch.
setup: ''                       # run once in a fresh worktree of the repo, e.g. (cd frontend && npm ci); '' = nothing to install
budgets:                        # minutes, from handoff-defaults.yml `orchestration:`; edit per plan
  review: 45
  revise: 30
  run: 240
  close: 30
  debrief: 30
  phase: 1440
  heartbeat: 20                 # no transcript movement for this long = stalled
notify: ''                      # '' = status file only
phases:
  - name: <what phase 1 delivers, three to six words>
    briefs: [YYYY-MM-DD-brief-N-<slug>.md, YYYY-MM-DD-brief-N+1-<slug>.md]
    status: pending             # pending | running | done | broken
    # branch: feat/<other>      # optional per-phase override of the plan branch
  - name: <what phase 2 delivers>
    briefs: []                  # written by /handoff-plan after phase 1 closes
    status: pending
    why-cut-here: <the fact a phase-2 brief's §2 or §3 needs, that only phase 1's run produces>
---

# Plan — <slug>

> Sub: [[02-projects/<main>/subprojects/<sub>/context]] · briefs live beside this file in `specs/`.
> Runtime state is not here: `<this file>.status.md` (first line is the verdict) and
> `<this file>.events.log`, both written by `handoff-orchestrate.sh`.

## Goal

<One paragraph: what the whole plan delivers when its last phase closes, and the
"done" a command can decide for the whole thing.>

## Phases

| # | Delivers | Briefs | Boundary after it |
|---|---|---|---|
| 1 | <name> | N, N+1 | <why-cut-here, one line> |
| 2 | <name> | written later | <or "last phase"> |

Each brief's §2 is written as the repo will be when that brief starts, assuming every
earlier brief in the plan landed whole. A phase ends at the first brief whose §2 or §3
cannot be written that way today.

## Run

```bash
handoff-orchestrate start <plan path relative to vault> --backend <backend>
```

`/handoff-orchestrate start` prints that after pre-flight and installs the watchdog.
Nothing here is launched by hand during a phase: the lock file beside the plan is the
signal that a driver is alive, and `handoff-plan.lock` in the checkout's git dir names the plan
that holds the checkout.

## Log

- YYYY-MM-DD — plan written; phase 1 briefs N..N+1 drafted; cut because <reason>.

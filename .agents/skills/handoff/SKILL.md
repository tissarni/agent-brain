---
name: handoff
description: Turn a sub-project's spec and decisions into a self-contained implementation brief for a fresh repo session. Use when user says "write the brief", "handoff [sub]", "brief for [sub]", "ready to implement", "hand this to an agent".
---

Arguments: sub-project name, plus an optional note about what this brief should cover.

Writes **one brief**: a document a Claude Code session rooted in the repo can execute
knowing nothing else. It is the only channel between this vault and that run.

## 1. Resolve and gate

Resolve the project with AGENTS.md § Project path resolution. A brief belongs to a
**sub**; if given a main, say so and ask which sub.

Then refuse, before reading anything expensive, if:

- the sub's `context.md` has no `## Key decisions` **and** `specs/` is empty — there is
  no settled design to hand over, and a brief written from an unsettled one hands the
  runner your open questions as if they were answers. Offer `/decision-needed` instead.
- `repo:` or `branch:` is missing or `-` in the sub's frontmatter — the brief cannot
  name a working directory.
- a brief for this sub already has `handoff: running`. A second brief against a live
  run collides with it. Say which one.

## 2. Read, cheapest first

`current.md`, then `context.md` — the `## Key decisions` summaries are usually enough.

Open ADR bodies **only** for a decision this brief must inline, and only that ADR.
This is the one place the vault's read rules bend, and the reason is specific: §3 and
§6 of a brief must carry the ruling and its one-line why in full, and a summary line
is not enough to write those from. Read the ADR, inline the ruling, drop the number.

## 3. Verify the perishable claims before writing them

§2 of a brief states what exists in the repo right now. Written from vault memory it
is wrong often enough to send a run down a dead path on turn one. Check it:

```
git -C <repo> status -sb && git -C <repo> log --oneline -8 && git -C <repo> branch --show-current
```

Never a bare `cd` into the repo: a vault session's working directory persists between
tool calls, and it would leave every later relative path pointing into the repo.

If the tree is dirty in ways the vault does not know about, **fix the brief to match
reality** and tell the user what disagreed. A branch that does not exist yet is not a
disagreement: under a plan the orchestrator creates it from the base at start, and a
brief launched by hand has the run create it (`git checkout -b <branch> origin/<base>`)
as its first step — write §2 as "branch `<branch>`, cut from `<base>` at `<sha>`", and
never ask the user to create it or to open the PR. Do
not write the vault's version and hope. If the repo is not on this host, say so and mark
§2 explicitly as unverified — never silently.

## 4. Write the brief

Path: `02-projects/<main>/subprojects/<sub>/specs/YYYY-MM-DD-brief-N-<slug>.md`,
where N is one past the highest existing brief number for this sub.

```yaml
---
updated: YYYY-MM-DD
tags: [spec, brief]
handoff: draft
revision: YYYY-MM-DD-r1
repo: <from sub frontmatter>
branch: <from sub frontmatter>
review-session:
  model: opus
  effort: medium
  permission-mode: acceptEdits
  disallowed-tools: Edit,Write,NotebookEdit
run-session:
  model: sonnet
  effort: medium
  permission-mode: acceptEdits
---
```

Resolve those two blocks from `02-projects/_templates/handoff-defaults.yml` — one
small read — applying, first hit wins: what the user said when invoking this skill
("handoff login-timeout, xhigh effort"), then the `per-main:` override for this
brief's main, then `defaults:`. Stamp the **resolved** values, never a reference to
the defaults file: the brief has to record what its run was actually given, or a
report six weeks later cannot be read against the settings that produced it.

If the user names a model or effort, say which layer you took each value from. A
silently-inherited `per-main` override is the one that surprises people.

Then the body, in this order. Every section earns its place; none is optional, and a
section with nothing to say says that in one line rather than being dropped.

**§0 Session preamble.** At most 12 non-blank lines of repo facts, nothing else — the
launcher prepends its own standing rules (push every commit, one draft PR, the
trailers, no planning `.md`, no background waits, quiet checks, read each file once,
finish with `/handoff-close`) to every run prompt, so §0 repeats none of them. Say:
the working directory; the branch and how it gets there — under a plan, *you are on
`<branch>`*, already cut from `<base>`; by hand, *first step: `git checkout -b <branch>
origin/<base>`*; the PR base `<base>`; *read `AGENTS.md` first, in full*; which hooks
are active and that they are not to be worked around; the check commands (§4); and any
secret hazard — a file never to read, a command that loads credentials — or the word
`none`.

**§0b Revision echo.** `⚠ Echo the exact string <revision> back in your first reply.`
Say why in one line: briefs get corrected, and a copy pasted from an older snapshot
has already sent a run down a path that was fixed days earlier.

**§1 Why this exists.** The problem in prose. If there was an incident, tell it —
including the failure mode and how it presented. A run that does not know the stakes
optimises the wrong axis.

**§2 State — what already exists.** From step 3, dated. Branch, working tree, the
files already touched and what each does, the open PR.

**§3 Settled — do not re-explore, do not re-measure.** Findings already paid for, with
their numbers and the mechanism behind them. This is the highest-value section in the
document: without it a fresh agent spends its run re-deriving what you already bought.

**§4 Goal, and Done when.** At least one criterion a command can decide. Apply the
disagreement test: if two people could argue about whether it is met, it is
underspecified. Then its second half: **if the run cannot decide it from inside the
repo, it is not a Done-when — it is a §11 human check.** A visual pass on the dev
stack, "does 160px feel right", anything needing credentials or hardware the run does
not have: never here. Every such item left in §4 comes back as a `NOT DONE` line the
orchestrator reads as a failed run.

Write every check command quiet: `set -o pipefail; <command> 2>&1 | tail -n 40`, which
keeps the exit code and the last 40 lines. Run vitest with `--reporter=dot`. A criterion
that names an output line names one inside those 40, or the run cannot see it either.

Time every check command before you write it in, and state its measured seconds beside it.
Each one must finish well inside the 600 s Bash timeout on its own, and the run and the
close stage each run them one per call, so never write two long checks as a single chained
command. A check that cannot fit under 600 s is split or narrowed, not left to run long.

The close stage does not choose what to run: before its session, the launcher re-runs
every §4 command it can read (`brief-check --done-when <brief>` lists them) and hands
the exit codes and output to the close. It reads a numbered item's code span, or fenced
`bash` block, that opens with a command and is followed by its verdict — `exits 0`,
`prints nothing`, `prints <literal>`, `→ …`. An item with no such command, a command
holding a `<placeholder>` or `…`, one that writes to git or the network, or a grep whose
file is named only in the prose, is a judged item: the close checks it by hand, which is
the step that used to fail. Write the command whole, file and all.

**§5 Step 0 — read before you write anything.** Name the exact files to read end to
end, what to extract from each, and close with: *where this brief disagrees with what
you find, the code is authoritative — adapt, and say so in the PR description.*

**§6 Constraints / must-not.** The design requirements a working implementation can
still violate. Each one gets its *why* — the why is what stops it being re-litigated
by a runner who thinks the rejected option looks cleaner.

**§7 Tasks.** Ordered so that stopping early leaves a working system. Say that
explicitly: *if you run out of room, stop at a section boundary and say where.*

The last task is always **sync, push, update the PR** — never left as a §11 human check:
bring the branch level with its base by `git merge origin/<base>` (not a rebase: the
run may not force-push), resolve what the brief names as expected conflicts, re-run the
§4 commands, `git push`, then update the draft PR's description — or, if no PR is open
yet, `gh pr create --draft --base <base>` now. On a GitLab origin (`git remote get-url
origin`) the PR is a merge request and every PR command is `glab mr` instead: `glab mr
create --draft --target-branch <base> --source-branch <branch>`, `glab mr update <n>
--description`; `gh` cannot reach a GitLab remote at all. Name `<base>` from the remote
(`git branch -r`), not from habit: a repo with no `dev` takes its PR on `main`. The PR
body is written for a repo reader (what, checks run, what to do after merge) with no
vault references. Only once §4 passes; a refused push or `gh`/`glab` error is reported with
the exact message, not worked around, and is not a failed Done-when. The operator's
part starts at *review and merge*.

**§8 Out of scope.** Named, not implied.

**§9 Known traps.** Everything that has already cost someone a day here.

**§10 What this brief may be wrong about.** Honest. Which claims came from memory
rather than from the repo, which assumptions are untested. This is where
`/handoff-review` starts, so a good §10 makes the review cheaper.

**§11 Human checks (after the run).** The checks only a person can do once the run has
closed: the dev-stack visual pass, a judgement call on a size or a colour, anything
behind credentials or hardware the run does not have. Say so in the section's first
line: *these are not the run's — do not attempt them, do not report on them.* The run
never lists them under `NOT DONE`; `/debrief` carries them into the sub's `current.md`
as open items. Write `- none`
if there are none, so the section is never mistaken for a forgotten one.

If the draft exceeds ~400 lines or ~6 top-level tasks in §7, stop and run
`/handoff-split` instead of shipping one oversized brief.

## 5. The self-containment sweep — do not skip, do not soften

The runner has no vault. A reference it cannot resolve does not read as *missing*, it
reads as *background I must already agree with*. Check the brief, from the vault root:

```
brief-check <brief>
```

It runs the sweep over every line after the frontmatter (wiki links, vault paths,
decision numbers, pointers to other notes, brief and plan file names; on a brief
whose repo is this vault, `02-projects/` and the word vault are allowed, and on one
whose repo is the handoff kit's own, the word vault), then checks the brief's git, path, line, symbol, size, boundary and done-when claims
against its repo.

- **Every `FAIL` line is a sweep hit, and a defect.** Fix it by **inlining what the
  reference points at** — an ADR becomes its ruling plus one line of why, with the
  number dropped. Do not "fix" it by rewording the pointer.
- **Every `WARN` line is a lead, not a stop.** Check the claim it names against the
  repo. Fix the brief when the claim is wrong; leave it when the claim holds, or when
  an earlier brief of the same plan creates what it names.
- **Exit 2 is a usage error**, not a verdict: fix the command.

When the brief's repo may be public, run `./publish-guard.sh guarded <the brief's repo>`
from the brain root. A private name in a public repo's text is public for good.

- **Exit 0** (the repo is guarded, so public): run `./publish-guard.sh files <brief>`.
  Treat each hit as a `FAIL`: reword until the word is gone, and never quote it. If
  `files` exits 2, the check did not run: fix the setup it names, and never treat it as
  a pass.
- **Exit 1**: nothing more to do.
- **Exit 2**: the repo is not on this host. Say so, as for an unverified §2.

Check with the gate, never with a grep that names the word: that command is one more
place the word is written down.

Earlier briefs in the same series are banned too. The runner is a new session; that
file does not exist for it. Inline what still matters and let the rest go.

Do not report the brief as finished while a `FAIL` line remains. The launcher runs the
same check before every review and stops the review on a `FAIL`, so a brief handed over
with one comes straight back.

## 5b. Claim check

The review stage checks a brief's claims after it is written, at review prices, and a
wrong claim found there costs a revise, sometimes a human. Check them now, cheaply,
while the facts are fresh.

Spawn **one** subagent with the Agent tool: `subagent_type: Explore`, `model: sonnet`.
It is read-only, which is the point: it checks, you fix. Give it the brief's path, the
repo from its frontmatter, today's date, and this task:

> List the claims about the repo in the brief's §1, §2 and §3, and the reasons in §6
> that state a fact about the repo: a file, a function, a line number, a count, a
> command and its output, a behaviour. Take at most 40, the ones that would send a run
> down a dead path first. Check each against the repo as it is now, by reading files
> and with read-only git, never by running the brief's own commands. In a brief of a
> plan, or a later part of a split, a claim about what an earlier brief or part
> produces cannot be checked here: mark it CANNOT TELL, with the reason "produced by an
> earlier brief". Reply with the table and nothing else.

```
# Claim check — <brief file name> — revision <revision> — <YYYY-MM-DD>

1. HOLDS — <claim> — `<path>:<line>` "<quote>"
2. DOES NOT HOLD — <claim> — `<path>:<line>` "<quote>"
3. CANNOT TELL — <claim> — <why>
RESULT <n> claims · <h> hold · <d> do not hold · <c> cannot tell
```

Write the reply verbatim to `<brief stem>.claims.md`, beside the brief. Then:

- **DOES NOT HOLD:** fix the brief to match the repo, or drop the claim, and append
  ` — fixed: <what changed>` or ` — dropped` to that row. When the fix is a decision,
  not a fact, ask the user.
- **CANNOT TELL:** name the claim in §10 as unchecked, unless it is produced by an
  earlier brief of the plan.
- Then run §5's check again: a fix can carry a reference.

The review is given this table and checks it rather than rediscovering it, so a row
that says HOLDS must quote the line that proves it. If your client has no subagent
tool, do the check yourself, in the same format.

## 6. Hand it over

Set `handoff: draft`. **Never hand-build a launch command.** the `handoff-launch` command
takes a mode and a brief and reads everything else — repo, revision, model,
effort, permission mode, tool denials — from the brief's own frontmatter. It also owns
the review wrapper, so that never has to be retyped or re-quoted.

`--backend` is **always spelled out on the command line**, so the user sees and chooses
it every time the command is pasted. Fill it in with a concrete value, never leave the
placeholder:

- `claude` by default — the CLI is at `~/.local/bin/claude` on this host. `hermes` or
  `devin` appear only when the user names one; the backend is never left to
  auto-detection, since on 2026-09-14 a loop that relied on it ran on another backend
  without saying so, while its brief recorded opus and sonnet.
- With `--backend hermes`, also check `~/.hermes/profiles/run/config.yaml`'s
  `model.default` and warn when it ends `:free`: the launcher refuses `run:*:free`
  without `--model <paid>` or `HANDOFF_ALLOW_FREE_RUN=1`, and a hermes loop line carries
  no `--model` to supply one — so a free-tier run profile stops the loop after revise.

A `review`, `run` or `lesson` line also carries `--model <model>`, filled with a
concrete value: for `claude`, the model the brief's `<mode>-session` block resolved
(e.g. `opus` for review, `sonnet` for run — a lesson's model is the brief's
`run-session` model, because the launcher configures a lesson from that block); for
`hermes`, the model of the profile the stage uses
(`~/.hermes/profiles/<review|run|close>/config.yaml`, `model.default`; the `default`
profile for vault stages) unless the user asks for another — it is passed as hermes
`-m` and wins over the profile; for `devin`, **print no `--model` at all** unless the
user names one: Devin's model availability is decided by the account tier, and an
account below Pro refuses every named model with *Upgrade to Pro to access this model*
while the CLI's own default works — so the launcher passes none there and says why in
its banner. Say in one line where each value came from. There is no single-stage
`devin` line; devin's only line is its loop.

A `loop` line never carries `--model`: the loop forwards it to every stage it spawns,
over each stage's own block, so a `--model opus` meant for the review would also put the
run on opus. It carries `--gate` instead. `--gate auto` reads the `gate:` line of the
latest `## Revise outcome` in `<brief>.review.md` and, from `draft`, reviews, revises,
runs, closes and debriefs with no human in the loop; it stops with `GATE: <reason>`
(exit 10) only when that token is not `clean`, and with `RUN: <reason>` (exit 20) when
the closed run fails its check. After a `GATE:` the user reads the `## Revise outcome`,
fixes what it names, and relaunches with `--gate human`. Every stage still prints
`LAUNCH <mode>: backend=… model=…` when it starts, whatever the loop's own flags were.

Devin's read-only stages are held by a `permissions.deny: ["edit"]` rule the launcher
builds into a temporary `--config` file (merged from the user's own Devin config, which
`--config` would otherwise replace), so the review can still run `git` to check claims but
cannot edit a file. That is the devin analogue of claude's `--disallowedTools`.

Dry-run it first and show the user the resolved config. It launches nothing:

```bash
handoff-launch review <brief path relative to vault> --dry-run --backend <claude|hermes|devin> --model <model>
```

The normal path is one command, the loop, with `--gate auto`: from `draft` it reviews,
revises, runs, closes and debriefs on its own, stopping only where a human is needed —
a held gate or a failed run check. Offer it as a **`bash`-tagged block** — the tag is
what gives it a Run button:

```bash
handoff-launch loop <brief path relative to vault> --backend <claude|hermes|devin> --gate auto
```

The review-only form is for when the user wants to read the findings before anything is
applied. It is read-only and short, so headless is safe; the block is written to
`<brief>.review.md` and one line comes back:

```bash
handoff-launch review <brief path relative to vault> --backend <claude|hermes|devin> --model <model>
```

Every skill prints its commands and stops — it never runs a stage itself. On
2026-09-14 a session ran the review it had just printed, and the operator's own `loop`
on the same brief landed two minutes later; both wrote the same review file, and the
operator's revise edited the brief while the session was still applying the other
review.

Three things are load-bearing, each learned by breaking something:

- **Never pass the brief as an argument or inline it into any shell string.**
  `$(cat <brief>)` inside a nested shell string does not survive the trip: the brief's
  text once arrived as script and executed, running a formatter over 82 files and
  staging them. The launcher opens the file itself, so nothing has to survive anything.
- **Order: every flag, then `--`, then the prompt last.** Two separate failures forced
  this. A brief starts with YAML frontmatter, so a bare positional prompt begins `---`
  and the parser dies with `error: unknown option '---`. And `--disallowedTools` /
  `--allowedTools` are variadic, so ahead of a bare positional they swallow it word by
  word. `--` ends option parsing outright and fixes both. The script does this for you —
  which is the reason never to hand-build the command.
- **The dry-run's argv count is the proof.** Intact means the prompt is the final
  argument, whole. Word-split shows a count in the hundreds — visible *before* anything
  runs.

If the dry-run warns that the brief has no `review-session:` block, fix the brief rather
than launching: without it the session inherits the machine's defaults and the brief no
longer records what its run was given.

Tell the user the next step is `/handoff-revise <sub>` with the review output pasted
in — only after a review-only launch. Do not run the command yourself.

Last, apply the rules filed under `### /handoff` in `AGENTS.local.md` § Local rules, if there are any.

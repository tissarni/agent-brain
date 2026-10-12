---
name: handoff-revise
description: Apply a repo-side review's findings to a brief, bump its revision, and print the run command. Use when user pastes a HANDOFF REVIEW block, names a .review.md file, or says "revise the brief", "apply the review", "the review says".
---

Arguments: `<sub> [<review file>] [unattended]`. The review is read from the file when
one is given, else from a paste. `handoff-launch review` writes it to
`<brief>.review.md` next to the brief and sets `handoff: reviewed`, so a file is the
normal case and a paste is the fallback for a review someone ran by hand. `unattended`
is how the launcher's `revise` and `loop` modes call this — see §7.

Consumes the `=== HANDOFF REVIEW ===` block a repo session produced, applies it to the
brief on disk, and moves the brief from `draft` to `ready`.

## 1. Match the review to the brief

Find the sub's most recent brief — with a review file, the brief is the file's name
minus `.review`, and its first line names the revision it was written against. Compare
the brief's `revision:` to the review's `brief-revision:`.

**They must be equal.** If they are not, the review looked at a different version of
this brief than the one on disk — stop and say which is which. Applying a stale
review's fixes to a newer brief writes corrections for text that is no longer there.
Ask whether to re-review the current brief or to discard the stale block.

If the review block is malformed or absent, say what is missing rather than guessing
at intent. A half-parsed review silently drops findings.

## 2. Read the verdict first

| verdict | Do |
|---|---|
| `RUN` | apply everything (step 3), bump, go to step 5 — a `RUN` review can still carry `WRONG`, `RISK`, `SCOPE` and `MISSING` findings (the verdict only means no `BLOCKER`, no `WRONG` showing the brief's §4 goal or a §3 decision must change, and no `WRONG` on a stated reason), and each one gets applied |
| `REVISE` | apply everything, bump, go to step 5 — a `WRONG` on a stated reason (a why in §1, §3 or §6) is applied by correcting the reason; the rule it supports stays |
| `REWRITE` | **stop.** The brief's §4 goal, or a decision its §3 settles, must change. Patching it produces a document that argues with itself. Say what the review contradicted and hand back to `/handoff` — or to `/decision-needed` if the premise was a decision |

`RUN` and `REVISE` differ in what the review found, not in how much of it you apply. The verdict
never narrows the findings: a finding left out because of the verdict alone lands in `skipped`,
holds the gate, and stops an unattended loop for a correction revise could have made itself (it
paged the operator over a one-line README line-number fix once).

## 3. Apply the findings

Per finding, in this order — `BLOCKER`, `WRONG`, `MISSING`, `RISK`, `SCOPE`:

- **BLOCKER / WRONG** — the repo is authoritative on operational facts. Rewrite the
  passage the `claim:` quotes, using `actual:` and `fix:`. Do not append a correction
  next to the wrong sentence; the runner will read both and pick one.
  A `WRONG` on a §4 Done-when the run cannot decide (a dev-stack visual pass, a "feels
  right" call, anything behind credentials or hardware) is a placement fix: move the
  item verbatim to §11 *Human checks (after the run)*, creating the section if the brief
  predates it, and delete it from §4. Never leave it in both.
- **MISSING** — add it where it belongs, not in a new section at the end.
- **RISK** — into §9 Known traps if it is a hazard, §10 if it is an untested
  assumption.
- **SCOPE** — into §8 Out of scope, or into §7 as an explicit task. Never leave it
  ambiguous, which is how it gets built by accident.
- **UNVERIFIABLE** — do not treat as confirmed. Fold into §10, named as unchecked and
  saying what would check it.

Anything the review confirmed *right* moves up into §3 Settled, with the evidence
string. That is the compounding half: the next brief in this series inherits a fact
that has now been checked against the code, and no future run re-checks it.

## 4. When a finding contradicts a decision, not a fact

A review that says *the code does not work the way the brief claims* is a fact, and the
repo wins. A review that says *this design is wrong* is a decision, and it does not get
settled by editing a brief.

Surface those separately. Offer `/decision-needed <sub> <topic>`, or `/supersede` if it
overturns a recorded ADR. Do not quietly rewrite the brief to the reviewer's
preference — that launders an architectural change through a document edit, and the
vault ends up with an ADR that no longer describes what is being built.

## 5. Bump, sweep, and set state

- `revision:` → next `rN` for today's date. Update the echoed string in §0b too — they
  must match, or the echo checks nothing.
- Add a short line at the top of §0b: what changed since the previous revision. One or
  two sentences. The runner should know it is holding a corrected document.
- Re-run the check, from the vault root — a review's `fix:` text often arrives carrying a
  path or a decision reference:

```
brief-check <brief>
```

  A `FAIL` line is a sweep hit: fix it by inlining what it points at, as `/handoff` §5
  says, and run the check again. A `WARN` line is a lead, never a stop: check the claim
  it names when this revision touched it.
- `handoff: ready`, `updated:` today — only once the check prints no `FAIL` line.

## 6. Print the run command

Built from the brief's own `run-session:` block — it was resolved when the brief was
written and stays put, so a brief revised three times still launches the way it was
configured. If the user names a different model or effort now, update the block in
frontmatter first, then render from it; never pass a flag the brief does not record.

**Never hand-build the command.** the `handoff-launch` command reads the repo,
revision, model, effort and permission mode out of the brief's own `run-session:`
block, so a brief always launches the way it records. `--backend` is spelled out every
time: `claude` by default, `hermes` or `devin` only when the user names one — never left
to auto-detection. A `run` line also carries `--model <model>`: for `claude`, the
brief's `run-session` model; for `hermes`, the `run` profile's `model.default` from
`~/.hermes/profiles/run/config.yaml`, passed as `-m`; for `devin`, none unless the user
names one, because the account tier decides what runs. Fill in concrete values, never
the placeholders.

Dry-run first and show the resolved config — it launches nothing, and its argv count is
the check that catches a mangled prompt before it executes:

```bash
handoff-launch run <brief path relative to vault> --dry-run --backend <claude|hermes|devin> --model <model>
```

Then the watched run — paste this into a terminal yourself, since a session started
through a tool call has no TTY:

```
handoff-launch run <brief path relative to vault> --backend <claude|hermes|devin> --model <model>
```

The dry-run also reports the repo's **current** branch against the one the brief
expects. Read it before launching — a brief whose §2 assumes a branch that is not
checked out, or a tree with uncommitted work in it, starts from a state it does not
describe.

### If the user says "delegate it" / "launch it" / "hand it to an agent"

Delegation is the loop with `--gate human`, since an interactive revise never writes the
`gate:` token `--gate auto` reads: it stops after revise for the human's read, and
running it again resumes from `handoff: ready` — that re-run *is* the approval:

```bash
handoff-launch loop <brief path relative to vault> --backend <claude|hermes|devin> --gate human
```

**Never build the command by inlining the brief into a shell string.** The launcher
opens the brief itself, puts every flag before `--` and the prompt last, resolves the
`claude` binary and forces the headless posture — that used to be a hand-built launcher
script's job, and hand-building it once ran the brief's *text* as script instead of as a
prompt: a formatter ran and `git add` staged 82 files in `back-end` before it was caught
and reverted. **`--bg` is not the mechanism**: it starts a *blank* detached session,
with no initial prompt from argv or from stdin. **A subagent is not the mechanism
either**: the Task tool inherits this session's own working directory, the vault, which
has none of the repo's guards.

So delegation means headless `-p`, backgrounded. It runs unattended and its final
output is the completion report. Say the trade-off out loud before starting: nobody can
interject. For a brief that builds images, locks dependencies or makes live requests,
offer the watched run instead and let the user decide.

### If they run it themselves

Set `handoff: running` only when they confirm they launched it, and ask for the session
name so it can be matched later. Until then it stays `ready`: that field is what tells
*waiting on you* from *waiting on an agent*, and setting it early makes it lie.

Tell them the run ends with `/handoff-close`, and its output comes back here as
`/debrief <sub>`.

## 7. Unattended posture (`unattended` argument)

`handoff-launch revise` and `loop` run this skill in a headless vault session with
the review file path and the word `unattended`. Nobody will answer a question, so:

- **Never ask.** Every "ask", "offer" or "stop and say" above becomes a line in the
  outcome section instead, and the skill carries on with what it can do alone.
- Steps 1, 2, 3 and 5 run as written. A revision mismatch or a `REWRITE` verdict stops
  **before any edit**: the brief keeps `handoff: reviewed` and the outcome says why. The
  loop reads that state and halts — the intended failure mode, not an error.
- Step 4 (a finding that contradicts a decision): do **not** rewrite the brief for it.
  List it under *decisions surfaced, not applied* with the exact `/decision-needed` or
  `/supersede` command a human would run.
- Step 6: launch nothing and print no command. The loop resumes from `handoff: ready`
  when the human re-runs it — that re-run *is* the approval of the revised brief.
- **Append the outcome to the review file, then set the state.** The launcher checks
  the state; the human reads the outcome:

```
## Revise outcome — <revision before> → <revision after> — <date>
applied: <n> findings (BLOCKER n · WRONG n · MISSING n · RISK n · SCOPE n)
settled into §3: <what moved up, with evidence strings>
unverifiable into §10: <what was named as unchecked>
decisions surfaced, not applied: <list with commands, or the literal none>
skipped: <findings that could not be applied, each with why, or the literal none>
state: reviewed -> ready   |   left at reviewed (<reason>)
gate: clean   |   held — <first failing check>
```

`gate:` is the one line a machine reads (`handoff-launch loop --gate auto` and the
orchestrator above it). `clean` means all of: verdict `RUN` or `REVISE`, `decisions
surfaced` is `none`, `skipped` is `none`, state moved to `ready`, revision bumped and
echoed in §0b, and the last `brief-check <brief>` printed no `FAIL` line. Anything else is `held` with the first failing check named. A `FAIL` line you could not fix leaves the brief at `reviewed`, with `gate: held — brief-check: <first FAIL line>`. `skipped` is only for a finding
you **could not** apply: its `claim:` text is no longer in the brief, or its `fix:` contradicts
another finding or the repo. A finding that is really a decision goes under *decisions
surfaced*, not here. "Out of scope for this verdict" is never a reason — see step 2. Write the
tokens literally — `none`, `clean`, `held`, ASCII `->` in `state:` — because the first
real outcome files carried them as free prose and nothing downstream could parse them.
Without the line the unattended loop fails closed and stops for a human.

The vault's Stop hook commits the edits. Keep the closing message to five lines: the
outcome section is the record, and stdout is read by nobody but the launcher.

Last, apply the rules filed under `### /handoff-revise` in `AGENTS.local.md` § Local rules, if there are any.

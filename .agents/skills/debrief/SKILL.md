---
name: debrief
description: Absorb an autonomous run's completion report back into the vault — state, decisions, divergences, lessons. Use when user pastes a COMPLETION REPORT block, names a .report.md file, or says "debrief", "the run finished", "absorb the report", "the agent is done".
---

Arguments: `<sub> [<report file>] [unattended]`. The report is read from the file when
one is given, else from a paste. A delegated run (`handoff-launch run --delegate`, or
`loop`) writes it to `<brief>.report.md` next to the brief and sets `handoff: reported`.
A *watched* run prints it in its own window, so for that one the user pastes — write the
pasted block to `<brief>.report.md` first, so the record exists on disk either way.
`unattended` is how the launcher's `debrief` and `loop` modes call this — see §6.

The return leg of the loop. A run just told you what it actually did; this turns that
into vault state, and nothing gets written until you have seen what will change.

## 1. Match the report to the brief

Find the sub's brief whose `revision:` equals the report's `brief-revision:`.

No match means the run executed a version of the brief that is not on disk — a stale
paste. **Say so and stop.** Absorbing it would record work against a document that
never existed, and every claim in §3 of the next brief would inherit that.

If several briefs are `running` or `reported`, match on revision, not on recency.

## 1b. When there is no report at all

A run can die before it reaches `/handoff-close` — context exhausted, a crash, a window
closed. The brief then sits `running` forever and the work is invisible, which is worse
than a partial report: the vault keeps claiming an agent is on it. (A delegated run that
finished properly is `reported`, with the file on disk — `running` with no
`<brief>.report.md` is the case this section is for.)

Confirm it is actually dead before reconstructing — a run that is merely slow, or
blocked on a permission prompt it cannot answer, should be attached to, not written off:

```
claude agents --json
```

Match the brief's `session-id:`, or `cwd` against its `repo:`. If a session is there and
working, stop and say so. If it is idle or blocked, say `claude attach <id>` — the run
may still produce a real report, which is worth far more than anything below.

For a `--backend devin` run the same question goes to the CLI, from the brief's repo:
`devin list --format json` reports the sessions rooted there with a
`last_activity_at`/`last_activity_ago` and no live state. Treat a session active minutes
ago as alive; for a stale one, read `~/.local/share/devin/cli/logs/devin_*.log` before
writing it off, and resume it with `devin -r <id>` if it is still answerable.

Only once nothing is alive, reconstruct instead of guessing:

```
git -C <repo> log --oneline <base>..HEAD && git -C <repo> status -sb && git -C <repo> diff --stat <base>..HEAD
```

Build the change set from that, and mark it plainly as **reconstructed, not reported**.
It carries less than a real report and you must not pretend otherwise: commits show
what landed, never what diverged, what the brief got wrong, or what hurt — the three
things only the run knew, and they are gone.

So: no `BRIEF WAS WRONG` corrections, no ADR drafts, no pain-point routing from a
reconstruction. Set the sub's `status:` from the tree, set the brief to `closed`, and
say in `current.md` that this brief's run ended without a report and the divergences
were lost. If the work looks unfinished, the next brief starts from a verified §2 —
which a reconstruction is actually good at.

Prefer asking the session for `/handoff-close` first if it is still alive. A real report
is worth far more than anything reconstructible here.

## 2. Build the change set — do not write yet

Read the sub's `current.md` and the `## Key decisions` of its `context.md`. Nothing
else; the report is the authority on what happened.

Assemble, and **print for confirmation**:

**a. Frontmatter changes.** `status:` from the closed-set vocabulary — `impl-done` if
the report is `COMPLETE` but nothing is merged, `blocked` with a `blocker:` line if
`BLOCKED`, `active` if `PARTIAL`. Never `done` from a report alone: `done` means
shipped and verified, and a report is the agent's account of its own work.
Refresh `summary:` if what the sub is has changed, and `branch:` if the run moved.

**b. `current.md` rewrite.** What is now true, what is next, what is blocked. The
`NOT DONE` items become the next task list. The brief's **§11 Human checks (after the
run)** — which the report never mentions, by design — are copied in under a heading
`Human checks — <brief> (open)`, one line each, so they are not lost with the brief.
Keep it short — this file is read at the start
of every session on this sub.

**c. `## Key decisions` additions.** Only for `DIVERGED` entries that were *choices*.
A divergence forced by reality — the function was named something else, the test
target did not exist — is a fact, not a decision, and belongs in `current.md`.

**d. ADR drafts.** For each divergence that changed a rule future code must follow.
Draft it in full — Context, Decision, Consequences, Alternatives — and **show the
draft**. Do not write it yet. An ADR authored unseen from a report is a decision
nobody made.
If a divergence contradicts an existing ADR, name that ADR and offer `/supersede`
rather than stacking a second, disagreeing ruling next to it.

**e. `BRIEF WAS WRONG` entries.** These are the vault being wrong about the repo, and
they matter more than they look. Print each as *the vault claimed X; the run found Y*
and correct the vault text that carried the claim — `current.md`, `context.md`, or the
spec. On operational facts, the repo wins.

**f. Brief frontmatter.** `handoff: closed`.

**g. Pain points → lessons.** For each `PAIN POINTS` entry, emit a ready-to-run
invocation for the repo side:

**Write each lesson to a file, then launch it through `handoff-launch`.** Do not build
the command by hand: a `/capture-lesson` line is prose, and prose contains apostrophes,
which is exactly what breaks a nested `bash -lc '...'` quote. That happened on
2026-08-25 and the text had to be reworded to survive the shell — a document altered by
its transport.

Write to `<sub>/specs/YYYY-MM-DD-lesson-<slug>.md`, one per pain point. They belong in the
vault: they record what you asked the repo to learn, and they trace back to the run that
produced them.

Then one **`bash`-tagged block** per lesson, with `--backend` (`claude` by default,
`hermes` or `devin` only when the user names one) and `--model` (the brief's
`run-session` model, since the launcher configures a lesson from that block) filled in
with concrete values:

```bash
cd <this brain's root> && handoff-launch lesson <brief path relative to vault> --note <lesson path relative to vault> --backend <claude|hermes|devin> --model <model>
```

Launch them **one at a time**, not in parallel — two simultaneous sessions both died on a
limit message where the same two run serially both succeeded.

State the lesson as what happened and what it cost, and stop there. Do not prescribe the
fix. Both lessons run on 2026-08-25 overrode the framing they were given and found a
cheaper structural lever than the one suggested — an over-specified lesson buys the fix
you imagined instead of the one that works.

**Read the diff, not the summary.** A lesson session reports on itself. Both of those runs
described their changes accurately, and one still justified a guard change with a fact
that turned out to be wrong. Check what it wrote before it is committed, especially when
it widened a guard.

Route them, do not paraphrase them into vault prose: the point of `/capture-lesson` is
that a lesson becomes a hook or a test case, and a paragraph here is the outcome it
exists to avoid. Entries marked machine-catchable go first.

**h. Anything unverified.** A `VERIFICATION RUN` claim with no command and no output
behind it is not evidence. List those separately as *asserted, not shown* — do not let
them into `current.md` as established facts.

Read the report's `audit:` header. It says how many of its own claims the run
re-checked before reporting, and how many it refuted or left unconfirmed. It is the run's
self-check, not the verdict — the close stage's `VERDICT:` is, on §4 results the launcher
re-ran. A report with refutations is not a worse report — it is a report that caught
itself, and the surviving claims are stronger for it. What matters is the opposite case:
**a missing `audit:` line, or `0 claims checked`, means the run never checked itself**,
so treat every `DONE` entry outside §4 as asserted rather than confirmed, and say so at
the gate. A run reporting only its own successes reads identically whether it was careful
or lucky.

## 3. Gate

Show a, b, c, d, e, f, g, h as a numbered list of intended writes, then ask. Accept
partial approval — *do 1, 2 and 5, skip the ADR* — and apply only what was approved.

## 4. Write, then propagate

After approval:

1. Apply the approved edits.
2. Run `/rollup <main>` — the parent `_index.md` is generated and does not notice
   frontmatter changes on its own. Skipping this is how the index starts lying.
3. If `status:` is now `impl-done` and the report says the branch is merged and
   verified, offer `/ship <sub>` — offer, do not run it. Shipping is a claim about the
   world, and the report only covers the repo.
4. Say what was **not** absorbed and why: unapproved items, unverifiable claims, the
   `NOT DONE` list.
5. Last, apply the rules filed under `### /debrief` in `AGENTS.local.md` § Local rules, if there are any.

## 5. If the next step is another brief

`NOT DONE` plus `BRIEF WAS WRONG` is most of the next brief's §2 and §3 already
written. Say so and offer `/handoff <sub>`, which will now inherit facts checked
against real code instead of remembered ones.

## 6. Unattended posture (`unattended` argument)

`handoff-launch debrief` and `loop` run this skill headless with the report file
path and the word `unattended`. The gate in §3 has nobody behind it, so the split is by
reversibility, not by asking:

- **Apply without asking** — a, b, e, f, h. These are state; a wrong one is visible in
  the brief's frontmatter and one edit from correct. Every `DONE` the run did not audit (§2h)
  goes into `current.md` marked *(asserted, not shown)*, never as an established fact.
- **Draft, do not apply** — c and d. A key decision or an ADR authored unseen is a
  decision nobody made. Write the drafts in full into the outcome section, with the
  exact `context.md` line or ADR filename a human would create.
- **Write, do not launch** — g. Write each lesson file; list its launch command in the
  outcome. Starting a repo session from inside a vault session is not this skill's call.
- §1b does not apply: the launcher runs this only when the report file exists. A
  revision mismatch stops **before any write**; the brief keeps `handoff: reported` and
  the outcome says why, and the loop halts on that state.
- Run `/rollup <main>` as in §4, then set `handoff: closed`.
- **Append the outcome to the report file:**

```
## Debrief outcome — <date>
sub status: <before> -> <after>
applied: <a, b, e, f, h — one line each: what changed, in which file>
asserted, not shown: <n> claims — <list>
drafts awaiting a human: <key-decision lines · ADR drafts in full · or "none">
lessons written, not launched: <file> — <handoff-launch lesson command>, one per line
not absorbed: <NOT DONE list · unverifiable claims>
human checks carried into current.md: <n> from the brief's §11, or none
state: reported -> closed   |   left at reported (<reason>)
```

Keep the closing message to five lines; the outcome section is the record.

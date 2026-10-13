# Skills — Reference Guide

> Generated from `.agents/skills/*/SKILL.md`. If this file and a SKILL.md disagree,
> **the SKILL.md is right** — regenerate this one rather than patching it.
> Run with `/skill-name`, or just describe what you want; the description frontmatter
> is what decides which skill triggers.

Canonical skills live in `.agents/skills/`. `.claude/skills/` is a generated mirror —
never edit it. After changing a skill run `./sync-skills.sh --apply`. See `AGENTS.md`.

A brain's own rules for a skill sit under `### /<skill>` in `AGENTS.local.md` § Local rules and
are applied as that skill's last step. A brain's own skills sit beside these in
`.agents/skills/`, and `AGENTS.local.md` lists them.

---

## How the vault runs

```
Scheduled                 weekdays 23:30, a system timer runs /rollup, then /day-log;
                          Mondays 06:00 it runs those two, then /week-recap.
                          Installed by ./setup.sh --journal y; otherwise run them by hand.

Before a work session     /project-status <name>
Facing a choice           /decision-needed <name> <topic>
Choice already made       /adr <name> <title>
A decision reversed       /supersede <ADR>
A sub is finished         /ship <sub>
After any status change   /rollup <main>

On demand                 /project-init · /doc-build · /md-html · /team-doc

Hand work to an agent     /handoff <sub>          writes the brief, prints the review command
  several briefs, phased  /handoff-plan <sub>     the plan + every brief of one phase
  run the phase           /handoff-orchestrate    pre-check, watchdog, prints the start command
  brief too big           /handoff-split
  review came back        /handoff-revise <sub>   bumps rN, prints the run command
  run came back           /debrief <sub>          confirmation-gated absorb
```

Nothing in the daily loop asks you anything. Both journal skills write **nothing at
all** on an empty day or week — silence means there was nothing to say.

---

## /day-log

**When:** by the timer, weekday evenings (it passes the date); by hand otherwise. Or "log today", "what changed today".
**Argument:** optional date `YYYY-MM-DD` (default today).

Builds the day's note from **what actually changed on disk**, not from your memory. It
finds every `.md` touched that day under `02-projects/`, `03-knowledge/` and `00-inbox/`,
plus the vault's own tooling — `.agents/skills/`, `AGENTS.md`, `SKILLS.md`, the scripts —
so a day spent on skills is not a blank note. It skips `.claude/skills/`, a generated
mirror that would double-count, and the generated `_index.md` files.

Everything is grouped by the project that owns it, at the most specific level — a
sub-project rather than its main — reading **only the frontmatter** of each `context.md`.

**A touched file is not an event.** Every claim is gated on a corroborating field, because
a restructure or a find-and-replace touches hundreds of files that nothing happened to:

- **Shipped** needs `closed:` in that `summary.md` to equal the log date
- **Blocked** needs `status: blocked`, so it cannot disagree with `/rollup`'s 🔴 count
- Above 12 projects touched it stops enumerating, writes counts plus a cause, and sets
  `projects: []` — a note claiming 44 projects would become "recent activity" for every
  one of them and evict the real activity from `/project-status`

Then day-log runs one follow-on, the inbox report: it **reports** anything sitting in `00-inbox/` without touching it — filing needs your
confirmation, and this run is unattended.

Sections: **Shipped · Moved · Blocked · Vault tooling · Inbox · Elsewhere**, then a
`## Notes` marker. Everything below that marker is yours; reruns never touch it.

**Writes nothing on a day with no changes.** Missed nights backfill up to 7 days.

---

## /week-recap

**When:** by the timer, Monday mornings after `/rollup` and `/day-log`; by hand
otherwise. Or "week recap", "what happened last week".
**Argument:** optional ISO week `YYYY-WNN`. Default: the most recent week that has
**fully** ended — never the week in progress, or the recap silently omits its last day.
That is why it runs Monday and not Sunday night.

Reads the week's daily notes — they are already summaries, so it reads them whole —
including your hand-written `## Notes`, which carry the most signal precisely because no
generator produced them.

Then **one** read of each touched main's `_index.md`. That single file is the end state
of every sub in the cluster, so the recap gets both what moved (from the dailies) and
where it landed (from the index), without opening a single project file.

Also lists the mains that were **quiet** all week. Absence is information.

Saves to `05-weekly/YYYY-WNN.md`. **Writes nothing if the week has no daily notes** —
and backfills any of the last 4 weeks that has notes but no recap, so a week whose dailies
arrived late is still recoverable rather than lost for good.

---

## /ship

**When:** a sub-project is finished. "ship X", "close X", "X is done".
**Argument:** a sub-project name. Mains are never shipped, only their subs.

Writes the sub's `summary.md`, flips `status: done`, drops any `blocker:`, offers to
archive the working notes, and runs `/rollup` so the parent index stops showing it as
active.

`summary.md` matters more than it looks: once a sub is `done`, `AGENTS.md` § Level 4
forbids reading its body ever again, so this file **replaces the folder**. It follows the
shape the existing summaries already use — Outcome, What changed, Why it still matters,
Decisions, Detail — where *Why it still matters* is the section future-you actually needs.

Reads the sub's `current.md` and `context.md` in full — the one time that is correct,
since you are closing it — and asks for confirmation once, not in an interview.

Needs no separate log entry: `/day-log` sees the new `summary.md` and files it as
**Shipped** on its own.

---

## /supersede

**When:** "supersede", "that ADR is obsolete", "we changed our mind about".
**Argument:** the ADR being replaced, and the decision replacing it.

Of 94 ADRs, 67 carry no `Status:` line and not one has ever been superseded. Decisions do
get reversed — so today a wrong one stays `Accepted` forever and `/project-status` serves
it as current.

Marks the old ADR `Superseded by ADR-NNN (date)` without rewriting its body — a superseded
ADR is the record of what was believed at the time — adds a `Supersedes` line to the new
one, and strikes through the old entry in `context.md` `## Key decisions`.

That last step is load-bearing: `/project-status` reads that section and never opens the
ADRs, so an unmarked line there makes the reversal invisible to every future session.

`/adr` and `/decision-needed` now offer this when a new decision reverses existing ground.

---

## /project-status

**When:** before a work session. "status of X", "brief me on X".
**Argument:** a main or sub name, resolved per `AGENTS.md` § Project path resolution.

**For a main:** reads `_index.md` — that one file is the state of every sub — then
`context.md`, then `current.md` if present. It does **not** open any sub-project file.

**For a sub:** reads that sub's `current.md` and `context.md`, plus only the Stack and
Constraints sections of the parent's `context.md`. No sibling subs.

Then a daily-note pass: the last 14 filenames, **frontmatter only**, keeping the 3 most
recent whose `projects:` names the target — bodies of those 3 only.

Never reads `decisions/`, `specs/`, `plans/` or `_archive/` — `context.md`'s Key
decisions section already summarises them. **Prints to the terminal, writes nothing.**

If `_index.md` contradicts a sub's `current.md`, it says so and offers `/rollup`.

---

## /rollup

**When:** after any change to a sub's `status`, `summary` or `blocker`. "rollup",
"refresh index".
**Argument:** a main's folder name. No argument → every main.

Regenerates `02-projects/<main>/_index.md` from its sub-projects' frontmatter.

Reads **frontmatter only** of each `subprojects/*/context.md`, stopping at the closing
`---`. A main with 13 subs costs about 13 × 15 lines instead of 13 × 400. That is the
entire point: it makes "where does all this stand" answerable in **one read**.

Validates and reports without silently fixing: `parent:` disagreeing with the folder,
`status: blocked` with no `blocker:`, `status: done` with no `summary.md`, over-long
`summary`/`blocker`, `related:` naming a project that does not exist.

Also rewrites the main's line in the `AGENTS.local.md` § Active projects tree: its status,
one count per sub status, and its subs by name, grouped by status. The description is kept
word for word, no other line is touched, and it never asks before writing.

**Never hand-edit an `_index.md`** — change the sub's frontmatter and rerun this.

---

## /project-init

**When:** "new project", "init project X", "new subproject".
**Argument:** kebab-case name, optionally `under <main>`.

Reads `02-projects/_templates/CONVENTION.md` first — that is the contract.

Decides **main** vs **sub** and states which it chose. A main is one deployable system
that would survive deleting every feature planned for it; a sub is one feature, incident,
migration or investigation inside a main. If genuinely ambiguous it asks once, and
recommends sub — subs are cheap to promote, mains are expensive to merge back.
**Never a third level.**

Scaffolds from `_templates/`, filling frontmatter completely — `parent:` and `summary:`
are what the parent's `_index.md` is built from.

Then wires it up: runs `/rollup <main>` (**not optional** — an unindexed sub is invisible
to every future session); that `/rollup` writes the main's line in the `## Active projects`
tree in **`AGENTS.local.md`**.

Creates no `.md` in the code repo. Bridge context stays vault-side.

---

## /decision-needed

**When:** facing an architecture choice. "I need to decide", "help me choose between".
**Argument:** project name + topic.

Interactive. Asks three questions one at a time — what context forces this decision,
what options you are considering, what constraints bind you — then helps you reason
through them and asks before writing anything.

Once confirmed: creates `decisions/ADR-NNN-[slug].md` in the project the decision
governs, and adds the summary line to `## Key decisions` in its `context.md`. If the
decision changes the sub's `status`/`summary`/`blocker`, updates them and runs `/rollup`.

---

## /adr

**When:** a decision already made that needs recording. "write an ADR".
**Argument:** project name + title.

The direct version of `/decision-needed`, without the interview.

The ADR goes where the code it governs lives — a sub-scoped decision in that sub, not in
its main; main-level `decisions/` is for choices binding every sub.

Adds one line to `## Key decisions` in that project's `context.md`. **That summary line
is what lets `/project-status` skip raw ADR files entirely** — it is the load-bearing
part, not an afterthought. Appends only; never re-reads context.md in full to do it.

---

## /team-doc

**When:** "team doc", "explain [sub] to my coworkers". **Argument:** a sub name, any
status.

The curated counterpart of `/doc-build`: one `<sub>-team-doc.md` in the sub's folder
stating the problem, the solution, the measurements, what will bite whoever touches it
next, and what the release must do — nothing else. Every line passes one test: *would a
coworker act wrongly, or waste time, without it?*

Reads the sub's `context.md`, `current.md` or `summary.md`, its non-brief specs, and the
run reports only for numbers. One read-only `Explore` subagent then reads the repo from
the remote ref, confirms each implementation claim at `file:symbol`, and sweeps the
branch diff for the config, migrations and API changes the Deployment section must name.

Fixed sections, read in layers — the top 15 lines give the outcome. No wikilinks, vault
paths, ADR numbers or process words; every number carries its conditions. Always written
`reviewed: no`: only your read sets a date. Renders the HTML with `/md-html` and
publishes it as a private page when the host has an artifact tool. No frontmatter change
on the sub, no commit.

---

## /md-html

**When:** "make an HTML of this doc", a standalone page of one file. **Argument:** a
path to a `.md`.

`node .agents/skills/md-html/build.js <file.md> [out.html]` renders one `.md` into one
standalone page in `/doc-build`'s design. It imports doc-build's `build.js` as a module,
so the two cannot drift visually. Output defaults to `<file>.html` next to the source.
Frontmatter `title`, `summary` and `kind` feed the sidebar; `##` headings make its table
of contents.

Deterministic: two renders of an unchanged source differ only in the footer's
timestamp line. Never hand-edit the output — fix `build.js` and rerun.

---

## /doc-build

**When:** handing a subproject to a teammate who has no vault access. "document this
subproject", "build docs for X", "make an onboarding doc".
**Argument:** a main or sub name, resolved per `AGENTS.md` § Project path resolution.

The problem it fixes: asking for "an HTML summary of this session" freehand re-derives
structure and wording every time, because it asks the model to redo judgment calls
already made and written down. Run it twice on an unchanged `web-app` and the
two documents could disagree with each other on the vault's own direction.

So this is a build, not a prompt — `.agents/skills/doc-build/build.js` renders
`context.md`, every `decisions/ADR-*.md`, every `specs/*.md`, then `summary.md` or
`current.md`, then any other loose `.md` file at the project root, straight to HTML.
No LLM pass over the content at any point. Verified byte-identical across two runs on
`web-app`'s 14 source files.

Handles two things the vault's real files don't agree on internally: ADR filenames are
sorted numerically, not alphabetically, because some folders use `ADR-003-slug.md` and
others plain `0003-slug.md`; and ADR status is read from either frontmatter or a plain
`Status:` body line, because the vault has both shapes in the wild (see `/supersede`'s
own note above — the mismatch between what it expects and what `/adr` actually
produces is a separate, real bug, not something this skill works around silently).

`[[wikilinks]]` never become real links — the reader has no vault to follow them into,
per AGENTS.md's boundary rule that this vault is personal memory, not team-shared. They
render as inert, dashed-underline text with the full path only in a tooltip.

Writes `doc.html` inside the project folder, alongside `context.md` — a local build
artifact like `_index.md`, regenerated, never hand-edited.

---

## The handoff loop — /handoff · /handoff-plan · /handoff-orchestrate · /handoff-revise · /handoff-split · /debrief

Six of the eight skills that carry work from this vault into a repo and back. The
other two — `/handoff-review` and `/handoff-close` — live in the handoff kit, installed
into `~/.claude/skills/`, and must never learn that this vault exists.

Both repo-side skills fan out internally. `/handoff-review` runs three diverse lenses
as subagents — first-hour breakage, every claim checked against real code, and whether
the goal itself is right — then hands each surviving `BLOCKER` (and a `WRONG` only when
the brief changes business code) to a refuter that defaults
to *refuted* when uncertain, because those two tags are the ones that make the next
revision rewrite text which may be correct. Every lens reads in one batched Bash call
per turn — never a lone `cd` or `ls`; turn count, not thinking depth, is where a
review's tokens go. `/handoff-close` audits its own report
against the repo with a clean-context agent that is given neither the brief nor the
conversation. One session each; subagents inherit the read-only denial.

```
/handoff          spec + ADRs -> brief r1, self-contained ── launch cmd ──> repo session #1
                                                                            /handoff-review
/handoff-revise   <- findings pasted back · brief r2 ──── launch cmd ─────> repo session #2
                                                                            /handoff-close
/debrief          <- completion report pasted back · gated absorb
```

**Two fresh sessions, never one.** The reviewer and the implementer do not share a
context on purpose: an implementer handed the reviewer's conclusions stops verifying
them, which is what the review existed to do. The brief is the only channel — which is
also what forces the brief to be complete.

### /handoff

**When:** the spec and the decisions for a sub are settled. **Argument:** sub name.

Writes `specs/YYYY-MM-DD-brief-N-<slug>.md`. Refuses when there is no settled design
to hand over, when the sub has no `repo:`/`branch:`, or when another brief for that sub
is already `running`.

Before writing the state section it runs `git status`/`git log` in the repo over WSL,
because the perishable claims are the ones a brief written from vault memory gets
wrong, and getting them wrong costs the run its first turn.

Eleven mandated sections, each reconstructed from a brief that worked — the ones that
matter most being **§3 Settled, do not re-explore** (the findings you already paid for,
with their numbers), **§5 Step 0** (read the code first; where the brief disagrees, the
code wins), and **§10 What this brief may be wrong about**, which is where the review
starts.

**Model, effort, permission posture and ponytail mode per session** come from
`02-projects/_templates/handoff-defaults.yml` — global defaults, optional `per-main:`
overrides, and whatever you say when you invoke the skill wins over both. The resolved
values are stamped into the brief's frontmatter as `review-session:` / `run-session:`,
so the brief records what its run was actually given. Both sessions are interactive and
watched; nothing in the loop uses `-p`, and everything spawned draws on the
subscription rather than API billing.

Then the **self-containment sweep**: no `[[wikilinks]]`, no `02-projects/` paths, no
`ADR-NNN`, no pointer to an earlier brief. The runner has no vault, and a reference it
cannot resolve does not read as *missing* — it reads as *background I must already
agree with*. Every hit gets inlined, not reworded. The skill will not report done while
one remains.

### /handoff-revise

**When:** a `=== HANDOFF REVIEW ===` block comes back. **Argument:** sub name.

Refuses on a revision mismatch — a review of `r1` applied to `r2` writes corrections
for text that is no longer there. Applies findings in severity order, moves whatever
the review *confirmed* up into §3 Settled so no future run re-checks it, bumps `rN`,
re-sweeps, prints the run command.

The one thing it will not do is quietly apply a finding that disagrees with a
**decision** rather than a fact. The repo wins on how the code behaves; it does not win
on what the design should be. Those get handed to `/decision-needed` or `/supersede`,
so an architectural change cannot be laundered through a document edit.

### /handoff-split

**When:** a brief passes ~400 lines or ~6 tasks. **Argument:** sub or brief path.

Cuts only where **stopping after part N leaves a working system** — a route moved
server-side but not yet called by the frontend is not a boundary. Where no such cut
exists, the part stays large and says so. Each part repeats every section it needs;
duplication across parts is correct, because each is read by a session that has read
nothing else. Only part 1 gets a launch command.

### /handoff-plan

**When:** a sub's work is several briefs that can run one after another unattended.
"plan the phases", "phase 1 closed, what next". **Argument:** sub name, plus an optional
note (backend, model, scope, or "next phase").

Writes one plan, `specs/YYYY-MM-DD-plan-<slug>.md`, and every brief of one phase. A phase
is the longest run of briefs that can all be written today and executed one after the
other with no human decision between them: the human boundary is the phase boundary, and
this is where it gets drawn. Refuses on an unsettled design, a sub with no
`repo:`/`branch:`, or a plan or brief already running on the sub — it owns the repo.

The cut rule: a brief joins the phase only if its §2 can be written honestly today,
assuming every earlier brief landed whole. A *name* an earlier run chooses can be fixed
in the plan; a *measurement* it produces cannot, so the phase ends there and that fact
becomes the next phase's `why-cut-here`. A brief whose Done-when needs a human ends its
phase.

Asks once: is the cut right, and which backend — never inferred. The model stays empty
unless you name one, because a plan-level model overrides every stage. When another plan
holds the repo's checkout, it makes a sibling worktree. Each brief is written through
`/handoff` with its §2 stacked on the previous brief's Done-when, then checked with
`brief-check`; a `FAIL` line means the phase is not written.

Ends at `orchestration: planned` and prints the `handoff-orchestrate start` command.
**Launches nothing.**

### /handoff-orchestrate

**When:** "start the phase", "orchestrate status", "stop the phase", "resume the phase".
**Argument:** a plan path or a sub name, plus `start`, `resume`, `stop` or `status`.

Prepares and reports for the kit's `handoff-orchestrate` driver, which chains the loop's
stages for every brief of a phase from a detached process. The skill **never runs
`start`, `resume` or `stop`** — launching or killing the driver is your keypress. The
one form it executes is `status`, because that only reads files: the plan's status file
and the watchdog timer's state.

For `start` and `resume` it runs the free half of pre-flight — the branch not behind
origin, the dirty set against the baseline, the Telegram notify file present (keys only,
never values), the backend binary on `$PATH`, the checkout lock — and confirms the plan's
30-minute watchdog timer, a systemd user unit the kit installs. Then it prints one
command, backend spelled out.

Refuses a form the plan's `orchestration:` state does not allow: `start` on a running
plan would race the driver, and a `phase-done` plan is `/handoff-plan`'s turn.

### /debrief

**When:** a `=== COMPLETION REPORT ===` block comes back. **Argument:** sub name.

Matches on revision, then builds the whole change set and **shows it before writing
anything** — frontmatter, `current.md`, `## Key decisions`, full ADR drafts, the brief
to `closed`. Partial approval is accepted.

Invoked with no report — a run that died before reaching `/handoff-close` — it
reconstructs from `git log` and labels the result *reconstructed, not reported*.
Commits show what landed and never what diverged, what the brief got wrong, or what
hurt, so a reconstruction files no ADRs and routes no lessons.

Three things it treats as more than bookkeeping: a `BRIEF WAS WRONG` entry is the vault
having been wrong about the repo, so the vault text that carried the claim gets
corrected; a verification claim with no command and no output behind it is listed as
*asserted, not shown* rather than believed; and each pain point comes back as a
ready-to-run `/capture-lesson` for the repo side, because a lesson that becomes a hook
stops happening to everyone and a lesson written up here stops happening to nobody.

Then `/rollup`, and an *offer* of `/ship` — never `done` from a report alone, since a
report is the agent's account of its own work.

---

## Summary

| Skill | Trigger | Writes |
|---|---|---|
| `/day-log` | the journal timer, weekdays 23:30; by hand otherwise | `01-daily/<date>.md` — or nothing |
| `/week-recap` | the journal timer, Mondays 06:00 after `/day-log`; by hand otherwise | `05-weekly/<week>.md` — or nothing |
| `/project-status` | before a work session | nothing (terminal only) |
| `/ship` | a sub-project is finished | `<sub>/summary.md` + `context.md` + `/rollup` |
| `/rollup` | after any sub status change | `02-projects/<main>/_index.md` |
| `/project-init` | new project or sub | `02-projects/…` + the `AGENTS.local.md` tree |
| `/decision-needed` | facing a choice | `decisions/ADR-NNN.md` + `context.md` |
| `/adr` | choice already made | `decisions/ADR-NNN.md` + `context.md` |
| `/supersede` | a decision gets reversed | old + new ADR + `context.md` |
| `/doc-build` | handing a project to a teammate | `<project>/doc.html` |
| `/team-doc` | explaining a sub to coworkers | `<sub>/<sub>-team-doc.md` + `.html` |
| `/md-html` | a standalone page of one `.md` | `<file>.html` |
| `/handoff` | spec + ADRs are settled | `<sub>/specs/…-brief-N-….md` |
| `/handoff-plan` | a sub's work spans several briefs | `<sub>/specs/…-plan-….md` + the phase's briefs |
| `/handoff-orchestrate` | start, resume, stop or check a phase | the watchdog timer; prints the command |
| `/handoff-revise` | a review block comes back | the brief, revision bumped |
| `/handoff-split` | a brief is too big for one session | N briefs |
| `/debrief` | a completion report comes back | `current.md` + `context.md` + ADR drafts + `/rollup` |

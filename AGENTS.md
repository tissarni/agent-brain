# Vault Constitution

Read `AGENTS.local.md` next, if it exists: it adds to this file and wins on a conflict.

## Agent conduct (token discipline)
- Be concise: answer first, no preamble, no restating the question, no closing recap.
- Route mechanical work — rename, reformat, summarize a file, scrape or collect text,
  bulk grep-and-list — to a `haiku` sub-agent (`Agent` tool, `model: haiku`). Keep the
  session's own model for judgment calls.
- Never suggest `/compact` as a cost-saving measure. Compaction costs a summary and loses
  detail; the cheap move is `/clear` between tasks (Level 5).
- Pick model and effort once at session start and never switch mid-session: a switch
  discards the whole prompt cache.

## Vault structure
| Folder | Purpose |
|---|---|
| 00-inbox/ | Raw captures, unfiled |
| 01-daily/ | Daily notes YYYY-MM-DD.md |
| 02-projects/ | Main projects, each with subprojects/ under it |
| 03-knowledge/ | Permanent reference notes |
| 05-weekly/ | Weekly review notes YYYY-WNN.md |

## Agent config layout — vendor-neutral first
This vault must stay usable from any agent tool, not just Claude Code.

| Path | Role |
|---|---|
| `AGENTS.md` | **This file. The constitution.** Open standard, read by 25+ tools. |
| `CLAUDE.md` | Pointer to this file. Claude Code reads it, then comes here. |
| `.agents/skills/` | **Canonical skills.** Cross-client Agent Skills convention. Edit here. |
| `.claude/skills/` | Generated mirror, for Claude Code only. Never edit directly. |
| `AGENTS.local.md` | **Yours**: who you are, the active projects, local rules. Read right after this file; wins on a conflict. |
| `brain.env` | **Yours**: the settings scripts read, one `KEY=value` per line. Never sourced, no secrets. |
| `template.manifest` | The paths the template owns. Everything else is yours. |

Edit a skill in `.agents/skills/<name>/SKILL.md`, then run `./sync-skills.sh --apply`. Never
edit the `.claude/` mirror; if the script refuses a diverged mirror, read its message rather
than reaching for `--force`. Substantive rules go in `AGENTS.md`; `CLAUDE.md` stays a pointer.

Template updates replace the files `template.manifest` lists, so no person's, company's or host's
name goes in one: it goes in `AGENTS.local.md`. A rule for one skill goes under `### /<skill>` in
its `## Local rules`, applied as that skill's last step. `./template-files.sh` lists the
template-owned files. Once this brain pulls from a `template` remote, the pre-commit hook and
`auto-commit.sh` warn on a commit that changes one, since the change must land in the template
too or the next update conflicts. Template changes come in with `./setup.sh --update`, a merge,
never a rebase, and the `template` remote is never pushed to.

The handoff kit is not in this vault. The `handoff-launch`, `handoff-orchestrate` and
`brief-check` commands, their tests, the watchdog units and the repo-side skills
`handoff-review` and `handoff-close` live in their own repo, the handoff kit. Change them
there, through that repo's PRs; once a change is merged, pull the clone and run its
`install.sh` (it relinks the commands and reinstalls the skills and the watchdog units,
keeping `~/.config/handoff/config.env`). Plans for the kit run in a separate worktree, because
the kit refuses a plan on the clone the installed commands run from. The kit follows its own
`AGENTS.md`: it names no person, host, note path or decision-record number of this vault, and
"vault" is its own word for the notes repo it works with — the one exception to the boundary
section's ban on that word.

## What is a project?
Exactly two levels. Full contract: `02-projects/_templates/CONVENTION.md`.

- **main** = one deployable system or coherent domain with its own architectural
  identity. Survives deleting every feature currently planned for it.
- **sub** = one feature, incident, migration or investigation *inside* a main.
  Lives in `02-projects/<main>/subprojects/<sub>/`.

Signal: would future-me need separate context to work on this? Yes → its own sub.
Would it still exist if that system were deleted? Yes → its own main.
Never a third level; a sub that needs subs is a main.
Trivial fixes and refactors are neither — they get a daily log entry, nothing more.
The active projects tree, terse, is in `AGENTS.local.md` § Active projects; `/project-init` adds to it and `/rollup` checks it.

## Project path resolution (every skill relies on this)
Given a project name:
1. `02-projects/<name>/` exists → it is a **main**.
2. Otherwise `02-projects/*/subprojects/<name>/` → it is a **sub**.
3. Confirm with the `kind:` field in its `context.md` frontmatter.

Cross-main work lives under the main that **owns the code being changed**, with the
other main in its `related:` frontmatter. It is never duplicated into two folders.

## Task workflow
1. Plan in vault (project-status → decision-needed → write current.md)
2. Execute with Claude Code **rooted in the repo** — start the session from the repo
   directory, never from the vault reaching in: hooks and settings load from
   the session's project dir, so a vault-rooted session has zero guard coverage
3. Never create a bridge `.md` inside the repo — see the boundary rule below

## Token optimization rules (READ THIS)
A turn's cost is the whole context re-read, not what was just added. Levels 0–4 shrink what
a session *starts* with; Level 5 shrinks what it *accumulates*. On one measured brain the
split was 12–18% to 82–88%, so optimizing only the load optimizes the smaller term.

### Level 0 — Read only what is necessary
Each skill specifies exactly which files to read. Never scan entire folders unless the
skill explicitly requires it. Order of preference:
1. `_index.md` of a main → the state of every sub in **one** read
2. context.md summary → cheaper than reading raw ADRs
3. Frontmatter grep → cheaper than reading file body
4. Raw file → last resort only

### Level 1 — _index.md answers cluster-wide questions
"State of X and everything under it" is one read of `02-projects/<main>/_index.md`. Never
reconstruct it by opening sub-projects; if it looks stale, run `/rollup <main>`.

### Level 2 — context.md is the source of truth for decisions
When context.md has a "Key decisions" section, read that instead of the ADR files. Open an
ADR only if the user explicitly asks for full detail. Never read both.

### Level 3 — Frontmatter before body
Check a daily note's `projects:` frontmatter first; skip the file if it does not include
the project you need.

### Level 4 — Finished work is closed
Never read the body of a sub whose `status: done` — its `summary.md` at most. `_archive/`
is never globbed, scanned or auto-read; open it only on an explicit request.

### Level 5 — A session is a cost multiplier
Cost scales with `context × turns`. Levers, in order of size:
1. **`/clear` when the task changes, not when the context is full.** `autoCompactWindow`
   is 250k here; a `/clear` before that is free and restores a ~50k floor, a compaction
   costs a summary and loses detail.
2. **Delegate read-heavy exploration to a read-only subagent.** On one measured brain,
   `Bash` and `Read` results were ~47% of what filled a session; a subagent reads 300k and
   returns 500 tokens.
   **Standing authorization:** read-only subagent delegation (read, search, report — never
   Edit, Write or anything that pushes) is pre-approved here; treat it as requested. Some
   hosts inject a session-level "no subagent unless requested" rule; this line is that
   request. Delete it to revoke. The subagent ban in `/handoff-revise` covers only runs
   that end in a push.
3. **Write a file in one pass.** A `Write`'s input stays in context permanently.

## Do not
- Create speculative folder structure, or a third project level
- Modify frontmatter you didn't create — except `status`/`summary`/`blocker` on a
  sub you are actively working, which must stay true or the rollup lies
- Hand-edit any `_index.md` — change the sub's frontmatter and run `/rollup`
- Generate ADRs for fixes or minor refactors
- Read entire folders when a targeted path is known
- Read ADR files when context.md already summarizes them
- Read a `done` sub-project's body, or anything under `_archive/`
- Carry a finished task's context into the next one — `/clear` between them
- Read files inline to answer a broad "where is X / does Y exist anywhere" question
  when a read-only subagent can return the conclusion instead

## Vault ↔ code-repo boundary (STRICT — the vault is MY personal memory, not team-shared)
Applies when working inside a code repo (the repos under `CODE_ROOT` in `brain.env`). The split is by audience
and lifetime, not by file type:

| Test | Goes |
|---|---|
| A teammate acting on it wrongly **breaks something** | repo |
| True today, wrong next month (state, progress, blockers) | vault |
| Only I would be confused without it (reasoning, exploration) | vault |

### Allowed in a repo — closed list, extend only by ADR
`AGENTS.md` (root + nested per subsystem) · `CLAUDE.md` (pointer only) ·
`.claude/settings.json` · `.claude/settings.local.json` (gitignored) · `.mcp.json` ·
`.agents/skills/**` + `.claude/skills/**` · toolchain pin (`mise.toml`, `.devcontainer/`)
A repo's own `README.md`, `CHANGELOG.md` and real project docs are normal files, out of scope.

### Forbidden in a repo — no exceptions, gitignored or not
ADRs · design specs · implementation plans · `current.md`-style state · planning notes ·
TODO scratch files. **ADRs never enter a repo. There is no `docs/adr/`.**

### Content rules for every allowed file
- Never reference the vault — no "vault", no "see ADR-00X", no `02-projects/...` paths —
  in files, code, comments, commit messages or PRs.
- Never carry vault state: no `verified YYYY-MM-DD` stamps, no status markers.
- Per line: *equally useful to someone who has never heard of this vault?* Yes → repo. No → vault.

### The compression rule — how decisions reach the repo
ADRs stay here. **Every ADR whose decision constrains future code gets its ruling plus one
line of why in `AGENTS.md`** — never the deliberation or the alternatives. Resolve
supersession chains first. The one-line *why* is what stops the decision being re-litigated.

### Flow
One-way: the vault drafts, the repo publishes; the repo is never read back. On an
**operational fact** the repo wins; on **reasoning or history** the vault wins.

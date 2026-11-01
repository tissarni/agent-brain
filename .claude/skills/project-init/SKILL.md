---
name: project-init
description: Scaffold a new main project or sub-project in the vault. Use when user says "new project", "init project", "create project [name]", "new subproject".
---

Arguments: project name in kebab-case, optionally `under <main>` (e.g. `login-timeout under web-app`).

Read `02-projects/_templates/CONVENTION.md` first — it is the contract. Templates live beside it.

## Step 1 — main or sub?
If `under <main>` was given, it is a **sub**. Otherwise decide, and state which you chose:

- **sub** — a feature, incident, migration or investigation *inside* an existing system.
  Signal: the code it touches already belongs to a main project.
- **main** — one deployable system or coherent domain with its own stack identity.
  Signal: it survives deleting every feature currently planned for it.

If genuinely ambiguous, ask once, recommending **sub** — sub-projects are cheap to
promote later, mains are expensive to merge back.

Never create a third level. A sub that needs subs is a main.

## Step 2a — scaffold a SUB
```
02-projects/<main>/subprojects/<name>/
├── context.md    ← from _templates/sub-context.md
├── current.md    ← from _templates/sub-current.md
└── decisions/
```
Fill the frontmatter completely — `parent:` and `summary:` are what the parent's
`_index.md` is built from. Set `status: active`. Add `blocker:` only if already blocked.
Add `related:` for any other project this touches; that work is **not** duplicated
into a second folder.

Body rules: link up to `[[02-projects/<main>/context]]` and do **not** restate the
parent's stack, architecture or constraints. Scope, why-it-exists, and current state only.

Add `[[backlinks]]` to the parent and to everything in `related:`.

## Step 2b — scaffold a MAIN
```
02-projects/<name>/
├── README.md     ← 5-line pointer
├── context.md    ← from _templates/main-context.md
├── _index.md     ← the step-3 /rollup writes it (empty-state file)
├── current.md
├── decisions/
└── subprojects/  ← create the empty dir
```

## Step 3 — merge policy
After scaffolding, ask only for a main whose `repo:` is a local Git checkout, or a sub
whose `repo:` differs from its main's and is a local Git checkout. If `repo: -`, say
there is no code repository and skip. If it is not a Git checkout, do not ask; say the
choice can be set later with `handoff-policy policy-init --repo <path> --choice true|false`.
Only ask when `git -C <repo> remote get-url origin` contains `github.com`; otherwise say
the repository stays manual because auto-merge is GitHub-only. If `handoff-policy` is
unavailable, do not ask; say: "`handoff-policy` is unavailable; check that `~/.local/bin` is on PATH and that handoff kit v1.1.0 or newer is installed; update with `./setup.sh --update` if needed."
Before asking, explain: auto = complete feature PRs into `dev` are squash-merged after a
final review and green CI; `dev` → `main` always stays manual. Show the proposed value
from `handoff-policy default-get` beside the current value from
`handoff-policy policy-get --repo <path>`. Let the user confirm or flip it, then run
`handoff-policy policy-init --repo <path> --choice true|false` and report its output.
The kit's store is the only record of this choice; write it nowhere else.

## Step 4 — wire it up
1. If `AGENTS.local.md` is missing, create it with three headings, one blank line after
   each: `## Who I am`, `## Active projects` and `## Local rules`.
2. Run `/rollup <main>`, for a sub's main or for the new main itself. It indexes the project
   and writes the main's tree line. **Not optional** — an unindexed project is invisible to
   every future session. Never add a tree line by hand: `/rollup` would duplicate it.
3. Do **not** create any `.md` in the code repo. Bridge context stays vault-side.
4. Last, apply the rules filed under `### /project-init` in `AGENTS.local.md` § Local rules, if there are any.

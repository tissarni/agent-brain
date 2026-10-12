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
├── _index.md     ← run /rollup (writes the empty-state file)
├── current.md
├── decisions/
└── subprojects/  ← create the empty dir
```

## Step 3 — wire it up
1. For a sub: run `/rollup <main>` so the parent index picks it up. **Not optional** —
   an unindexed sub is invisible to every future session.
2. Add one line to the `## Active projects` tree in `AGENTS.local.md`, nested under its
   main for a sub. If that file is missing, create it first with three headings:
   `## Who I am`, `## Active projects` and `## Local rules`.
3. Do **not** create any `.md` in the code repo. Bridge context stays vault-side.
4. Last, apply the rules filed under `### /project-init` in `AGENTS.local.md` § Local rules, if there are any.

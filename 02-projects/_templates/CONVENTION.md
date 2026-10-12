# 02-projects convention — main / sub

Two levels. No third. A project is either a **main** (one deployable system or
coherent domain) or a **sub** (one feature, incident, or investigation inside a main).

```
02-projects/<main>/
├── README.md          # 5-line pointer. Read only if lost.
├── context.md         # global view: what it is, stack, constraints, risks. HAND-WRITTEN.
├── _index.md          # rollup table of all subs. GENERATED from sub frontmatter. Never hand-edit.
├── current.md         # main-level task (server/system-wide work only)
├── decisions/         # ADRs about the main itself
└── subprojects/<sub>/
    ├── context.md     # what this sub is, scoped. Links up to parent.
    ├── current.md     # the live task
    ├── decisions/     # ADRs scoped to this sub
    ├── specs/         # design docs + implementation plans (optional)
    ├── summary.md     # written when status hits `done` — replaces reading anything else
    └── _archive/      # NEVER auto-read. Bulky finished specs/plans/action-lists.
```

## Frontmatter schema — this IS the machine-readable layer

`_index.md` is generated from these fields **only**. Bodies are never parsed.
Keep them accurate; a stale `summary` poisons every future read.

### main `context.md`
```yaml
---
project: web-app              # == folder name, kebab-case
kind: main
status: active                # see vocabulary below
created: YYYY-MM-DD
updated: YYYY-MM-DD
repo: /path/to/repo           # or `-` if not code
branch: main
summary: >-                   # ≤160 chars, one line, no markdown
  what this system is, in one sentence
tags: [project, main]
---
```

### sub `context.md`
```yaml
---
project: login-timeout
kind: sub
parent: web-app               # folder name of the main. REQUIRED.
status: active
created: YYYY-MM-DD
updated: YYYY-MM-DD
repo: /path/to/repo
branch: feat/whatever
summary: >-                   # ≤160 chars — this becomes the _index.md row
  what this sub does
blocker: >-                   # ≤120 chars, or omit the key entirely if unblocked
  what is stopping it right now
related: [api, mobile-app]     # other projects touched. Folder names. Optional.
team_doc: none                # only when the user decided this sub needs no team doc; add `# why`. Omit otherwise.
tags: [project, sub]
---
```

## Status vocabulary — closed set, no improvising
| Status | Means | Rollup section |
|---|---|---|
| `active` | being worked on now | Active |
| `blocked` | cannot progress; `blocker:` MUST be set | Active |
| `impl-done` | code written + tested, not shipped/merged/pushed | Active |
| `done` | shipped and verified; `summary.md` exists | Done |
| `paused` | deliberately parked, not blocked | Paused |

## Read order — cheapest first, always
1. `_index.md` of the main → answers "state of everything" in **one read**
2. main `context.md` → architecture, stack, cross-cutting constraints
3. sub `current.md` → the live task, only for the one sub you need
4. sub `context.md` → only if `current.md` assumes background you lack
5. `decisions/*.md` → **only** when the user asks for full ADR reasoning
6. `_archive/**` → only on explicit request. Never globbed, never scanned.

Never read a `done` sub's body. Read its `summary.md` if you need it at all.
Never read both `context.md` and the ADR it summarises.

## Rules
- A sub's `parent:` must match its folder location. Path and frontmatter agree or the rollup is wrong.
- Cross-main work lives under the main that **owns the code being changed**, with the
  other main listed in `related:`. It is never duplicated into two folders.
- New sub → always links to its parent's `context.md` and to anything in `related:`.
- When a sub reaches `done`: write `summary.md`, move bulky specs/plans to `_archive/`,
  set `status: done`, regenerate the parent `_index.md`.
- `_index.md` carries a `<!-- GENERATED -->` marker. If you hand-edit it, you have broken it.
- Never create a third level. A sub that needs subs is a main.

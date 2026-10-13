# agent-brain

The developer's working memory and the control room of their agent work: notes on every
project, the decisions behind them, the skills agents follow, and the briefs that hand a
settled decision to an unattended agent session in a code repository.

Plain Markdown, opened in Obsidian as a vault and read by agent sessions (Claude Code
first, any tool that reads `AGENTS.md` in principle).

## Start here

- [AGENTS.md](AGENTS.md) — the constitution: layout, read order, project rules, the
  vault ↔ code-repo boundary. Every agent session loads it.
- `AGENTS.local.md` — yours: who you are, your projects, your local rules. It is read right
  after `AGENTS.md` and wins on a conflict.
- [SKILLS.md](SKILLS.md) — what each of the 18 template skills does and when it runs; a brain
  may add its own.
- [CONVENTION.md](02-projects/_templates/CONVENTION.md) — mains and subs, the frontmatter
  schema, the status vocabulary.

## Layout

| Path | What it holds |
|---|---|
| `00-inbox/` | Raw captures, filed by hand |
| `01-daily/` | Daily notes, `YYYY-MM-DD.md`, written by `/day-log` |
| `02-projects/` | Mains and their subs; `_templates/` holds the templates and `handoff-defaults.yml` |
| `03-knowledge/` | Permanent reference notes |
| `05-weekly/` | Weekly recaps, `YYYY-WNN.md`, written by `/week-recap` |
| `.agents/skills/` | The canonical skills — edit here |
| `.claude/skills/` | Generated mirror for Claude Code — never edit |
| `.claude/settings.json` | The hooks |
| `AGENTS.md`, `CLAUDE.md` | The rules; `CLAUDE.md` only points to `AGENTS.md` |
| `AGENTS.local.md` | This brain's own rules, projects and owner; the template never ships it |
| `brain.env` | This brain's settings, one `KEY=value` per line, the first one of a key wins; never sourced, no secrets |
| `template.manifest`, `template-files.sh` | The paths the template owns; the script lists them |
| `.githooks/pre-commit` | Checks the skills mirror, and warns on a change to a template-owned file |
| `sync-skills.sh` | Checks the mirror; `--apply` re-copies it |
| `auto-commit.sh` | The Stop hook: commits each session's edits |
| `themes/<name>/` | The HTML theme `HTML_THEME` names: `theme.css`, optional `logo.svg` or `logo.png`; local, optional |
| `reconcile-repos.sh` | Reports each tracked repo's git state; `/week-recap` runs it |

A **main** is one system (an app, a database, a domain); a **sub** is one feature,
incident or investigation inside it, at `02-projects/<main>/subprojects/<sub>/`. Each
main's `_index.md` is generated from its subs' frontmatter by `/rollup`.

## How it runs

- **Obsidian** is the reader and editor for the notes; `.obsidian/` holds its settings.
- **Agent sessions** start in this directory, load `AGENTS.md`, and act through skills.
- **The Stop hook** (`auto-commit.sh`) runs at the end of every session: it syncs the
  skills mirror, stages everything, and commits as `vault: <areas> (<n> files)`. It never
  pushes; push `main` yourself.
- **The journaling skills** (`/rollup`, `/day-log`, Mondays `/week-recap`) run from system timers (systemd on Linux and WSL2, launchd on macOS) that
  `./setup.sh --journal y` installs: weekdays 23:30 `/rollup` and `/day-log`, Mondays 06:00 the
  same, then `/week-recap`. By hand otherwise.
- **The handoff kit**, a separate repository
  ([tissarni/handoff-kit](https://github.com/tissarni/handoff-kit)), provides the
  `handoff-launch`, `handoff-orchestrate` and `brief-check` commands, the repo-side skills
  `/handoff-review` and `/handoff-close`, and the watchdog timer. It runs the loop: review,
  revise, run, close, debrief, each a fresh session.

## Prerequisites

`setup.sh` checks for these and stops with a fix when one is missing: git, bash 4 or newer,
python3, node, curl, the GNU coreutils, findutils, sed and grep, and pgrep;
flock and setsid (Linux and WSL2 only: on macOS, what uses them falls back to python3 or a
lock directory).
When a package is missing, it offers to install it (with `--yes`, it does): Homebrew on macOS
(which also brings bash 4), the system package manager (`apt-get` or `dnf`) on Linux.

You also need:

- An agent CLI, installed and logged in. Claude Code is the default; setup checks
  `claude auth status`.
- Optional: `gh` or `glab`, for pull requests; Obsidian, to read the notes as a vault.

## Setup on a new host

```
git clone https://github.com/tissarni/agent-brain my-brain
cd my-brain && ./setup.sh
```

`setup.sh` takes a fresh clone to a working brain and is safe to run again: it never overwrites
a file of yours. It asks five questions: your name, role, working languages, principles, and the
root directory of your code repos. With `--yes` it asks nothing and the flags answer instead:
`--name`, `--role`, `--languages`, `--principles`, `--code-root` (the defaults are your git
name, `software engineer`, none, `TDD, SOLID, YAGNI, KISS, DRY` and `~/projects`).
`--backends claude,hermes,devin` picks the agent backends, `--kit <dir>` uses a kit checkout
instead of the one pinned in `handoff-kit.pin`, and `--remote <name>|none` creates a private
GitHub repository for the brain.

Three extras are asked, or set by flag: `--linger y|n` keeps your user services running with no
login session, `--telegram y|n` sets up Telegram notifications, and `--journal y|n` installs the
journal timers (`--journal-daily HH:MM`, `--journal-weekly HH:MM`). `--hermes-hooks y|n` answers whether to
register the brain's hooks with hermes (see Backends).

**Update.** `./setup.sh --update` merges the template's latest into the brain, never rebases,
and re-runs the idempotent steps. The clone's `origin` becomes the `template` remote, with its
push URL set to `DISABLED`: it is only ever pulled from. Commit your changes first. It lists the
template-owned files you changed locally, since those may conflict; a conflict stops with
`git merge --abort` as the way back.

**The example.** Setup copies a demo main, `02-projects/example/`, and a demo repository next
to your code repos, to try the handoff kit on. `./setup.sh --remove-example` deletes both, only
what setup made, and nothing returns on a later `--update`. The demo repository has no GitHub or
GitLab remote, so a real pull request needs a repository on one of them.

**Platforms.** Linux, WSL2 and macOS. On macOS, setup installs bash 4 and the GNU tools
through Homebrew when they are missing.

## Your first loop

Setup ends by printing the command for the example brief. Try it with `--dry-run` first: it
starts nothing and shows the resolved configuration.

```
handoff-launch loop <example brief> --gate auto --backend claude --dry-run
handoff-launch loop <example brief> --gate auto --backend claude
```

The loop is review, revise, run, close, debrief, each a fresh agent session. Without
`--dry-run` it starts those sessions on your own account, so they use your quota or are billed
to you.

## Backends

`claude` is the default. `--backends claude,hermes,devin` picks others, and `DEFAULT_BACKEND`
in `brain.env` is the backend each skill offers by default.

Setup asks whether to register the Bash guard and the auto-commit as hermes hooks, but only
when hermes is a chosen backend, is installed, and `~/.hermes` exists. The answer defaults to
No, so pressing Enter leaves hermes unguarded; `--yes` or `--hermes-hooks y` registers without
asking. Registering writes the default profile (`~/.hermes/config.yaml`) and records the
consent in `~/.hermes/shell-hooks-allowlist.json`.
The hooks live in the default profile only (other profiles, `-p <name>`, are not guarded), and
both act only in a hermes session started in the brain or below it, or with `--in`:
`terminal.cwd` and gateway sessions are not covered. Running `hermes hooks doctor` or
`hermes hooks test` from the brain fires the allowlisted hooks there, so it commits whatever is
dirty. `--hermes-hooks y|n` answers the question. An existing brain first runs
`./setup.sh --update` (its old `setup.sh` rejects the new flag), then
`./setup.sh --update --hermes-hooks y` to register them later. `hermes hooks revoke '<command>'`
withdraws one. `--update` refreshes the recorded script times, which re-approves a guard or
auto-commit that a template update changed. The context guard runs only under Claude Code.
Under devin, run `sh ./auto-commit.sh` by hand after a session (the file is not executable, and
every caller runs it through `sh`). The journal runner commits after its own runs.

## The docs site

The Stop hook rebuilds an HTML mirror of the brain outside the repo, at `DOCS_SITE_DIR` in
`brain.env`, or by default `~/.local/share/<brain directory name>-docs/site`. Serve that
folder, never the brain's root. For a clone named `my-brain`:

```
python3 -m http.server --directory ~/.local/share/my-brain-docs/site 8000
```

## Changing a skill

1. Edit `.agents/skills/<name>/SKILL.md` — never the `.claude/skills/` copy.
2. `sh sync-skills.sh --apply`, then `sh sync-skills.sh` must print `in sync — <n> skills`.
3. Update the skill's section and summary row in [SKILLS.md](SKILLS.md).
4. A rule only this brain needs goes under `### /<skill>` in `AGENTS.local.md` § Local
   rules instead, applied as that skill's last step.
5. A change to a template-owned file (`./template-files.sh` lists them) must also land in the
   template, or the next template update conflicts.
6. A skill that runs unattended (`/debrief`, `/handoff-revise`, `/rollup`, `/day-log`,
   `/week-recap`) has nobody watching: change only what you mean to change.

Never use `sync-skills.sh --force`: it mirrors anyway, discarding edits made in the
mirror.

## Publish guard

A brain writes briefs, commits and PR texts for your code repositories. When one of them is public,
any private name in that text (a client, a colleague, a host, an employer) is public for good: a
pushed commit stays fetchable by its hash, a PR text keeps its old revisions, and a word in a PR
title ends up in the squash commit. `publish-guard.sh` refuses such text before it leaves. It is
opt-in, one command per public clone:

```bash
./publish-guard.sh install <clone>
```

That writes the clone's `pre-push` hook (shared by its worktrees) and links `publish-guard` into
`~/.local/bin`. The hook checks what a push adds: commit messages, author and committer, paths,
file contents (binary too), branch and tag names. `install` refuses, writing nothing, when the
list has no pattern, when `core.hooksPath` is set (git would then ignore the hook), when the clone
already has another `pre-push` hook (it never overwrites or chains one), or when `publish-guard` in
`~/.local/bin` is something else. `./publish-guard.sh guarded <repo>` exits 0 when a repo's hook
runs the gate, 1 when not, 2 when it is not a repository.

**The list.** `publish-guard.patterns` in the brain root holds one extended regex per line, matched
case-insensitively; blank lines and `#` lines are ignored. `install` creates it with a header and no
pattern, and refuses until you add one. The brain owns it and commits it like a note; the template
never holds a real list, and it never goes into a public repository. `PUBLISH_GUARD_PATTERNS`
points elsewhere. A missing, empty or invalid list refuses rather than passes.

**Four audits**, each printing `where: matched words` and exiting 1 on a hit:

- `history <repo> [<rev>...]`: every commit reachable from the revs, default every ref.
- `tree <dir>`: every file under a directory, contents and names.
- `files <file>...`: plain files, such as a brief or a PR body before it is sent.
- `github <owner/repo>`: issue, PR, review and release texts, branch and tag names, description
  (needs `gh`).

Set `PUBLISH_GUARD_WHERE_ONLY=1` in a public CI log: locations print with any matching part replaced
by `[hidden]`, never the words.

This repository audits its own GitHub texts and history with `.github/workflows/publish-guard.yml`,
on every PR event (a title or body edit included) and every push to `main`. The list comes from the
Actions secret `PUBLISH_GUARD_LIST`; without it the audit skips. The log shows where a hit is, never
the word. Copy the workflow for a public repository of your own.

On macOS the script needs GNU grep, GNU sed and bash 4.2 or later:
`brew install grep gnu-sed bash`. It finds GNU grep as `ggrep`, then `grep`, and refuses without it.
Tests: `bash tests/publish-guard.sh`.

## Privacy

A brain holds its owner's notes, so keep its repository private. Template-owned files hold no
person's, company's or host's name: those go in `AGENTS.local.md`, `brain.env` or local files.

## License

MIT, see [LICENSE](LICENSE).

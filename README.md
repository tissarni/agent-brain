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
| `brain.env` | This brain's settings, one `KEY=value` per line; never sourced, no secrets |
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
journal timers (`--journal-daily HH:MM`, `--journal-weekly HH:MM`).

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

The hooks in `.claude/settings.json` (the Bash guard, the context guard, the auto-commit on
Stop) run only under Claude Code. Under hermes or devin, run `sh ./auto-commit.sh` by hand
after a session (the file is not executable, and every caller runs it through `sh`). The
journal runner commits after its own runs.

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

## Privacy

A brain holds its owner's notes, so keep its repository private. Template-owned files hold no
person's, company's or host's name: those go in `AGENTS.local.md`, `brain.env` or local files.

## License

MIT, see [LICENSE](LICENSE).

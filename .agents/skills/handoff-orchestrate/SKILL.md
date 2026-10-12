---
name: handoff-orchestrate
description: Resolve a plan, pre-check it, install its 30-minute watchdog timer, and print the exact start/resume/stop command — never launches the driver itself. Use when user says "handoff-orchestrate", "start the phase", "install the watchdog", "orchestrate status", "stop the phase", "resume the phase".
---

Arguments: a plan path (relative to vault, as `/handoff-plan` prints it) or a sub-project
name (resolve to its newest non-`done` plan), plus a form — `start`, `resume`, `stop`,
`status`. If the form is not named, read the plan's `orchestration:` and pick the only one
that makes sense (below); if more than one would, ask.

This skill prepares and reports. It **never runs `start`, `resume` or `stop`** — those
launch or kill a detached driver that chains `handoff-launch loop` stages, and the user
runs every launcher stage themselves. The one thing this skill executes directly is `status`,
because it only reads files.

## 1. Resolve

Given a sub name: `specs/*-plan-*.md` also matches a plan's own `.status.md` file and any
debrief note whose name happens to carry `-plan-`; only a real plan has an
`orchestration:` key, so list this sub's plans with:

```
/usr/bin/grep -l '^orchestration:' 02-projects/<main>/subprojects/<sub>/specs/*-plan-*.md
```

and take the one with the newest `updated:` whose `orchestration:` is not `done`. Given a
path, use it as-is (absolute, or relative to the vault root). Refuse if none exists —
that's `/handoff-plan`'s job, not this one.

Read the plan's frontmatter: `orchestration:`, `phase:`, `backend:`, `model:`, `branch:`,
`notify:`. `BASE="${PLAN%.md}"`; the runtime files are `$BASE.status.md`, `.events.log`,
`.lock`, `.baseline`, `.stage`, `.driver.log`, `.tick` — read them, never write them by
hand.

Map `orchestration:` to the form this call is for:

| `orchestration:` | Valid form(s) | Refuse otherwise with |
|---|---|---|
| `planned` | `start` | "not started yet — run with `start`" |
| `running` | `stop`, `status` | "already running — `start`/`resume` would race the driver; use `status` or `stop`" |
| `paused` | `resume`, `status` | "paused, not broken — a hand fix isn't needed, just `resume`" |
| `broken` | `resume`, `status` | "broken: `<reason>` from the status file — fix that first, then `resume`" |
| `phase-done` | none of these | "phase finished — this is `/handoff-plan`'s turn (next phase), not orchestrate's" |
| `done` | `status` | "plan is done — every phase closed; a human reviews and squash-merges the PR the status file names" |

## 2. `status` (the only form this skill runs)

```bash
handoff-orchestrate status <plan>
```

Then show the full `$BASE.status.md` (it is short and Obsidian-readable — verdict line,
per-brief table, last twenty events, and the phase summary once one exists), and the
timer's own state for this instance:

```bash
systemctl --user is-active  "handoff-watchdog@$(systemd-escape "<plan path relative to vault>").timer"
systemctl --user is-enabled "handoff-watchdog@$(systemd-escape "<plan path relative to vault>").timer"
systemctl --user list-timers "handoff-watchdog@*" --all
```

A verdict of `RUNNING` with an inactive or missing timer means the watchdog isn't
watching — say so and offer to reinstall it (§4), same as a `resume` would.

## 3. Vault-side pre-check (`start` and `resume` only)

Before touching systemd, run the checks this session can do without racing the driver —
catches most pre-flight failures before the user spends a launch on them. Do
**not** claim this replaces the script's own pre-flight; it's the free half.

```bash
cd <repo from the sub's context.md> && git status -sb && git branch --show-current \
  && git rev-list --count "origin/<plan branch>..HEAD" && git rev-list --count "HEAD..origin/<plan branch>"
```

- the plan's `branch:` (or the phase's override) **need not exist and the repo need not
  be on it** — `start`/`resume` check it out, or cut it from `origin/<base>` and push it.
  Never ask the user to create a branch or open a PR; say the script will. The
  `rev-list` lines simply fail when the branch is new; that is not a finding.
- when the branch does exist, `HEAD..origin/<branch>` must be 0 (nothing to pull) — a
  stale local HEAD is the most common real failure here
- the dirty set shown by `git status -sb`, read against `$BASE.baseline` if it exists
  (`resume` only — `start` has no baseline yet, so any dirty tree is just noted, not
  judged)
- `notify:` non-empty in the plan → `~/.config/handoff/notify.env` exists, mode `600`,
  and both `TELEGRAM_BOT_TOKEN=` / `TELEGRAM_CHAT_ID=` lines are present (grep for the
  keys; never print the values — they're secrets). First-time setup, if the file is
  missing:
  1. Message **@BotFather** on Telegram, `/newbot`, keep the token it gives you.
  2. Send the new bot any message from the account that should receive alerts.
  3. `curl -s "https://api.telegram.org/bot<token>/getUpdates"` → the chat id is
     `.result[-1].message.chat.id`.
  4. Write `~/.config/handoff/notify.env` (`chmod 600`) with `TELEGRAM_BOT_TOKEN=` and
     `TELEGRAM_CHAT_ID=`, never inside the vault.
  Tell the user to do this themselves if secrets aren't already in place; don't collect the
  token through this session.
- backend binary on `$PATH` for the plan's `backend:` (`which claude` / `hermes` /
  `devin`) — presence only; auth/profile checks are the script's job
- the checkout lock: `cat "$(git -C <repo> rev-parse --absolute-git-dir)/handoff-plan.lock"`
  names the plan holding the checkout, if any. When it names another plan whose
  `orchestration:` is `running`, `paused` or `broken`, the script will refuse with
  `preflight:checkout` and print the worktree command. Say so now.

Report every failure found, in one place, before §4. A clean pre-check is not a green
light on its own — the script's pre-flight is the one that actually decides.

## 4. Confirm the watchdog timer (`start` and `resume`)

`handoff-orchestrate start|resume` arms the plan's timer itself (`arm_watchdog`:
`enable --now` on the plan's instance of the two template units), so a start run
straight from the printed command is covered. Arming it here beforehand is still
harmless and lets the report confirm it; the script then prints `(already active)`.

The template units, `~/.config/systemd/user/handoff-watchdog@.service` and
`handoff-watchdog@.timer`, are shared by every plan. They are the handoff kit's
`systemd/` files, copied there by the kit's `install.sh`; this skill never writes or
edits them. If either file is missing, say that the kit's `install.sh` has not run on
this host and must run before `start`, and stop.

`%I` is the *unescaped* instance name, so the plan's path — slashes and all — round-trips
through `systemd-escape` without a lookup table. Then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now "handoff-watchdog@$(systemd-escape "<plan path relative to vault>").timer"
```

`tick` is a no-op before `start` has ever run (`[ -f "$LOCK" ]` is false → it logs and
exits 0 — see the orchestrator's `tick()`), so enabling the timer here, before
the user runs `start`, is safe: the watchdog is armed and waiting, not acting. Confirm with
`systemctl --user is-enabled` and report it.

Do not remove or disable the timer on `stop` or when `orchestration:` reaches `paused` —
a paused plan's tick keeps no-op'ing (`orchestration: paused` branch of `tick()`) until
`resume`, which is the point of `Persistent=true` surviving the gap. The driver retires
the timer itself when the LAST phase completes (`retire_watchdog` in the orchestrator, also
run by the first `tick` after a finished plan), so nothing is left for a human to disable;
an intermediate `phase-done` keeps it for the next phase's `start`.

## 5. Print the command — and stop

One `bash`-tagged block, the same shape `/handoff-plan` §6 prints, spelling out backend
(always) and model (only if the plan overrides it — a plan-level model overrides every
stage, so naming it here matters more than usual, per the launch-commands convention):

```bash
handoff-orchestrate start <plan> --backend <backend>
```

or, for `resume`, the same with `resume` in place of `start` and one line above it
naming what the hand fix should have already done (read `$BASE.status.md`'s Break
section — don't re-derive the reason, it's already written there).

For `stop`:

```bash
handoff-orchestrate stop <plan>
```

with a one-line reminder that `stop` kills the current stage too, not just the driver —
if a `run` stage is mid-way, killing it leaves whatever it had committed and the brief at
`handoff: running`; `resume` after that starts by reading the same state `/debrief` would.

Do not run any of these three. This skill's output is the pre-check, the timer, and the
command — starting, resuming or stopping a phase is the user's decision and the user's keypress.

Last, apply the rules filed under `### /handoff-orchestrate` in `AGENTS.local.md` § Local rules, if there are any.

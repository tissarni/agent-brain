#!/usr/bin/env bash
# journal/run.sh daily|weekly — run the brain's journal skills headless on its default backend.
#
#   daily   /rollup, then /day-log <date>
#   weekly  the daily job, then /week-recap (skipped when the daily part failed)
#
# Started by the systemd user timers or launchd agents that journal/install.sh sets up.
# The brain is this script's parent directory. Exit 0: every session ran well; 1: one failed;
# 2: bad usage. JOURNAL_NOW=YYYY-MM-DDTHH:MM replaces the clock (tests).

set -u

JOB=${1:-}
case "$JOB" in daily|weekly) ;; *) echo "usage: journal/run.sh daily|weekly" >&2; exit 2 ;; esac

BRAIN=$(cd "$(dirname "$0")/.." && pwd)
cd "$BRAIN" || exit 1

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-brain"
LOG="$LOG_DIR/journal-$JOB.log"
mkdir -p "$LOG_DIR"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s %s\n' "$(stamp)" "$*" >>"$LOG"; }

# One run at a time per brain: a boot that missed both timers starts both at once, and two
# runs would fight over .git/index.lock while auto-commit.sh swallows the failure.
COMMON=$(git -C "$BRAIN" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -z "$COMMON" ]; then log "not a git repository: $BRAIN"; exit 1; fi
LOCK="$COMMON/agent-brain-journal.lock"
MKDIR_LOCK=""
cleanup() { [ -z "$MKDIR_LOCK" ] || rmdir "$MKDIR_LOCK" 2>/dev/null; }
trap cleanup EXIT
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  flock -w 3600 9 || { log "journal $JOB: another run holds the lock, giving up"; exit 1; }
else
  waited=0
  until mkdir "$LOCK.d" 2>/dev/null; do
    if [ "$waited" -ge 3600 ]; then log "journal $JOB: another run holds the lock, giving up"; exit 1; fi
    sleep 5; waited=$((waited + 5))
  done
  MKDIR_LOCK="$LOCK.d"
fi

# The date the day-log covers: 12:00 or later is today, earlier is yesterday. Computed once,
# when the run starts, with python3 (GNU and BSD date differ).
NOW=${JOURNAL_NOW:-$(date '+%Y-%m-%dT%H:%M')}
DATE=$(python3 -I -c '
import sys, datetime
n = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M")
d = n.date() if n.hour >= 12 else n.date() - datetime.timedelta(days=1)
print(d.isoformat())' "$NOW") || { log "bad JOURNAL_NOW: $NOW"; exit 1; }

# One key of brain.env, never sourced.
BACKEND=$(grep -m 1 '^DEFAULT_BACKEND=' "$BRAIN/brain.env" 2>/dev/null | cut -d= -f2-)
BACKEND=${BACKEND:-claude}
BIN=$(command -v "$BACKEND" 2>/dev/null || true)
[ -n "$BIN" ] || { [ -x "$HOME/.local/bin/$BACKEND" ] && BIN="$HOME/.local/bin/$BACKEND"; }
if [ -z "$BIN" ]; then log "backend $BACKEND not found on PATH or in ~/.local/bin"; exit 1; fi

# The vault block of the defaults file, parsed by indentation as the kit does: the file has
# review:, run:, vault: and close: blocks, each with its own model:.
CFG_MODEL="" CFG_EFFORT="" CFG_PERM=""
if [ "$BACKEND" = claude ] && [ -f "$BRAIN/02-projects/_templates/handoff-defaults.yml" ]; then
  {
    IFS= read -r CFG_MODEL; IFS= read -r CFG_EFFORT; IFS= read -r CFG_PERM
  } < <(python3 -I - "$BRAIN/02-projects/_templates/handoff-defaults.yml" <<'PY'
import sys
root = {}
stack = [(-1, root)]
for raw in open(sys.argv[1], encoding="utf-8").read().splitlines():
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    ind = len(raw) - len(raw.lstrip())
    key, _, val = raw.strip().partition(":")
    key, val = key.strip(), val.strip().strip("\"'")
    while len(stack) > 1 and stack[-1][0] >= ind:
        stack.pop()
    if val == "":
        child = {}
        stack[-1][1][key] = child
        stack.append((ind, child))
    else:
        stack[-1][1][key] = val
v = root.get("defaults", {}).get("vault", {})
if not isinstance(v, dict):
    v = {}
for k in ("model", "effort", "permission-mode"):
    print(v.get(k, ""))
PY
)
fi

FAILED=0 # any session failed
DAILY_FAILED=0

session() { # session <skill> <args-or-none>; 0 on success
  local skill=$1 args=$2 prompt rc pf
  prompt="Read .agents/skills/$skill/SKILL.md and follow it. This is an unattended run: never ask a question. Arguments: $args."
  log "== $BACKEND $skill $args"
  case "$BACKEND" in
    claude)
      local argv=(-p)
      [ -z "$CFG_MODEL" ] || argv+=(--model "$CFG_MODEL")
      [ -z "$CFG_EFFORT" ] || argv+=(--effort "$CFG_EFFORT")
      [ -z "$CFG_PERM" ] || argv+=(--permission-mode "$CFG_PERM")
      argv+=(--name "journal $JOB $skill" -- "$prompt")
      ( export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 ENABLE_CLAUDEAI_MCP_SERVERS=false
        exec "$BIN" "${argv[@]}" ) </dev/null >>"$LOG" 2>&1
      rc=$? ;;
    hermes)
      "$BIN" -p default --in "$BRAIN" -z "$prompt" </dev/null >>"$LOG" 2>&1
      rc=$? ;;
    devin)
      pf=$(mktemp "${TMPDIR:-/tmp}/agent-brain-journal.XXXXXX")
      printf '%s\n' "$prompt" >"$pf"
      "$BIN" --permission-mode dangerous --respect-workspace-trust false -p --prompt-file "$pf" </dev/null >>"$LOG" 2>&1
      rc=$?
      rm -f "$pf" ;;
    *) log "unknown backend $BACKEND"; rc=1 ;;
  esac
  [ "$rc" -eq 0 ] || { log "!! $skill failed (exit $rc)"; FAILED=1; return 1; }
}

daily_part() {
  session rollup none || DAILY_FAILED=1
  session day-log "$DATE" || DAILY_FAILED=1
}

daily_part
if [ "$JOB" = weekly ]; then
  if [ "$DAILY_FAILED" -eq 0 ]; then
    session week-recap none
  else
    log "week-recap skipped: the daily part failed, and a recap built on missing notes is never redone"
  fi
fi

# Only Claude Code has the Stop hook that commits; hermes and devin need this call.
if [ -f "$BRAIN/auto-commit.sh" ]; then
  sh "$BRAIN/auto-commit.sh" </dev/null >>"$LOG" 2>&1
fi

log "journal $JOB done, failed=$FAILED"
exit "$FAILED"

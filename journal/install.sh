#!/usr/bin/env bash
# journal/install.sh <brain> [--daily HH:MM] [--weekly HH:MM] [--platform linux|macos]
#
# Installs the journal timers for one brain: systemd user timers on Linux and WSL2, launchd
# agents on macOS. Safe to run again. Defaults: daily 23:30 (Mon-Fri), weekly 06:00 (Mon),
# the platform from uname.

set -euo pipefail

USAGE="usage: journal/install.sh <brain> [--daily HH:MM] [--weekly HH:MM] [--platform linux|macos]"
DAILY=23:30 WEEKLY=06:00 PLATFORM="" BRAIN_ARG=""
usage_exit() { printf '%s\n' "$USAGE" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --daily) [ $# -ge 2 ] || usage_exit; DAILY=$2; shift 2 ;;
    --weekly) [ $# -ge 2 ] || usage_exit; WEEKLY=$2; shift 2 ;;
    --platform) [ $# -ge 2 ] || usage_exit; PLATFORM=$2; shift 2 ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    -*) usage_exit ;;
    *) [ -z "$BRAIN_ARG" ] || usage_exit; BRAIN_ARG=$1; shift ;;
  esac
done
[ -n "$BRAIN_ARG" ] || usage_exit
for t in "$DAILY" "$WEEKLY"; do
  printf '%s' "$t" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$' || { echo "install.sh: not a time HH:MM: $t" >&2; exit 2; }
done
if [ -z "$PLATFORM" ]; then
  case "$(uname -s)" in Darwin) PLATFORM=macos ;; *) PLATFORM=linux ;; esac
fi
case "$PLATFORM" in linux|macos) ;; *) usage_exit ;; esac
[ -f "$BRAIN_ARG/journal/run.sh" ] || { echo "install.sh: no journal/run.sh in $BRAIN_ARG" >&2; exit 2; }

BRAIN=$(cd "$BRAIN_ARG" && pwd)
SRC=$(cd "$(dirname "$0")" && pwd)

# The timers' sessions need the CLIs: hand them this shell's PATH.
mkdir -p "$HOME/.config/agent-brain"
printf 'PATH=%s\n' "$PATH" >"$HOME/.config/agent-brain/journal.env"

if [ "$PLATFORM" = linux ]; then
  UNITS="$HOME/.config/systemd/user"
  mkdir -p "$UNITS"
  INST=$(systemd-escape --path "$BRAIN")
  for f in "$SRC"/systemd/*; do cp "$f" "$UNITS/"; done
  for job in daily weekly; do
    if [ "$job" = daily ]; then T=$DAILY; DAYS="Mon..Fri"; else T=$WEEKLY; DAYS="Mon"; fi
    D="$UNITS/agent-brain-journal-$job@$INST.timer.d"
    mkdir -p "$D"
    printf '[Timer]\nOnCalendar=\nOnCalendar=%s *-*-* %s:00\n' "$DAYS" "$T" >"$D/time.conf"
  done
  systemctl --user daemon-reload
  for job in daily weekly; do
    systemctl --user enable --now "agent-brain-journal-$job@$INST.timer"
  done
  echo "journal timers installed for $BRAIN (daily $DAILY Mon-Fri, weekly $WEEKLY Mon)"
else
  AGENTS="$HOME/Library/LaunchAgents"
  mkdir -p "$AGENTS"
  LOGDIR="${XDG_STATE_HOME:-$HOME/.local/state}/agent-brain"
  mkdir -p "$LOGDIR"
  for job in daily weekly; do
    if [ "$job" = daily ]; then T=$DAILY; else T=$WEEKLY; fi
    PLIST=$(python3 -I - "$SRC/launchd/journal.plist.in" "$BRAIN" "$job" "$T" "$PATH" "$LOGDIR/journal-$job.log" "$AGENTS" <<'PY'
import hashlib, sys
from xml.sax.saxutils import escape
src, brain, job, t, path, log, agents = sys.argv[1:8]
digest = hashlib.sha256(brain.encode()).hexdigest()[:8]
label = f"io.github.tissarni.agent-brain.journal.{job}.{digest}"
hour, minute = (int(x) for x in t.split(":"))
days = [1, 2, 3, 4, 5] if job == "daily" else [1]
cal = "\n".join(
    f"    <dict><key>Weekday</key><integer>{d}</integer><key>Hour</key><integer>{hour}</integer>"
    f"<key>Minute</key><integer>{minute}</integer></dict>" for d in days)
text = open(src, encoding="utf-8").read()
for k, v in (("@LABEL@", label), ("@BRAIN@", escape(brain)), ("@JOB@", job),
             ("@PATH@", escape(path)), ("@LOG@", escape(log)), ("@CALENDAR@", cal)):
    text = text.replace(k, v)
out = f"{agents}/{label}.plist"
open(out, "w", encoding="utf-8").write(text)
print(out)
PY
)
    LABEL=$(basename "$PLIST" .plist)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
  done
  echo "journal agents installed for $BRAIN (daily $DAILY Mon-Fri, weekly $WEEKLY Mon)"
fi

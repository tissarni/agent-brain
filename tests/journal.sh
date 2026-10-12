#!/usr/bin/env bash
# Tests for journal/run.sh and journal/install.sh, offline.
# Every case builds its own git-repo brain under mktemp -d, with fake CLIs first on PATH and
# HOME and XDG_STATE_HOME inside the case; nothing real is called or written elsewhere.
# Output: one "PASS <case>" or "FAIL <case> — <why>" per case, then "<n> passed, <m> failed".

unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0

pass() { echo "PASS $1"; passed=$((passed + 1)); }
fail() { echo "FAIL $1 — $2"; failed=$((failed + 1)); }

has() { /usr/bin/grep -q -F -e "$2" "$1"; }

# new_case <name> [backend]: builds $TMP/<name>/{brain,home,fakes,log}; prints the case dir.
new_case() {
  local c="$TMP/$1" b="${2:-claude}" n
  mkdir -p "$c/brain/journal" "$c/brain/02-projects/_templates" "$c/home" "$c/fakes" "$c/log" "$c/state"
  cp "$ROOT"/journal/run.sh "$c/brain/journal/"
  cp "$ROOT"/journal/install.sh "$c/brain/journal/" 2>/dev/null
  cp -r "$ROOT/journal/systemd" "$ROOT/journal/launchd" "$c/brain/journal/" 2>/dev/null
  cp "$ROOT/.seed/02-projects/_templates/handoff-defaults.yml" "$c/brain/02-projects/_templates/"
  printf 'DEFAULT_BACKEND=%s\n' "$b" >"$c/brain/brain.env"
  printf '#!/bin/sh\necho "stub $*" >>"%s/log/stub.log"\n' "$c" >"$c/brain/auto-commit.sh"
  git -C "$c/brain" init -q
  for n in claude hermes devin systemctl launchctl; do
    # Each call: one line, argv then the working directory. FAIL_ON makes a call fail when its argv contains it.
    cat >"$c/fakes/$n" <<FAKE
#!/bin/bash
echo "$n \$* | cwd=\$PWD" >>"$c/log/$n.log"
if [ -n "\${FAIL_ON:-}" ]; then case "\$*" in *"\$FAIL_ON"*) exit 1 ;; esac; fi
exit 0
FAKE
  done
  chmod +x "$c/fakes"/* "$c/brain/auto-commit.sh"
  echo "$c"
}

# run_job <case> <job> [env...]: runs journal/run.sh in the case's sandbox; returns its exit code.
run_job() {
  local c=$1 job=$2; shift 2
  env -i HOME="$c/home" XDG_STATE_HOME="$c/state" TMPDIR="$c/log" \
    PATH="$c/fakes:/usr/local/bin:/usr/bin:/bin" JOURNAL_NOW=2026-10-12T23:30 "$@" \
    bash "$c/brain/journal/run.sh" "$job" >"$c/out.log" 2>&1
}

case_date_evening() {
  local c; c=$(new_case date-evening)
  run_job "$c" daily JOURNAL_NOW=2026-10-12T23:30
  has "$c/log/claude.log" 'Arguments: 2026-10-12.' && pass date-evening || fail date-evening "$(tail -n 3 "$c/log/claude.log" 2>&1)"
}

case_date_morning() {
  local c; c=$(new_case date-morning)
  run_job "$c" daily JOURNAL_NOW=2026-10-12T06:00
  has "$c/log/claude.log" 'Arguments: 2026-10-11.' && pass date-morning || fail date-morning "$(tail -n 3 "$c/log/claude.log" 2>&1)"
}

case_daily_order() {
  local c n; c=$(new_case daily-order)
  run_job "$c" daily
  n=$(wc -l <"$c/log/claude.log")
  [ "$n" -eq 2 ] || { fail daily-order "$n claude sessions, not 2"; return; }
  sed -n 1p "$c/log/claude.log" | /usr/bin/grep -q 'rollup/SKILL.md.*Arguments: none\.' || { fail daily-order "first is not rollup"; return; }
  sed -n 2p "$c/log/claude.log" | /usr/bin/grep -q 'day-log/SKILL.md.*Arguments: 2026-10-12\.' || { fail daily-order "second is not day-log 2026-10-12"; return; }
  /usr/bin/grep -q -e '^claude -p --model sonnet --effort medium --permission-mode bypassPermissions ' "$c/log/claude.log" || { fail daily-order "argv lacks -p/--model sonnet/--permission-mode: $(head -n 1 "$c/log/claude.log")"; return; }
  [ "$(/usr/bin/grep -c "cwd=$c/brain\$" "$c/log/claude.log")" -eq 2 ] || { fail daily-order "not run in the brain"; return; }
  [ "$(wc -l <"$c/log/stub.log")" -eq 1 ] || { fail daily-order "stub not called once"; return; }
  pass daily-order
}

case_weekly_order() {
  local c; c=$(new_case weekly-order)
  run_job "$c" weekly
  [ "$(wc -l <"$c/log/claude.log")" -eq 3 ] || { fail weekly-order "not 3 sessions"; return; }
  sed -n 1p "$c/log/claude.log" | /usr/bin/grep -q 'rollup/SKILL' && sed -n 2p "$c/log/claude.log" | /usr/bin/grep -q 'day-log/SKILL' \
    && sed -n 3p "$c/log/claude.log" | /usr/bin/grep -q 'week-recap/SKILL.*Arguments: none\.' || { fail weekly-order "order is not rollup, day-log, week-recap"; return; }
  [ -s "$c/log/stub.log" ] && pass weekly-order || fail weekly-order "stub not called"
}

case_backend_hermes() {
  local c; c=$(new_case backend-hermes hermes)
  run_job "$c" daily
  /usr/bin/grep -q -e "^hermes -p default --in $c/brain -z " "$c/log/hermes.log" && [ ! -e "$c/log/claude.log" ] \
    && pass backend-hermes || fail backend-hermes "$(head -n 1 "$c/log/hermes.log" 2>&1)"
}

case_backend_devin() {
  local c; c=$(new_case backend-devin devin)
  run_job "$c" daily
  /usr/bin/grep -q -e '--permission-mode dangerous' "$c/log/devin.log" && /usr/bin/grep -q -e '--prompt-file ' "$c/log/devin.log" \
    && [ -z "$(ls "$c/log" | /usr/bin/grep agent-brain-journal)" ] && pass backend-devin || fail backend-devin "$(head -n 1 "$c/log/devin.log" 2>&1)"
}

case_log_file() {
  local f c; c=$(new_case log-file)
  run_job "$c" daily
  f="$c/state/agent-brain/journal-daily.log"
  [ -f "$f" ] && has "$f" rollup && has "$f" day-log && pass log-file || fail log-file "log missing or incomplete"
}

case_failure_exit() {
  local c rc; c=$(new_case failure-exit)
  run_job "$c" weekly FAIL_ON=day-log; rc=$?
  [ "$rc" -eq 1 ] || { fail failure-exit "exit $rc, not 1"; return; }
  ! has "$c/log/claude.log" week-recap || { fail failure-exit "week-recap ran"; return; }
  [ -s "$c/log/stub.log" ] && pass failure-exit || fail failure-exit "stub did not run"
}

# run_install <case> [args...]: journal/install.sh in the case's sandbox.
run_install() {
  local c=$1; shift
  env -i HOME="$c/home" XDG_STATE_HOME="$c/state" PATH="$c/fakes:/usr/local/bin:/usr/bin:/bin" \
    bash "$c/brain/journal/install.sh" "$c/brain" "$@" >"$c/out.log" 2>&1
}

case_install_linux() {
  local c inst u s f1 f2 job; c=$(new_case install-linux)
  run_install "$c" --platform linux --daily 22:15 || { fail install-linux "exit $?: $(tail -n 2 "$c/out.log")"; return; }
  u="$c/home/.config/systemd/user"
  [ "$(ls "$u"/agent-brain-journal-*@.* | wc -l)" -eq 4 ] || { fail install-linux "not four unit files"; return; }
  for s in daily weekly; do
    f="$u/agent-brain-journal-$s@.service"
    has "$f" "%f/journal/run.sh" && ! has "$f" '%I' || { fail install-linux "$s service: no %f/journal/run.sh, or has %I"; return; }
  done
  inst=$(systemd-escape --path "$c/brain")
  has "$u/agent-brain-journal-daily@$inst.timer.d/time.conf" 'OnCalendar=Mon..Fri *-*-* 22:15:00' || { fail install-linux "daily drop-in lacks 22:15"; return; }
  has "$u/agent-brain-journal-weekly@$inst.timer.d/time.conf" 'OnCalendar=Mon *-*-* 06:00:00' || { fail install-linux "weekly drop-in lacks 06:00"; return; }
  has "$c/log/systemctl.log" 'daemon-reload' || { fail install-linux "no daemon-reload"; return; }
  for job in daily weekly; do
    has "$c/log/systemctl.log" "enable --now agent-brain-journal-$job@$inst.timer" || { fail install-linux "$job timer not enabled"; return; }
  done
  f1=$(cd "$u" && find . -type f | sort | xargs -d '\n' cat | cksum)
  run_install "$c" --platform linux --daily 22:15 || { fail install-linux "second run failed"; return; }
  f2=$(cd "$u" && find . -type f | sort | xargs -d '\n' cat | cksum)
  [ "$f1" = "$f2" ] && pass install-linux || fail install-linux "second run changed the files"
}

case_install_macos() {
  local c d p n; c=$(new_case install-macos)
  run_install "$c" --platform macos --weekly 07:30 || { fail install-macos "exit $?: $(tail -n 2 "$c/out.log")"; return; }
  d="$c/home/Library/LaunchAgents"
  [ "$(ls "$d" | wc -l)" -eq 2 ] || { fail install-macos "not two plists"; return; }
  for p in "$d"/*.plist; do
    n=$(python3 -I -c '
import plistlib, sys, re
d = plistlib.load(open(sys.argv[1], "rb"))
assert re.fullmatch(r"io\.github\.tissarni\.agent-brain\.journal\.(daily|weekly)\.[0-9a-f]{8}", d["Label"]), d["Label"]
print(d["Label"].split(".")[-2], len(d["StartCalendarInterval"]))' "$p" 2>&1) || { fail install-macos "$p: $n"; return; }
    case "$n" in "daily 5"|"weekly 1") ;; *) fail install-macos "calendar entries: $n"; return ;; esac
  done
  [ "$(/usr/bin/grep -c '^launchctl bootstrap ' "$c/log/launchctl.log")" -eq 2 ] && pass install-macos || fail install-macos "bootstrap not called twice"
}

case_date_evening
case_date_morning
case_daily_order
case_weekly_order
case_backend_hermes
case_backend_devin
case_log_file
case_failure_exit
case_install_linux
case_install_macos

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

#!/usr/bin/env bash
# Smoke test for setup.sh: run it unattended in a sandbox and check the brain it leaves.
# The sandbox is a fresh clone of the template under mktemp -d, a sandbox HOME, fake CLIs
# and a PATH built from the sandbox only. Offline; nothing is written elsewhere.
# Output: one "PASS <case>" or "FAIL <case> — <why>" per case, then "<n> passed, <m> failed".

CASES=(setup-runs commands-resolve seeds-filled demo-repo git-config remote-template
  example-brief-check loop-dry-run idempotent nothing-installed bad-flag extras bad-time
  ignores-temp-files env-first-wins)

. "$(dirname "$0")/sandbox.sh"

EXAMPLE=$BRAIN/02-projects/example/subprojects/example-version-flag/specs/2026-10-10-brief-1-version-flag.md

sandbox "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" --kit "$KIT" >"$TMP/setup1.log" 2>&1
RC1=$?
tail_log() { tail -n 3 "$1" | paste -s -d'|'; }

case_setup_runs() {
  [ "$RC1" -eq 0 ] && pass setup-runs || fail setup-runs "exit $RC1: $(tail_log "$TMP/setup1.log")"
}

case_commands_resolve() {
  local c
  for c in handoff-launch handoff-orchestrate brief-check; do
    [ -L "$HOME_DIR/.local/bin/$c" ] && [ -x "$HOME_DIR/.local/bin/$c" ] || { fail commands-resolve "$c is not an executable link"; return; }
  done
  pass commands-resolve
}

case_seeds_filled() {
  local stray
  /usr/bin/grep -q -F 'ci — ci.' "$BRAIN/AGENTS.local.md" || { fail seeds-filled "AGENTS.local.md lacks 'ci — ci.'"; return; }
  stray=$(cd "$BRAIN" && git ls-files --others --exclude-standard | xargs /usr/bin/grep -l -E '@[A-Z_]+@' 2>/dev/null)
  stray="$stray$(cd "$BRAIN" && git ls-files -m | xargs /usr/bin/grep -l -E '@[A-Z_]+@' 2>/dev/null)"
  [ -z "$stray" ] || { fail seeds-filled "token left in: $stray"; return; }
  /usr/bin/grep -q -x "CODE_ROOT=$CODE" "$BRAIN/brain.env" || { fail seeds-filled "brain.env CODE_ROOT is not $CODE"; return; }
  /usr/bin/grep -q -x 'DEFAULT_BACKEND=claude' "$BRAIN/brain.env" || { fail seeds-filled "brain.env DEFAULT_BACKEND is not claude"; return; }
  pass seeds-filled
}

case_demo_repo() {
  local d=$CODE/agent-brain-demo n a b
  [ -d "$d/.git" ] || { fail demo-repo "no repository at $d"; return; }
  n=$(git -C "$d" rev-list --count main 2>/dev/null)
  [ "$n" = 1 ] || { fail demo-repo "main has $n commits, not 1"; return; }
  a=$(git -C "$d" rev-parse main)
  b=$(git -C "$d.git" rev-parse main 2>/dev/null)
  [ "$a" = "$b" ] || { fail demo-repo "main differs from the bare origin's"; return; }
  (cd "$d" && sandbox python3 -m unittest -q >/dev/null 2>&1) || { fail demo-repo "its tests fail"; return; }
  pass demo-repo
}

case_git_config() {
  [ "$(git -C "$BRAIN" config --local --get core.hooksPath)" = .githooks ] || { fail git-config "core.hooksPath is not .githooks"; return; }
  /usr/bin/grep -q -x -F '.claude/worktrees/' "$BRAIN/.gitignore" && pass git-config || fail git-config ".gitignore lacks .claude/worktrees/"
}

case_remote_template() {
  local remotes
  remotes=$(git -C "$BRAIN" remote | paste -s -d,)
  [ "$remotes" = template ] || { fail remote-template "remotes: $remotes"; return; }
  [ "$(git -C "$BRAIN" remote get-url --push template)" = DISABLED ] && pass remote-template || fail remote-template "push URL is not DISABLED"
}

case_example_brief_check() {
  local out
  out=$(sandbox brief-check "$EXAMPLE" 2>&1) && pass example-brief-check || fail example-brief-check "$(echo "$out" | tail -n 2 | paste -s -d'|')"
}

case_loop_dry_run() {
  local out
  out=$(sandbox handoff-launch loop "$EXAMPLE" --gate auto --backend claude --dry-run 2>&1) && pass loop-dry-run || fail loop-dry-run "$(echo "$out" | tail -n 2 | paste -s -d'|')"
}

case_idempotent() {
  local before after rc
  echo "my own line" >>"$BRAIN/AGENTS.local.md"
  before="$(git -C "$BRAIN" remote -v)|$(git -C "$CODE/agent-brain-demo" rev-list --count main)"
  sandbox "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" --kit "$KIT" >"$TMP/setup2.log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { fail idempotent "second run exit $rc: $(tail_log "$TMP/setup2.log")"; return; }
  /usr/bin/grep -q -x 'my own line' "$BRAIN/AGENTS.local.md" || { fail idempotent "the added line is gone"; return; }
  after="$(git -C "$BRAIN" remote -v)|$(git -C "$CODE/agent-brain-demo" rev-list --count main)"
  [ "$before" = "$after" ] && pass idempotent || fail idempotent "remotes or demo history changed"
}

case_nothing_installed() {
  local n
  for n in sudo apt-get dnf brew; do
    [ ! -s "$TMP/log/$n.log" ] || { fail nothing-installed "$n was called: $(head -n 1 "$TMP/log/$n.log")"; return; }
  done
  pass nothing-installed
}

case_bad_flag() {
  sandbox "$BRAIN/setup.sh" --nope >/dev/null 2>&1
  [ $? -eq 2 ] && pass bad-flag || fail bad-flag "exit was not 2"
}

case_extras() {
  local rc inst nt
  sandbox env TELEGRAM_BOT_TOKEN=fake-token-123 TELEGRAM_CHAT_ID=42 "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" \
    --linger y --telegram y --journal y --journal-daily 22:15 --kit "$KIT" >"$TMP/setup3.log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { fail extras "exit $rc: $(tail_log "$TMP/setup3.log")"; return; }
  nt=$HOME_DIR/.config/handoff/notify.env
  [ "$(stat -c %a "$nt" 2>/dev/null || stat -f %Lp "$nt")" = 600 ] || { fail extras "notify.env is not mode 600"; return; }
  /usr/bin/grep -q '^TELEGRAM_BOT_TOKEN=.' "$nt" && /usr/bin/grep -q '^TELEGRAM_CHAT_ID=.' "$nt" || { fail extras "notify.env lacks a key"; return; }
  /usr/bin/grep -q -x 'NOTIFY=telegram' "$BRAIN/brain.env" || { fail extras "brain.env lacks NOTIFY=telegram"; return; }
  ! /usr/bin/grep -q -F 'fake-token-123' "$TMP/log/curl.log" || { fail extras "curl.log holds the token"; return; }
  [ -s "$TMP/log/curl.log" ] || { fail extras "no test message sent"; return; }
  if [ "$(uname -s)" = Darwin ]; then
    /usr/bin/grep -q 'bootstrap' "$TMP/log/launchctl.log" || { fail extras "launchctl saw no bootstrap"; return; }
  else
    /usr/bin/grep -q 'enable-linger' "$TMP/log/loginctl.log" || { fail extras "loginctl saw no enable-linger"; return; }
    /usr/bin/grep -q 'enable --now agent-brain-journal-daily@' "$TMP/log/systemctl.log" \
      && /usr/bin/grep -q 'enable --now agent-brain-journal-weekly@' "$TMP/log/systemctl.log" || { fail extras "timers not enabled"; return; }
    inst=$(ls -d "$HOME_DIR"/.config/systemd/user/agent-brain-journal-daily@*.timer.d 2>/dev/null | head -n 1)
    /usr/bin/grep -q -F '22:15' "$inst/time.conf" 2>/dev/null || { fail extras "daily drop-in lacks 22:15"; return; }
  fi
  pass extras
}

case_bad_time() {
  sandbox "$BRAIN/setup.sh" --journal-daily 25:00 >/dev/null 2>&1
  [ $? -eq 2 ] && pass bad-time || fail bad-time "exit was not 2"
}

case_ignores_temp_files() {
  local d=$BRAIN/02-projects/example listed
  : >"$d/x.md.tmp.123"
  : >"$BRAIN/brain.env.tmp.45"
  : >"$d/y.html.tmp"
  listed=$(git -C "$BRAIN" status --porcelain --untracked-files=all | /usr/bin/grep -F -e '.tmp' | paste -s -d'|')
  rm -f "$d/x.md.tmp.123" "$BRAIN/brain.env.tmp.45" "$d/y.html.tmp"
  [ -z "$listed" ] && pass ignores-temp-files || fail ignores-temp-files "git lists: $listed"
}

case_env_first_wins() {
  local rc
  echo 'DEFAULT_BACKEND=devin' >>"$BRAIN/brain.env"
  sandbox "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" --kit "$KIT" >"$TMP/setup4.log" 2>&1
  rc=$?
  /usr/bin/grep -v -x 'DEFAULT_BACKEND=devin' "$BRAIN/brain.env" >"$TMP/env" && cat "$TMP/env" >"$BRAIN/brain.env"
  [ "$rc" -eq 0 ] || { fail env-first-wins "exit $rc: $(tail_log "$TMP/setup4.log")"; return; }
  /usr/bin/grep -q -e '--gate auto --backend claude$' "$TMP/setup4.log" && pass env-first-wins || fail env-first-wins "backend is not claude: $(tail_log "$TMP/setup4.log")"
}

case_setup_runs
case_commands_resolve
case_seeds_filled
case_demo_repo
case_git_config
case_remote_template
case_example_brief_check
case_loop_dry_run
case_idempotent
case_nothing_installed
case_bad_flag
case_extras
case_bad_time
case_env_first_wins
case_ignores_temp_files

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

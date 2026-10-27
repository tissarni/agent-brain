#!/usr/bin/env bash
# Component reconciliation is checked against artifacts, not saved consent alone.
CASES=(no-reinstall identity-override preserve-remote explicit-telegram repair-skill repair-hook
  keep-hooks journal-resume repair-journal homebrew-first backend-failure
  repair-kit-config repair-watchdog repair-profile stale-profile-diagnostic stale-hook-approval
  repair-journal-env repair-hook-approval-date)
. "$(dirname "$0")/sandbox.sh"
fake_hermes
sandbox "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" --kit "$KIT" --backends hermes,claude \
  --hermes-hooks n --linger n --telegram n --journal n >"$TMP/first.log" 2>&1 || fail_all 'initial setup failed'
echo 'keep this personal rule' >>"$BRAIN/AGENTS.local.md"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/keep.log" 2>&1
grep -q 'kit components verified: no reinstall needed' "$TMP/keep.log" && pass no-reinstall || fail no-reinstall 'reinstalled valid components'
sandbox "$BRAIN/setup.sh" --yes --name 'new name' --role 'new role' >"$TMP/identity.log" 2>&1
if [ $? = 0 ] && grep -q '^new name — new role\.$' "$BRAIN/AGENTS.local.md" && grep -qx 'keep this personal rule' "$BRAIN/AGENTS.local.md"; then pass identity-override; else fail identity-override 'override ignored or personal content lost'; fi
git -C "$BRAIN" remote add origin https://example.invalid/private-brain.git
git -C "$BRAIN" remote remove template
sandbox "$BRAIN/setup.sh" --yes >"$TMP/remote.log" 2>&1
if [ $? = 0 ] && [ "$(git -C "$BRAIN" remote get-url origin)" = https://example.invalid/private-brain.git ] && ! git -C "$BRAIN" remote get-url template >/dev/null 2>&1; then pass preserve-remote; else fail preserve-remote 'existing origin renamed'; fi
mkdir -p "$HOME_DIR/.config/handoff"
printf 'TELEGRAM_BOT_TOKEN=fixture-token\nTELEGRAM_CHAT_ID=42\n' >"$HOME_DIR/.config/handoff/notify.env"
sandbox "$BRAIN/setup.sh" --yes --telegram-test >"$TMP/telegram.log" 2>&1
[ $? = 0 ] && [ -s "$TMP/log/curl.log" ] && pass explicit-telegram || fail explicit-telegram 'explicit test did not send'
printf '\ncorruption\n' >>"$HOME_DIR/.claude/skills/handoff-review/SKILL.md"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/skill.log" 2>&1
cmp -s "$HOME_DIR/.claude/skills/handoff-review/SKILL.md" "$KIT/skills/handoff-review/SKILL.md" && pass repair-skill || fail repair-skill 'outdated installed skill left unchanged'
sandbox "$BRAIN/setup.sh" --yes --backends hermes --hermes-hooks y >"$TMP/hooks.log" 2>&1
sandbox python3 -I - "$HOME_DIR/.hermes/config.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['hooks']['on_session_end']=[]
with open(p,'w') as f: json.dump(d,f)
PY
sandbox "$BRAIN/setup.sh" --yes >"$TMP/hooks-repair.log" 2>&1
sandbox python3 -I - "$HOME_DIR/.hermes/config.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert len(d['hooks']['on_session_end'])==1
PY
[ $? = 0 ] && pass repair-hook || fail repair-hook 'partial registration not repaired'
: >"$TMP/log/hermes.log"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/hooks-keep.log" 2>&1
if ! grep -q 'config set' "$TMP/log/hermes.log"; then pass keep-hooks; else fail keep-hooks 'valid hooks re-registered'; fi
sandbox "$BRAIN/setup.sh" --yes --journal y --journal-daily 21:17 >"$TMP/journal.log" 2>&1
: >"$TMP/log/systemctl.log"
: >"$TMP/log/launchctl.log"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/journal-keep.log" 2>&1
if [ $? = 0 ] && ! grep -q 'enable --now' "$TMP/log/systemctl.log" && ! grep -q 'bootstrap' "$TMP/log/launchctl.log" && grep -q 'journal timers verified' "$TMP/journal-keep.log"; then pass journal-resume; else
  cat "$TMP/journal-keep.log"
  fail journal-resume 'valid timers reinstalled'
fi
if [ "$(uname -s)" = Darwin ]; then
  rm "$HOME_DIR"/Library/LaunchAgents/*journal.daily.*.plist
else
  rm "$HOME_DIR/.config/systemd/user/agent-brain-journal-daily@.service"
fi
sandbox "$BRAIN/setup.sh" --yes >"$TMP/journal-repair.log" 2>&1
if [ $? = 0 ] && ! grep -q 'journal timers verified' "$TMP/journal-repair.log"; then pass repair-journal; else fail repair-journal 'missing timer component not repaired'; fi
# Saved consent is not proof of working config, units or role profiles.
printf 'VAULT=/missing-fixture\nHANDOFF_DEFAULTS=wrong\nHANDOFF_PROJECTS=wrong\n' >"$HOME_DIR/.config/handoff/config.env"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/config-repair.log" 2>&1
repair_rc=$?
sandbox python3 -I - "$BRAIN" "$HOME_DIR/.config/handoff/config.env" <<'PY'
from pathlib import Path
import sys
values = dict(line.split('=', 1) for line in Path(sys.argv[2]).read_text().splitlines() if '=' in line)
assert Path(values['VAULT']).resolve() == Path(sys.argv[1]).resolve()
PY
path_rc=$?
if [ "$repair_rc" = 0 ] && [ "$path_rc" = 0 ]; then pass repair-kit-config; else
  cat "$TMP/config-repair.log"
  fail repair-kit-config 'stale config not reconciled'
fi
printf 'outdated\n' >"$HOME_DIR/.config/systemd/user/handoff-watchdog@.timer"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/watchdog-repair.log" 2>&1
if [ $? = 0 ] && cmp -s "$KIT/systemd/handoff-watchdog@.timer" "$HOME_DIR/.config/systemd/user/handoff-watchdog@.timer"; then pass repair-watchdog; else fail repair-watchdog 'stale unit not reconciled'; fi
mv "$HOME_DIR/.hermes/profiles/run" "$TMP/saved-run-profile"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/profile-repair.log" 2>&1
if [ $? = 0 ] && cmp -s "$KIT/hermes/profiles/run/SOUL.md" "$HOME_DIR/.hermes/profiles/run/SOUL.md"; then pass repair-profile; else fail repair-profile 'missing role not installed'; fi
printf 'custom role without stage protocol\n' >"$HOME_DIR/.hermes/profiles/run/SOUL.md"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/profile-stale.log" 2>&1
if [ $? = 1 ] && grep -q 'FAIL: hermes profile run' "$TMP/profile-stale.log" \
   && grep -qx 'custom role without stage protocol' "$HOME_DIR/.hermes/profiles/run/SOUL.md"; then pass stale-profile-diagnostic; else fail stale-profile-diagnostic 'stale custom role hidden or overwritten'; fi
cp "$KIT/hermes/profiles/run/SOUL.md" "$HOME_DIR/.hermes/profiles/run/SOUL.md"
sandbox python3 -I - "$BRAIN/auto-commit.sh" <<'PY'
import os,sys
p=sys.argv[1]; s=os.stat(p); os.utime(p,(s.st_atime,s.st_mtime+2))
PY
sandbox "$BRAIN/setup.sh" --yes >"$TMP/approval-repair.log" 2>&1
if [ $? = 0 ] && grep -q 'PASS: hermes brain hooks' "$TMP/approval-repair.log"; then pass stale-hook-approval; else fail stale-hook-approval 'stale approval not reconciled'; fi
printf 'PATH=/missing-fixture\n' >"$HOME_DIR/.config/agent-brain/journal.env"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/journal-env-repair.log" 2>&1
if [ $? = 0 ] && ! grep -q 'missing-fixture' "$HOME_DIR/.config/agent-brain/journal.env"; then pass repair-journal-env; else fail repair-journal-env 'stale journal executable PATH not repaired'; fi
sandbox python3 -I - "$HOME_DIR/.hermes/shell-hooks-allowlist.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['approvals'][0]['approved_at']='invalid'
with open(p,'w') as f: json.dump(d,f)
PY
sandbox "$BRAIN/setup.sh" --yes >"$TMP/approval-date-repair.log" 2>&1
if [ $? = 0 ] && grep -q 'PASS: hermes brain hooks' "$TMP/approval-date-repair.log"; then pass repair-hook-approval-date; else fail repair-hook-approval-date 'invalid approval date not repaired'; fi
# Simulate macOS with GNU tools hidden behind Homebrew's gnubin directories.
HB=$TMP/homebrew
for pair in coreutils:sort findutils:find gnu-sed:sed grep:grep; do
  pkg=${pair%:*}; tool=${pair#*:}; real=$(command -v "$tool")
  mkdir -p "$HB/opt/$pkg/libexec/gnubin"
  ln -s "$real" "$HB/opt/$pkg/libexec/gnubin/$tool"
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = --version ]; then echo BSD; else exec "%s" "$@"; fi\n' "$real" >"$TMP/fakes/$tool"
done
printf '#!/usr/bin/env bash\nif [ "${1:-}" = --prefix ]; then echo "%s"; else echo "$*" >>"%s/log/brew-install.log"; exit 1; fi\n' "$HB" "$TMP" >"$TMP/fakes/brew"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = -s ]; then echo Darwin; else /usr/bin/uname "$@"; fi\n' >"$TMP/fakes/uname"
chmod +x "$TMP/fakes"/*
sandbox "$BRAIN/setup.sh" --yes --journal n >"$TMP/mac.log" 2>&1
if [ $? = 0 ] && [ ! -s "$TMP/log/brew-install.log" ]; then pass homebrew-first; else fail homebrew-first 'existing GNU tools not activated before install check'; fi
rm "$TMP/fakes/uname" "$TMP/fakes/sort" "$TMP/fakes/find" "$TMP/fakes/sed" "$TMP/fakes/grep"
printf '#!/usr/bin/env bash\necho '\''{"loggedIn": false}'\''\n' >"$TMP/fakes/claude"
sandbox "$BRAIN/setup.sh" --yes --backends claude --journal n >"$TMP/failure.log" 2>&1
if [ $? = 1 ] && grep -q '10. Final checks' "$TMP/failure.log" && grep -q 'NOT READY: backend claude' "$TMP/failure.log"; then pass backend-failure; else fail backend-failure 'backend failure skipped final checks or reported ready'; fi
echo "$passed passed, $failed failed"
[ "$failed" = 0 ]

#!/usr/bin/env bash
# Real reruns, including a controlling terminal; offline and sandboxed.
CASES=(saved-backends no-telegram-send real-rerun explicit-override repair-links final-checks
  rerun-acceptance rerun-acceptance-failure)
. "$(dirname "$0")/sandbox.sh"
fake_hermes
sandbox "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" --kit "$KIT" --backends hermes,claude \
  --hermes-hooks n --linger n --telegram n --journal n >"$TMP/first.log" 2>&1 || fail_all "initial setup failed"
# Existing valid notification configuration must never cause an implicit test message.
mkdir -p "$HOME_DIR/.config/handoff"
printf 'TELEGRAM_BOT_TOKEN=fixture-token\nTELEGRAM_CHAT_ID=42\n' >"$HOME_DIR/.config/handoff/notify.env"
chmod 600 "$HOME_DIR/.config/handoff/notify.env"
: >"$TMP/log/curl.log"
sandbox "$BRAIN/setup.sh" --yes --kit "$KIT" >"$TMP/yes.log" 2>&1
if grep -qx 'DEFAULT_BACKEND=hermes' "$BRAIN/brain.env" && grep -qx 'SETUP_BACKENDS=hermes claude' "$BRAIN/brain.env"; then pass saved-backends; else fail saved-backends 'backend selection not retained'; fi
[ ! -s "$TMP/log/curl.log" ] && pass no-telegram-send || fail no-telegram-send 'sent without explicit test request'
# A plain rerun in a real terminal must finish without a single interview/consent prompt.
sandbox python3 -I - "$BRAIN/setup.sh" "$TMP/interactive.log" <<'PY'
import os,pty,select,signal,sys,time
pid,fd=pty.fork()
if pid==0:
    os.execv(sys.argv[1],[sys.argv[1]])
output=b''; status=None; deadline=time.monotonic()+40
while time.monotonic()<deadline:
    if select.select([fd],[],[],0.1)[0]:
        try: output+=os.read(fd,65536)
        except OSError: pass
    done,s=os.waitpid(pid,os.WNOHANG)
    if done: status=s; break
    if b'[y/N]' in output or b'Your name [' in output or b'Backends (' in output:
        break
if status is None:
    os.kill(pid,signal.SIGKILL); os.waitpid(pid,0)
with open(sys.argv[2],'wb') as f: f.write(output)
sys.exit(0 if status==0 else 1)
PY
[ $? = 0 ] && pass real-rerun || fail real-rerun 'plain setup prompted or failed'
sandbox "$BRAIN/setup.sh" --yes --kit "$KIT" --backends claude --telegram n >"$TMP/override.log" 2>&1
[ $? = 0 ] && grep -qx 'DEFAULT_BACKEND=claude' "$BRAIN/brain.env" && pass explicit-override || fail explicit-override 'explicit backend ignored'
rm "$HOME_DIR/.local/bin/brief-check"
sandbox "$BRAIN/setup.sh" --yes --kit "$KIT" >"$TMP/repair.log" 2>&1
[ $? = 0 ] && [ -x "$HOME_DIR/.local/bin/brief-check" ] && pass repair-links || fail repair-links 'missing command was not repaired'
grep -q '10. Final checks' "$TMP/repair.log" && pass final-checks || fail final-checks 'skipped final checks'
# Interpose only the checker's entry point, retaining its real diagnostics. An old
# example-only final check cannot satisfy this marker or propagate this failure.
mv "$BRAIN/setup-check.sh" "$BRAIN/setup-check-real.sh"
printf '#!/bin/sh\nprintf "called\\n" >>"%s/checker.calls"\nexec sh "%s/setup-check-real.sh" "$@"\n' "$TMP" "$BRAIN" >"$BRAIN/setup-check.sh"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/acceptance.log" 2>&1
if [ $? = 0 ] && [ -f "$TMP/checker.calls" ] && [ "$(wc -l <"$TMP/checker.calls")" -eq 1 ] \
   && grep -q 'PASS: local canary baseline' "$TMP/acceptance.log" \
   && grep -q 'live handoff NOT TESTED' "$TMP/acceptance.log" \
   && ! grep -q 'ready: brief-check on the example brief' "$TMP/acceptance.log"; then
  pass rerun-acceptance
else fail rerun-acceptance 'real final acceptance not executed on rerun'; fi
printf '#!/bin/sh\nexit 37\n' >"$BRAIN/setup-check.sh"
sandbox "$BRAIN/setup.sh" --yes >"$TMP/acceptance-fail.log" 2>&1
if [ $? = 1 ] && grep -q 'NOT READY: local setup acceptance' "$TMP/acceptance-fail.log"; then
  pass rerun-acceptance-failure
else fail rerun-acceptance-failure 'checker failure ignored on rerun'; fi
echo "$passed passed, $failed failed"
[ "$failed" = 0 ]

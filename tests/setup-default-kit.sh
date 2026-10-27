#!/usr/bin/env bash
# Default dependency path, not --kit. Offline by default; explicit network opt-in
# exercises the same installation against the public pinned source in an isolated HOME.
CASES=(repaired-pin default-install default-revision default-rerun default-profiles default-safety)
. "$(dirname "$0")/sandbox.sh"
fake_hermes
pin_url=$(sed -n 's/^HANDOFF_KIT_URL=//p' "$ROOT/handoff-kit.pin")
pin_ref=$(sed -n 's/^HANDOFF_KIT_TAG=//p' "$ROOT/handoff-kit.pin")
expected=$(git -C "$KIT" rev-parse "$pin_ref^{commit}") || fail_all 'pin cannot resolve'
# This repair must remain in every subsequently selected kit version.
required=6a1eae82e0644237d4c80db652da3f68e00a9848
if git -C "$KIT" merge-base --is-ancestor "$required" "$expected"; then
  pass repaired-pin
else
  fail repaired-pin 'default dependency predates the Hermes compatibility repair'
fi
if [ "${SETUP_DEFAULT_KIT_NETWORK:-0}" != 1 ]; then
  # Interpose only the public clone transport; real git checkout and real kit install
  # still run. The production pin and installer arguments are never rewritten.
  real_git=$(command -v git)
  python3 -I - "$TMP/fakes/git" "$real_git" "$pin_url" "$KIT" "$TMP/log/default-clone.log" <<'PY'
import pathlib, sys
path, git, url, kit, log = sys.argv[1:]
pathlib.Path(path).write_text('''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if args[:1] == ['clone']:
    if %r in args:
        with open(%r, 'a') as f: f.write('default-source-requested\\n')
        args = [%r if x == %r else x for x in args]
    elif any(x.startswith(('https://', 'http://', 'ssh://')) for x in args):
        sys.exit('unexpected network clone in offline test')
os.execv(%r, [%r] + args)
''' % (url, log, kit, url, git, git))
pathlib.Path(path).chmod(0o755)
PY
fi
installed=$HOME_DIR/.local/share/handoff-kit
sandbox "$BRAIN/setup.sh" "${SETUP_ARGS[@]}" --backends hermes --hermes-hooks n \
  --telegram n --journal n --linger n >"$TMP/first.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass default-install || fail default-install "fresh default setup exit $rc"
actual=$(git -C "$installed" rev-parse HEAD 2>/dev/null)
if [ "$actual" = "$expected" ] && ! /usr/bin/grep -q '^SETUP_KIT=.' "$BRAIN/brain.env"; then
  pass default-revision
else fail default-revision 'wrong installed revision or custom-kit override saved'; fi
sandbox "$BRAIN/setup.sh" --yes >"$TMP/rerun.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ "$(git -C "$installed" rev-parse HEAD 2>/dev/null)" = "$expected" ]; then
  pass default-rerun
else fail default-rerun 'plain rerun failed or changed the dependency'; fi
bad=0
for profile in review run close; do
  [ -s "$HOME_DIR/.hermes/profiles/$profile/SOUL.md" ] && \
    [ -s "$HOME_DIR/.hermes/profiles/$profile/config.yaml" ] || bad=1
done
[ "$bad" = 0 ] && pass default-profiles || fail default-profiles 'missing seeded stage profiles'
bad=0
for cmd in sudo apt-get dnf curl launchctl loginctl; do
  [ ! -s "$TMP/log/$cmd.log" ] || bad=1
done
if /usr/bin/grep -E 'enable|start|restart' "$TMP/log/systemctl.log" >/dev/null 2>&1; then bad=1; fi
if /usr/bin/grep '^hermes ' "$TMP/log/hermes.log" | /usr/bin/grep -v -E '^hermes (-p [^ ]+ )?config (path|get|set)( |$)' >/dev/null; then bad=1; fi
[ "$bad" = 0 ] && pass default-safety || fail default-safety 'unexpected package, service, notification or model command'
if [ "$failed" -ne 0 ]; then
  for log in "$TMP/first.log" "$TMP/rerun.log"; do [ ! -f "$log" ] || cat "$log"; done
fi
echo "default dependency $expected (public network: ${SETUP_DEFAULT_KIT_NETWORK:-0})"
echo "$passed passed, $failed failed"
[ "$failed" = 0 ]

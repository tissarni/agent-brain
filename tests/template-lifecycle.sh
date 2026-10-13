#!/usr/bin/env bash
# Lifecycle test: extract the template, update a brain from it, remove the example.
# Same sandbox as tests/setup-smoke.sh (tests/sandbox.sh), offline; nothing is written
# outside its mktemp -d. Output: one "PASS <case>" or "FAIL <case> — <why>" per case,
# then "<n> passed, <m> failed".

CASES=(extract-copies extract-refuses update-merges update-lists-local update-conflict
  update-refuses-dirty update-fills-example-seed remove-example remove-example-again update-after-remove
  update-after-hand-delete update-hermes-hooks)

. "$(dirname "$0")/sandbox.sh"

DEMO=$CODE/agent-brain-demo
EX_LINE_1='- **example** 🟢 — 🟢1 — a demo main to try the handoff kit on; ./setup.sh --remove-example deletes it'
EX_LINE_2='  - example-version-flag'
BR=(git -C "$BRAIN")
SRC=(git -C "$TMP/src")

tail_log() { tail -n 3 "$1" | paste -s -d'|'; }
brain_commit() { # brain_commit <msg>: commit everything in the brain
  "${BR[@]}" add -A && "${BR[@]}" "${GIT_ID[@]}" commit -q -m "$1"
}
src_commit() { # src_commit <msg>: commit in the template source and publish it to the bare repo
  "${SRC[@]}" add -A && "${SRC[@]}" "${GIT_ID[@]}" commit -q -m "$1" \
    && "${SRC[@]}" push -q "$TMP/template.git" main
}
update() { run_setup "$BRAIN" --update --yes --kit "$KIT" >"$TMP/update.log" 2>&1; }

case_extract_copies() {
  local want got
  bash "$ROOT/extract-template.sh" "$TMP/x" >/dev/null 2>&1 || { fail extract-copies "exit $?"; return; }
  want=$(cd "$ROOT" && ./template-files.sh)
  got=$(cd "$TMP/x" && find . -type f | sed 's|^\./||' | sort)
  [ "$want" = "$got" ] || { fail extract-copies "file lists differ"; return; }
  [ -x "$TMP/x/setup.sh" ] || { fail extract-copies "setup.sh lost its execute bit"; return; }
  pass extract-copies
}

case_extract_refuses() {
  local rc
  mkdir -p "$TMP/full" && : >"$TMP/full/f"
  bash "$ROOT/extract-template.sh" "$TMP/full" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] || { fail extract-refuses "non-empty destination exited $rc"; return; }
  bash "$ROOT/extract-template.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && pass extract-refuses || fail extract-refuses "no argument exited $rc"
}

# The brain is set up once; the update and remove cases build on each other.
run_setup "$BRAIN" "${SETUP_ARGS[@]}" --kit "$KIT" >"$TMP/setup1.log" 2>&1 \
  || fail_all "first setup failed: $(tail_log "$TMP/setup1.log")"
brain_commit "brain: first setup" || fail_all "cannot commit the set-up brain"

case_update_merges() {
  local rc
  echo "template line one" >>"$TMP/src/SKILLS.md"
  src_commit "template: skills line" || { fail update-merges "cannot publish the template commit"; return; }
  echo "a note of mine" >"$BRAIN/00-inbox/note.md"
  brain_commit "brain: note" || { fail update-merges "cannot commit the note"; return; }
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-merges "exit $rc: $(tail_log "$TMP/update.log")"; return; }
  /usr/bin/grep -q -x 'template line one' "$BRAIN/SKILLS.md" || { fail update-merges "the template change did not arrive"; return; }
  [ -f "$BRAIN/00-inbox/note.md" ] || { fail update-merges "the note is gone"; return; }
  [ "$("${BR[@]}" rev-list --parents -n 1 HEAD | wc -w)" -eq 3 ] || { fail update-merges "HEAD is not a merge commit"; return; }
  pass update-merges
}

case_update_lists_local() {
  local rc
  echo "local tweak" >>"$BRAIN/README.md"
  brain_commit "brain: readme tweak" || { fail update-lists-local "cannot commit"; return; }
  echo "template line two" >>"$TMP/src/SKILLS.md"
  src_commit "template: skills line two" || { fail update-lists-local "cannot publish"; return; }
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-lists-local "exit $rc: $(tail_log "$TMP/update.log")"; return; }
  /usr/bin/grep -q -F 'README.md' "$TMP/update.log" && pass update-lists-local || fail update-lists-local "output does not name README.md"
}

case_update_conflict() {
  local rc
  echo "brain side" >>"$BRAIN/SKILLS.md"
  brain_commit "brain: skills side" || { fail update-conflict "cannot commit"; return; }
  echo "template side" >>"$TMP/src/SKILLS.md"
  src_commit "template: skills side" || { fail update-conflict "cannot publish"; return; }
  update; rc=$?
  [ "$rc" -eq 1 ] || { fail update-conflict "exit $rc, not 1"; return; }
  /usr/bin/grep -q -F 'git merge --abort' "$TMP/update.log" || { fail update-conflict "no 'git merge --abort' in the output"; return; }
  "${BR[@]}" merge --abort >/dev/null 2>&1
  # Take the template's side so the next cases start from a clean, merged brain.
  "${BR[@]}" "${GIT_ID[@]}" merge -q -s ours --no-edit template/main >/dev/null 2>&1 || true
  pass update-conflict
}

case_update_refuses_dirty() {
  local rc
  echo "uncommitted" >>"$BRAIN/AGENTS.local.md"
  update; rc=$?
  "${BR[@]}" checkout -q -- AGENTS.local.md
  [ "$rc" -eq 1 ] && pass update-refuses-dirty || fail update-refuses-dirty "exit $rc, not 1"
}

case_update_fills_example_seed() {
  local rc f
  f=$(ls "$BRAIN"/02-projects/example/subprojects/example-version-flag/specs/*-brief-1-* 2>/dev/null | head -n 1)
  [ -n "$f" ] || { fail update-fills-example-seed "no example brief to remove"; return; }
  rm -f "$f"
  brain_commit "brain: example brief removed" || { fail update-fills-example-seed "cannot commit"; return; }
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-fills-example-seed "exit $rc: $(tail_log "$TMP/update.log")"; return; }
  [ -f "$f" ] || { fail update-fills-example-seed "the brief did not come back"; return; }
  ! /usr/bin/grep -q -F '@DEMO_REPO@' "$f" || { fail update-fills-example-seed "@DEMO_REPO@ is still in the brief"; return; }
  /usr/bin/grep -q -F "$DEMO" "$f" || { fail update-fills-example-seed "the demo path is not in the brief"; return; }
  # update leaves the re-seeded file untracked; remove-example needs a clean tree.
  brain_commit "brain: example brief restored" || { fail update-fills-example-seed "cannot commit the restored brief"; return; }
  pass update-fills-example-seed
}

case_remove_example() {
  local rc before after
  before=$(/usr/bin/grep -v -x -F -e "$EX_LINE_1" -e "$EX_LINE_2" "$BRAIN/AGENTS.local.md")
  run_setup "$BRAIN" --remove-example --yes >"$TMP/remove.log" 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { fail remove-example "exit $rc: $(tail_log "$TMP/remove.log")"; return; }
  [ ! -e "$BRAIN/02-projects/example" ] || { fail remove-example "the example folder is still there"; return; }
  { [ ! -e "$DEMO" ] && [ ! -e "$DEMO.git" ]; } || { fail remove-example "the demo repository or its origin is still there"; return; }
  ! /usr/bin/grep -q -x -F -e "$EX_LINE_1" -e "$EX_LINE_2" "$BRAIN/AGENTS.local.md" || { fail remove-example "an example line is still in AGENTS.local.md"; return; }
  after=$(cat "$BRAIN/AGENTS.local.md")
  [ "$before" = "$after" ] || { fail remove-example "AGENTS.local.md changed beyond the two lines"; return; }
  pass remove-example
}

case_remove_example_again() {
  local rc
  run_setup "$BRAIN" --remove-example --yes >"$TMP/remove2.log" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && pass remove-example-again || fail remove-example-again "exit $rc: $(tail_log "$TMP/remove2.log")"
}

case_update_after_remove() {
  local rc
  brain_commit "brain: example removed" >/dev/null 2>&1
  echo "# template line three" >>"$TMP/src/.gitattributes"
  src_commit "template: skills line three" || { fail update-after-remove "cannot publish"; return; }
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-after-remove "exit $rc: $(tail_log "$TMP/update.log")"; return; }
  if [ ! -e "$BRAIN/02-projects/example" ] && [ ! -e "$DEMO" ] && [ ! -e "$DEMO.git" ]; then
    pass update-after-remove
  else
    fail update-after-remove "the example or the demo came back"
  fi
}

case_update_after_hand_delete() {
  local rc
  # The brain has no example; forget that it was removed, as a hand-delete would have.
  /usr/bin/grep -v -x 'EXAMPLE=removed' "$BRAIN/brain.env" >"$TMP/brain.env.new"
  cat "$TMP/brain.env.new" >"$BRAIN/brain.env"
  ! /usr/bin/grep -q '^EXAMPLE=' "$BRAIN/brain.env" || { fail update-after-hand-delete "EXAMPLE= is still in brain.env"; return; }
  brain_commit "brain: example forgotten" || { fail update-after-hand-delete "cannot commit"; return; }
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-after-hand-delete "exit $rc: $(tail_log "$TMP/update.log")"; return; }
  [ ! -e "$BRAIN/02-projects/example" ] || { fail update-after-hand-delete "the example came back"; return; }
  [ ! -e "$DEMO" ] || { fail update-after-hand-delete "the demo repository was created"; return; }
  /usr/bin/grep -q -x 'EXAMPLE=removed' "$BRAIN/brain.env" || { fail update-after-hand-delete "brain.env has no EXAMPLE=removed line"; return; }
  brain_commit "brain: example recorded as removed" >/dev/null 2>&1
  pass update-after-hand-delete
}

case_update_hermes_hooks() {
  local rc bad=
  fake_hermes
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-hermes-hooks "exit $rc: $(tail_log "$TMP/update.log")"; return; }
  /usr/bin/grep -q -F -e '--hermes-hooks y' "$TMP/update.log" || bad="$bad [log does not name --hermes-hooks y]"
  if [ -f "$TMP/log/hermes.log" ] && /usr/bin/grep -q -F ' config set ' "$TMP/log/hermes.log"; then
    bad="$bad [registered without a flag]"
  fi
  printf '%s\n' "{\"hooks\": {\"pre_tool_call\": [{\"matcher\": \"terminal\", \"command\": \"python3 $BRAIN/.claude/hooks/guard-git-refs.py\"}]}}" >"$HOME_DIR/.hermes/config.json"
  update; rc=$?
  [ "$rc" -eq 0 ] || { fail update-hermes-hooks "second update exit $rc: $(tail_log "$TMP/update.log")"; return; }
  python3 -I - "$HOME_DIR/.hermes" "$BRAIN" <<'EOF' || bad="$bad [config or allowlist]"
import json, shlex, sys
home, brain = sys.argv[1:3]
cfg = json.load(open(home + "/config.json"))["hooks"]
guard = "python3 " + shlex.quote(brain + "/.claude/hooks/guard-git-refs.py")
auto = "sh %s --hermes-hook" % shlex.quote(brain + "/auto-commit.sh")
assert [e["command"] for e in cfg["pre_tool_call"]] == [guard], cfg
assert [e["command"] for e in cfg["on_session_end"]] == [auto], cfg
ap = json.load(open(home + "/shell-hooks-allowlist.json"))["approvals"]
assert sorted((a["event"], a["command"]) for a in ap) == sorted([("pre_tool_call", guard), ("on_session_end", auto)]), ap
EOF
  [ -z "$bad" ] && pass update-hermes-hooks || fail update-hermes-hooks "$bad"
}

case_extract_copies
case_extract_refuses
case_update_merges
case_update_lists_local
case_update_conflict
case_update_refuses_dirty
case_update_fills_example_seed
case_remove_example
case_remove_example_again
case_update_after_remove
case_update_after_hand_delete
case_update_hermes_hooks

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

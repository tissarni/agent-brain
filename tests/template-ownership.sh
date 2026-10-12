#!/usr/bin/env bash
# Tests for template-files.sh, the pre-commit drift warning and auto-commit.sh.
# Every case runs in a throwaway repository under mktemp -d; nothing touches this worktree.
# Output: one "PASS <case>" or "FAIL <case> — <why>" per case, then "<n> passed, <m> failed".

# The launcher's git config override would send commits to its hooks instead of the ones under test.
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0
OUT=""
RC=0

pass() { echo "PASS $1"; passed=$((passed + 1)); }
fail() { echo "FAIL $1 — $2"; failed=$((failed + 1)); }

# new_repo <name>: an empty repository with identity, hooks path and an initial commit.
new_repo() {
  local d="$TMP/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.name tester
  git -C "$d" config user.email tester@example.invalid
  git -C "$d" config core.hooksPath .githooks
  git -C "$d" config commit.gpgsign false
  echo "$d"
}

# install_kit <repo>: copies of the real files the cases exercise.
install_kit() {
  local d="$1" f
  mkdir -p "$d/.githooks"
  for f in template.manifest template-files.sh .githooks/pre-commit auto-commit.sh AGENTS.md; do
    cp "$ROOT/$f" "$d/$f"
  done
  chmod +x "$d/.githooks/pre-commit" "$d/template-files.sh"
}

# commit_all <repo> <msg>: stage everything and commit; sets OUT and RC.
commit_all() {
  git -C "$1" add -A
  OUT=$(git -C "$1" commit -q -m "$2" 2>&1)
  RC=$?
}

case_files_lists_covered() {
  local d; d=$(new_repo files-lists)
  printf 'x/handoff\nx/one.md\n' > "$d/template.manifest"
  cp "$ROOT/template-files.sh" "$d/"
  mkdir -p "$d/x/handoff" "$d/x/handoff-local"
  echo a > "$d/x/handoff/SKILL.md"; echo b > "$d/x/one.md"
  echo c > "$d/x/handoff-local/SKILL.md"; echo d > "$d/local.md"
  git -C "$d" add -A
  local got want
  got=$(cd / && sh "$d/template-files.sh"); RC=$?
  want=$(printf 'x/handoff/SKILL.md\nx/one.md')
  [ "$RC" -eq 0 ] && [ "$got" = "$want" ] || { fail files-lists-covered "got: $(echo "$got" | paste -s -d,)"; return; }
  : > "$d/template.manifest"
  got=$(sh "$d/template-files.sh")
  [ -z "$got" ] || { fail files-lists-covered "empty manifest printed: $got"; return; }
  pass files-lists-covered
}

case_files_staged() {
  local d; d=$(new_repo files-staged)
  printf 'x/handoff\nx/one.md\nx/two.md\n' > "$d/template.manifest"
  cp "$ROOT/template-files.sh" "$d/"
  mkdir -p "$d/x/handoff"
  echo a > "$d/x/handoff/SKILL.md"; echo b > "$d/x/one.md"; echo c > "$d/x/two.md"; echo d > "$d/local.md"
  git -C "$d" add -A && git -C "$d" commit -q -m init
  echo edit >> "$d/x/handoff/SKILL.md"
  git -C "$d" rm -q x/one.md
  git -C "$d" mv x/two.md local-two.md
  echo edit >> "$d/local.md"
  git -C "$d" add -A
  local got want
  got=$(sh "$d/template-files.sh" --staged)
  want=$(printf 'x/handoff/SKILL.md\nx/one.md\nx/two.md')
  [ "$got" = "$want" ] && pass files-staged || fail files-staged "got: $(echo "$got" | paste -s -d,)"
}

case_files_usage() {
  local d; d=$(new_repo files-usage)
  printf 'x\n' > "$d/template.manifest"
  cp "$ROOT/template-files.sh" "$d/"
  sh "$d/template-files.sh" --bogus >/dev/null 2>&1; local rc1=$?
  rm "$d/template.manifest"
  sh "$d/template-files.sh" >/dev/null 2>&1; local rc2=$?
  [ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && pass files-usage || fail files-usage "exit codes $rc1 $rc2"
}


# downstream <name> <brain.env yes|no> <remote yes|no>: a kit repository with one commit.
downstream() {
  local d; d=$(new_repo "$1")
  install_kit "$d"
  mkdir -p "$d/notes"; echo n > "$d/notes/a.md"
  git -C "$d" add -A && git -C "$d" commit -q -m init
  [ "$2" = yes ] && echo 'CODE_ROOT=~/x' > "$d/brain.env" && git -C "$d" add brain.env && git -C "$d" commit -q -m env
  [ "$3" = yes ] && git -C "$d" remote add template https://example.invalid/t.git
  echo "$d"
}

hook_quiet() { # <case> <brain.env> <remote>
  local d; d=$(downstream "$1" "$2" "$3")
  echo change >> "$d/AGENTS.md"
  commit_all "$d" change
  if [ "$RC" -ne 0 ]; then fail "$1" "commit exited $RC"
  elif [[ "$OUT" == *template-owned* ]]; then fail "$1" "warned: $OUT"
  else pass "$1"; fi
}

case_hook_quiet_without_brain_env() { hook_quiet hook-quiet-without-brain-env no yes; }
case_hook_quiet_without_template_remote() { hook_quiet hook-quiet-without-template-remote yes no; }

case_hook_warns_downstream() {
  local d; d=$(downstream hook-warns yes yes)
  echo change >> "$d/AGENTS.md"; echo change >> "$d/notes/a.md"
  commit_all "$d" change
  if [ "$RC" -ne 0 ]; then fail hook-warns-downstream "commit exited $RC"
  elif [[ "$OUT" != *template-owned* || "$OUT" != *AGENTS.md* ]]; then fail hook-warns-downstream "no warning: $OUT"
  elif [[ "$OUT" == *notes/a.md* ]]; then fail hook-warns-downstream "named the note: $OUT"
  else pass hook-warns-downstream; fi
}

case_hook_mirror_still_refuses() {
  local d; d=$(downstream hook-mirror no no)
  cp "$ROOT/sync-skills.sh" "$d/"
  mkdir -p "$d/.agents/skills/foo" "$d/.claude/skills/foo"
  echo a > "$d/.agents/skills/foo/SKILL.md"; echo b > "$d/.claude/skills/foo/SKILL.md"
  commit_all "$d" drift
  [ "$RC" -ne 0 ] && pass hook-mirror-still-refuses || fail hook-mirror-still-refuses "commit succeeded"
}

# run_auto <repo>: run auto-commit.sh, sets OUT and records HEAD before/after.
run_auto() {
  BEFORE=$(git -C "$1" rev-parse HEAD)
  OUT=$(sh "$1/auto-commit.sh" 2>&1)
  AFTER=$(git -C "$1" rev-parse HEAD)
}

case_autocommit_warns_downstream() {
  local d; d=$(downstream autocommit-warns yes yes)
  echo change >> "$d/AGENTS.md"
  run_auto "$d"
  local msg
  msg=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["systemMessage"])' 2>&1) \
    || { fail autocommit-warns-downstream "bad JSON: $OUT"; return; }
  [ "$(printf '%s\n' "$OUT" | wc -l)" -eq 1 ] || { fail autocommit-warns-downstream "not one line: $OUT"; return; }
  [[ "$msg" == *template-owned* && "$msg" == *AGENTS.md* ]] || { fail autocommit-warns-downstream "message: $msg"; return; }
  [ "$BEFORE" != "$AFTER" ] && pass autocommit-warns-downstream || fail autocommit-warns-downstream "HEAD did not move"
}

case_autocommit_quiet_local() {
  local d; d=$(downstream autocommit-quiet yes yes)
  echo change >> "$d/notes/a.md"
  run_auto "$d"
  [ "$OUT" = '{"suppressOutput": true}' ] && [ "$BEFORE" != "$AFTER" ] && pass autocommit-quiet-local || fail autocommit-quiet-local "out: $OUT"
}

case_autocommit_caps_list() {
  local d f; d=$(downstream autocommit-caps yes yes)
  for f in AGENTS.md template.manifest template-files.sh auto-commit.sh .githooks/pre-commit; do
    echo "# more" >> "$d/$f"
  done
  run_auto "$d"
  [[ "$OUT" == *"+2 more"* ]] && [ "$BEFORE" != "$AFTER" ] && pass autocommit-caps-list || fail autocommit-caps-list "out: $OUT"
}

case_files_lists_covered
case_files_staged
case_files_usage
case_hook_quiet_without_brain_env
case_hook_quiet_without_template_remote
case_hook_warns_downstream
case_hook_mirror_still_refuses
case_autocommit_warns_downstream
case_autocommit_quiet_local
case_autocommit_caps_list

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

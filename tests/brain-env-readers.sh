#!/usr/bin/env bash
# Tests for the scripts that read brain.env: the HTML theme and the docs-site builder.
# Every case runs in a throwaway directory under mktemp -d; HOME points inside it, so
# nothing touches this worktree or the live docs site.
# Output: one "PASS <case>" or "FAIL <case> — <why>" per case, then "<n> passed, <m> failed".

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0

pass() { echo "PASS $1"; passed=$((passed + 1)); }
fail() { echo "FAIL $1 — $2"; failed=$((failed + 1)); }

# new_brain <name>: a plain directory (not a repository) holding a copy of doc-build,
# one main project and an empty brain.env. Prints its path.
new_brain() {
  local d="$TMP/$1/brain"
  mkdir -p "$d/.agents/skills" "$d/02-projects/demo" "$TMP/$1/home"
  cp -r "$ROOT/.agents/skills/doc-build" "$d/.agents/skills/"
  printf -- '---\nproject: demo\nkind: main\n---\n# Demo\n' > "$d/02-projects/demo/context.md"
  : > "$d/brain.env"
  echo "$d"
}

# page <brain>: builds the demo project's page, prints its path.
page() {
  HOME="$(dirname "$1")/home" node "$1/.agents/skills/doc-build/build.js" "$1/02-projects/demo" "$1/page.html" >/dev/null 2>&1
  echo "$1/page.html"
}

has() { /usr/bin/grep -q -F -e "$2" "$1"; }

case_theme_neutral() {
  local d p; d=$(new_brain theme-neutral); p=$(page "$d")
  [ -f "$p" ] || { fail theme-neutral "no page built"; return; }
  has "$p" '<img class="brand-logo"' && { fail theme-neutral "logo present"; return; }
  has "$p" '--brand: #1d4ed8' && pass theme-neutral || fail theme-neutral "neutral colour missing"
}

case_theme_local() {
  local d p; d=$(new_brain theme-local)
  mkdir -p "$d/themes/t"
  echo 'HTML_THEME=themes/t' > "$d/brain.env"
  echo ':root { --brand: #123456; }' > "$d/themes/t/theme.css"
  echo '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>' > "$d/themes/t/logo.svg"
  p=$(page "$d")
  [ -f "$p" ] || { fail theme-local "no page built"; return; }
  has "$p" '#123456' && has "$p" '<img class="brand-logo"' && has "$p" 'svg+xml;base64,' \
    && pass theme-local || fail theme-local "colour, logo or svg type missing"
}

case_theme_home_path() {
  local d p; d=$(new_brain theme-home)
  mkdir -p "$TMP/theme-home/home/th"
  echo 'HTML_THEME=~/th' > "$d/brain.env"
  echo ':root { --brand: #654321; }' > "$TMP/theme-home/home/th/theme.css"
  p=$(page "$d")
  has "$p" '#654321' && pass theme-home-path || fail theme-home-path "home theme not applied"
}

case_docs_site_dir() {
  local d t; d=$(new_brain docs-site); t="$TMP/docs-site"
  cp "$ROOT/build-docs-site.py" "$d/"
  echo 'DOCS_SITE_DIR=~/site' > "$d/brain.env"
  (cd "$d" && HOME="$t/home" python3 build-docs-site.py >/dev/null 2>&1) || { fail docs-site-dir "builder failed"; return; }
  [ -f "$t/home/site/index.html" ] && [ -f "$t/home/site/02-projects/demo/doc.html" ] \
    || { fail docs-site-dir "pages missing"; return; }
  has "$t/home/site/index.html" '<title>brain docs</title>' && pass docs-site-dir || fail docs-site-dir "title is not 'brain docs'"
}

case_docs_site_dir_inside_brain() {
  local d t v rc; d=$(new_brain docs-inside); t="$TMP/docs-inside"
  cp "$ROOT/build-docs-site.py" "$d/"
  for v in . out "$t"; do
    echo "DOCS_SITE_DIR=$v" > "$d/brain.env"
    echo keep > "$d/keep.txt"
    (cd "$d" && HOME="$t/home" python3 build-docs-site.py >/dev/null 2>&1); rc=$?
    [ "$rc" -ne 0 ] || { fail docs-site-dir-inside-brain "DOCS_SITE_DIR=$v exited 0"; return; }
    [ ! -e "$d/index.html" ] && [ ! -e "$d/out" ] && [ ! -e "$t/index.html" ] \
      || { fail docs-site-dir-inside-brain "DOCS_SITE_DIR=$v wrote output"; return; }
    [ -f "$d/keep.txt" ] || { fail docs-site-dir-inside-brain "DOCS_SITE_DIR=$v removed keep.txt"; return; }
  done
  pass docs-site-dir-inside-brain
}

case_theme_neutral
case_theme_local
case_theme_home_path
case_docs_site_dir
case_docs_site_dir_inside_brain

# guard_exit <brain> <home> <command>: the guard's exit status for one Bash command.
# The command is JSON-encoded by python3; stdin is the hook payload.
guard_exit() {
  local d="$1" h="$2" c="$3"
  python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$c" \
    | CLAUDE_PROJECT_DIR="$d" HOME="$h" python3 "$ROOT/.claude/hooks/guard-git-refs.py" >/dev/null 2>&1
  echo $?
}

# expect <want> <command>...: appends to $bad each command whose status differs from want.
# Uses $G_BRAIN and $G_HOME.
expect() {
  local want="$1" c got; shift
  for c in "$@"; do
    got=$(guard_exit "$G_BRAIN" "$G_HOME" "$c")
    [ "$got" = "$want" ] || bad="$bad [$c: $got, want $want]"
  done
}

# new_guard_brain <name> <brain.env content>: <t>/code/brain, sets G_BRAIN and G_HOME.
new_guard_brain() {
  local t="$TMP/$1" d="$TMP/$1/code/brain"
  mkdir -p "$d" "$t/code/app"
  printf '%s\n' "$2" > "$d/brain.env"
  G_BRAIN="$d"; G_HOME="$t"
}

case_guard_run_commands() {
  local t="$TMP/g-run"; bad=
  new_guard_brain g-run "CODE_ROOT=$t/code
PROTECTED_BRANCHES=main release"
  expect 0 'git merge origin/main' \
    'git push origin feat/x && gh pr create --draft --base main' \
    'git push -u origin feat/x && rm -f x' \
    "git -C $t/code/brain commit -m x"
  [ -z "$bad" ] && pass guard-run-commands || fail guard-run-commands "$bad"
}

case_guard_this_brain() {
  local b=main first; bad=
  if [ -f "$ROOT/brain.env" ]; then
    first=$(sed -n 's/^PROTECTED_BRANCHES=//p' "$ROOT/brain.env" | head -1 | cut -d' ' -f1)
    [ -n "$first" ] && b=$first
  fi
  G_BRAIN="$ROOT"; G_HOME="$HOME"
  expect 0 'git merge origin/main' \
    "git push origin feat/x && gh pr create --draft --base $b" \
    'git push -u origin feat/x && rm -f x' \
    "git -C $ROOT commit -m x"
  expect 2 "git push origin $b"
  [ -z "$bad" ] && pass guard-this-brain || fail guard-this-brain "$bad"
}

case_guard_nested_brain() {
  local t="$TMP/g-nest" d="$TMP/g-nest/code/grp/brain" i="$TMP/g-in/brain"; bad=
  mkdir -p "$d" "$t/code/grp/other" "$i/code/app"
  echo 'CODE_ROOT=~/code' > "$d/brain.env"
  G_BRAIN="$d"; G_HOME="$t"
  expect 0 "git -C $d commit -m x" 'git -C ~/code/grp/brain commit -m x' "git -C $d/sub commit -m x"
  expect 2 "git -C $t/code/grp commit -m x" "git -C $t/code/grp/other commit -m x" 'git -C ~/code/app commit -m x'
  echo 'CODE_ROOT=code' > "$i/brain.env"
  G_BRAIN="$i"; G_HOME="$TMP/g-in"
  expect 2 "git -C $i/code/app commit -m x"
  [ -z "$bad" ] && pass guard-nested-brain || fail guard-nested-brain "$bad"
}

case_guard_protected_from_env() {
  bad=
  new_guard_brain g-env "PROTECTED_BRANCHES=main release"
  expect 2 'git push origin release'
  expect 0 'git push origin dev'
  [ -z "$bad" ] && pass guard-protected-from-env || fail guard-protected-from-env "$bad"
}

case_guard_defaults() {
  bad=
  new_guard_brain g-def ""
  rm -f "$G_BRAIN/brain.env"
  expect 2 'git push origin dev'
  [ -z "$bad" ] && pass guard-defaults || fail guard-defaults "$bad"
}

case_guard_refusals() {
  local t="$TMP/g-ref"; bad=
  new_guard_brain g-ref "CODE_ROOT=$t/code"
  expect 2 'git push --force origin feat/x' 'git push' 'git merge main' \
    'git checkout main && git merge feat/x' 'gh pr merge 3' \
    "git -C $t/code/app commit -m x" 'git -C ~/code/app commit -m x'
  expect 0 'git checkout -b feat/x origin/main' 'git switch -c feat/x main'
  [ -z "$bad" ] && pass guard-refusals || fail guard-refusals "$bad"
}

case_guard_commit_subcommand() {
  local t="$TMP/g-sub"; bad=
  new_guard_brain g-sub "CODE_ROOT=$t/code"
  expect 0 "git -C $t/code/app log --grep commit" \
    "git -C $t/code/app rev-parse HEAD^{commit}" \
    $'git -C '"$t"$'/code/app status\necho commit' \
    "wsl -d Debian -- git commit -m x"
  expect 2 "cd $t/code/app && git commit -m x" \
    "git -c user.name=x -C $t/code/app commit -m x" \
    'git --no-pager -C ~/code/app commit -m x'
  [ -z "$bad" ] && pass guard-commit-subcommand || fail guard-commit-subcommand "$bad"
}

case_guard_subcommand_args() {
  local t="$TMP/g-args"; bad=
  new_guard_brain g-args "CODE_ROOT=$t/code"
  expect 0 'git diff main -- .githooks/pre-push' \
    'git rm -f .githooks/pre-push' \
    'git merge-base main HEAD' \
    'git log main -- docs/merge.md' \
    'git -C ~/code/main push origin feat/x'
  expect 2 'git -C ~/code/app push origin main' \
    'git --no-pager push origin main' \
    'git --no-pager push' \
    'git -c core.x=y merge main'
  [ -z "$bad" ] && pass guard-subcommand-args || fail guard-subcommand-args "$bad"
}

case_guard_quoted_options() {
  local t="$TMP/g-quoted"; bad=
  new_guard_brain g-quoted "CODE_ROOT=$t/code"
  expect 2 'git -C "/a b" push origin main' \
    "git -C '/a b' push --force origin feat/x" \
    'git -c user.name="A B" push origin main' \
    'git --git-dir="/a b/.git" push origin main' \
    'git -C "/a b" push' \
    'git -C "/a b" merge main' \
    "git -c user.name=\"A B\" -C $t/code/app commit -m x"
  expect 0 'git -C "/a b" push origin feat/x' \
    'git -c user.name="A B" log --oneline'
  [ -z "$bad" ] && pass guard-quoted-options || fail guard-quoted-options "$bad"
}

case_guard_fail_open() {
  local rc
  echo 'not json' | CLAUDE_PROJECT_DIR="$ROOT" python3 "$ROOT/.claude/hooks/guard-git-refs.py" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && pass guard-fail-open || fail guard-fail-open "exit $rc"
}

# payload_exit <guard> <event> <cwd> <command> <CLAUDE_PROJECT_DIR>: sends the guard a hook
# payload and prints its exit code.
payload_exit() {
  local g="$1" ev="$2" cwd="$3" cmd="$4" proj="$5" rc
  python3 -I -c 'import json,sys; print(json.dumps({"hook_event_name": sys.argv[1], "tool_name": "terminal", "cwd": sys.argv[2], "tool_input": {"command": sys.argv[3]}}))' "$ev" "$cwd" "$cmd" \
    | CLAUDE_PROJECT_DIR="$proj" python3 "$g" >/dev/null 2>&1; rc=$?
  echo "$rc"
}

case_guard_hermes_scope() {
  local t="$TMP/g-hermes" g got; bad=
  new_guard_brain g-hermes "PROTECTED_BRANCHES=trunk"
  mkdir -p "$G_BRAIN/.claude/hooks" "$G_BRAIN/notes" "$t/code/brain-x" "$t/other"
  cp "$ROOT/.claude/hooks/guard-git-refs.py" "$G_BRAIN/.claude/hooks/"
  echo 'PROTECTED_BRANCHES=main' > "$t/other/brain.env"
  g="$G_BRAIN/.claude/hooks/guard-git-refs.py"
  chk() { # chk <want> <event> <cwd> <command> <project dir>
    got=$(payload_exit "$g" "$2" "$3" "$4" "$5")
    [ "$got" = "$1" ] || bad="$bad [$2 $3 '$4': $got, want $1]"
  }
  chk 2 pre_tool_call "$G_BRAIN" 'git push origin trunk' "$t/other"
  chk 2 pre_tool_call "$G_BRAIN/notes" 'git push origin trunk' "$t/other"
  chk 0 pre_tool_call "$G_BRAIN" 'git push origin main' "$t/other"
  chk 0 pre_tool_call "$t/code/app" 'git push origin trunk' "$t/other"
  chk 0 pre_tool_call "" 'git push origin trunk' "$t/other"
  chk 0 pre_tool_call "$t/code/brain-x" 'git push origin trunk' "$t/other"
  chk 2 PreToolUse "$t/code/app" 'git push origin trunk' "$G_BRAIN"
  [ -z "$bad" ] && pass guard-hermes-scope || fail guard-hermes-scope "$bad"
}

# ctx_run <case> <tokens> <stdin>: runs a copy of context-guard.sh beside a brain.env with
# a threshold of 1000; sets $out and $rc.
ctx_run() {
  local t="$TMP/$1"
  mkdir -p "$t/home/.claude/projects/p" "$t/tmp" "$t/brain"
  cp "$ROOT/context-guard.sh" "$t/brain/"
  echo 'CONTEXT_GUARD_THRESHOLD=1000' > "$t/brain/brain.env"
  echo "{\"usage\":{\"cache_read_input_tokens\":$2}}" > "$t/home/.claude/projects/p/S1.jsonl"
  out=$(printf '%s' "$3" | HOME="$t/home" TMPDIR="$t/tmp" sh "$t/brain/context-guard.sh" 2>/dev/null); rc=$?
}

case_ctx_warns() {
  ctx_run ctx-warns 2000 '{"session_id":"S1"}'
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | wc -l)" = 1 ] \
    && printf '%s' "$out" | python3 -c 'import json,sys; m=json.load(sys.stdin)["systemMessage"]; assert "Context at 2k" in m' 2>/dev/null \
    && pass ctx-warns || fail ctx-warns "rc=$rc out=$out"
}

case_ctx_quiet() {
  ctx_run ctx-quiet 400 '{"session_id":"S1"}'
  [ "$rc" = 0 ] && [ -z "$out" ] && pass ctx-quiet || fail ctx-quiet "rc=$rc out=$out"
}

case_ctx_garbage() {
  ctx_run ctx-garbage 2000 x
  [ "$rc" = 0 ] && [ -z "$out" ] && pass ctx-garbage || fail ctx-garbage "rc=$rc out=$out"
}

case_guard_run_commands
case_guard_this_brain
case_guard_nested_brain
case_guard_protected_from_env
case_guard_defaults
case_guard_refusals
case_guard_commit_subcommand
case_guard_subcommand_args
case_guard_quoted_options
case_guard_hermes_scope
case_guard_fail_open
case_ctx_warns
case_ctx_quiet
case_ctx_garbage

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

#!/usr/bin/env bash
# Offline tests for publish-guard.sh.
# Everything happens under mktemp -d: a work repo with the gate as its pre-push hook, bare
# remotes on disk, a stand-in for a hook that chains to the gate, and a fake gh answering
# from JSON fixtures. No network, no host git config, no real HOME.
# Output: one "PASS <case>" or "FAIL <case> — <why>" per case, then "<n> passed, <m> failed".
# Needs git, GNU grep, jq (for the fake gh) and a temp dir.

unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_DIR GIT_WORK_TREE

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/publish-guard.sh"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

# No host config, and no launcher hooksPath override.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@example.com
export GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@example.com

# GNU grep, found as the script finds it: the grep on PATH may be BSD grep or ugrep.
GREP=
for c in ggrep grep; do
  p=$(command -v "$c" 2>/dev/null) || continue
  case "$("$p" --version 2>&1 | head -n 1)" in *"GNU grep"*) GREP=$p; break ;; esac
done
[ -n "$GREP" ] || { echo "GNU grep not found (on macOS: brew install grep)" >&2; exit 2; }

passed=0
failed=0

pass() { echo "PASS $1"; passed=$((passed + 1)); }
fail() { echo "FAIL $1 — $2"; failed=$((failed + 1)); sed 's/^/      /' "$T/out" 2>/dev/null; }

cat >"$T/patterns" <<'EOF'
# The test list.
acme

ti9999
\bbob\b
EOF
export PUBLISH_GUARD_PATTERNS="$T/patterns"

R="$T/remote.git" W="$T/work"
git init -q --bare "$R"
git init -q -b main "$W"
git -C "$W" remote add origin "$R"
printf '#!/bin/sh\nexec %s pre-push "$@"\n' "$GUARD" >"$W/.git/hooks/pre-push"
chmod +x "$W/.git/hooks/pre-push"

# put <path> <printf %b content> [message]: write a file in the work repo and commit it
put() {
  mkdir -p "$(dirname "$W/$1")"
  printf '%b' "$2" >"$W/$1"
  git -C "$W" add -A && git -C "$W" commit -q -m "${3:-add $1}"
}
branch() { git -C "$W" switch -q -c "$1" main; }
drop()   { git -C "$W" switch -q main && git -C "$W" branch -q -D "$1"; }
remote_refs() { git -C "$R" for-each-ref --format='%(refname) %(objectname)'; }

# push_ok <name> <git args...>
push_ok() {
  local name="$1"
  shift
  if git -C "$W" "$@" >"$T/out" 2>&1; then pass "$name"; else fail "$name" "the push was refused"; fi
}
# push_refused <name> <regex the output must hold> <git args...>
push_refused() {
  local name="$1" want="$2" before
  shift 2
  before="$(remote_refs)"
  if git -C "$W" "$@" >"$T/out" 2>&1; then fail "$name" "the push went through"; return; fi
  [ "$(remote_refs)" = "$before" ] || { fail "$name" "the remote changed"; return; }
  "$GREP" -qE "$want" "$T/out" || { fail "$name" "no /$want/ in the output"; return; }
  pass "$name"
}
# expect <exit code> <name> <command...>
expect() {
  local want="$1" name="$2" got
  shift 2
  "$@" >"$T/out" 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$name"; else fail "$name" "exit $got, wanted $want"; fi
}
# says <regex> <name>: the last output holds the regex
says() { if "$GREP" -qE "$1" "$T/out"; then pass "$2"; else fail "$2" "no /$1/ in the output"; fi; }

# pre-push gate
put README.md 'hello\n'
push_ok clean-push-passes push -q origin main

branch t2; put notes.txt 'built for ACME corp\n'
push_refused hit-in-file-text-refused 'notes.txt: ACME' push -q origin t2
drop t2

branch t3; put blob.bin 'x\0\001\002acme\0\377'
push_refused hit-in-binary-content-refused 'blob.bin: acme' push -q origin t3
drop t3

branch t4; put 'src/Acme/readme.txt' 'clean\n'
push_refused hit-in-directory-name-refused 'path: Acme' push -q origin t4
drop t4

branch t5; git -C "$W" commit -q --allow-empty -m 'fix for ti9999'
push_refused hit-in-commit-message-refused 'ti9999' push -q origin t5
drop t5

branch t6; GIT_AUTHOR_EMAIL=dev@acme.example git -C "$W" commit -q --allow-empty -m 'clean message'
push_refused hit-in-author-address-refused 'acme' push -q origin t6
drop t6

branch t7; GIT_COMMITTER_NAME=Bob git -C "$W" commit -q --allow-empty -m 'clean message'
push_refused hit-in-committer-name-refused 'Bob' push -q origin t7
drop t7

branch feature/ACME-login; put login.txt 'ok\n'
push_refused hit-in-branch-name-refused 'pushed ref refs/heads/feature/ACME-login' push -q origin feature/ACME-login
drop feature/ACME-login

git -C "$W" tag -a v0.1 -m 'release for Bob' main
push_refused hit-in-annotated-tag-refused 'tag object refs/tags/v0.1: Bob' push -q origin v0.1
git -C "$W" tag -d v0.1 >/dev/null
git -C "$W" tag v0.2 main
push_ok clean-lightweight-tag-passes push -q origin v0.2

branch t10; put cat.txt 'a bobcat\n'
push_ok word-edges-bobcat-passes push -q origin t10
put bob.txt 'ask Bob\n'
push_refused word-edges-bob-refused 'bob.txt: Bob' push -q origin t10
drop t10

branch t12; put planted.txt 'acme\n'
git -C "$W" push -q --no-verify origin t12   # a hit already public: only an audit can report it
put more.txt 'clean\n'
push_ok push-checks-only-what-remote-lacks push -q origin t12
drop t12

git -C "$W" push -q --no-verify origin main:refs/heads/acme-old
push_ok delete-remote-branch-named-with-hit-passes push -q origin --delete acme-old
push_ok delete-remote-branch-holding-hit-passes push -q origin --delete t12

# recreated remote: a repo recreated empty under its old URL leaves the remote-tracking refs
# pointing at commits the new repo does not have.
git init -q --bare "$T/fresh.git"
git -C "$W" remote add fresh "$T/fresh.git"
branch t11; put old.txt 'acme inside\n'
git -C "$W" push -q --no-verify fresh t11
rm -rf "$T/fresh.git" && git init -q --bare "$T/fresh.git"
put new.txt 'clean\n'
push_refused stale-tracking-refs-do-not-hide-old-commits 'old.txt: acme' push -q fresh t11
drop t11
git -C "$W" remote remove fresh

# chained after another hook, which reads every ref line before it hands over
mkdir -p "$T/other-hooks"
cat >"$T/other-hooks/pre-push" <<'EOF'
#!/bin/sh
while read -r local_ref local_sha remote_ref remote_sha; do :; done
exec "$(git rev-parse --git-common-dir)/hooks/pre-push" "$@"
EOF
chmod +x "$T/other-hooks/pre-push"
CHAIN=(-c "core.hooksPath=$T/other-hooks")
branch t9; put t9.txt 'from acme\n'
push_refused chained-hit-refused 'stdin was empty' "${CHAIN[@]}" push -q origin t9
drop t9
git -C "$W" switch -q --detach main; put d.txt 'ask bob\n'
push_refused chained-hit-on-detached-head-refused 'd.txt: bob' "${CHAIN[@]}" push -q origin HEAD:refs/heads/t9d
git -C "$W" switch -q main
branch t9b; put t9b.txt 'clean\n'
push_ok chained-clean-push-passes "${CHAIN[@]}" push -q origin t9b

# a broken setup refuses
branch t13; put t13.txt 'clean\n'
PUBLISH_GUARD_PATTERNS="$T/nope" push_refused missing-list-refuses 'not readable' push -q origin t13
printf '(\n' >"$T/badpats"
PUBLISH_GUARD_PATTERNS="$T/badpats" push_refused invalid-pattern-refuses 'invalid pattern' push -q origin t13
printf '# a comment only\n\n' >"$T/nopats"
PUBLISH_GUARD_PATTERNS="$T/nopats" push_refused empty-list-refuses 'no patterns' push -q origin t13
drop t13
printf 'acme\r\n' >"$T/crlfpats"; printf 'acme\n' >"$T/a.txt"
PUBLISH_GUARD_PATTERNS="$T/crlfpats" expect 1 crlf-list-still-matches "$GUARD" files "$T/a.txt"
expect 2 no-mode-prints-usage "$GUARD"
says 'pre-push <remote>' usage-names-the-modes

# history
branch t14; put gone.txt 'acme\n'
git -C "$W" rm -q gone.txt && git -C "$W" commit -q -m 'remove it'
expect 1 history-finds-blob-added-then-deleted "$GUARD" history "$W" t14
says 'gone.txt: acme' history-hit-names-the-file
drop t14
branch t15a; put m.txt 'one\n'
branch t15b; put m.txt 'two\n'
git -C "$W" merge -q t15a >/dev/null 2>&1
printf 'acme\n' >"$W/m.txt" && git -C "$W" add m.txt && git -C "$W" commit -q --no-edit
expect 1 history-finds-hit-from-merge-resolution "$GUARD" history "$W" t15b
drop t15b; git -C "$W" branch -q -D t15a
git -C "$W" tag -a v0.3 -m 'tag for acme' main
expect 1 history-reads-named-revs-tag-text "$GUARD" history "$W" v0.3
git -C "$W" tag -d v0.3 >/dev/null
expect 0 history-of-clean-repo-passes "$GUARD" history "$W"

# tree
mkdir -p "$T/tree/clean/docs" "$T/tree/clean/.git"
printf 'hello\n' >"$T/tree/clean/docs/a.md"; printf 'acme\n' >"$T/tree/clean/.git/config"
expect 0 tree-clean-skips-dot-git "$GUARD" tree "$T/tree/clean"
mkdir -p "$T/tree/dir/src/Acme"; printf 'hello\n' >"$T/tree/dir/src/Acme/b.md"
expect 1 tree-checks-directory-names "$GUARD" tree "$T/tree/dir"
says '^name src/Acme: Acme$' tree-reports-directory-hit-once
mkdir -p "$T/tree/bin"; printf 'x\0acme\0' >"$T/tree/bin/b.bin"
expect 1 tree-checks-binary-content "$GUARD" tree "$T/tree/bin"
mkdir -p "$T/tree/link"; ln -s /opt/acme/tool "$T/tree/link/tool"
expect 1 tree-checks-symlink-target "$GUARD" tree "$T/tree/link"

# files
printf 'A plan.\n' >"$T/plan.md"
expect 0 files-clean-passes "$GUARD" files "$T/plan.md"
printf 'A plan.\n' >"$T/plan-acme.md"
expect 1 files-checks-file-name "$GUARD" files "$T/plan-acme.md"
printf 'Ask Bob.\n' >"$T/brief.md"
expect 1 files-checks-content "$GUARD" files "$T/plan.md" "$T/brief.md"
expect 2 files-missing-refuses "$GUARD" files "$T/nope.md"
H="$T/home/ti9999"
printf 'repo: %s/src/kit\nRun `cd %s` first.\n' "$H" "$H" >"$T/brief-home.md"
HOME="$H" expect 0 files-home-reads-as-tilde "$GUARD" files "$T/brief-home.md"
printf 'repo: %s/src/acme-kit\n' "$H" >"$T/brief-home2.md"
HOME="$H" expect 1 files-name-after-home-still-counts "$GUARD" files "$T/brief-home2.md"
says 'brief-home2\.md: acme$' files-name-after-home-is-the-only-hit
printf 'repo: %s0/src\n' "$H" >"$T/brief-home3.md"
HOME="$H" expect 1 files-longer-path-is-not-cut "$GUARD" files "$T/brief-home3.md"
printf 'repo: %s/src\nAs ti9999 on the host.\n' "$H" >"$T/brief-home4.md"
HOME="$H" expect 1 files-user-name-outside-path-counts "$GUARD" files "$T/brief-home4.md"
mkdir -p "$T/tree/home"; printf 'See %s/src.\n' "$H" >"$T/tree/home/note.md"
HOME="$H" expect 1 tree-never-reads-home-as-tilde "$GUARD" tree "$T/tree/home"

# github
mkdir -p "$T/bin"
cat >"$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Stands in for `gh api [--paginate] <endpoint> --jq <filter>`: the answer is the JSON
# file at $FAKE_GH/<endpoint path>.json, run through the same filter.
[ "$1" = api ] || exit 9
shift
ep="" filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) ;;
    --jq) filter="$2"; shift ;;
    *) ep="$1" ;;
  esac
  shift
done
f="$FAKE_GH/${ep%%\?*}.json"
[ -f "$f" ] || { echo "fake gh: no fixture for $ep" >&2; exit 1; }
exec jq -r "$filter" "$f"
EOF
chmod +x "$T/bin/gh"
fixtures() {  # fixtures <dir> <description> <issue body> <PR head> <review body>
  local d="$1/repos/o/r"
  mkdir -p "$d/issues" "$d/pulls/2"
  printf '{"description":"%s","homepage":null,"topics":["agents"]}' "$2" >"$1/repos/o/r.json"
  echo '[{"name":"main"}]' >"$d/branches.json"
  echo '[{"name":"v1.0.0"}]' >"$d/tags.json"
  printf '[{"html_url":"https://example.com/o/r/issues/1","title":"Add a flag","body":"%s"}]' "$3" >"$d/issues.json"
  echo '[]' >"$d/issues/comments.json"
  echo '[]' >"$d/pulls/comments.json"
  echo '[]' >"$d/comments.json"
  echo '[{"html_url":"https://example.com/o/r/releases/1","name":"v1.0.0","tag_name":"v1.0.0","body":null}]' >"$d/releases.json"
  printf '[{"number":2,"html_url":"https://example.com/o/r/pull/2","head":{"ref":"%s"}}]' "$4" >"$d/pulls.json"
  printf '[{"html_url":"https://example.com/o/r/pull/2#r1","body":"%s"}]' "$5" >"$d/pulls/2/reviews.json"
}
fixtures "$T/gh-clean" 'An agent kit' 'Line one.\r\nLine two.' 'feat/flag' 'Looks good.'
fixtures "$T/gh-dirty" 'Kit by ACME' 'Ask\nBob\tabout it' 'feat/acme-flag' 'LGTM ti9999'
fixtures "$T/gh-broken" 'An agent kit' 'x' 'feat/flag' 'x'
rm "$T/gh-broken/repos/o/r/pulls/2/reviews.json"
PATH="$T/bin:$PATH" FAKE_GH="$T/gh-clean" expect 0 github-clean-texts-pass "$GUARD" github o/r
PATH="$T/bin:$PATH" FAKE_GH="$T/gh-dirty" expect 1 github-texts-are-checked "$GUARD" github o/r
says '^description: ACME$' github-description-is-read
says '^https://example.com/o/r/issues/1 body: Bob$' github-multi-line-body-is-read-whole
says '^https://example.com/o/r/pull/2 head: acme$' github-pr-head-is-read
says '^https://example.com/o/r/pull/2#r1: ti9999$' github-pr-review-is-read
PATH="$T/bin:$PATH" FAKE_GH="$T/gh-broken" expect 2 github-failed-call-refuses "$GUARD" github o/r

# GNU grep lookup: ggrep first, then grep, each only when its --version says GNU grep
mkdir -p "$T/stub-ggrep" "$T/stub-none"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "grep (BSD grep) 2.6.0"; exit 0; }\nexit 2\n' >"$T/stub-ggrep/grep"
printf '#!/bin/sh\necho used >>"%s/ggrep.log"\nexec "%s" "$@"\n' "$T" "$GREP" >"$T/stub-ggrep/ggrep"
printf '#!/bin/sh\n[ "$1" = --version ] && { echo "ugrep 7.0"; exit 0; }\nexit 2\n' >"$T/stub-none/grep"
cp "$T/stub-none/grep" "$T/stub-none/ggrep"
chmod +x "$T/stub-ggrep/grep" "$T/stub-ggrep/ggrep" "$T/stub-none/grep" "$T/stub-none/ggrep"

case_gnu_grep_found_as_ggrep() {
  local got
  : >"$T/ggrep.log"
  PATH="$T/stub-ggrep:$PATH" "$GUARD" files "$T/a.txt" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 1 ] || { fail gnu-grep-found-as-ggrep "exit $got, wanted 1"; return; }
  [ -s "$T/ggrep.log" ] || { fail gnu-grep-found-as-ggrep "the ggrep on PATH was not used"; return; }
  pass gnu-grep-found-as-ggrep
}
case_gnu_grep_found_as_ggrep

case_gnu_grep_missing_refuses() {
  local got
  PATH="$T/stub-none:$PATH" "$GUARD" files "$T/a.txt" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 2 ] || { fail gnu-grep-missing-refuses "exit $got, wanted 2"; return; }
  "$GREP" -q 'GNU grep not found' "$T/out" || { fail gnu-grep-missing-refuses "no message naming the fix"; return; }
  pass gnu-grep-missing-refuses
}
case_gnu_grep_missing_refuses

# PUBLISH_GUARD_WHERE_ONLY: a location prints without the matched words, whatever its entry
case_where_only_hides_the_match() {
  local wo="$T/where-only" got
  printf 'acme\ncorp/secret\n' >"$T/wo-patterns"
  git init -q -b main "$wo"
  mkdir -p "$wo/corp/secret"
  printf 'acme corp/secret\n' >"$wo/acme-notes.txt"
  printf 'acme\n' >"$wo/corp/secret/x.txt"
  git -C "$wo" add -A && git -C "$wo" commit -q -m 'add notes'
  PUBLISH_GUARD_PATTERNS="$T/wo-patterns" PUBLISH_GUARD_WHERE_ONLY=1 "$GUARD" history "$wo" main >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 1 ] || { fail where-only-hides-the-match "exit $got, wanted 1"; return; }
  "$GREP" -q '^commit [0-9a-f]\{10\}' "$T/out" || { fail where-only-hides-the-match "no line names the commit"; return; }
  "$GREP" -q '\[hidden\]' "$T/out" || { fail where-only-hides-the-match "nothing was hidden"; return; }
  if "$GREP" -qiE 'acme|corp/secret' "$T/out"; then fail where-only-hides-the-match "a line holds a list word"; return; fi
  pass where-only-hides-the-match
}
case_where_only_hides_the_match

# the list beside the script, reached through a symlink
case_list_beside_the_script() {
  local d="$T/beside" got
  mkdir -p "$d/real" "$d/links"
  cp "$GUARD" "$d/real/publish-guard.sh"
  printf 'acme\n' >"$d/real/publish-guard.patterns"
  ln -s "$d/real/publish-guard.sh" "$d/links/pg"
  env -u PUBLISH_GUARD_PATTERNS "$d/links/pg" files "$T/a.txt" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 1 ] || { fail list-beside-the-script "exit $got, wanted 1"; return; }
  env -u PUBLISH_GUARD_PATTERNS "$d/links/pg" files "$T/plan.md" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 0 ] || { fail list-beside-the-script "a clean file: exit $got, wanted 0"; return; }
  pass list-beside-the-script
}
case_list_beside_the_script

# install and guarded: each case gets its own clone and its own HOME under $T
REAL=$(readlink -f "$GUARD")
mkclone() { git init -q -b main "$T/c-$1"; }
nohome() { [ ! -e "$T/h-$1/.local/bin/publish-guard" ] && [ ! -L "$T/h-$1/.local/bin/publish-guard" ]; }
install_in() {  # install_in <case> [env assignments...]: install into the case's clone and HOME
  local n="$1"
  shift
  env HOME="$T/h-$n" "$@" "$GUARD" install "$T/c-$n" >"$T/out" 2>&1
}

case_install_writes_the_hook() {
  local n=writes got
  mkclone $n
  # a launcher session sets core.hooksPath at the command scope: install ignores it
  install_in $n GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$T/launcher-hooks"
  got=$?
  [ "$got" -eq 0 ] || { fail install-writes-the-hook "exit $got, wanted 0"; return; }
  [ -x "$T/c-$n/.git/hooks/pre-push" ] || { fail install-writes-the-hook "no executable hook"; return; }
  [ "$(sed -n 1p "$T/c-$n/.git/hooks/pre-push")" = '#!/bin/sh' ] || { fail install-writes-the-hook "bad first line"; return; }
  [ "$(sed -n 2p "$T/c-$n/.git/hooks/pre-push")" = "exec '$REAL' pre-push \"\$@\"" ] || { fail install-writes-the-hook "bad exec line"; return; }
  [ "$(readlink -f "$T/h-$n/.local/bin/publish-guard")" = "$REAL" ] || { fail install-writes-the-hook "the link does not resolve to the script"; return; }
  pass install-writes-the-hook
}
case_install_writes_the_hook

case_install_is_idempotent() {
  local n=idem got before
  mkclone $n
  install_in $n
  before=$(cksum <"$T/c-$n/.git/hooks/pre-push")
  install_in $n
  got=$?
  [ "$got" -eq 0 ] || { fail install-is-idempotent "second run: exit $got, wanted 0"; return; }
  [ "$(cksum <"$T/c-$n/.git/hooks/pre-push")" = "$before" ] || { fail install-is-idempotent "the hook changed"; return; }
  "$GREP" -q 'nothing to do' "$T/out" || { fail install-is-idempotent "no nothing-to-do message"; return; }
  pass install-is-idempotent
}
case_install_is_idempotent

case_install_refuses_a_foreign_hook() {
  local n=foreign got
  mkclone $n
  printf '#!/bin/sh\necho other\n' >"$T/c-$n/.git/hooks/pre-push"
  install_in $n
  got=$?
  [ "$got" -eq 2 ] || { fail install-refuses-a-foreign-hook "exit $got, wanted 2"; return; }
  [ "$(sed -n 2p "$T/c-$n/.git/hooks/pre-push")" = 'echo other' ] || { fail install-refuses-a-foreign-hook "the hook was changed"; return; }
  "$GREP" -qF "$T/c-$n/.git/hooks/pre-push" "$T/out" || { fail install-refuses-a-foreign-hook "the message does not name the hook"; return; }
  nohome $n || { fail install-refuses-a-foreign-hook "a link was written"; return; }
  pass install-refuses-a-foreign-hook
}
case_install_refuses_a_foreign_hook

case_install_refuses_hooks_path() {
  local n=hookspath got
  mkclone $n
  git -C "$T/c-$n" config core.hooksPath .githooks
  install_in $n
  got=$?
  [ "$got" -eq 2 ] || { fail install-refuses-hooks-path "exit $got, wanted 2"; return; }
  "$GREP" -qE 'core\.hooksPath.*\.githooks.*config' "$T/out" || { fail install-refuses-hooks-path "the message does not name the value and its origin"; return; }
  [ ! -e "$T/c-$n/.git/hooks/pre-push" ] || { fail install-refuses-hooks-path "a hook was written"; return; }
  nohome $n || { fail install-refuses-hooks-path "a link was written"; return; }
  pass install-refuses-hooks-path
}
case_install_refuses_hooks_path

# a missing list is created with comment lines only, and a list with no pattern refuses
NEWLIST="$T/brain/publish-guard.patterns"
mkdir -p "$T/brain"
case_install_creates_the_list() {
  local n=creates
  mkclone $n
  install_in $n PUBLISH_GUARD_PATTERNS="$NEWLIST"
  [ -s "$NEWLIST" ] || { fail install-creates-the-list "no list was created"; return; }
  if "$GREP" -qv '^#' "$NEWLIST"; then fail install-creates-the-list "the new list holds more than comments"; return; fi
  pass install-creates-the-list
}
case_install_creates_the_list

case_install_refuses_an_empty_list() {
  local n=empty got
  mkclone $n
  install_in $n PUBLISH_GUARD_PATTERNS="$NEWLIST"
  got=$?
  [ "$got" -eq 2 ] || { fail install-refuses-an-empty-list "exit $got, wanted 2"; return; }
  [ ! -e "$T/c-$n/.git/hooks/pre-push" ] || { fail install-refuses-an-empty-list "a hook was written"; return; }
  nohome $n || { fail install-refuses-an-empty-list "a link was written"; return; }
  pass install-refuses-an-empty-list
}
case_install_refuses_an_empty_list

case_install_links_on_path() {
  local n=links
  mkclone $n
  install_in $n
  "$GREP" -q 'not on PATH' "$T/out" || { fail install-links-on-path "no note when ~/.local/bin is off PATH"; return; }
  [ "$(readlink -f "$T/h-$n/.local/bin/publish-guard")" = "$REAL" ] || { fail install-links-on-path "no link"; return; }
  mkclone ${n}2
  env HOME="$T/h-$n" PATH="$T/h-$n/.local/bin:$PATH" "$GUARD" install "$T/c-${n}2" >"$T/out" 2>&1
  if "$GREP" -q 'not on PATH' "$T/out"; then fail install-links-on-path "a note although ~/.local/bin is on PATH"; return; fi
  pass install-links-on-path
}
case_install_links_on_path

case_install_refuses_a_foreign_link() {
  local n=flink got
  mkclone $n
  mkdir -p "$T/h-$n/.local/bin"
  ln -s /bin/true "$T/h-$n/.local/bin/publish-guard"
  install_in $n
  got=$?
  [ "$got" -eq 2 ] || { fail install-refuses-a-foreign-link "exit $got, wanted 2"; return; }
  [ ! -e "$T/c-$n/.git/hooks/pre-push" ] || { fail install-refuses-a-foreign-link "a hook was written"; return; }
  [ "$(readlink "$T/h-$n/.local/bin/publish-guard")" = /bin/true ] || { fail install-refuses-a-foreign-link "the link was changed"; return; }
  pass install-refuses-a-foreign-link
}
case_install_refuses_a_foreign_link

case_installed_hook_refuses_a_hit() {
  local n=live c="$T/c-live" before
  mkclone $n
  git init -q --bare "$T/live.git"
  git -C "$c" remote add origin "$T/live.git"
  install_in $n
  printf 'clean\n' >"$c/b.txt"
  git -C "$c" add -A && git -C "$c" commit -q -m 'add b'
  before=$(git -C "$c" rev-parse HEAD)
  git -C "$c" switch -q -c hit
  printf 'built for acme\n' >"$c/a.txt"
  git -C "$c" add -A && git -C "$c" commit -q -m 'add a'
  if git -C "$c" push -q origin hit >"$T/out" 2>&1; then fail installed-hook-refuses-a-hit "a hit went through"; return; fi
  [ -z "$(git -C "$T/live.git" for-each-ref)" ] || { fail installed-hook-refuses-a-hit "the remote changed"; return; }
  git -C "$c" push -q origin main >"$T/out" 2>&1 || { fail installed-hook-refuses-a-hit "a clean push was refused"; return; }
  [ "$(git -C "$T/live.git" rev-parse refs/heads/main)" = "$before" ] || { fail installed-hook-refuses-a-hit "the clean push did not land"; return; }
  pass installed-hook-refuses-a-hit
}
case_installed_hook_refuses_a_hit

case_guarded_yes() {
  local got
  "$GUARD" guarded "$T/c-live" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 0 ] || { fail guarded-yes "exit $got, wanted 0"; return; }
  [ ! -s "$T/out" ] || { fail guarded-yes "it printed something"; return; }
  pass guarded-yes
}
case_guarded_yes

case_guarded_reads_a_hand_written_hook() {
  local n=hand got
  mkclone $n
  printf '#!/bin/sh\nexec /opt/tools/publish-guard pre-push "$@"\n' >"$T/c-$n/.git/hooks/pre-push"
  "$GUARD" guarded "$T/c-$n" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 0 ] || { fail guarded-reads-a-hand-written-hook "unquoted form: exit $got, wanted 0"; return; }
  printf '#!/bin/sh\nexec "/opt/tools/publish-guard.sh" pre-push "$@"\n' >"$T/c-$n/.git/hooks/pre-push"
  "$GUARD" guarded "$T/c-$n" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 0 ] || { fail guarded-reads-a-hand-written-hook "double-quoted form: exit $got, wanted 0"; return; }
  printf '#!/bin/sh\necho other\n' >"$T/c-$n/.git/hooks/pre-push"
  "$GUARD" guarded "$T/c-$n" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 1 ] || { fail guarded-reads-a-hand-written-hook "foreign hook: exit $got, wanted 1"; return; }
  pass guarded-reads-a-hand-written-hook
}
case_guarded_reads_a_hand_written_hook

case_guarded_no_or_not_a_repo() {
  local got
  mkclone bare-hooks
  "$GUARD" guarded "$T/c-bare-hooks" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 1 ] || { fail guarded-no-or-not-a-repo "no hook: exit $got, wanted 1"; return; }
  mkdir -p "$T/plain"
  "$GUARD" guarded "$T/plain" >"$T/out" 2>&1
  got=$?
  [ "$got" -eq 2 ] || { fail guarded-no-or-not-a-repo "not a repo: exit $got, wanted 2"; return; }
  pass guarded-no-or-not-a-repo
}
case_guarded_no_or_not_a_repo

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

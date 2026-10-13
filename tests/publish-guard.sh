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

# <install-and-guarded-cases>

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

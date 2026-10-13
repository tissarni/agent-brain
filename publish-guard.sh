#!/usr/bin/env bash
# Keep private names out of a public repository: a pre-push gate, four audits, an installer.
#
#   ./publish-guard.sh install <clone>              opt a public clone in: write its pre-push hook
#   ./publish-guard.sh guarded <repo>               exit 0 when the repo's pre-push hook runs this gate
#   ./publish-guard.sh pre-push <remote> [<url>]    as the pre-push hook of a public clone
#   ./publish-guard.sh history <repo> [<rev>...]    every commit reachable from the revs (default: every ref)
#   ./publish-guard.sh tree <dir>                   every file under <dir>: contents, binary too, and names
#   ./publish-guard.sh files <file>...              plain files, such as a brief before it is sent;
#                                                   the home directory's path reads as ~
#   ./publish-guard.sh github <owner/repo>          issue, PR, review, comment and release texts, branch,
#                                                   tag and PR head names, description, homepage, topics
#
# Why: a pushed commit stays fetchable by its hash, a PR text keeps its old revisions, and a
# word in a PR title ends up in the squash commit. A private name (a client, a colleague, a
# host, an employer) that reaches a public repository is public for good, so this gate refuses
# it before the push.
#
# The list is publish-guard.patterns beside this script, or the file named by
# PUBLISH_GUARD_PATTERNS. It holds one extended regex per line, matched case-insensitively;
# blank lines and lines starting with # are ignored. It stays in the brain: the list is itself
# what must not be published, so never copy it into a public repository.
#
# `install` writes <git common dir>/hooks/pre-push in the clone (its worktrees share it) and
# links publish-guard into ~/.local/bin. It never overwrites or chains another pre-push hook.
# The hook checks what the push adds: the commits the remote lacks, asked of the remote itself,
# since remote-tracking refs go stale when a repo is recreated under its old name. If another
# hook hands over to this one after reading stdin, no ref lines are left: the gate then checks
# every local branch, tag and worktree HEAD the remote lacks.
#
# `history` sees only the commits the clone has. To audit a GitHub repo's PR commits too,
# fetch them first: git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*'
#
# PUBLISH_GUARD_WHERE_ONLY=1 prints each hit's location alone, with any part of it that matches
# the list replaced by [hidden], for a log that is itself public.
#
# Exit 0: nothing matched. 1: something matched, and each hit is printed as `where: match`.
# 2: usage or setup error. A missing, empty or invalid list, a missing GNU grep or a failed
# git or gh call is a setup error, so the gate refuses rather than passing. Needs bash 4.2 and
# GNU grep (on macOS: brew install grep gnu-sed bash).

set -u              # no -e: grep exits 1 when clean, so each failure is checked by hand
shopt -s lastpipe   # in `... | report`, report runs in this shell and HITS keeps counting
export LC_ALL=C     # the patterns are ASCII, and binary content is read byte by byte

die() { printf 'publish-guard: %s\n' "$*" >&2; exit 2; }

mode="${1:-}"
case "$mode" in
  install|guarded|pre-push|history|tree|files|github) shift ;;
  *) sed -n '/^#   \.\/publish-guard/,/^#$/p' "$0" >&2; exit 2 ;;
esac

SELF="$(readlink -f "$0")" || die "cannot resolve $0"
HERE="$(dirname "$SELF")"
PATTERNS="${PUBLISH_GUARD_PATTERNS:-$HERE/publish-guard.patterns}"

# The grep on PATH may be BSD grep (macOS) or an alias to ugrep, whose regex dialect differs.
find_grep() {
  local c p
  for c in ggrep grep; do
    p="$(command -v "$c" 2>/dev/null)" || continue
    case "$("$p" --version 2>&1 | head -n 1)" in
      *"GNU grep"*) GREP="$p"; return 0 ;;
    esac
  done
  die "GNU grep not found (tried ggrep, then grep): install it, on macOS with: brew install grep"
}

# Resolve a clone's git common dir, as an absolute path.
common_dir() {  # $1 = repo
  local d
  d="$(cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$d" ] || return 1
  (cd "$1" && cd "$d" && pwd -P)
}

hook_line_re="^exec +['\"]?[^'\"]*publish-guard(\.sh)?['\"]? +pre-push"

mode_guarded() {  # $1 = repo
  local common line
  common="$(common_dir "$1")" || return 2
  [ -f "$common/hooks/pre-push" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ $hook_line_re ]] && return 0
  done <"$common/hooks/pre-push"
  return 1
}

if [ "$mode" = guarded ]; then
  [ $# -eq 1 ] || die "guarded: name one repo"
  mode_guarded "$1"
  exit $?
fi

find_grep
TMP="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

load_patterns() {
  [ -r "$PATTERNS" ] || die "pattern file not readable: $PATTERNS, refusing"
  # A CR or an edge blank would make a pattern silently unmatchable.
  tr -d '\r' <"$PATTERNS" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | "$GREP" -vE '^(#|$)' >"$TMP/pats"
  [ -s "$TMP/pats" ] || die "no patterns in $PATTERNS, refusing"
  "$GREP" -E -f "$TMP/pats" </dev/null 2>"$TMP/err"
  [ $? -eq 1 ] || die "invalid pattern in $PATTERNS: $(cat "$TMP/err")"
}

HITS=0
hide() {  # $1 = where; prints it with each part that matches the list replaced by [hidden]
  local out="$1" pat word
  while IFS= read -r pat; do
    printf '%s' "$out" | "$GREP" -a -i -o -E -e "$pat" >"$TMP/words" 2>/dev/null
    while IFS= read -r word; do
      [ -z "$word" ] || out="${out//"$word"/[hidden]}"
    done <"$TMP/words"
  done <"$TMP/pats"
  printf '%s' "$out"
}
report() {  # $1 = where; stdin = text that would be published
  local m
  m="$("$GREP" -a -i -o -E -f "$TMP/pats")"
  [ $? -le 1 ] || die "grep failed on $1"
  [ -n "$m" ] || return 0
  if [ "${PUBLISH_GUARD_WHERE_ONLY:-}" = 1 ]; then
    printf '%s\n' "$(hide "$1")"
  else
    m="$(printf '%s\n' "$m" | sort -u | tr '\n' ' ')"
    printf '%s: %s\n' "$1" "${m% }"
  fi
  HITS=$((HITS + 1))
}

declare -A SEEN_BLOB SEEN_COMMIT
check_commit() {  # $1 = repo, $2 = commit: its raw object, then each path and blob it adds
  local repo="$1" c="$2" meta path mode sha st
  local -a span=(--root "$c")
  [ -z "${SEEN_COMMIT[$c]:-}" ] || return 0
  SEEN_COMMIT[$c]=1
  # The raw object holds the author, the committer, any extra header, and the message.
  git -C "$repo" cat-file commit "$c" >"$TMP/obj" || die "cannot read commit $c"
  report "commit ${c:0:10}" <"$TMP/obj"
  # A merge is read against its first parent, so text written while resolving it is caught.
  if git -C "$repo" rev-parse -q --verify "$c^2" >/dev/null; then span=("$c^1" "$c"); fi
  git -C "$repo" diff-tree -r -z --no-commit-id "${span[@]}" >"$TMP/diff" || die "cannot diff commit $c"
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    read -r _ mode _ sha st <<<"$meta"
    [ "$st" != D ] || continue
    printf '%s' "$path" | report "commit ${c:0:10} path"
    [ "$mode" != 160000 ] || continue   # a submodule pointer: its content lives in another repo
    [ -z "${SEEN_BLOB[$sha]:-}" ] || continue
    SEEN_BLOB[$sha]=1
    git -C "$repo" cat-file blob "$sha" >"$TMP/blob" || die "cannot read $path in commit $c"
    report "commit ${c:0:10} $path" <"$TMP/blob"
  done <"$TMP/diff"
}

check_revs() {  # $1 = repo; the rest go to rev-list, which also reads revs from $TMP/want
  local repo="$1" c
  shift
  git -C "$repo" rev-list "$@" --stdin <"$TMP/want" >"$TMP/revs" || die "git rev-list failed in $repo"
  while IFS= read -r c; do check_commit "$repo" "$c"; done <"$TMP/revs"
}

check_ref() {  # $1 = repo, $2 = full ref name; an annotated tag's own text too
  printf '%s' "$2" | report "ref $2"
  [ "$(git -C "$1" cat-file -t "$2" 2>/dev/null)" = tag ] || return 0
  git -C "$1" cat-file tag "$2" | report "tag object $2"
}

mode_history() {  # $1 = repo, then the revs
  local repo="$1" arg ref
  shift
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $repo"
  if [ $# -eq 0 ]; then
    git -C "$repo" for-each-ref --format='%(refname)' >"$TMP/refs"
    while IFS= read -r ref; do check_ref "$repo" "$ref"; done <"$TMP/refs"
    set -- --all
  else
    for arg in "$@"; do
      ref="$(git -C "$repo" rev-parse -q --verify --symbolic-full-name "$arg" 2>/dev/null)" || continue
      case "$ref" in refs/*) check_ref "$repo" "$ref" ;; esac
    done
  fi
  : >"$TMP/want"
  check_revs "$repo" "$@"
}

FALLBACK=0
mode_prepush() {  # $1 = remote, $2 = its URL; stdin = git's ref lines, or nothing when chained
  local lref lsha rref rsha n=0
  git ls-remote "${2:-$1}" >"$TMP/ls" || die "cannot list ${2:-$1}, refusing"
  cut -f1 "$TMP/ls" | sort -u | git cat-file --batch-check='%(objectname) %(objecttype)' |
    awk '$2 == "commit" || $2 == "tag" { print "^" $1 }' >"$TMP/have"
  while read -r lref lsha rref rsha; do
    [ -n "$rref" ] || continue
    n=$((n + 1))
    case "$lsha" in *[!0]*) ;; *) continue ;; esac   # all zeros: a deletion publishes nothing
    printf '%s' "$rref" | report "pushed ref $rref"
    [ "$(git cat-file -t "$lsha")" != tag ] || git cat-file tag "$lsha" | report "tag object $rref"
    { printf '%s\n' "$lsha"; cat "$TMP/have"; } >"$TMP/want"
    check_revs .
  done
  [ "$n" -eq 0 ] || return 0
  # Chained after a hook that read stdin first. A clean push can then be refused for a hit
  # on another local branch, which is the safe way to be wrong.
  FALLBACK=1
  git for-each-ref --format='%(refname)' refs/heads refs/tags >"$TMP/refs"
  while IFS= read -r lref; do check_ref . "$lref"; done <"$TMP/refs"
  { git for-each-ref --format='%(objectname)' refs/heads refs/tags
    git worktree list --porcelain | sed -n 's/^HEAD //p' | "$GREP" -v '^0*$'
    cat "$TMP/have"
  } >"$TMP/want"
  check_revs .
}

mode_tree() {  # $1 = dir; .git is skipped, since `history` reads it
  local dir="${1%/}" f rel
  [ -d "$dir" ] || die "not a directory: $1"
  find "$dir" -mindepth 1 -name .git -prune -o -print0 >"$TMP/find" || die "find failed under $dir"
  while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    printf '%s' "${rel##*/}" | report "name $rel"
    if [ -L "$f" ]; then
      readlink "$f" | report "link $rel"
    elif [ -f "$f" ]; then
      [ -r "$f" ] || die "unreadable: $f"
      report "$rel" <"$f"
    fi
  done <"$TMP/find"
}

# A brief gives its repo as an absolute path, so every brief holds the home directory and
# the user name in it. Read that path as ~: what follows it still counts.
home_as_tilde() {
  local h="${HOME%/}" re
  [ -n "$h" ] || { cat; return; }
  re="$(printf '%s' "$h" | sed 's/[][\.*^$/+?(){}|]/\\&/g')"
  sed -E "s/$re(\/|\$|[^A-Za-z0-9._-])/~\1/g"
}

mode_files() {  # a plan's file name becomes the slug in its PR body, so names count too
  local f
  [ $# -gt 0 ] || die "files: name at least one file"
  for f in "$@"; do
    [ -f "$f" ] && [ -r "$f" ] || die "not a readable file: $f"
    printf '%s' "${f##*/}" | report "name $f"
    home_as_tilde <"$f" | report "$f"
  done
}

ghq() {  # $1 = endpoint, $2 = jq filter printing "where<TAB>text" lines
  gh api --paginate "$1" --jq "$2" </dev/null >>"$TMP/texts" || die "gh api $1 failed (gh auth status?)"
}

mode_github() {  # $1 = owner/repo: every text GitHub shows beside the code
  local r="$1" n where text
  local flat='gsub("\\s+"; " ")'
  : >"$TMP/texts"
  ghq "repos/$r" '"description\t\(.description // "")", "homepage\t\(.homepage // "")", "topics\t\((.topics // []) | join(" "))"'
  ghq "repos/$r/branches?per_page=100" '.[] | "branch\t\(.name)"'
  ghq "repos/$r/tags?per_page=100" '.[] | "tag\t\(.name)"'
  ghq "repos/$r/issues?state=all&per_page=100" ".[] | \"\(.html_url) title\t\(.title | $flat)\", \"\(.html_url) body\t\((.body // \"\") | $flat)\""
  ghq "repos/$r/issues/comments?per_page=100" ".[] | \"\(.html_url)\t\((.body // \"\") | $flat)\""
  ghq "repos/$r/pulls/comments?per_page=100" ".[] | \"\(.html_url)\t\((.body // \"\") | $flat)\""
  ghq "repos/$r/comments?per_page=100" ".[] | \"\(.html_url)\t\((.body // \"\") | $flat)\""
  ghq "repos/$r/releases?per_page=100" ".[] | \"\(.html_url)\t\((.name // \"\") | $flat) \(.tag_name) \((.body // \"\") | $flat)\""
  ghq "repos/$r/pulls?state=all&per_page=100" '.[] | "\(.html_url) head\t\(.head.ref)"'
  # Review summaries are listed per PR only.
  gh api --paginate "repos/$r/pulls?state=all&per_page=100" --jq '.[].number' </dev/null >"$TMP/prs" ||
    die "gh api repos/$r/pulls failed (gh auth status?)"
  while IFS= read -r n; do
    ghq "repos/$r/pulls/$n/reviews?per_page=100" ".[] | \"\(.html_url)\t\((.body // \"\") | $flat)\""
  done <"$TMP/prs"
  while IFS=$'\t' read -r where text; do
    printf '%s' "$text" | report "$where"
  done <"$TMP/texts"
}

# Every refusal check runs before the first write, bar creating a missing list: a link with
# no hook, or a hook with an empty list, would look installed and not be.
mode_install() {  # $1 = the clone
  local clone="$1" common hook link linkdir q scope origin value
  local hook_ok=0 link_ok=0
  common="$(common_dir "$clone")" || die "not a git repo: $clone"
  [ -n "${HOME:-}" ] || die "HOME is not set"
  hook="$common/hooks/pre-push"
  linkdir="$HOME/.local/bin"
  link="$linkdir/publish-guard"

  if [ ! -e "$PATTERNS" ]; then
    cat >"$PATTERNS" <<'EOF' || die "cannot create $PATTERNS"
# publish-guard patterns: one extended regex per line, matched case-insensitively.
# Blank lines and lines starting with # are ignored.
# List each private name here: a client, a colleague, a host, an employer.
# This file stays in the brain. Never copy it into a public repository.
EOF
    printf 'publish-guard: created %s\n' "$PATTERNS" >&2
  fi
  load_patterns   # refuses while the list has no pattern: that hook would refuse every push

  # The command scope is a launcher session's own hooks, which hand over to the hook below.
  git -C "$clone" config --show-scope --show-origin --get-all core.hooksPath >"$TMP/hp" 2>/dev/null
  while IFS=$'\t' read -r scope origin value; do
    [ -n "$scope" ] && [ "$scope" != command ] || continue
    die "core.hooksPath is set to '$value' ($scope, $origin): git would ignore $hook. Unset it first, refusing"
  done <"$TMP/hp"

  q="'"
  printf '#!/bin/sh\nexec %s pre-push "$@"\n' "'${SELF//$q/$q\\$q$q}'" >"$TMP/want"
  if [ -e "$hook" ] || [ -L "$hook" ]; then
    cmp -s "$TMP/want" "$hook" || die "a pre-push hook already exists: $hook. Never overwritten or chained, refusing"
    [ -x "$hook" ] && hook_ok=1
  fi

  if [ -e "$link" ] || [ -L "$link" ]; then
    [ "$(readlink -f "$link")" = "$SELF" ] || die "$link exists and is not this script, refusing"
    link_ok=1
  fi

  if [ "$hook_ok" -eq 0 ]; then
    mkdir -p "$common/hooks" && cp "$TMP/want" "$hook" && chmod 755 "$hook" || die "cannot write $hook"
    printf 'publish-guard: wrote %s\n' "$hook"
  fi
  if [ "$link_ok" -eq 0 ]; then
    mkdir -p "$linkdir" && ln -s "$SELF" "$link" || die "cannot link $link"
    printf 'publish-guard: linked %s\n' "$link"
  fi
  [ "$hook_ok$link_ok" != 11 ] || printf 'publish-guard: %s already guarded, nothing to do\n' "$clone"
  case ":$PATH:" in
    *":$linkdir:"*) ;;
    *) printf 'publish-guard: note: %s is not on PATH, so briefs cannot call publish-guard yet\n' "$linkdir" ;;
  esac
}

if [ "$mode" != install ]; then load_patterns; fi

case "$mode" in
  install)  [ $# -eq 1 ] || die "install: name one clone"; mode_install "$1" ;;
  pre-push) [ $# -ge 1 ] || die "pre-push: missing remote"; mode_prepush "$@" ;;
  history)  [ $# -ge 1 ] || die "history: name the repo"; mode_history "$@" ;;
  tree)     [ $# -eq 1 ] || die "tree: name one directory"; mode_tree "$1" ;;
  files)    mode_files "$@" ;;
  github)   [ $# -eq 1 ] || die "github: name one owner/repo"; mode_github "$1" ;;
esac

if [ "$HITS" -gt 0 ]; then
  if [ "$mode" = pre-push ]; then
    printf 'publish-guard: %d hit(s), push refused. Rewrite the unpushed commits without these words, never quote them in a commit, PR text or comment, and do not bypass this hook.\n' "$HITS" >&2
    [ "$FALLBACK" -eq 0 ] || printf 'publish-guard: stdin was empty, so every local branch, tag and worktree HEAD the remote lacks was checked.\n' >&2
  else
    printf 'publish-guard: %d hit(s) (%s)\n' "$HITS" "$mode" >&2
  fi
  exit 1
fi
case "$mode" in pre-push|install) ;; *) printf 'publish-guard: clean (%s)\n' "$mode" >&2 ;; esac
exit 0

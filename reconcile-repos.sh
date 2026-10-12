#!/usr/bin/env bash
# Report the real git state of every repo the vault claims to track.
# Run from the vault root:  bash reconcile-repos.sh < <repo-list>
#
# Reads repo paths on stdin, one per line (the `repo:` frontmatter values).
# Emits one TSV line per repo:  <repo>\t<branch>\t<unpushed>\t<dirty>\t<branches-ahead>
#
# Why a script and not an inline command: the login shell here is zsh, which
# glob-expands `%(refname:short)` and `*` before git ever sees them. One file, no
# nesting, no surprises.
#
# Always exits 0 — a missing repo is a finding to report, not a failure to abort on.

while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  [ "$repo" = "-" ] && continue

  if [ ! -d "$repo/.git" ]; then
    printf '%s\tMISSING\t-\t-\t-\n' "$repo"
    continue
  fi

  cd "$repo" || continue

  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  # The integration branch this repo merges into.
  base=""
  for cand in dev main master; do
    git show-ref --verify --quiet "refs/heads/$cand" && { base="$cand"; break; }
  done

  # Commits on the CURRENT branch not yet in the integration branch.
  if [ -n "$base" ] && [ "$branch" != "$base" ]; then
    unpushed=$(git log --oneline "$base..$branch" 2>/dev/null | wc -l | tr -d ' ')
  else
    unpushed=$(git log --oneline "@{u}..HEAD" 2>/dev/null | wc -l | tr -d ' ')
    [ -z "$unpushed" ] && unpushed=0
  fi

  # Deliberately NOT enumerating every local branch that looks "ahead".
  #
  # Two attempts failed. `git log --not --remotes` counts commits absent from every
  # remote — a squash-merge rewrites history, so a merged branch reads as unpushed
  # forever. `git diff base...b` is a three-dot diff against the FORK POINT, so it is
  # non-empty for any branch that ever changed anything, merged or not. Neither detects
  # a squash-merge, and there is no cheap test that does.
  #
  # These repos carry years of stale local branches — one of them has 80+. Listing them
  # buries the two or three lines that matter. Uncommitted files and commits on the
  # branch you are actually on are unambiguous; that is what this reports.
  # Stale local branches are archaeology, and archaeology is not drift.
  ahead="-"

  printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "$branch" "$unpushed" "$dirty" "$ahead"
done
exit 0

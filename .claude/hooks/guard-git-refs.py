#!/usr/bin/env python3
"""PreToolUse guard: refuse git operations that write to a protected branch.

Wired to Bash tool calls. Inspects the COMMAND TEXT, not the working directory —
a command aimed at another repository (`bash -lc 'cd ~/projects/X && git push ...'`)
runs with the brain as its cwd, so a cwd check waves it through.

Settings come from brain.env, found in $CLAUDE_PROJECT_DIR, else two directories above
this file. Read line by line, never sourced: PROTECTED_BRANCHES (space-separated, default
"main dev") and CODE_ROOT (default ~/projects).

Push rules read only the push command's own segment: from `git` up to the next `&&`,
`||`, `;`, `|` or newline. A force push, a protected target and a bare push are refused.
A merge is refused when its own segment names a protected branch with no `/` before it
(`git merge main`; `git merge origin/main` syncs a feature branch and passes), or when the
command checks out or switches to a protected branch (`-b`/`-c` start points do not count).
A commit is refused when `commit` is git's subcommand, on one line, and the command names
a path under CODE_ROOT that is not this brain, e.g. `~/projects/X`. The brain and any path
inside it is the brain, even when it sits several levels below CODE_ROOT.

Exit 0 = allow, silently. Exit 2 = block; stderr is returned to the model as the reason.

Deliberately NOT blocked: the brain's own auto-commit.sh. The brain versions itself by
committing on every Stop — that is the design, and it has no push step.

Fails OPEN by design (exit 0 on any internal error). A guard that breaks every Bash
call the moment its own parsing is surprised gets removed within the hour, and then
there is no guard at all. The protection this gives is against the routine mistake,
not against a determined agent.
"""
import json
import os
import re
import sys
from pathlib import Path

SELF_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or SELF_ROOT)

PROMOTION = (
    "Protected branches here: %s. They change only through a pull request: push the "
    "feature branch by explicit refspec, then say which PR to open and against which "
    "target. Opening or merging the PR is the user's action, not yours."
)


def brain_env(key):
    """The value after the first `KEY=` in brain.env, "" when absent. Read, never sourced."""
    try:
        lines = (ROOT / "brain.env").read_text().splitlines()
    except OSError:
        return ""
    for line in lines:
        if line.startswith(key + "="):
            return line[len(key) + 1:].rstrip("\r")
    return ""


# `git`, then any global options, then `commit` as the subcommand, all on one line:
# `git log --grep commit` and `HEAD^{commit}` are not commits.
COMMIT = (
    r"\bgit(?:[ \t]+(?:-C|-c|--git-dir|--work-tree|--namespace|--config-env)[ \t]+\S+"
    r"|[ \t]+-\S*)*[ \t]+commit(?![\w-])"
)
PROTECTED = brain_env("PROTECTED_BRANCHES").split() or ["main", "dev"]


def block(reason):
    sys.stderr.write(
        "BLOCKED by guard-git-refs: %s\n\n%s\n" % (reason, PROMOTION % " ".join(PROTECTED))
    )
    sys.exit(2)


def code_root():
    v = brain_env("CODE_ROOT") or "~/projects"
    home = os.path.expanduser("~")
    if v == "~" or v.startswith("~/"):
        return Path(home) / v[2:]
    p = Path(v)
    return p if p.is_absolute() else ROOT / p


def other_code_dir(cmd):
    """True when cmd names a path under CODE_ROOT that is not this brain or inside it.

    The whole path counts, not its first segment: a brain at <CODE_ROOT>/group/brain is
    not the project <CODE_ROOT>/group. Inside the brain counts as the brain only when the
    brain sits below CODE_ROOT; a CODE_ROOT inside the brain holds code repos, not it.
    """
    cr = code_root().resolve()
    home = Path(os.path.expanduser("~")).resolve()
    prefixes = {str(code_root()), str(cr)}
    for base in list(prefixes):
        try:
            rel = Path(base).relative_to(home)
        except ValueError:
            continue
        prefixes.add("~/" + str(rel))
        prefixes.add("$HOME/" + str(rel))
    root = ROOT.resolve()
    below = cr in root.parents
    for pre in prefixes:
        for m in re.finditer(re.escape(pre.rstrip("/")) + r"/([^\s'\"`;&|)]+)", cmd):
            p = (cr / m.group(1)).resolve()
            if p != root and not (below and root in p.parents):
                return True
    return False


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return
    cmd = (json.loads(raw).get("tool_input") or {}).get("command") or ""
    if not cmd:
        return

    # The brain's own versioning path — allow ahead of every other rule.
    if "auto-commit.sh" in cmd or "sync-skills.sh" in cmd:
        return

    if not re.search(r"\b(git|gh|glab)\b", cmd):
        return

    # A protected ref as a standalone word, as the right half of a refspec, or as the
    # last segment of a full ref path (`refs/heads/main`). Called on a push segment.
    #
    # `/` is deliberately ALLOWED in the lookbehind: excluding it let
    # `git push origin refs/heads/main` through, which is the exact thing to stop.
    # `feat/main-thing` is still safe: the lookahead rejects it.
    def targets(branch, text):
        return re.search(r"(?<![\w.-])%s(?![\w/.-])" % re.escape(branch), text) is not None

    # For merges and checkouts: no `/` before the name, so `origin/main` (a sync of a
    # feature branch from its base) passes while `main` does not.
    def names_bare(branch, text):
        return re.search(r"(?<![\w./-])%s(?![\w/.-])" % re.escape(branch), text) is not None

    seg = r"\bgit\b[^&|;\n]*"

    for m in re.finditer(seg + r"\bpush\b[^&|;\n]*", cmd):
        s = m.group(0)
        if re.search(r"--force\b|--force-with-lease\b|(?<!\w)-f(?!\w)", s):
            block("a force push. Rewriting a published branch is not an agent action.")
        for b in PROTECTED:
            if targets(b, s):
                block("a push targeting '%s'." % b)

    # A bare `git push` inherits its upstream, which is invisible here — and
    # `git switch -c` off a base branch sets exactly that misleading upstream.
    if re.search(r"\bgit\s+push\s*(?:$|[&|;'\"])", cmd):
        block(
            "a bare 'git push' — the upstream is not visible from the command. "
            "Push by explicit refspec: git push origin <feature-branch>."
        )

    merges = list(re.finditer(seg + r"\bmerge\b[^&|;\n]*", cmd))
    for m in merges:
        for b in PROTECTED:
            if names_bare(b, m.group(0)):
                block("a git merge involving '%s'." % b)

    for m in merges and re.finditer(seg + r"\b(?:checkout|switch)\b([^&|;\n]*)", cmd):
        toks = m.group(1).split()
        if any(t in ("-b", "-B", "-c", "-C", "--orphan") for t in toks):
            continue  # creating a branch: the start point is only read
        if "--" in toks:
            toks = toks[: toks.index("--")]
        for t in toks:
            if t.startswith("-"):
                continue
            for b in PROTECTED:
                if names_bare(b, t):
                    block("a git merge after switching to '%s'." % b)

    if re.search(r"\bgh\s+pr\s+merge\b", cmd):
        block("'gh pr merge'. The PR is the review gate; merging it is the user's call.")
    if re.search(r"\bglab\s+mr\s+merge\b", cmd):
        block("'glab mr merge'. Same reason as gh pr merge.")

    # Committing into a code repository under CODE_ROOT from a brain-rooted session:
    # that repo's own hooks and settings are not in play, so there is no branch guard
    # but this one.
    if re.search(COMMIT, cmd):
        if other_code_dir(cmd):
            block(
                "a git commit against a code repository under CODE_ROOT from a "
                "brain-rooted session. Code work belongs in a session started in the "
                "repo, where that repo's own hooks and settings apply."
            )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        pass  # fail open — see the module docstring
    sys.exit(0)

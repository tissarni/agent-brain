---
updated: 2026-10-10
tags: [spec, brief]
handoff: draft
revision: 2026-10-10-r1
repo: @DEMO_REPO@
branch: feat/version-flag
review-session:
  model: opus
  effort: medium
  permission-mode: acceptEdits
  disallowed-tools: Edit,Write,NotebookEdit
run-session:
  model: sonnet
  effort: medium
  permission-mode: acceptEdits
---

# Brief — a --version flag for the demo program

## §0 Session preamble

- Working directory: the repository named in `repo:`. Read its `AGENTS.md` first.
- You are on `feat/version-flag`. origin is a local bare repository: push `feat/version-flag` to it, no pull request.
- Checks (§4): `python3 -m unittest -q` and `python3 hello.py --version`.

## §0b Revision echo

Echo the exact string `2026-10-10-r1` back in your first reply.

## §1 Why this exists

A first change to try the handoff loop on: small enough to finish in one run, real enough to need a test.

## §2 State — what already exists

- `hello.py` has `greet(name="world")` returning `Hello, <name>!`; run as a script it prints `greet(sys.argv[1])` when given an argument, else `greet()`.
- `test_hello.py` is a `unittest` module with two tests of `greet`.
- Standard library only.

## §3 Settled — do not re-explore

- The flag is `--version`, checked before the greeting branch, with no argument parser.
- The output is exactly `hello 0.1.0`.

## §4 Goal, and Done when

`python3 hello.py --version` prints `hello 0.1.0`, and a test covers it. Run each check from the repository root.

1. `python3 -m unittest -q` exits 0.
2. `python3 hello.py --version` prints `hello 0.1.0`.

## §5 Step 0 — read before you write anything

Read `AGENTS.md`, `hello.py` and `test_hello.py`, once each.

## §6 Constraints / must-not

- No third-party package. Why: the demo runs where only `python3` is installed.
- `greet` keeps its behavior. Why: its two tests must still pass.

## §7 Tasks

1. Add a test that runs the version output, then make it pass by handling `--version` in `hello.py`. Check: §4 items 1 and 2. Commit.

## §8 Out of scope

Reading the version from packaging metadata; any other flag.

## §9 Known traps

None known.

## §10 What this brief may be wrong about

Nothing unchecked: the repository is small enough to read in full.

## §11 Human checks (after the run)

Read the diff: it should be a few lines in `hello.py` and one test.

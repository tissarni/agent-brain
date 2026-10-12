---
updated: 2026-10-10
status: active
tags: [task]
---

# Current task: example-version-flag

> Parent: [[02-projects/example/context]] · Sub context: [[02-projects/example/subprojects/example-version-flag/context]]

## Task
Add a `--version` flag to `hello.py` that prints `hello 0.1.0`, with a test.

## Acceptance criteria
- `python3 hello.py --version` prints `hello 0.1.0`.
- `python3 -m unittest -q` exits 0.

## Files likely involved
`hello.py`, `test_hello.py`

## Open questions
None.

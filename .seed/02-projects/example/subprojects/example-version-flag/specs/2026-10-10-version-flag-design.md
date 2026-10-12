---
updated: 2026-10-10
tags: [spec]
---

# Design — a --version flag

## Goal
`python3 hello.py --version` prints `hello 0.1.0` and exits.

## Design
Check `sys.argv[1] == "--version"` before the greeting branch and print the fixed string. No argument parser: the program has one optional argument and the standard library's `argparse` would be more than the change needs.

## Out of scope
Reading the version from packaging metadata.

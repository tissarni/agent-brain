---
project: example-version-flag
kind: sub
parent: example
status: active
created: 2026-10-10
updated: 2026-10-10
repo: @DEMO_REPO@
branch: feat/version-flag
summary: >-
  Add a --version flag to the demo program
related: []
tags: [project, sub]
---

# example-version-flag — Context

> Parent: [[02-projects/example/context]] — stack, architecture and constraints live there, not here.

## What this is
Add a `--version` flag to `hello.py` that prints `hello 0.1.0`. A small change, chosen to try the handoff loop end to end.

## Key decisions
- Print a fixed version string — the demo has no packaging, so no version lookup.

## Current state
Brief drafted, not yet run.

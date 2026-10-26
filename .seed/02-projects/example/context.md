---
project: example
kind: main
status: active
created: 2026-10-10
updated: 2026-10-10
repo: ''
branch: main
summary: >-
  A demo main to try the handoff kit on; delete it with ./setup.sh --remove-example.
tags: [project, main]
---

# example — Context

> Sub-project states: [[02-projects/example/_index]] — read that first.

## What this is
Start with `./setup-check.sh` at the brain root: free local setup diagnostics, with a
separate explicit `--live` canary when you want to spend model quota. A local PASS is
not end-to-end PASS; live handoff stays NOT TESTED until explicitly exercised.

This legacy demo main and its version-flag brief remain for compatibility. The checker
creates a fresh disposable repository on every run and never edits `agent-brain-demo`.

## Stack
Python 3, standard library only.

## Key decisions
<!-- `- [Title] — ADR-NNN (YYYY-MM-DD): one sentence` — added by /adr. -->

## Current state
Demo only; nothing is deployed.

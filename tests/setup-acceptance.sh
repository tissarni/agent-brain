#!/usr/bin/env bash
# Included by the existing Linux/macOS test loop. Never calls paid backends.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT/tests" -p '*_test.py' -v

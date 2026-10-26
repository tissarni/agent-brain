#!/bin/sh
# Free diagnostics unless --live is explicitly requested; Python stdlib only.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 -I "$ROOT/setup-check.py" "$@"

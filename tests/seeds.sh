#!/usr/bin/env bash
# Tests for the seed files under .seed/ and the kit pin.
# Every case works in a copy under mktemp -d; nothing is written elsewhere.
# Output: one "PASS <case>" or "FAIL <case> — <why>" per case, then "<n> passed, <m> failed".

unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0

pass() { echo "PASS $1"; passed=$((passed + 1)); }
fail() { echo "FAIL $1 — $2"; failed=$((failed + 1)); }

SUB=.seed/02-projects/example/subprojects/example-version-flag
SEEDS=(
  .seed/AGENTS.local.md
  .seed/brain.env
  .seed/docs-exclude.txt
  .seed/02-projects/_templates/handoff-defaults.yml
  .seed/02-projects/example/context.md
  .seed/02-projects/example/_index.md
  "$SUB/context.md"
  "$SUB/current.md"
  "$SUB/specs/2026-10-10-version-flag-design.md"
  "$SUB/specs/2026-10-10-brief-1-version-flag.md"
  .seed/demo-repo/hello.py
  .seed/demo-repo/test_hello.py
  .seed/demo-repo/README.md
  .seed/demo-repo/AGENTS.md
)
BRIEF="$ROOT/$SUB/specs/2026-10-10-brief-1-version-flag.md"

case_seed_files() {
  local f n
  for f in "${SEEDS[@]}"; do
    [ -f "$ROOT/$f" ] || { fail seed-files "missing $f"; return; }
  done
  n=$(git -C "$ROOT" ls-files .seed | wc -l)
  [ "$n" -eq 14 ] && pass seed-files || fail seed-files "git ls-files .seed lists $n, not 14"
}

case_seed_placeholders() {
  local t f others
  for t in @NAME@ @ROLE@ @LANGUAGES@ @PRINCIPLES@; do
    /usr/bin/grep -q -F "$t" "$ROOT/.seed/AGENTS.local.md" || { fail seed-placeholders "AGENTS.local.md lacks $t"; return; }
  done
  for f in "$SUB/context.md" "$SUB/specs/2026-10-10-brief-1-version-flag.md"; do
    /usr/bin/grep -q -F @DEMO_REPO@ "$ROOT/$f" || { fail seed-placeholders "$f lacks @DEMO_REPO@"; return; }
  done
  others=$(cd "$ROOT" && printf '%s\n' "${SEEDS[@]}" | /usr/bin/grep -v -x -e .seed/AGENTS.local.md -e "$SUB/context.md" -e "$SUB/specs/2026-10-10-brief-1-version-flag.md" \
    | xargs /usr/bin/grep -l -E '@[A-Z_]+@')
  [ -z "$others" ] && pass seed-placeholders || fail seed-placeholders "stray token in: $others"
}

case_seed_brain_env() {
  local want got
  got=$(/usr/bin/grep -v '^#' "$ROOT/.seed/brain.env")
  want=$(printf '%s\n' 'CODE_ROOT=~/projects' 'PROTECTED_BRANCHES=main dev' DEFAULT_BACKEND=claude NOTIFY= DOCS_SITE_DIR= DOCS_URL= HTML_THEME= CONTEXT_GUARD_THRESHOLD=150000)
  [ "$got" = "$want" ] && pass seed-brain-env || fail seed-brain-env "got: $(echo "$got" | paste -s -d,)"
}

case_seed_defaults_generic() {
  local f="$ROOT/.seed/02-projects/_templates/handoff-defaults.yml" out
  /usr/bin/grep -q -x 'per-main:' "$f" || { fail seed-defaults-generic "no bare per-main: line"; return; }
  /usr/bin/grep -q -x "  notify: ''" "$f" || { fail seed-defaults-generic "no notify: ''"; return; }
  out=$(awk '/^per-main:/{p=1;next} /^[^ #]/{p=0} p && /^ +[^ #]/{print}' "$f")
  [ -z "$out" ] || { fail seed-defaults-generic "indented line under per-main: $out"; return; }
  out=$(python3 - "$f" <<'PY'
import sys
want = {
    "review": ("opus", "medium", "acceptEdits", "Edit,Write,NotebookEdit"),
    "run": ("sonnet", "medium", "acceptEdits", ""),
    "vault": ("sonnet", "medium", "bypassPermissions", ""),
    "close": ("sonnet", "medium", "bypassPermissions", "Edit,Write,NotebookEdit"),
}
keys = ("model", "effort", "permission-mode", "disallowed-tools")
got, block, in_defaults = {}, None, False
for line in open(sys.argv[1]):
    s = line.rstrip("\n")
    if not s.strip() or s.lstrip().startswith("#"):
        continue
    if not s.startswith(" "):
        in_defaults = s.startswith("defaults:")
        block = None
    elif in_defaults and s.startswith("  ") and not s.startswith("   ") and s.strip().endswith(":"):
        block = s.strip()[:-1]
        got[block] = {}
    elif in_defaults and block and ":" in s:
        k, v = s.strip().split(":", 1)
        got[block][k] = v.strip().strip("'")
for b, vals in want.items():
    have = tuple(got.get(b, {}).get(k) for k in keys)
    if have != vals:
        print(f"{b}: {have} != {vals}")
PY
)
  [ -z "$out" ] && pass seed-defaults-generic || fail seed-defaults-generic "$out"
}

case_seed_demo_tests() {
  local d="$TMP/demo-tests" out
  cp -r "$ROOT/.seed/demo-repo" "$d"
  (cd "$d" && python3 -m unittest -q >/dev/null 2>&1) || { fail seed-demo-tests "unittest failed"; return; }
  out=$(cd "$d" && python3 hello.py)
  [ "$out" = "Hello, world!" ] && pass seed-demo-tests || fail seed-demo-tests "hello.py printed: $out"
}

case_seed_brief_check() {
  local d="$TMP/demo-brief" out rc
  command -v brief-check >/dev/null 2>&1 || { fail seed-brief-check "brief-check is not on PATH"; return; }
  cp -r "$ROOT/.seed/demo-repo" "$d"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.name=tester -c user.email=tester@example.invalid -c commit.gpgsign=false commit -q -m init
  sed "s|@DEMO_REPO@|$d|" "$BRIEF" > "$TMP/brief.md"
  out=$(brief-check "$TMP/brief.md" 2>&1); rc=$?
  [ "$rc" -eq 0 ] && [[ "$(echo "$out" | tail -n 1)" == "RESULT 0 FAIL"* ]] && pass seed-brief-check || fail seed-brief-check "rc $rc: $(echo "$out" | tail -n 1)"
}

case_kit_pin() {
  local want got
  want=$(printf '%s\n' HANDOFF_KIT_URL=https://github.com/tissarni/handoff-kit HANDOFF_KIT_TAG=v1.0.1)
  got=$(cat "$ROOT/handoff-kit.pin")
  [ "$got" = "$want" ] && pass kit-pin || fail kit-pin "got: $(echo "$got" | paste -s -d,)"
}

case_seed_files
case_seed_placeholders
case_seed_brain_env
case_seed_defaults_generic
case_seed_demo_tests
case_seed_brief_check
case_kit_pin

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]

#!/usr/bin/env bash
# Shared sandbox for tests/setup-smoke.sh and tests/template-lifecycle.sh. Sourced, not run.
# The caller sets CASES first; this builds a fresh clone of the template under mktemp -d, a
# sandbox HOME, fake CLIs and a PATH made of the sandbox only. Offline; nothing is written
# elsewhere. It leaves ROOT, TMP, BRAIN, HOME_DIR, CODE, KIT, GIT_ID, SETUP_ARGS, pass, fail,
# fail_all, sandbox and run_setup to the caller.

unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

passed=0
failed=0

pass() { echo "PASS $1"; passed=$((passed + 1)); }
fail() { echo "FAIL $1 — $2"; failed=$((failed + 1)); }

BRAIN=$TMP/brain
HOME_DIR=$TMP/home
CODE=$TMP/code
GIT_ID=(-c user.name=tester -c user.email=tester@example.invalid -c commit.gpgsign=false)
SETUP_ARGS=(--yes --name ci --role ci --languages bash --principles KISS --code-root "$CODE" --remote none)

fail_all() { local c; for c in "${CASES[@]}"; do fail "$c" "$1"; done; echo "$passed passed, $failed failed"; exit 1; }

sandbox() { # sandbox <command...>: run under env -i with the sandbox HOME and PATH
  env -i HOME="$HOME_DIR" TMPDIR="$TMP/tmp" USER=ci LANG=C.UTF-8 SHELL=/bin/bash \
    PATH="$TMP/fakes:$HOME_DIR/.local/bin:$TMP/tools:/usr/local/bin:/usr/bin:/bin" "$@"
}

run_setup() { # run_setup <brain> <args...>: setup.sh of that brain, under the sandbox
  local brain=$1; shift
  sandbox "$brain/setup.sh" "$@"
}

# The kit: $SMOKE_KIT, else the checkout the installed brief-check resolves into.
KIT=${SMOKE_KIT:-}
if [ -z "$KIT" ]; then
  bc=$(command -v brief-check 2>/dev/null) && KIT=$(dirname "$(readlink -f "$bc")")
fi
[ -n "$KIT" ] && [ -f "$KIT/install.sh" ] || fail_all "no kit: set SMOKE_KIT or put brief-check on PATH"

PY=$(command -v python3) || fail_all "python3 not found"
NODE=$(command -v node) || fail_all "node not found"
mkdir -p "$TMP/tools" "$TMP/fakes" "$TMP/log" "$TMP/tmp" "$HOME_DIR" "$CODE"
ln -s "$PY" "$TMP/tools/python3"
ln -s "$NODE" "$TMP/tools/node"
if [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
  # Link Homebrew's GNU tools (gnubin first) and its bash, so setup.sh does not re-exec
  # through the fake brew under /bin/bash 3.2.
  hb=$(brew --prefix)
  for d in "$hb"/opt/{coreutils,findutils,gnu-sed,grep}/libexec/gnubin "$hb/bin"; do
    [ -d "$d" ] || continue
    for t in "$d"/*; do [ -e "$TMP/tools/${t##*/}" ] || ln -s "$t" "$TMP/tools/${t##*/}"; done
  done
fi

# Fakes, written fresh.
cat >"$TMP/fakes/claude" <<EOF
#!/usr/bin/env bash
echo "claude \$*" >>"$TMP/log/claude.log"
if [ "\${1:-}" = auth ] && [ "\${2:-}" = status ]; then echo '{"loggedIn": true}'; fi
exit 0
EOF
for n in systemctl loginctl; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s/log/%s.log"\nexit 0\n' "$n" "$TMP" "$n" >"$TMP/fakes/$n"
done
for n in curl launchctl; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s/log/%s.log"\nexit 0\n' "$n" "$TMP" "$n" >"$TMP/fakes/$n"
done
for n in sudo apt-get dnf brew gh glab; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s/log/%s.log"\nexit 1\n' "$n" "$TMP" "$n" >"$TMP/fakes/$n"
done
chmod +x "$TMP/fakes"/*

# The template, as a bare repo, and the brain cloned from it.
mkdir "$TMP/src"
(cd "$ROOT" && ./template-files.sh) | while IFS= read -r f; do
  mkdir -p "$TMP/src/$(dirname "$f")" && cp -p "$ROOT/$f" "$TMP/src/$f"
done
git -C "$TMP/src" init -q -b main
git -C "$TMP/src" add -A
git -C "$TMP/src" "${GIT_ID[@]}" commit -q -m template
git clone -q --bare "$TMP/src" "$TMP/template.git"
git clone -q "$TMP/template.git" "$BRAIN"

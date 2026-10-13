#!/usr/bin/env bash
# setup.sh — turn a fresh clone of this template into a working brain.
#
#   ./setup.sh [--yes] [--name <n>] [--role <r>] [--languages <l>] [--principles <p>]
#              [--code-root <dir>] [--backends <claude,hermes,devin>] [--kit <dir>]
#              [--remote <name>|none] [--linger y|n] [--telegram y|n] [--journal y|n]
#              [--journal-daily HH:MM] [--journal-weekly HH:MM] [--hermes-hooks y|n] [-h|--help]
#   ./setup.sh --update [--yes] [--kit <dir>] [--hermes-hooks y|n]
#       merge the template's latest, re-run the idempotent steps
#   ./setup.sh --remove-example [--yes]           delete the example project and its demo repository
#
# The brain is the directory this script sits in. Safe to run again: nothing already
# right is changed, and no file of yours is ever overwritten.
# Exit 0: ready. 1: a final check failed (each failure is printed with its fix).
# 2: bad usage, no terminal without --yes, or an unsupported platform.
#
# Steps 1-2 run under bash 3.2 (the macOS /bin/bash): nothing newer in them.

set -euo pipefail

USAGE="usage: ./setup.sh [--yes] [--name <n>] [--role <r>] [--languages <l>] [--principles <p>]
                  [--code-root <dir>] [--backends <claude,hermes,devin>] [--kit <dir>]
                  [--remote <name>|none] [--linger y|n] [--telegram y|n] [--journal y|n]
                  [--journal-daily HH:MM] [--journal-weekly HH:MM] [--hermes-hooks y|n] [-h|--help]
       ./setup.sh --update [--yes] [--kit <dir>] [--hermes-hooks y|n]
       ./setup.sh --remove-example [--yes]"

BRAIN=$(cd "$(dirname "$0")" && pwd)
TAB=$(printf '\t')
NL='
'

YES=0 NAME="" ROLE="" LANGUAGES="" PRINCIPLES="" CODE_ROOT_RAW="" BACKENDS="" KIT_ARG="" REMOTE=""
LINGER="" TELEGRAM="" JOURNAL="" J_DAILY=23:30 J_WEEKLY=06:00 HERMES_HOOKS=""
MODE=setup
HAVE_NAME=0 HAVE_ROLE=0 HAVE_LANGUAGES=0 HAVE_PRINCIPLES=0 HAVE_CODE_ROOT=0 HAVE_BACKENDS=0 HAVE_REMOTE=0

usage_exit() { printf '%s\n' "$USAGE" >&2; exit 2; }
need_val() { [ "$1" -ge 2 ] || usage_exit; }

# In a function, so its shifts leave the script's own "$@" for the bash 4 restart.
parse_args() {
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --name) need_val $#; NAME=$2; HAVE_NAME=1; shift 2 ;;
    --role) need_val $#; ROLE=$2; HAVE_ROLE=1; shift 2 ;;
    --languages) need_val $#; LANGUAGES=$2; HAVE_LANGUAGES=1; shift 2 ;;
    --principles) need_val $#; PRINCIPLES=$2; HAVE_PRINCIPLES=1; shift 2 ;;
    --code-root) need_val $#; CODE_ROOT_RAW=$2; HAVE_CODE_ROOT=1; shift 2 ;;
    --backends) need_val $#; BACKENDS=$2; HAVE_BACKENDS=1; shift 2 ;;
    --kit) need_val $#; KIT_ARG=$2; shift 2 ;;
    --remote) need_val $#; REMOTE=$2; HAVE_REMOTE=1; shift 2 ;;
    --linger) need_val $#; LINGER=$2; shift 2 ;;
    --telegram) need_val $#; TELEGRAM=$2; shift 2 ;;
    --journal) need_val $#; JOURNAL=$2; shift 2 ;;
    --journal-daily) need_val $#; J_DAILY=$2; shift 2 ;;
    --journal-weekly) need_val $#; J_WEEKLY=$2; shift 2 ;;
    --hermes-hooks) need_val $#; HERMES_HOOKS=$2; shift 2 ;;
    --update) [ "$MODE" = setup ] || usage_exit; MODE=update; shift ;;
    --remove-example) [ "$MODE" = setup ] || usage_exit; MODE=remove; shift ;;
    -h|--help) printf '%s\n' "$USAGE"; exit 0 ;;
    *) usage_exit ;;
  esac
done
}
parse_args ${1+"$@"}

if [ "$HAVE_BACKENDS" = 1 ]; then
  BACKENDS=$(printf '%s' "$BACKENDS" | tr ',' ' ')
  [ -n "$BACKENDS" ] || usage_exit
  for b in $BACKENDS; do
    case "$b" in claude|hermes|devin) ;; *) usage_exit ;; esac
  done
fi
for v in "$LINGER" "$TELEGRAM" "$JOURNAL" "$HERMES_HOOKS"; do
  case "$v" in ""|y|n) ;; *) usage_exit ;; esac
done
for v in "$J_DAILY" "$J_WEEKLY"; do
  printf '%s' "$v" | grep -Eq '^([01][0-9]|2[0-3]):[0-5][0-9]$' || usage_exit
done
if [ -n "$KIT_ARG" ]; then
  [ -f "$KIT_ARG/install.sh" ] || { echo "setup.sh: --kit: no install.sh in $KIT_ARG" >&2; exit 2; }
  KIT_ARG=$(cd "$KIT_ARG" && pwd)
fi

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

# Results of the final checks: one "ready<TAB>label" or "bad<TAB>label<TAB>fix" per line.
RES=""
record_ok() { RES="$RES""ok${TAB}$1${NL}"; }
record_bad() { RES="$RES""bad${TAB}$1${TAB}$2${NL}"; }

# Prompts read from /dev/tty; under --yes nothing is asked.
ask() { # ask <prompt> <default> -> answer on stdout
  local ans=""
  if [ "$YES" = 1 ]; then printf '%s' "$2"; return; fi
  printf '%s [%s]: ' "$1" "$2" >&2
  read -r ans </dev/tty || ans=""
  printf '%s' "${ans:-$2}"
}
confirm() { # confirm <question>: y/N, --yes accepts
  local ans=""
  [ "$YES" = 1 ] && return 0
  printf '%s [y/N]: ' "$1" >&2
  read -r ans </dev/tty || ans=""
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
expand_home() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s' "$HOME/${1#"~/"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# ---- Step 1: platform -------------------------------------------------------------
case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux)
    if [ -r /proc/version ] && grep -qi microsoft /proc/version; then PLATFORM=wsl2; else PLATFORM=linux; fi ;;
  *) echo "setup.sh: unsupported platform: $(uname -s) (Linux, WSL2 and macOS only)" >&2; exit 2 ;;
esac
if [ "$YES" = 0 ] && ! ( exec </dev/tty ) 2>/dev/null; then
  echo "no terminal: pass --yes" >&2
  exit 2
fi
step "1. Platform: $PLATFORM"

# ---- Step 2: dependencies ---------------------------------------------------------
step "2. Dependencies"
SUDO=""
[ "$(id -u)" = 0 ] || SUDO=sudo
PM=""
if [ "$PLATFORM" = macos ]; then PM=brew
elif command -v apt-get >/dev/null 2>&1; then PM=apt-get
elif command -v dnf >/dev/null 2>&1; then PM=dnf
fi

is_gnu() { case "$("$1" --version 2>&1 || true)" in *GNU*) return 0 ;; *) return 1 ;; esac; }
tool_ok() {
  case "$1" in
    bash) [ "${BASH_VERSINFO[0]}" -ge 4 ] ;;
    coreutils) is_gnu sort ;;
    findutils) is_gnu find ;;
    sed) is_gnu sed ;;
    grep) is_gnu grep ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}
pkg_for() {
  case "$1" in
    node) [ "$PM" = brew ] && echo node || echo nodejs ;;
    sed) [ "$PM" = brew ] && echo gnu-sed || echo sed ;;
    flock|setsid) echo util-linux ;;
    pgrep) [ "$PM" = dnf ] && echo procps-ng || echo procps ;;
    *) echo "$1" ;;
  esac
}
install_cmd() { # install_cmd <pkgs...>
  case "$PM" in
    apt-get) echo "${SUDO:+$SUDO }apt-get install -y $*" ;;
    dnf) echo "${SUDO:+$SUDO }dnf install -y $*" ;;
    brew) echo "brew install $*" ;;
  esac
}
gnubin_path() {
  local p
  for p in coreutils findutils gnu-sed grep; do
    PATH="$(brew --prefix)/opt/$p/libexec/gnubin:$PATH"
  done
  export PATH
}

REQUIRED="git bash python3 node curl coreutils findutils sed grep pgrep"
# flock and setsid: Homebrew's util-linux is keg-only, and on macOS every caller
# falls back (python3, a lock directory), so only Linux and WSL2 require them.
[ "$PLATFORM" = macos ] || REQUIRED="$REQUIRED flock setsid"
MISSING=""
for t in $REQUIRED; do tool_ok "$t" || MISSING="$MISSING $t"; done
for t in gh glab; do
  if command -v "$t" >/dev/null 2>&1; then say "optional: $t found"; else say "optional: $t not found (never installed by this script)"; fi
done

if [ -n "$MISSING" ]; then
  say "missing:$MISSING"
  if [ -z "$PM" ]; then
    for t in $MISSING; do record_bad "dependency $t" "install $t with your package manager"; done
  else
    if [ "$PM" = brew ] && ! command -v brew >/dev/null 2>&1; then
      BREW_CMD='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      say "Homebrew is needed first. Installer: $BREW_CMD"
      if confirm "run it?"; then
        say "+ $BREW_CMD"
        bash -c "$BREW_CMD" || true
        for _hb in /opt/homebrew /usr/local; do
          [ -x "$_hb/bin/brew" ] && { PATH="$_hb/bin:$PATH"; export PATH; break; }
        done
      fi
    fi
    if [ "$PM" = brew ] && ! command -v brew >/dev/null 2>&1; then
      for t in $MISSING; do record_bad "dependency $t" "install Homebrew (https://brew.sh), then ./setup.sh"; done
    else
      PKGS=""
      for t in $MISSING; do
        for p in $(pkg_for "$t"); do
          case " $PKGS " in *" $p "*) ;; *) PKGS="$PKGS $p" ;; esac
        done
      done
      PKGS=${PKGS# }
      CMD=$(install_cmd $PKGS)
      say "install command: $CMD"
      if confirm "run it?"; then
        say "+ $CMD"
        $CMD || say "install command failed"
        [ "$PM" = brew ] && gnubin_path
      else
        say "declined"
      fi
      for t in $MISSING; do
        tool_ok "$t" || record_bad "dependency $t" "$CMD"
      done
    fi
  fi
fi

# macOS: the rest of the script needs bash 4; re-exec under Homebrew's.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  if [ "$PLATFORM" = macos ] && [ -z "${AGENT_BRAIN_REEXEC:-}" ] && command -v brew >/dev/null 2>&1 \
     && [ -x "$(brew --prefix)/bin/bash" ]; then
    export AGENT_BRAIN_REEXEC=1
    exec "$(brew --prefix)/bin/bash" "$0" ${1+"$@"}
  fi
  echo "setup.sh: needs bash 4 or newer; install it, then run ./setup.sh again" >&2
  exit 1
fi

ENV_FILE="$BRAIN/brain.env"
env_get() { # env_get <key> <default>
  local v=""
  [ -f "$ENV_FILE" ] && v=$(grep -m 1 "^$1=" "$ENV_FILE" | cut -d= -f2- || true)
  [ -n "$v" ] || v=$2
  expand_home "$v"
}
env_set() { # env_set <key> <value>: rewrite that one line, keep the rest
  local tmp="$ENV_FILE.tmp.$$"
  K=$1 V=$2 awk '
    index($0, ENVIRON["K"] "=") == 1 && !done { print ENVIRON["K"] "=" ENVIRON["V"]; done = 1; next }
    { print }
    END { if (!done) print ENVIRON["K"] "=" ENVIRON["V"] }' "$ENV_FILE" >"$tmp"
  cat "$tmp" >"$ENV_FILE"
  rm -f "$tmp"
}
# ---- Step 3: five questions -------------------------------------------------------
step "3. About you"
if [ "$MODE" != setup ]; then
  # --update and --remove-example ask nothing: the code root is the one setup stored.
  CODE_ROOT_X=$(env_get CODE_ROOT "~/projects")
  CODE_ROOT_X=${CODE_ROOT_X%/}
  DEMO="$CODE_ROOT_X/agent-brain-demo"
  say "skipped ($MODE)"
else
  if [ "$HAVE_NAME" = 0 ]; then
    default_name=$(git config user.name 2>/dev/null || true)
    NAME=$(ask "Your name" "${default_name:-${USER:-me}}")
  fi
  [ "$HAVE_ROLE" = 1 ] || ROLE=$(ask "Your role" "software engineer")
  if [ "$HAVE_LANGUAGES" = 0 ]; then
    if [ "$YES" = 1 ]; then LANGUAGES=""; else LANGUAGES=$(ask "Working languages (empty for none)" ""); fi
  fi
  [ -n "$LANGUAGES" ] || LANGUAGES="none yet"
  [ "$HAVE_PRINCIPLES" = 1 ] || PRINCIPLES=$(ask "Principles" "TDD, SOLID, YAGNI, KISS, DRY")
  [ "$HAVE_CODE_ROOT" = 1 ] || CODE_ROOT_RAW=$(ask "Root directory of your code repos" "~/projects")
  [ -n "$CODE_ROOT_RAW" ] || CODE_ROOT_RAW="~/projects"
  CODE_ROOT_X=$(expand_home "$CODE_ROOT_RAW")
  CODE_ROOT_X=${CODE_ROOT_X%/}
  DEMO="$CODE_ROOT_X/agent-brain-demo"
fi

# ---- --remove-example: delete what setup made for the demo, nothing else ---------------
EX_LINE_1='- **example** 🟢 — 🟢1 — a demo main to try the handoff kit on; ./setup.sh --remove-example deletes it'
EX_LINE_2='  - example-version-flag'
if [ "$MODE" = remove ]; then
  step "Remove the example"
  EX_DIR="$BRAIN/02-projects/example"
  LOCAL_MD="$BRAIN/AGENTS.local.md"
  DEL_DIR=0 DEL_DEMO=0 DEL_BARE=0 DEL_LINES=0
  if [ -f "$EX_DIR/context.md" ] && grep -q -F './setup.sh --remove-example' "$EX_DIR/context.md"; then DEL_DIR=1
  elif [ -e "$EX_DIR" ]; then say "kept $EX_DIR: it is not the example setup made"; fi
  if [ -d "$DEMO/.git" ] && [ "$(git -C "$DEMO" remote get-url origin 2>/dev/null || true)" = "$DEMO.git" ]; then
    DEL_DEMO=1
    if [ -d "$DEMO.git" ] && [ "$(git -C "$DEMO.git" rev-parse --is-bare-repository 2>/dev/null || true)" = true ]; then DEL_BARE=1; fi
  elif [ -e "$DEMO" ]; then say "kept $DEMO: it is not the demo repository setup made"; fi
  if [ -f "$LOCAL_MD" ] && grep -q -x -F -e "$EX_LINE_1" -e "$EX_LINE_2" "$LOCAL_MD"; then DEL_LINES=1; fi
  if [ "$((DEL_DIR + DEL_DEMO + DEL_BARE + DEL_LINES))" = 0 ]; then
    say "nothing to remove"
  else
    [ "$DEL_DIR" = 0 ] || say "will delete $EX_DIR"
    [ "$DEL_DEMO" = 0 ] || say "will delete $DEMO"
    [ "$DEL_BARE" = 0 ] || say "will delete $DEMO.git"
    [ "$DEL_LINES" = 0 ] || say "will remove the two example lines from AGENTS.local.md"
    confirm "Delete them?" || { say "declined: nothing removed"; exit 1; }
    [ "$DEL_DIR" = 0 ] || rm -rf "$EX_DIR"
    [ "$DEL_DEMO" = 0 ] || rm -rf "$DEMO"
    [ "$DEL_BARE" = 0 ] || rm -rf "$DEMO.git"
    if [ "$DEL_LINES" = 1 ]; then
      L1=$EX_LINE_1 L2=$EX_LINE_2 awk '$0 != ENVIRON["L1"] && $0 != ENVIRON["L2"]' "$LOCAL_MD" >"$LOCAL_MD.tmp.$$"
      cat "$LOCAL_MD.tmp.$$" >"$LOCAL_MD"
      rm -f "$LOCAL_MD.tmp.$$"
    fi
    say "example removed"
  fi
  # Step 4 reads this: neither a later --update nor a plain ./setup.sh brings the example back.
  [ -f "$ENV_FILE" ] || : >"$ENV_FILE"
  env_set EXAMPLE removed
  exit 0
fi

# ---- --update: merge the template's latest ----------------------------------------------
ID_ARGS=()
if [ "$MODE" = update ]; then
  step "Template update"
  G=(git -C "$BRAIN")
  if ! "${G[@]}" remote get-url template >/dev/null 2>&1; then
    echo "setup.sh: no 'template' remote. Add it, then run --update again:" >&2
    echo "  git remote add template <url> && git remote set-url --push template DISABLED" >&2
    exit 1
  fi
  if [ -n "$("${G[@]}" status --porcelain --untracked-files=no)" ]; then
    echo "setup.sh: the working tree has uncommitted changes. Commit them first (git add -A && git commit), then run --update again." >&2
    exit 1
  fi
  "${G[@]}" fetch -q template || { echo "setup.sh: git fetch template failed" >&2; exit 1; }
  BASE=$("${G[@]}" merge-base HEAD template/main 2>/dev/null) \
    || { echo "setup.sh: template/main shares no history with this brain: nothing was merged" >&2; exit 1; }
  LOCAL_CHANGED=$(comm -12 <("$BRAIN/template-files.sh") <("${G[@]}" -c core.quotePath=false diff --name-only --no-renames "$BASE" HEAD | sort))
  if [ -n "$LOCAL_CHANGED" ]; then
    say "template-owned files you changed since the last merge with the template (they may conflict):"
    printf '%s\n' "$LOCAL_CHANGED" | sed 's/^/  /'
  fi
  [ -n "$("${G[@]}" config user.email 2>/dev/null || true)" ] || ID_ARGS=(-c user.name=agent-brain -c user.email=agent-brain@localhost)
  if ! "${G[@]}" ${ID_ARGS[@]+"${ID_ARGS[@]}"} merge --no-edit template/main; then
    echo "setup.sh: the merge stopped on conflicts. Resolve them and commit, or go back with: git merge --abort" >&2
    exit 1
  fi
fi

# ---- Step 4: seeds ----------------------------------------------------------------
step "4. Seeds"
fill_placeholders() { # literal replacement, no regex
  python3 -I - "$1" "@NAME@" "$NAME" "@ROLE@" "$ROLE" "@LANGUAGES@" "$LANGUAGES" \
    "@PRINCIPLES@" "$PRINCIPLES" "@DEMO_REPO@" "$DEMO" <<'PY'
import sys
path, pairs = sys.argv[1], sys.argv[2:]
with open(path, encoding="utf-8", newline="") as fh:
    text = fh.read()
for i in range(0, len(pairs), 2):
    text = text.replace(pairs[i], pairs[i + 1])
with open(path, "w", encoding="utf-8", newline="") as fh:
    fh.write(text)
PY
}

fill_demo_repo() { # update mode asked nothing: only @DEMO_REPO@ is known
  python3 -I - "$1" "$DEMO" <<'PY'
import sys
path, demo = sys.argv[1:3]
with open(path, encoding="utf-8", newline="") as fh:
    text = fh.read()
with open(path, "w", encoding="utf-8", newline="") as fh:
    fh.write(text.replace("@DEMO_REPO@", demo))
PY
}

COPIED=""
EXAMPLE_REMOVED=0
[ "$(env_get EXAMPLE "")" = removed ] && EXAMPLE_REMOVED=1
if [ "$MODE" = update ] && [ "$EXAMPLE_REMOVED" = 0 ] && [ ! -e "$BRAIN/02-projects/example" ]; then
  # Deleted by hand: re-seeding it would leave @DEMO_REPO@ unfilled and fail the final check.
  [ -f "$ENV_FILE" ] || : >"$ENV_FILE"
  env_set EXAMPLE removed
  EXAMPLE_REMOVED=1
  say "example not found: recorded as removed (EXAMPLE=removed in brain.env)"
fi
SEED_SKIP=(! -path './demo-repo/*')
[ "$EXAMPLE_REMOVED" = 0 ] || SEED_SKIP+=(! -path './02-projects/example/*')
SEEDS=$(cd "$BRAIN/.seed" && find . -type f "${SEED_SKIP[@]}" | sed 's|^\./||' | sort)
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  dest="$BRAIN/$rel"
  if [ -e "$dest" ]; then say "kept $rel"; continue; fi
  mkdir -p "$(dirname "$dest")"
  cp "$BRAIN/.seed/$rel" "$dest"
  COPIED="$COPIED$rel$NL"
  if [ "$MODE" = update ]; then
    if grep -q -F '@DEMO_REPO@' "$dest"; then fill_demo_repo "$dest"; fi
    if grep -q -E '@[A-Z_]+@' "$dest"; then say "created $rel (placeholders unfilled: edit it by hand)"; else say "created $rel"; fi
  else
    if grep -q -F '@' "$dest"; then fill_placeholders "$dest"; fi
    say "created $rel"
  fi
done <<EOF
$SEEDS
EOF
seed_copied() { printf '%s' "$COPIED" | grep -qx -F -- "$1"; }

if [ "$MODE" = setup ] && seed_copied brain.env; then env_set CODE_ROOT "$CODE_ROOT_RAW"; fi

for d in 00-inbox 01-daily 03-knowledge 05-weekly; do
  if [ ! -d "$BRAIN/$d" ]; then mkdir -p "$BRAIN/$d"; : >"$BRAIN/$d/.gitkeep"; say "created $d/"; fi
done

if [ "$EXAMPLE_REMOVED" = 1 ]; then
  say "example removed: no demo repository"
elif [ -e "$DEMO" ]; then
  say "kept demo repository $DEMO"
else
  say "creating demo repository $DEMO"
  mkdir -p "$CODE_ROOT_X"
  cp -R "$BRAIN/.seed/demo-repo" "$DEMO"
  git -C "$DEMO" init -q -b main
  git -C "$DEMO" add -A
  if [ -n "$(git -C "$DEMO" config user.name 2>/dev/null || true)" ] && [ -n "$(git -C "$DEMO" config user.email 2>/dev/null || true)" ]; then
    git -C "$DEMO" commit -q -m "Initial commit"
  else
    git -C "$DEMO" -c user.name=agent-brain -c user.email=agent-brain@localhost commit -q -m "Initial commit"
  fi
  git clone -q --bare "$DEMO" "$DEMO.git"
  git -C "$DEMO" remote add origin "$DEMO.git"
  git -C "$DEMO" push -q -u origin main
fi

# ---- Step 5: git ------------------------------------------------------------------
step "5. Git"
git -C "$BRAIN" config core.hooksPath .githooks
say "core.hooksPath = .githooks"
if git -C "$BRAIN" remote get-url origin >/dev/null 2>&1 && ! git -C "$BRAIN" remote get-url template >/dev/null 2>&1; then
  git -C "$BRAIN" remote rename origin template >/dev/null 2>&1
  git -C "$BRAIN" remote set-url --push template DISABLED
  say "origin renamed to template; its push URL is DISABLED"
fi
if [ "$MODE" = update ] && [ "$HAVE_REMOTE" = 0 ]; then REMOTE=none; HAVE_REMOTE=1; fi
if [ "$HAVE_REMOTE" = 0 ]; then
  if [ "$YES" = 1 ]; then REMOTE=none; else REMOTE=$(ask "Private GitHub repo to create for this brain (name, or none)" "none"); fi
fi
[ -n "$REMOTE" ] || REMOTE=none
if [ "$REMOTE" != none ]; then
  if git -C "$BRAIN" remote get-url origin >/dev/null 2>&1; then
    say "origin already exists: not creating $REMOTE"
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    say "+ gh repo create $REMOTE --private --source . --remote origin --push"
    (cd "$BRAIN" && gh repo create "$REMOTE" --private --source . --remote origin --push) \
      || say "gh repo create failed: create the repository by hand and add it as origin"
  else
    say "gh is missing or not logged in: no remote created (run gh auth login, then gh repo create $REMOTE --private --source . --remote origin --push)"
  fi
fi
if git -C "$BRAIN" remote get-url origin >/dev/null 2>&1 && command -v gh >/dev/null 2>&1; then
  vis=$( (cd "$BRAIN" && gh repo view --json visibility -q .visibility) 2>/dev/null || true)
  if [ "$vis" = PUBLIC ] || [ "$vis" = public ]; then
    say "WARNING: origin is a PUBLIC repository. This brain holds private notes: make it private."
  fi
fi

# ---- Step 6: skills ---------------------------------------------------------------
step "6. Skills"
if ! sh "$BRAIN/sync-skills.sh" --apply; then
  record_bad "skills mirror" "run ./sync-skills.sh and read its message"
fi

# ---- Step 7: kit ------------------------------------------------------------------
step "7. Handoff kit"
pin_get() { grep "^$1=" "$BRAIN/handoff-kit.pin" | tail -n 1 | cut -d= -f2-; }
KIT_URL=$(pin_get HANDOFF_KIT_URL)
KIT_TAG=$(pin_get HANDOFF_KIT_TAG)
KIT_OK=1
KIT_SKIP=0
if [ -n "$KIT_ARG" ]; then
  KIT=$KIT_ARG
  say "using kit $KIT (HEAD untouched)"
else
  KIT="${XDG_DATA_HOME:-$HOME/.local/share}/handoff-kit"
  BC_REAL=""
  if [ "$MODE" = update ] && [ -e "$HOME/.local/bin/brief-check" ]; then
    BC_REAL=$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$HOME/.local/bin/brief-check")
  fi
  if [ -n "$BC_REAL" ] && [ "$(dirname "$BC_REAL")" != "$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$KIT")" ]; then
    KIT_SKIP=1
    say "WARNING: ~/.local/bin/brief-check resolves to $BC_REAL, outside $KIT: the kit is left alone (pass --kit <dir> to reinstall it)"
  elif [ -d "$KIT/.git" ]; then
    say "updating $KIT to $KIT_TAG"
    git -C "$KIT" fetch -q --tags origin && git -C "$KIT" checkout -q --detach "$KIT_TAG" || KIT_OK=0
  else
    say "cloning $KIT_URL into $KIT at $KIT_TAG"
    mkdir -p "$(dirname "$KIT")"
    { git clone -q "$KIT_URL" "$KIT" && git -C "$KIT" checkout -q --detach "$KIT_TAG"; } || KIT_OK=0
  fi
fi
KIT_INSTALL_ARGS="--vault $BRAIN --defaults 02-projects/_templates/handoff-defaults.yml --projects 02-projects"
if [ "$KIT_OK" = 1 ] && [ "$KIT_SKIP" = 0 ]; then
  bash "$KIT/install.sh" $KIT_INSTALL_ARGS || KIT_OK=0
fi
[ "$KIT_OK" = 1 ] || record_bad "handoff kit" "re-run ./setup.sh, then run the failing command by hand to read its message"

RC_BLOCK_LINE='export PATH="$HOME/.local/bin:$PATH"'
GNU_PKGS="coreutils findutils gnu-sed grep"
rc_file() { case "$(basename "${SHELL:-bash}")" in zsh) echo "$HOME/.zshrc" ;; *) echo "$HOME/.bashrc" ;; esac; }
rc_text() {
  printf '# agent-brain setup\n%s\n' "$RC_BLOCK_LINE"
  if [ "$PLATFORM" = macos ]; then
    for p in $GNU_PKGS; do printf 'export PATH="$(brew --prefix)/opt/%s/libexec/gnubin:$PATH"\n' "$p"; done
  fi
}
NEED_RC=0
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) NEED_RC=1 ;; esac
if [ "$PLATFORM" = macos ] && ! is_gnu sed; then NEED_RC=1; fi
RC=$(rc_file)
if [ "$NEED_RC" = 1 ]; then
  if [ -f "$RC" ] && grep -q -F '# agent-brain setup' "$RC"; then
    say "$RC already has the agent-brain block"
  else
    say "$HOME/.local/bin is not on PATH. This block would be appended to $RC:"
    rc_text | sed 's/^/    /'
    if confirm "append it?"; then
      { printf '\n'; rc_text; } >>"$RC"
      say "appended to $RC (open a new shell to pick it up)"
    fi
  fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH"; export PATH ;; esac
fi
if [ "$PLATFORM" != macos ]; then
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    say "NOTE: no systemd user session. The plan watchdog needs one. Either:"
    say "  - enable systemd (on WSL2: put [boot] systemd=true in /etc/wsl.conf, then run wsl --shutdown), or"
    say "  - run /loop 30m handoff-orchestrate tick <plan> in an open agent session."
  fi
fi

# Hermes shell hooks, in hermes's default profile: the Bash guard before each terminal call,
# auto-commit at the end of each turn. Both act only in a hermes process running in this brain.
HH_LATER="./setup.sh --update --hermes-hooks y"
hermes_hooks() { # hermes_hooks present|set: 0 when one is registered | register both, with consent
  python3 -I - "$1" "$BRAIN" <<'PY'
import datetime, json, os, shlex, subprocess, sys
mode, brain = sys.argv[1:3]
guard, auto = brain + "/.claude/hooks/guard-git-refs.py", brain + "/auto-commit.sh"
mine = {  # event: (this brain's entry, the script hermes dates the consent by)
    "pre_tool_call": ({"matcher": "terminal", "command": "python3 " + shlex.quote(guard), "timeout": 10}, guard),
    "on_session_end": ({"command": "sh %s --hermes-hook" % shlex.quote(auto), "timeout": 30}, auto),
}
def config(*args):
    return subprocess.run(["hermes", "-p", "default", "config", *args], capture_output=True, text=True)
def entries(ev):  # the event's hook list: [] when unset, None when it is not a list; any other failure exits 1
    p = config("get", "hooks." + ev, "--json", "--raw")
    if p.returncode:
        if "Config key not set" in p.stderr:
            return []
        sys.exit(1)
    v = json.loads(p.stdout or "null")
    return [] if v is None else v if isinstance(v, list) else None
def ours(e, ev):
    return isinstance(e, dict) and e.get("command") == mine[ev][0]["command"]
if mode == "present":
    sys.exit(0 if any(ours(e, ev) for ev in mine for e in entries(ev) or []) else 1)
p = config("path")
if p.returncode or not p.stdout.strip():
    sys.exit(1)
allow = os.path.join(os.path.dirname(p.stdout.strip()), "shell-hooks-allowlist.json")
try:
    with open(allow, encoding="utf-8") as fh:
        data = json.load(fh)
except FileNotFoundError:
    data = {"approvals": []}
except ValueError:
    sys.exit(1)
if not isinstance(data, dict) or not isinstance(data.get("approvals", []), list):
    sys.exit(1)
iso = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat().replace("+00:00", "Z")
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
keys = {(ev, entry["command"]) for ev, (entry, _) in mine.items()}
approvals = [a for a in data.get("approvals", []) if not (isinstance(a, dict) and (a.get("event"), a.get("command")) in keys)]
for ev, (entry, script) in mine.items():
    cur = entries(ev)
    if cur is None or config("set", "hooks." + ev, json.dumps([e for e in cur if not ours(e, ev)] + [entry])).returncode:
        sys.exit(1)
    approvals.append({"event": ev, "command": entry["command"], "approved_at": now,
                      "script_mtime_at_approval": iso(os.path.getmtime(script))})
data["approvals"] = approvals
tmp = "%s.tmp.%d" % (allow, os.getpid())
with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp, allow)
PY
}
hermes_hooks_record() {
  if hermes_hooks set; then record_ok "hermes hooks"; else record_bad "hermes hooks" "$HH_LATER"; fi
}

# Steps 8 and 9 ask about this host: --update leaves them alone, except the journal times.
if [ "$MODE" = setup ]; then
# ---- Step 8: backends -------------------------------------------------------------
step "8. Backends"
if [ "$HAVE_BACKENDS" = 0 ]; then
  if [ "$YES" = 1 ]; then BACKENDS=claude
  else
    BACKENDS=$(ask "Backends (any of claude, hermes, devin)" "claude" | tr ',' ' ')
    HAVE_BACKENDS=1
  fi
  for b in $BACKENDS; do
    case "$b" in claude|hermes|devin) ;; *) echo "setup.sh: unknown backend: $b" >&2; exit 2 ;; esac
  done
fi

run_installer() { # run_installer <label> <command>; 0 on success
  say "$1 is missing. Installer: $2"
  if confirm "run it?"; then
    say "+ $2"
    bash -c "$2" && return 0
    say "installer failed"
  fi
  return 1
}
find_claude() {
  if [ -n "${CLAUDE_BIN:-}" ] && [ -x "$CLAUDE_BIN" ]; then echo "$CLAUDE_BIN"
  elif command -v claude >/dev/null 2>&1; then command -v claude
  elif [ -x "$HOME/.local/bin/claude" ]; then echo "$HOME/.local/bin/claude"
  fi
}
claude_logged_in() { "$1" auth status 2>/dev/null | grep -Eq '"loggedIn"[[:space:]]*:[[:space:]]*true'; }
devin_logged_in() {
  local out; out=$(devin auth status 2>&1 || true)
  printf '%s' "$out" | grep -qi 'logged in' && ! printf '%s' "$out" | grep -qi 'not logged in'
}

setup_claude() {
  local bin cmd="curl -fsSL https://claude.ai/install.sh | bash"
  bin=$(find_claude)
  if [ -z "$bin" ]; then
    run_installer claude "$cmd" || { record_bad "backend claude" "$cmd"; return; }
    bin=$(find_claude)
    [ -n "$bin" ] || { record_bad "backend claude" "$cmd"; return; }
  fi
  if ! claude_logged_in "$bin"; then
    say "claude is not logged in. Login: claude auth login"
    if [ "$YES" = 0 ] && confirm "run it?"; then "$bin" auth login || true; fi
    claude_logged_in "$bin" || { record_bad "backend claude" "claude auth login"; return; }
  fi
  record_ok "backend claude"
}
setup_hermes() {
  if ! command -v hermes >/dev/null 2>&1; then
    say "hermes is not installed, and this script has no installer for it."
    say "See '## Hermes profiles' in the kit README: $KIT/README.md"
    record_bad "backend hermes" "install hermes, then see '## Hermes profiles' in $KIT/README.md"
    return
  fi
  if [ ! -d "$HOME/.hermes" ]; then
    record_bad "backend hermes" "run hermes once to create ~/.hermes, set its provider and log in, then ./setup.sh"
    return
  fi
  [ "$KIT_OK" = 1 ] && { bash "$KIT/install.sh" $KIT_INSTALL_ARGS --hermes-profiles || true; }
  say "hermes: set its provider and log in (see '## Hermes profiles' in $KIT/README.md)"
  record_ok "backend hermes"
  case "$HERMES_HOOKS" in
    y) hermes_hooks_record ;;
    n) say "hermes hooks: not registered (later: $HH_LATER)" ;;
    *)
      if confirm "Register the brain's Bash guard and auto-commit as hermes hooks (default profile)?"; then
        hermes_hooks_record
      else
        say "hermes hooks: not registered (later: $HH_LATER)"
      fi ;;
  esac
}
setup_devin() {
  local cmd="curl -fsSL https://cli.devin.ai/install.sh | bash" login="devin auth login"
  if ! command -v devin >/dev/null 2>&1; then
    run_installer devin "$cmd" || { record_bad "backend devin" "$cmd"; return; }
    command -v devin >/dev/null 2>&1 || { record_bad "backend devin" "$cmd"; return; }
  fi
  if ! devin_logged_in; then
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$PLATFORM" != macos ]; then
      login="$login --force-manual-token-flow"
    fi
    say "devin is not logged in. Login: $login"
    if [ "$YES" = 0 ] && confirm "run it?"; then $login || true; fi
    devin_logged_in || { record_bad "backend devin" "$login"; return; }
  fi
  record_ok "backend devin"
}
for b in $BACKENDS; do
  case "$b" in claude) setup_claude ;; hermes) setup_hermes ;; devin) setup_devin ;; esac
done
case " $BACKENDS " in
  *" hermes "*) ;;
  *) if [ "$HERMES_HOOKS" = y ]; then say "hermes hooks: hermes backend not chosen, flag ignored"; fi ;;
esac
if [ "$HAVE_BACKENDS" = 1 ] || seed_copied brain.env; then
  set -- $BACKENDS
  env_set DEFAULT_BACKEND "$1"
fi

# ---- Step 9: extras ---------------------------------------------------------------
step "9. Extras"
want() { # want <flag value> <question>: the flag wins; else no under --yes, else ask
  case "$1" in y) return 0 ;; n) return 1 ;; esac
  [ "$YES" = 1 ] && return 1
  confirm "$2"
}

# Linger: user timers run with no login session.
if [ "$PLATFORM" = macos ]; then
  say "linger: skipped, launchd agents run while the user is logged in"
elif want "$LINGER" "Keep your user services running with no login session (loginctl enable-linger)?"; then
  say "+ loginctl enable-linger ${USER:-$(id -un)}"
  loginctl enable-linger "${USER:-$(id -un)}" || record_bad "linger" "loginctl enable-linger ${USER:-$(id -un)}"
  [ "$PLATFORM" != wsl2 ] || say "WSL2: the timers fire only while the WSL VM is running."
else
  say "linger: not enabled"
fi

# Telegram: ~/.config/handoff/notify.env, read line by line, never sourced.
NOTIFY_ENV="$HOME/.config/handoff/notify.env"
tg_get() { grep "^$1=" "$NOTIFY_ENV" 2>/dev/null | tail -n 1 | cut -d= -f2- || true; }
tg_ready() { [ -n "$(tg_get TELEGRAM_BOT_TOKEN)" ] && [ -n "$(tg_get TELEGRAM_CHAT_ID)" ]; }
if want "$TELEGRAM" "Set up Telegram notifications?"; then
  if tg_ready; then
    say "kept $NOTIFY_ENV"
  else
    TG_TOK="" TG_CHAT=""
    if [ "$YES" = 1 ]; then
      TG_TOK=${TELEGRAM_BOT_TOKEN:-}; TG_CHAT=${TELEGRAM_CHAT_ID:-}
    else
      printf 'Bot token (hidden): ' >&2; read -rs TG_TOK </dev/tty || TG_TOK=""; printf '\n' >&2
      printf 'Chat id (hidden): ' >&2; read -rs TG_CHAT </dev/tty || TG_CHAT=""; printf '\n' >&2
    fi
    if [ -z "$TG_TOK" ] || [ -z "$TG_CHAT" ]; then
      record_bad "telegram" "set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in the environment, then ./setup.sh --telegram y"
    else
      ( umask 077
        mkdir -p "$(dirname "$NOTIFY_ENV")"
        printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "$TG_TOK" "$TG_CHAT" >"$NOTIFY_ENV" )
      chmod 600 "$NOTIFY_ENV"
      say "wrote $NOTIFY_ENV (mode 600)"
    fi
    TG_TOK="" TG_CHAT=""
  fi
  if tg_ready; then
    env_set NOTIFY telegram
    if confirm "Send one test message?"; then
      # The token goes to curl on stdin, never on its command line.
      if printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$(tg_get TELEGRAM_BOT_TOKEN)" \
           | curl -fsS -m 20 -X POST -K - --data-urlencode "chat_id=$(tg_get TELEGRAM_CHAT_ID)" \
               --data-urlencode "text=agent-brain: Telegram is set up" >/dev/null 2>&1; then
        say "test message sent"
      else
        record_bad "telegram test message" "check the token and chat id in $NOTIFY_ENV, then ./setup.sh --telegram y"
      fi
    fi
  fi
else
  say "telegram: not set up"
fi

# Journal timers.
if want "$JOURNAL" "Install the journal timers (/rollup and /day-log on weekday evenings, /week-recap on Mondays)?"; then
  if ! bash "$BRAIN/journal/install.sh" "$BRAIN" --daily "$J_DAILY" --weekly "$J_WEEKLY"; then
    record_bad "journal timers" "on WSL2 enable systemd ([boot] systemd=true in /etc/wsl.conf, then wsl --shutdown); then ./setup.sh --journal y"
  fi
else
  say "journal timers: not installed (bash journal/install.sh $BRAIN, or ./setup.sh --journal y)"
fi

else
  step "Journal timers"
  if [ ! -f "$HOME/.config/agent-brain/journal.env" ]; then
    say "journal timers: not installed, nothing to refresh"
  else
    journal_time() { # journal_time <daily|weekly>: the chosen HH:MM, empty when this brain has no timer
      if [ "$PLATFORM" = macos ]; then
        python3 -I - "$BRAIN" "$1" "$HOME/Library/LaunchAgents" <<'PY'
import hashlib, re, sys
brain, job, agents = sys.argv[1:4]
digest = hashlib.sha256(brain.encode()).hexdigest()[:8]
try:
    text = open(f"{agents}/io.github.tissarni.agent-brain.journal.{job}.{digest}.plist", encoding="utf-8").read()
except OSError:
    sys.exit(0)
m = re.search(r"<key>Hour</key><integer>(\d+)</integer><key>Minute</key><integer>(\d+)</integer>", text)
if m:
    print("%02d:%02d" % (int(m.group(1)), int(m.group(2))))
PY
      else
        local inst conf
        inst=$(systemd-escape --path "$BRAIN" 2>/dev/null) || return 0
        conf="$HOME/.config/systemd/user/agent-brain-journal-$1@$inst.timer.d/time.conf"
        [ -f "$conf" ] || return 0
        grep '^OnCalendar=.' "$conf" | tail -n 1 | sed -n 's/.* \([0-9][0-9]:[0-9][0-9]\)\(:00\)\{0,1\}$/\1/p'
      fi
    }
    JD=$(journal_time daily); JW=$(journal_time weekly)
    if [ -z "$JD$JW" ]; then
      say "journal timers: none installed for this brain, left alone"
    else
      bash "$BRAIN/journal/install.sh" "$BRAIN" --daily "${JD:-$J_DAILY}" --weekly "${JW:-$J_WEEKLY}" \
        || record_bad "journal timers" "bash journal/install.sh $BRAIN, then ./setup.sh --update"
    fi
  fi

  step "Hermes hooks"
  if ! command -v hermes >/dev/null 2>&1; then
    if [ "$HERMES_HOOKS" = y ]; then
      record_bad "hermes hooks" "install hermes, then $HH_LATER"
    else
      say "hermes hooks: hermes is not installed, nothing to refresh"
    fi
  elif [ "$HERMES_HOOKS" = n ]; then
    say "hermes hooks: left alone (--hermes-hooks n)"
  elif [ "$HERMES_HOOKS" = y ] || hermes_hooks present; then
    hermes_hooks_record
  else
    say "hermes hooks: not registered; to register them: $HH_LATER"
  fi
fi

# ---- Step 10: final checks (free: no agent session, nothing billed) ----------------
step "10. Final checks"
DB=$(env_get DEFAULT_BACKEND claude)
for c in handoff-launch handoff-orchestrate brief-check; do
  if command -v "$c" >/dev/null 2>&1; then record_ok "$c on PATH"
  else record_bad "$c on PATH" "add this to $RC: $RC_BLOCK_LINE"; fi
done
bin_of() { if command -v "$1" >/dev/null 2>&1; then command -v "$1"; else echo "$HOME/.local/bin/$1"; fi; }
EX_BRIEF=""
for f in "$BRAIN"/02-projects/example/subprojects/example-version-flag/specs/*-brief-1-*; do
  [ -f "$f" ] && { EX_BRIEF=$f; break; }
done
FIX_BY_HAND="re-run ./setup.sh, then run the failing command by hand to read its message"
if [ -n "$EX_BRIEF" ]; then
  if out=$("$(bin_of brief-check)" "$EX_BRIEF" 2>&1); then record_ok "brief-check on the example brief"
  else record_bad "brief-check on the example brief" "$FIX_BY_HAND"; printf '%s\n' "$out" | tail -n 5 | sed 's/^/    /'; fi
  if out=$("$(bin_of handoff-launch)" loop "$EX_BRIEF" --gate auto --backend "$DB" --dry-run 2>&1); then
    record_ok "handoff-launch loop dry-run"
  else record_bad "handoff-launch loop dry-run" "$FIX_BY_HAND"; printf '%s\n' "$out" | tail -n 5 | sed 's/^/    /'; fi
fi

echo
BAD=0
while IFS="$TAB" read -r kind label fix; do
  [ -n "$kind" ] || continue
  if [ "$kind" = ok ]; then echo "ready: $label"
  else echo "NOT READY: $label — fix: $fix"; BAD=1; fi
done <<EOF
$RES
EOF
if [ -n "$EX_BRIEF" ]; then
  echo
  echo "First command to try:"
  echo "  handoff-launch loop $EX_BRIEF --gate auto --backend $DB"
fi
[ "$BAD" = 0 ]

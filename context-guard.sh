#!/bin/sh
# UserPromptSubmit hook: warn when this session's context has grown past a threshold.
#
# Why a warning and not additionalContext: injecting text into the model's context
# on every prompt would itself add tokens, which is the thing this guard exists to
# prevent. systemMessage is UI-only and costs nothing.
#
# Why session_id and not transcript_path: session_id is the documented field of the
# hook payload. The transcript is found from it, so the hook does not depend on an
# undocumented one.
#
# The threshold sits below autoCompactWindow on purpose. A /clear here is free; an
# auto-compaction costs a summary and loses detail. The point is to land the first.

# CONTEXT_GUARD_THRESHOLD comes from brain.env beside this script, read with sed, never
# sourced. Anything but digits takes the default: the arithmetic below needs a number.
# Every path exits 0: a UserPromptSubmit hook that exits 2 blocks and erases the prompt.
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
THRESHOLD=$(sed -n 's/^CONTEXT_GUARD_THRESHOLD=//p' "$here/brain.env" 2>/dev/null | head -1 | tr -d '\r')
case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD=150000 ;;
esac

sid=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$sid" ] || exit 0

transcript=$(ls -t "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -1)
[ -f "$transcript" ] || exit 0

# Last cache_read seen = the context the next turn will re-read and re-pay.
ctx=$(tail -c 400000 "$transcript" \
      | grep -o '"cache_read_input_tokens":[0-9]*' \
      | tail -1 | cut -d: -f2)
[ -n "$ctx" ] || exit 0

state="${TMPDIR:-/tmp}/claude-ctx-guard-$sid"

# Re-arm once the context has actually come back down (a /clear or a compaction).
if [ "$ctx" -lt $((THRESHOLD / 2)) ]; then
  rm -f "$state"
  exit 0
fi

[ "$ctx" -lt "$THRESHOLD" ] && exit 0
[ -f "$state" ] && exit 0
: > "$state"

k=$((ctx / 1000))
printf '{"systemMessage":"Context at %sk. Every turn re-reads this context. If the task at hand is done, /clear now costs nothing; waiting for the auto-compaction at 250k costs a summary and lost detail."}\n' "$k"

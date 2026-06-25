#!/usr/bin/env bash
# Run the external code reviewers (CodeRabbit + Codex) on the current branch vs <base>,
# in parallel, skipping any that aren't available locally. Deterministic glue only —
# the opus review and the fix/dispute judgment live in the review-gate SKILL.
#
# Usage:  run_external_reviewers.sh <base-branch>   (default: master)
# Prints, one per line:  <reviewer>=<ran|error|unavailable>[:<output-file>]
# Output files hold each reviewer's raw findings for the skill to read.

BASE="${1:-master}"
# Unique output dir per invocation so concurrent gates (different repos/worktrees,
# run in parallel) never clobber each other's findings. The caller reads the exact
# paths printed below, so the location is opaque to it.
OUT="$(mktemp -d "${TMPDIR:-/tmp}/review-gate.XXXXXX")"

# Resolve codex-companion.mjs (prefer the newest installed cache, else the marketplace clone).
CODEX="$(ls -1 "$HOME"/.claude/plugins/cache/openai-codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)"
[ -z "$CODEX" ] && CODEX="$(ls -1 "$HOME"/.claude/plugins/marketplaces/openai-codex/plugins/codex/scripts/codex-companion.mjs 2>/dev/null | head -1)"

cr=unavailable
if command -v coderabbit >/dev/null 2>&1; then
  cr=ran
  ( coderabbit review --agent --base "$BASE" >"$OUT/coderabbit.txt" 2>&1; echo $? >"$OUT/coderabbit.rc" ) &
fi

cx=unavailable
if [ -n "$CODEX" ]; then
  cx=ran
  ( node "$CODEX" review --scope branch --base "$BASE" --wait >"$OUT/codex.txt" 2>&1; echo $? >"$OUT/codex.rc" ) &
fi

wait

[ "$cr" = ran ] && { [ "$(cat "$OUT/coderabbit.rc" 2>/dev/null)" = 0 ] || cr=error; }
[ "$cx" = ran ] && { [ "$(cat "$OUT/codex.rc" 2>/dev/null)" = 0 ] || cx=error; }

suffix() { case "$1" in ran|error) printf ':%s' "$2" ;; esac; }
echo "coderabbit=$cr$(suffix "$cr" "$OUT/coderabbit.txt")"
echo "codex=$cx$(suffix "$cx" "$OUT/codex.txt")"

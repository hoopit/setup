#!/usr/bin/env bash
# Claude Code status line for Hoopit.
#
# The script is split into two blocks:
#
#   DATA   — computes every value the status line needs (accurate context usage,
#            session token totals, git facts). Owned by the
#            skill; keep it verbatim. The built-in /statusline agent must NOT
#            touch this block.
#
#   RENDER — turns those values into the displayed string (order, separators,
#            colour, glyphs, truncation). Pure presentation. Safe to regenerate
#            with the built-in /statusline agent to match your shell prompt; it
#            only reads the variables the DATA block exports, never recomputes
#            them.
#
# Contract — variables the DATA block guarantees for RENDER:
#   cwd            absolute current directory (always set)
#   model          model display name                      ("" if absent)
#   effort         reasoning effort level                  ("" if absent)
#   ctx_used       real context tokens of the last request ("" if no transcript)
#   ctx_max        model context-window size               ("" if absent)
#   tok_sent       session cumulative non-cached input     ("" if no transcript)
#   tok_recv       session cumulative output tokens        ("" if no transcript)
#   tok_cache      session cumulative cache-read tokens     ("" if no transcript)
#   git_branch     branch name / short SHA                 ("" if not a repo)
#   git_untracked  1 if untracked files present, else 0
#   git_modified   1 if tracked files modified, else 0
#   git_conflict   1 if merge conflicts present, else 0
#   git_ahead      commits ahead of upstream (0 if none/unknown)
#   git_behind     commits behind upstream  (0 if none/unknown)

input=$(cat)

# ============================================================================
# DATA  — skill-owned. Do not edit when restyling; the built-in /statusline
#         agent must leave this block untouched.
# ============================================================================

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
ctx_max=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Git facts (non-blocking). Booleans are 0/1; counts are integers.
git_branch=""
git_untracked=0
git_modified=0
git_conflict=0
git_ahead=0
git_behind=0
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$git_branch" ]; then
    status_out=$(git -C "$cwd" status --porcelain 2>/dev/null)
    echo "$status_out" | grep -q "^?"   && git_untracked=1
    echo "$status_out" | grep -qP "^.M" && git_modified=1
    echo "$status_out" | grep -q "^U"   && git_conflict=1

    ahead_behind=$(git -C "$cwd" rev-list --count --left-right "@{upstream}...HEAD" 2>/dev/null || echo "")
    if [ -n "$ahead_behind" ]; then
      git_behind=$(echo "$ahead_behind" | awk '{print $1}')
      git_ahead=$(echo "$ahead_behind" | awk '{print $2}')
    fi
  fi
fi

# Real context usage + session token totals, read from the transcript.
# The .context_window field Claude Code passes only counts new (non-cached)
# input tokens, so the displayed value collapses to ~0 once caching kicks in —
# hence we read transcript usage instead:
#   ctx_used  = input + cache_read + cache_creation of the most recent
#               assistant message (the real size of the last request).
#   tok_sent  = session-cumulative non-cached input (input + cache_creation),
#               i.e. what is billed at full/write price.
#   tok_recv  = session-cumulative output tokens.
#   tok_cache = session-cumulative cache reads (billed at ~10%).
# Streaming writes several transcript entries per assistant message (same
# message.id, same usage), so the session sums dedupe by id.
ctx_used=""
tok_sent=""
tok_recv=""
tok_cache=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  ctx_used=$(tac "$transcript" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.usage
        | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null \
    | awk 'NF { print; exit }')

  read -r tok_sent tok_recv tok_cache <<< "$(jq -rs '
    [.[] | select(.type == "assistant" and .message.usage != null)
         | {id: (.message.id // ""), u: .message.usage}]
    | unique_by(.id)
    | map(.u)
    | "\(map((.input_tokens // 0) + (.cache_creation_input_tokens // 0)) | add // 0) \(map(.output_tokens // 0) | add // 0) \(map(.cache_read_input_tokens // 0) | add // 0)"
    ' "$transcript" 2>/dev/null)"
fi

# ============================================================================
# RENDER  — presentation only. Reads the variables above; never recomputes
#           them. Regenerate this block with the built-in /statusline agent to
#           match your shell prompt. Default below is the standard Hoopit look:
#
#             …/Hoopit/api master  Fable 5 [medium] (85k/1M) ↑72k ↓45k ↯2.6M
# ============================================================================

# format_k: integer tokens -> compact "847" / "26k" / "1.2M"
format_k() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "null" ]; then echo ""; return; fi
  if [ "$n" -ge 999500 ]; then
    # Millions: whole number if (near-)exact, else one decimal
    local whole=$(( n / 1000000 ))
    local tenths=$(( (n % 1000000 + 50000) / 100000 ))
    if [ "$tenths" -eq 10 ]; then
      whole=$(( whole + 1 ))
      tenths=0
    fi
    if [ "$tenths" -eq 0 ]; then
      echo "${whole}M"
    else
      echo "${whole}.${tenths}M"
    fi
  elif [ "$n" -ge 1000 ]; then
    echo "$(( (n + 500) / 1000 ))k"
  else
    echo "$n"
  fi
}

# ---------------------------------------------------------------------------
# Glyph set. `use_nerd` is set by the installer (SKILL.md prints a sample and
# asks whether your terminal renders Nerd Font icons, like the powerline setup).
#   1 -> Nerd Font icons     0 -> plain width-1 fallbacks (any Unicode font)
# Codepoints are written \uXXXX so this file stays pure ASCII — the literal git
# glyphs were silently blanked once before; ASCII escapes can't be. Keep every
# glyph single-cell (see the cache note below). Needs bash 4.2+ for \u / \U.
# ---------------------------------------------------------------------------
use_nerd=0
if [ "$use_nerd" = "1" ]; then
  g_branch=$'\ue0a0 '       # U+E0A0 powerline branch, then a space
  g_model=$'\U000f06a9 '    # U+F06A9 robot, then a space
  g_mod=$'\uf040'           # U+F040 pencil  -> modified
  g_conf=$'\uf071'          # U+F071 warning -> conflict
  g_cache=$'\uf0e7'         # U+F0E7 bolt    -> cache reads
else
  g_branch=''
  g_model=''
  g_mod='!'
  g_conf='='
  g_cache='↯'
fi

# Directory: home as ~, then last 2 path segments with a …/ prefix if truncated
dir="${cwd/#$HOME/~}"
IFS='/' read -ra _parts <<< "$dir"
if [ "${#_parts[@]}" -gt 3 ]; then
  dir="…/${_parts[$(( ${#_parts[@]} - 2 ))]}/${_parts[$(( ${#_parts[@]} - 1 ))]}"
fi

# Git segment: optional branch icon, branch name, then status markers
# (untracked ?, modified, conflict, ⇡ ahead, ⇣ behind).
git_part=""
if [ -n "$git_branch" ]; then
  sym=""
  [ "$git_untracked" -eq 1 ] && sym="${sym}?"
  [ "$git_modified" -eq 1 ] && sym="${sym}${g_mod}"
  [ "$git_conflict" -eq 1 ] && sym="${sym}${g_conf}"
  [ "$git_ahead"  -gt 0 ] 2>/dev/null && sym="${sym}⇡${git_ahead}"
  [ "$git_behind" -gt 0 ] 2>/dev/null && sym="${sym}⇣${git_behind}"
  git_part=" ${g_branch}${git_branch}"
  [ -n "$sym" ] && git_part="${git_part} ${sym}"
fi

model_part=""
[ -n "$model" ] && model_part=" ${g_model}$model"

effort_part=""
[ -n "$effort" ] && effort_part=" [$effort]"

ctx_part=""
if [ -n "$ctx_used" ] && [ -n "$ctx_max" ]; then
  ctx_part=" ($(format_k "$ctx_used")/$(format_k "$ctx_max"))"
fi

# Tokens: ↑ sent, ↓ received, ↯ cache reads. Keep these glyphs width-1: a
# double-width glyph like ⚡ (U+26A1) is drawn 2 cells wide by the terminal but
# counted as 1 by the status bar, which desyncs the redraw and leaves stale
# characters behind when a value's length changes. ↯ (U+21AF) is width-1.
tok_part=""
if [ -n "$tok_sent" ] && [ -n "$tok_recv" ]; then
  tok_part=" ↑$(format_k "$tok_sent") ↓$(format_k "$tok_recv")"
  if [ -n "$tok_cache" ] && [ "$tok_cache" -gt 0 ] 2>/dev/null; then
    tok_part="${tok_part} ${g_cache}$(format_k "$tok_cache")"
  fi
fi

out="${dir}${git_part}${model_part}${effort_part}${ctx_part}${tok_part}"
printf '%s' "$out"

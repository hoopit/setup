#!/usr/bin/env bash
# Claude Code status line — mirrors Starship config (directory + git branch + git status)

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')

# Truncate directory: show last 2 path segments, with …/ prefix if truncated
truncate_dir() {
  local dir="$1"
  local home="$HOME"
  # Replace home with ~
  dir="${dir/#$home/~}"
  # Split into parts
  IFS='/' read -ra parts <<< "$dir"
  local count="${#parts[@]}"
  if [ "$count" -le 3 ]; then
    echo "$dir"
  else
    # Show last 2 segments with …/ prefix
    echo "…/${parts[$((count-2))]}/${parts[$((count-1))]}"
  fi
}

dir=$(truncate_dir "$cwd")

# Git info (non-blocking)
git_part=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    # Git status symbols matching Starship config
    status_out=$(git -C "$cwd" status --porcelain 2>/dev/null)
    ahead_behind=$(git -C "$cwd" rev-list --count --left-right "@{upstream}...HEAD" 2>/dev/null || echo "")

    sym=""
    echo "$status_out" | grep -q "^?" && sym="$sym?"
    echo "$status_out" | grep -qP "^.M" && sym="${sym} "
    echo "$status_out" | grep -q "^U" && sym="${sym} "

    if [ -n "$ahead_behind" ]; then
      behind=$(echo "$ahead_behind" | awk '{print $1}')
      ahead=$(echo "$ahead_behind" | awk '{print $2}')
      [ "$ahead" -gt 0 ] 2>/dev/null && sym="${sym}⇡${ahead} "
      [ "$behind" -gt 0 ] 2>/dev/null && sym="${sym}⇣${behind} "
    fi

    git_part=" $branch $sym"
  fi
fi

model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
ctx_max=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

# Real context usage: sum input + cache_read + cache_creation from the most
# recent assistant message in the transcript. The .context_window field that
# Claude Code passes only reports new (non-cached) input tokens, which makes
# the displayed value collapse to ~0 once caching kicks in.
# Also accumulate session totals: sent (non-cached input, i.e. fresh input +
# cache writes), received (output), and cache reads shown separately.
# Streaming can write several transcript entries per assistant message
# (same message.id, same usage), so dedupe by id.
ctx_used=""
tok_sent=""
tok_recv=""
tok_cache=""
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
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

# Format context as e.g. 26k/200k or 1.2M/1M
format_k() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" = "null" ]; then echo ""; return; fi
  if [ "$n" -ge 999500 ]; then
    # Millions: show whole number if exact multiple, else 1 decimal
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

ctx_part=""
if [ -n "$ctx_used" ] && [ -n "$ctx_max" ]; then
  ctx_part=" ($(format_k "$ctx_used")/$(format_k "$ctx_max"))"
fi

tok_part=""
if [ -n "$tok_sent" ] && [ -n "$tok_recv" ]; then
  tok_part=" ↑$(format_k "$tok_sent") ↓$(format_k "$tok_recv")"
  if [ -n "$tok_cache" ] && [ "$tok_cache" -gt 0 ] 2>/dev/null; then
    tok_part="${tok_part} ⚡$(format_k "$tok_cache")"
  fi
fi

model_part=""
[ -n "$model" ] && model_part=" $model"

effort_part=""
[ -n "$effort" ] && effort_part=" [$effort]"

# Time since last request — prompt cache TTL is ~5 min, so past that a new
# message pays full input price again.
age_part=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last_ts=$(tac "$transcript" 2>/dev/null \
    | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null \
    | awk 'NF { print; exit }')
  if [ -n "$last_ts" ]; then
    last_epoch=$(date -d "$last_ts" +%s 2>/dev/null)
    if [ -n "$last_epoch" ]; then
      age=$(( $(date +%s) - last_epoch ))
      if [ "$age" -lt 60 ]; then
        age_fmt="${age}s"
      elif [ "$age" -lt 3600 ]; then
        age_fmt="$(( age / 60 ))m"
      else
        age_fmt="$(( age / 3600 ))h"
      fi
      # ⏱ while the cache is presumably warm, ⏱! once past the ~5 min TTL
      if [ "$age" -ge 300 ]; then
        age_part=" ⏱!${age_fmt}"
      else
        age_part=" ⏱${age_fmt}"
      fi
    fi
  fi
fi

out="${dir}${git_part}${model_part}${effort_part}${ctx_part}${tok_part}${age_part}"
printf '%s' "$out"

---
name: setup-statusline
description: Install the team's custom Claude Code status line (directory, git status, model, effort, exact context usage, session token totals, cache-TTL timer). Use when the user asks to set up, install, or fix the Hoopit status bar / statusline.
---

# Set up the Hoopit Claude Code status line

Installs a status line that shows, in order: truncated cwd, git branch + dirty/ahead/behind symbols, model name, effort level, **exact context usage**, session token totals, and time since the last request:

```
…/Hoopit/api master  Fable 5 [medium] (85k/1M) ↑72k ↓45k ⚡2.6M ⏱14s
```

## Why a custom script

The `context_window` field Claude Code passes to statusline commands only counts **non-cached** input tokens, so it collapses to ~0 once prompt caching kicks in. This script instead reads the session transcript (`transcript_path` in the payload) and derives:

- **Context used** — `input + cache_read + cache_creation` of the most recent assistant message (the real size of the last request).
- **↑ sent** — session-cumulative *non-cached* input (`input + cache_creation`), i.e. what is billed at full/write price.
- **↓ received** — session-cumulative output tokens.
- **⚡ cache** — session-cumulative cache reads (billed at ~10%). Grows very fast during active turns (every API call re-reads the whole context) — values in the millions are normal, not a bug.
- **⏱** — time since the last request. Flips to `⏱!` past 5 minutes, signalling the prompt cache TTL has likely expired and the next message will re-write the cache at full input price.

Streaming writes several transcript entries per assistant message (same `message.id`, same usage), so the sums dedupe by message id.

## Install steps

1. Copy `statusline-command.sh` (in this skill's directory) to `~/.claude/statusline-command.sh` and `chmod +x` it.
2. Merge into `~/.claude/settings.json` (preserve existing keys):

   ```json
   "statusLine": {
     "type": "command",
     "command": "bash /home/<user>/.claude/statusline-command.sh"
   }
   ```

   Use the absolute home path, not `~`.
3. Verify dependencies: `jq`, GNU `tac`, GNU `date -d`, and `grep -P`. The bundled script targets **Linux**; for macOS or Windows apply the adjustments under "OS portability" below.
4. Smoke-test before telling the user it works:

   ```bash
   t=$(ls -t ~/.claude/projects/*/*.jsonl | head -1)
   echo "{\"workspace\":{\"current_dir\":\"$PWD\"},\"transcript_path\":\"$t\",\"context_window\":{\"context_window_size\":200000},\"model\":{\"display_name\":\"Test\"},\"effort\":{\"level\":\"medium\"}}" \
     | bash ~/.claude/statusline-command.sh
   ```

   Expect a single line ending with the `(used/max) ↑… ↓… ⚡… ⏱…` segments.
5. The status line appears on the next render — no restart needed if the session was launched after `settings.json` already had a `statusLine` entry; otherwise restart Claude Code.
6. **Final output (required).** After the install steps succeed, end your turn by printing the explanation block below verbatim — this is the only thing the user sees that tells them what each new segment in their status bar means, so do not skip it, summarize it, or fold it into other text. Print it after any other completion notes.

   ```
   Status line segments (left to right):
   - …/parent/dir — current working directory, truncated to the last two path segments (home shown as ~).
   -   branch — current git branch. Followed by status glyphs:
       ? untracked,   modified,   merge conflict, ⇡N ahead of upstream, ⇣N behind upstream.
   -  Model — the active Claude model's display name (e.g. Fable 5, Opus 4.8).
   - [effort] — reasoning effort level (low / medium / high / max).
   - (used/max) — real context usage of the last request: input + cache reads + cache writes,
     vs. the model's context window. Unlike Claude Code's built-in counter, this stays accurate
     after prompt caching kicks in.
   - ↑sent — session-cumulative non-cached input tokens (fresh input + cache writes).
     This is what you're billed at full/write price.
   - ↓recv — session-cumulative output tokens.
   - ⚡cache — session-cumulative cache reads (billed at ~10%). Grows fast during active turns
     because every API call re-reads the whole cached context; millions are normal.
   - ⏱age — time since the last request. Flips to ⏱! past 5 minutes, signalling the prompt
     cache TTL has likely expired and the next message will re-write the cache at full price.
   ```

## OS portability

The script in this directory is written for **Linux** (GNU coreutils) — keep it that way. When installing on another OS, adjust the *installed copy* (`~/.claude/statusline-command.sh`), not the version in this skill.

### macOS

BSD userland lacks several GNU tools the script uses:

- `tac` — install `coreutils` (`brew install coreutils`) and substitute `gtac`, or replace `tac "$file"` with `tail -r "$file"`.
- `date -d "$ts" +%s` — substitute `gdate -d` (coreutils), or use BSD syntax: `date -j -f '%Y-%m-%dT%H:%M:%S' "${last_ts%%.*}" +%s`.
- `grep -qP` — BSD grep has no `-P`; the pattern (`^.M`) doesn't need PCRE, so change it to `grep -qE`.
- macOS ships bash 3.2; the script avoids 4+ features, so no change needed there. `jq` still needs installing (`brew install jq`).

### Windows

Claude Code on native Windows can't run a bash script directly. Two options:

- **Git Bash** (simplest): point the statusLine command at Git's bash with a Windows path, e.g.
  `"command": "C:\\Program Files\\Git\\bin\\bash.exe C:\\Users\\<user>\\.claude\\statusline-command.sh"`.
  Git Bash bundles GNU coreutils (`tac`, `date -d`) and grep with `-P`, but **not `jq`** — install it (e.g. `winget install jqlang.jq`) and make sure it's on PATH for non-interactive shells. The `transcript_path` in the payload is a Windows path (`C:\Users\...`); Git Bash usually handles it in `[ -f ... ]` and `jq` args as-is, but if not, convert it with `cygpath -u` right after extracting it.
- **WSL**: works unchanged (it's Linux), but only if Claude Code itself runs inside WSL. A native-Windows Claude Code calling into WSL bash will hand over Windows transcript paths that need `wslpath -u` conversion and adds noticeable per-render latency — prefer Git Bash for native installs.

In both cases the home-directory tilde shortening (`${dir/#$home/~}`) and the `…/` path truncation work on the POSIX-style paths bash sees; expect the directory segment to show a `/c/Users/...`-style prefix on Windows unless converted.

## Caveats

- **Never edit `~/.claude/statusline-command.sh` in place during a live session.** The status bar re-runs it every few seconds and will execute a half-written file, flashing garbage values. Build the new version in a temp file and `mv` it into place atomically.
- **Claude Code itself briefly paints low token values** right after a message is submitted from an idle state, before the next script render lands. This is harness-side (verified by logging every render — script output was always correct), self-corrects within seconds, and cannot be fixed in the script.
- The git status symbols include Nerd Font glyphs (` `, ` `). If the user's terminal font lacks them, substitute plain characters like `!` and `=`.
- The numbers measure different things and are **not** expected to satisfy `context = ↑ + ↓`. The useful invariant is roughly `context ≈ ↑ + prefix cached by an earlier session` (system prompt and project context are often cache-shared across sessions, so the first call reads tokens this session never paid to write).

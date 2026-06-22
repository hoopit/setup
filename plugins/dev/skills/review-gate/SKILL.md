---
name: review-gate
description: Run multiple independent code reviewers (opus + CodeRabbit + Codex) on the committed branch changes before a PR, aggregate and de-dup findings, fix what is valid, and BLOCK the PR (with notes) on any disputed Critical/High finding. Use right before opening a PR; handle-jira-issue Step 7 calls it. CodeRabbit/Codex are skipped if not installed locally; the opus review always runs.
---

# Review Gate

Runs up to three **independent** reviewers on the current branch's changes vs the repo's default
branch, then gates PR creation. The opus review always runs; **CodeRabbit and Codex run only if
available locally** (skipped, not failed, when absent). Diversity is the point — CodeRabbit and Codex
are separate engines; the opus pass runs as a **fresh independent subagent when the runner can spawn
one** (genuinely independent eyes), and falls back to inline self-review when it can't (e.g. when the
gate is itself running inside a subagent).

## Contract

Call after the fix is committed on the branch, **before** push/PR. Return exactly one verdict:

- **`PASS`** — every *valid* finding is fixed; anything left is Low/Medium that you deliberately
  skipped with a one-line justification. Caller opens the PR and pastes the gate notes into it.
- **`BLOCK: <reason>`** — there is a **disputed Critical/High** finding (you judge it invalid/not worth
  fixing), or a valid Critical/High that isn't safe to fix here. You may **not** unilaterally dismiss a
  Critical/High. Caller must NOT open the PR — surface the blocking findings; in an unattended loop the
  caller takes its escape hatch (Jira comment + transition to **Escalated** + return `BLOCKED`).

## Steps

1. **Base branch.** Resolve `$DEFAULT_BRANCH` from the repo's CLAUDE.md *Workflow skills config*
   (e.g. `master`). Run from inside the worktree being reviewed.
2. **External reviewers (parallel, skip-if-unavailable).** Run the bundled script:
   ```bash
   bash "$(find ~/.claude/plugins -path '*review-gate/scripts/run_external_reviewers.sh' | head -1)" "$DEFAULT_BRANCH"
   ```
   It prints `coderabbit=<ran|error|unavailable>[:file]` and `codex=<…>`. Read each `:file` for that
   reviewer's findings. Treat `error`/`unavailable` as **skipped** — note it, never fail the gate on it.
3. **Opus review (always).** Prefer an *independent* reviewer over grading your own work:
   - **If the subagent-spawning tool (Agent/Task) is available to you** — i.e. you're running as a
     primary agent, not yourself a subagent — spawn a fresh `general-purpose` opus subagent to review
     the change **cold**: give it only the repo path and `git diff "$DEFAULT_BRANCH"...HEAD` (withhold
     your implementation reasoning and the triage hypothesis). It returns findings + severities; *you*
     do any fixing in step 5.
   - **If that tool is NOT available** (you are a subagent — e.g. the auto-fix implementer), review the
     diff yourself inline instead.
   Either way look for: correctness/logic bugs, security, data-integrity/regressions, missed edge cases,
   and repo conventions (read the relevant `$REPO/.claude/skills/*` for the area you touched). Emit
   findings with a severity each (Critical / High / Medium / Low). Note in the PR which mode was used
   (independent reviewer vs self-review).
4. **Aggregate + de-dup.** Merge findings from every reviewer that ran; collapse duplicates (same
   location + same issue → one finding, keep the highest severity and note which reviewers raised it).
5. **Triage each finding (judgment on all):**
   - **Valid → fix it.** Commit each fix separately (convention below). After fixing, re-run the
     affected reviewer(s); loop until no new *valid* Critical/High remains.
   - **Invalid Low/Medium → skip**, recording a one-line reason (collected for the PR).
   - **Invalid (disputed) Critical/High → `BLOCK`.** Record the finding + your reasoning. Do not skip it.
   - **Valid but unsafe / too large to fix in this change → `BLOCK`** with that reason.
6. **Return the verdict:**
   - `PASS` + a notes block for the PR: which reviewers ran (and which were skipped/unavailable),
     findings fixed, findings skipped (with reasons).
   - `BLOCK: <one-line reason>` + the blocking findings and your reasoning.

## Fix commit convention

One commit per fix, **no Jira key** in the message (review fixes aren't tied to a ticket):

```
<short imperative subject>

Reviewer finding (<reviewer> · <severity>):
<the finding as reported>

Solution:
<what was changed and why>
```

## Notes

- If only the opus review ran (CodeRabbit + Codex both unavailable), say so explicitly in the PR notes
  so the human knows review coverage was reduced.
- `coderabbit`/`codex` may be slow (minutes) and need their own auth (`coderabbit auth`, codex setup);
  an auth/`error` result is treated as a skipped reviewer, not a gate failure.
- The script invokes `coderabbit review --agent` (structured NDJSON findings). The older `--prompt-only`
  flag was removed from the CodeRabbit CLI — on a CLI that predates `--agent`, CodeRabbit will `error`
  (silently dropping to opus-only coverage). Keep the CLI current (`coderabbit --version`).

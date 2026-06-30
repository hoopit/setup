---
name: review-gate
description: Run multiple independent code reviewers (the matt-picks two-axis /review + CodeRabbit + Codex) on the committed branch changes before a PR, aggregate and de-dup findings, fix what is valid, and BLOCK the PR (with notes) on any disputed Critical/High finding. Use right before opening a PR; handle-jira-issue Step 7 calls it. CodeRabbit/Codex are skipped if not installed locally; an independent review always runs (matt-picks /review, else a cold subagent, else inline self-review).
---

# Review Gate

Runs up to three **independent** reviewers on the current branch's changes vs the repo's default
branch, then gates PR creation. An independent review always runs; **CodeRabbit and Codex run only if
available locally** (skipped, not failed, when absent). Diversity is the point — CodeRabbit and Codex
are separate engines, and the always-on review prefers the **matt-picks `mattpocock-skills:review`
skill** (a two-axis Standards + Spec reviewer that spawns its own cold sub-agents — genuinely
independent eyes). If that skill isn't installed it falls back to a fresh independent subagent, and to
inline self-review only when no subagent tool is available.

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
3. **Independent review (always).** Prefer a cold, independent reviewer over grading your own work:
   - **Preferred — invoke the `mattpocock-skills:review` skill** (the matt-picks two-axis reviewer;
     use the namespaced name so it isn't confused with the built-in `/review`, which reviews an
     existing GitHub PR). Give it **`$DEFAULT_BRANCH` as the fixed point** — it runs
     `git diff "$DEFAULT_BRANCH"...HEAD`, spawns its own parallel **Standards** and **Spec** sub-agents
     (cold and independent by construction — don't hand it your implementation reasoning or the triage
     hypothesis), and returns `## Standards` + `## Spec` findings. If you have the originating Jira
     issue / PRD (e.g. handle-jira-issue passes it through), give it to the skill as the spec argument
     so the **Spec** axis runs; otherwise that axis self-skips.
   - **Fallback — if that skill isn't installed** (e.g. only `hoopit-dev`, not `hoopit-matt-picks`):
     if the Agent/Task tool is available, spawn a fresh `general-purpose` subagent to review the change
     **cold** — give it only the repo path and `git diff "$DEFAULT_BRANCH"...HEAD`; otherwise review
     the diff yourself inline. For this fallback look for: correctness/logic bugs, security,
     data-integrity/regressions, missed edge cases, and repo conventions (read the relevant
     `$REPO/.claude/skills/*` for the area you touched).
   Note in the PR which mode ran (`mattpocock-skills:review` · independent subagent · self-review).
   `mattpocock-skills:review` findings aren't pre-labelled by severity — assign each a severity when you
   triage (step 5): a missing/incorrect spec requirement, or any correctness/security/data-integrity
   issue, is usually Critical/High; baseline code-smells and style nits are Medium/Low.
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

- If only the always-on review ran (CodeRabbit + Codex both unavailable), say so explicitly in the PR
  notes so the human knows review coverage was reduced — `mattpocock-skills:review` covers standards +
  spec, so bug/security depth leans on CodeRabbit/Codex when they run.
- `mattpocock-skills:review` ships via the **`hoopit-matt-picks`** plugin (a curated pick of
  `mattpocock/skills`). If that plugin isn't installed the gate uses the cold-subagent fallback above —
  equivalent independence, but you lose the structured two-axis split.
- `coderabbit`/`codex` may be slow (minutes) and need their own auth (`coderabbit auth`, codex setup);
  an auth/`error` result is treated as a skipped reviewer, not a gate failure.
- The script invokes `coderabbit review --agent` (structured NDJSON findings). The older `--prompt-only`
  flag was removed from the CodeRabbit CLI — on a CLI that predates `--agent`, CodeRabbit will `error`
  (silently dropping coverage to the always-on review only). Keep the CLI current (`coderabbit --version`).

---
name: auto-fix-next-bug
description: Pick the next open, unassigned, agent-ready bug from the current repo's Jira project and fix it end-to-end (branch → fix → tests → multi-reviewer gate → PR) via a dedicated opus implementer agent. Reports the PR link plus any Critical/High review items and key decisions. Processes EXACTLY ONE bug per run; drive the 30-minute cadence with /loop. Use when the user wants to auto-burn-down agent-ready bugs unattended.
---

# Auto-fix the next open bug

Each run of this skill processes **exactly one** open bug. The repeat /
"wait 30 minutes" cadence is owned by `/loop`, not by this skill — see
*Driving it with /loop* at the bottom. Designed to run **unattended (AFK)**, so
it must never hang waiting for human input.

Selection is purely mechanical (no judgment), so the orchestrator does it by running a
small **selector script** — zero LLM tokens, deterministic, and it prints one line so
the loop's context stays flat. The only sub-agent is the **opus implementer** that runs
the `handle-jira-issue` skill on the claimed bug.

## Config (read from this repo's CLAUDE.md → "Workflow skills config")

This skill is **project-agnostic** — it auto-fixes bugs in whatever Hoopit repo it
is invoked in. Read every **per-project** value from the current repo's `CLAUDE.md`
(`## Agent skills` → `### Workflow skills config`); never hardcode it:

- **Jira project key** (e.g. `BAC` for api, `WEB` for web-admin, `FA` for flutter-app)
  — the project the selector pulls bugs from.
- **GitHub repo** and **Default branch** — consumed by the implementer (`handle-jira-issue`).

`JIRA_BASE_URL` (`https://hoopit.atlassian.net`) is Hoopit-wide and the same in every
repo. If any **per-project** value is missing from CLAUDE.md, **stop and ask** — don't guess.

## Eligibility gate

A bug is only picked up when its **`AI: Agent suitability`** custom field is set to
**`agent-ready`** (plus open + unassigned). This is the human triage signal that a
bug is safe to hand to an agent — the loop never touches anything not explicitly
marked. The field is newly adopted, so if a run finds nothing, that usually just
means no open bug is marked `agent-ready` yet — it is **not** a bug in the skill.

## State / dedup

A local, gitignored dispatch log records every bug already claimed:

```
.claude/local/auto-fix-next-bug/dispatched.log
```

Format, one line per claim: `<KEY>\t<ISO-8601 UTC>\t<status>` where status is
`dispatched`, `pr=<url>`, or `blocked:<reason>`. This is the backstop; the
primary dedup is the Jira status transition (a claimed bug leaves `status = Open`).

## Step 1 — Select & claim the next bug (deterministic script)

Selection has no judgment in it, so the orchestrator runs it as a script — no LLM
tokens, deterministic, testable, and it prints a single line so the loop's context
stays flat. Pass the repo's Jira project key (from CLAUDE.md) via `--project`. The
script path is relative to this skill; run it from inside the target repo (it finds
the repo root via git):

```bash
python3 scripts/select_next_bug.py --project "<JIRA_PROJECT_KEY>"
```

The script reads the dispatch log, runs the eligibility JQL (`project = <KEY> AND
type = Bug AND status = Open AND assignee IS EMPTY AND "AI: Agent Suitability" =
"Agent-ready"`, ordered by `AI: Priority Score` DESC then `created ASC`), picks the
first candidate that isn't already dispatched, branched (`<KEY>/*`), or has an open
PR, transitions it to **In Progress**, appends a `dispatched` line to the log, and
prints exactly one line. (`--project` is **required** — read it from CLAUDE.md;
`--dry-run` shows the pick without claiming — use it to verify, never in the loop.)

Parse that single stdout line:

- `NONE` → report *"No eligible open bugs right now; will re-check next
  iteration."* and **end the run** (the loop re-checks later).
- `ERROR: <reason>` → report it and **end the run** (usually stale `acli` auth;
  the loop retries next iteration).
- `KEY=<KEY> | SUMMARY=… | PRIORITY=…` → extract `<KEY>` (e.g. `BAC-7243`) and
  continue to Step 2.

## Step 2 — Implement the fix (opus sub-agent)

Spawn **one** sub-agent and wait for it:

- `subagent_type`: `general-purpose`
- `model`: `opus`  (the only opus tier selectable; resolves to the current Opus — 4.8)
- `mode`: `bypassPermissions`  (must push + open a PR with no prompts)
- `description`: `fix <KEY>`

Prompt (substitute `<KEY>`):

> Think hard and be thorough. You are an autonomous implementer running unattended
> — never pause to ask the user a question; if you would normally ask, take the
> safest sensible default or abort per the escape hatch below.
>
> Use the `handle-jira-issue` skill to fix `<KEY>` end-to-end: it is a
> project-originated bug, so branch → implement the minimal fix → add a
> regression test → review gate (its Step 7 runs `review-gate`: opus + CodeRabbit +
> Codex) → push → **open a normal PR**. Follow that skill exactly, including its
> worktree, testing, and PR-link conventions.
>
> VERIFY THE TRIAGE — DO NOT TRUST IT. Everything attached to this issue by triage
> is an unverified hypothesis, possibly wrong: the description, the suspected root
> cause, the reproduction steps, any "affected file/component" pointers, and the
> AI-generated fields (`AI: Priority score`, `AI: Agent suitability`). Before you
> change any code, independently confirm from the actual codebase and behaviour:
> (1) the bug is real and reproducible, (2) the true root cause — derive it
> yourself from the code; do not copy the triage's guess, and (3) the fix actually
> addresses that root cause (prove it with the regression test failing before /
> passing after). If your investigation contradicts the triage — it's not a bug,
> the root cause is different, it's already fixed, or it's not safe to auto-fix —
> do NOT force the triage's version. Either fix the *real* problem you found
> (noting the discrepancy in the PR), or take the escape hatch below.
>
> ESCAPE HATCH — if the bug cannot be understood, reproduced, or safely fixed from
> the available information (this includes the case where your verification
> contradicts the triage), DO NOT hang and DO NOT open a low-confidence PR.
> Instead, do all of:
>   1. Add a Jira comment on `<KEY>` explaining what's blocking an automated fix,
>      what you found, and what a human needs to provide:
>      `acli jira workitem comment create --key <KEY> --comment "..."`
>   2. Transition the issue to **Escalated**:
>      `acli jira workitem transition --key <KEY> --status "Escalated" --yes`
>      If that transition isn't available from the issue's current status, don't
>      fail the run — just note in the comment that auto-escalation couldn't be
>      applied so a human can move it manually.
>   3. Stop and return the `RESULT: BLOCKED` block (below).
>
> FINAL OUTPUT — return a compact block at the very end; the orchestrator prints it,
> so use one short line per item and no prose. On success:
> ```
> RESULT: PR
> PR: <pr-url>
> REVIEW: <"none", or e.g. "2 Critical/High to consider">
> - <Critical|High> · <reviewer>: <short finding> — <fixed | LEFT FOR HUMAN: why>
> DECISIONS:
> - <notable choice / triage discrepancy / assumption / deliberately-skipped Med-Low finding + why>
> ```
> Under REVIEW list ONLY Critical/High items a human should still eye — the review
> gate already fixed valid ones and blocks on disputed ones, so this is usually
> `none`; include an item only when something high-severity was left for a human
> (with why). Under DECISIONS surface what a reviewer would want to know: a deviation
> from the triage's root cause, a non-obvious approach choice, an assumption, or a
> Medium/Low finding you skipped. If you escalated instead of opening a PR:
> ```
> RESULT: BLOCKED
> BLOCKED: <one-line reason>
> REVIEW: <the disputed Critical/High finding(s) that blocked the PR, or "none">
> DECISIONS:
> - <what you tried / why it couldn't be safely auto-fixed>
> ```

## Step 3 — Record the outcome & report

Read the implementer's final block (`RESULT: PR` or `RESULT: BLOCKED`) and append a
status line to the dispatch log for `<KEY>`:

- success → `<KEY>\t<UTC ISO-8601>\tpr=<url>`
- blocked → `<KEY>\t<UTC ISO-8601>\tblocked:<reason>`

Then print a compact report to the user — lead with the PR link, and surface the
review highlights and decisions so they aren't missed:

```
<KEY> (<priority>) — <one-line summary>
PR: <url>                         ← or "BLOCKED — <reason> (escalated to Escalated)"
Review to consider: <the Critical/High items from REVIEW, or "none">
Key decisions: <the DECISIONS bullets, or "none">
```

Keep every line short (one finding/decision per line, no prose) — this output is
re-read by the loop each iteration, so verbosity compounds. The PR link and any
Critical/High review items are the parts worth a glance; everything else stays terse.

This is the end of one run. Do not loop here.

## Driving it with /loop

This skill does one bug; `/loop` does the repeating and the spacing:

```
/loop 30m /auto-fix-next-bug
```

Each iteration blocks until the implementer finishes, so bugs are handled strictly
one at a time, with ~30 minutes between iterations. To stop, end the loop.

### Requirements for unattended operation

- **Run the loop in a session that allows unattended actions** (start Claude Code
  with permissions to bypass prompts), so the `bypassPermissions` sub-agents can
  push branches and open PRs without stopping. In a normal/supervised session the
  loop will pause on every outward action and is not AFK.
- **Keep auth fresh for the whole run:** `acli auth status`, `gh auth status`, and
  a valid `aws login` session (the worktree/test setup may need AWS). If a session
  expires mid-loop, iterations will fail until you re-auth.
- Each fix creates a worktree under `.worktrees/`. Prune merged ones periodically
  (`git worktree prune` + delete merged branches).
- New skills register at session start — after creating/editing this skill,
  restart Claude Code (or reload) so `/auto-fix-next-bug` is invocable.

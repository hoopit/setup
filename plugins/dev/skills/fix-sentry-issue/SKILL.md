---
name: fix-sentry-issue
description: Fix a Sentry issue end-to-end — fetch details, create or link a Jira ticket (with a native bidirectional Sentry↔Jira link), branch, fix, test, review, and open a PR. Use then the user links to a sentry issue.
---

# Fix Sentry Issue Workflow

Triggered when the user says something like "fix this sentry issue" and provides a Sentry URL or issue ID (e.g. `BAC-QCB` or `https://hoopit.sentry.io/issues/...`).

## Configuration — read from CLAUDE.md, never hardcode

This skill is project-agnostic. Run it from inside the affected repo, then read
its **`## Agent skills` → `### Workflow skills config`** block in `CLAUDE.md` and
use those values throughout — **do not hardcode or guess them**. If a value you
need is missing (or marked TODO), **stop and ask the user to add it** to CLAUDE.md.

- `JIRA_PROJECT` — the repo's **Jira project key** (e.g. `BAC`).
- `JIRA_BASE_URL` — the **Jira base URL** (e.g. `https://hoopit.atlassian.net`).
- `SENTRY_ORG` — the **Sentry org** (e.g. `hoopit`).
- `SENTRY_PROJECT` — the **Sentry project** slug.
- `DEFAULT_BRANCH` — the repo's **default branch** (e.g. `master`).
- `SENTRY_JIRA_INTEGRATION_ID` — the numeric id of the Sentry↔Jira integration, used to create the native two-way issue link (e.g. `12493`). If it's missing from CLAUDE.md, derive it once with the command in Step 2c and add it.

Wherever the steps below show `BAC`, `hoopit`, `https://hoopit.atlassian.net`, or
`master`, substitute `$JIRA_PROJECT`, `$SENTRY_ORG`, `$JIRA_BASE_URL`, and
`$DEFAULT_BRANCH`. Resolve the repo from where you are invoked (cwd) and its
CLAUDE.md — not from the Sentry ID prefix.

> **PR/Jira link hygiene:** when naming the branch, writing commit messages, or
> authoring the PR, load the `create-pull-request` skill and follow it. For this
> workflow the only work item the PR may link is `JIRA_KEY`; the Sentry short ID
> (e.g. `BAC-QCB`) is safe (no digits after the dash). Keep every other Jira key
> out of those surfaces.

## Step 1 — Fetch Sentry issue details

Load the `sentry-cli` skill for full guidance on the `sentry` CLI before running any commands.

Use the `sentry` CLI to get full issue details. If a full Sentry URL is provided, extract the short issue ID from it (e.g. `BAC-QCB` from `https://hoopit.sentry.io/issues/BAC-QCB/...`).

```bash
sentry issue view <SENTRY_ID> --json
```

If the CLI cannot auto-detect the org, prefix the issue ID with the org slug (`$SENTRY_ORG` from CLAUDE.md):

```bash
sentry issue view $SENTRY_ORG/<SENTRY_ID> --json
```

For a recent event with stacktrace and request context, also fetch one event:

```bash
sentry issue events <SENTRY_ID> --limit 1 --json
sentry event view <EVENT_ID> --json   # if more detail is needed
```

Optionally, get an AI root-cause analysis to seed the fix:

```bash
sentry issue explain <SENTRY_ID>
```

Extract and note:
- **Sentry Issue ID** (e.g. `BAC-QCB`) — used in commit message
- **Numeric Sentry group ID** — the `id` field in the JSON (e.g. `7271613592`); required for the native Jira link in Step 2c. This is **not** the short ID.
- **Error type and message**
- **Most relevant stack frame** — file, line number
- **Full stacktrace**
- **HTTP request context** (method, URL, payload)
- **Occurrence count and user impact**

If the issue cannot be understood or reproduced from the available information, stop and ask the user for clarification.

## Step 2 — Identify or create a Jira issue

### 2a — Check for an existing linked Jira issue

> **Note:** The `sentry` CLI does **not** expose Jira-linked issues — even if a Jira link is visible in the Sentry UI, it won't appear in `sentry issue view` output. Instead, search Jira directly using the Sentry issue ID as a text match (it will appear in issue descriptions or comments that were linked via the workflow):

```bash
acli jira workitem search \
  --jql "project = $JIRA_PROJECT AND text ~ \"<SENTRY_ID>\" ORDER BY created DESC" \
  --limit 5 \
  --fields 'key,summary,status'
```

If that returns nothing, also try a summary keyword search:

```bash
acli jira workitem search \
  --jql "project = $JIRA_PROJECT AND summary ~ \"<short error description>\" AND resolution = Unresolved ORDER BY created DESC" \
  --limit 5 \
  --fields 'key,summary,status'
```

If a matching unresolved issue already exists, use it — note its key (e.g. `BAC-6932`).

### 2b — Create a new Jira issue if none exists

The issue type must be **Bug**.

```bash
acli jira workitem create \
  --project "$JIRA_PROJECT" \
  --type Bug \
  --summary '<concise bug title>' \
  --description '## Summary
<1-2 sentence description of the bug>

## Root cause
<technical explanation>

## References
- Sentry: [<SENTRY_ID>](<SENTRY_URL>)
- First seen: <date>, Occurrences: <N>, Users impacted: <N>'
```

Note the new Jira issue key printed by the command (e.g. `BAC-6934`).

### 2c — Create the bidirectional Sentry↔Jira link

Create the **native** two-way integration link — the same one as the Sentry UI's "Link Jira Issue", not a
plain text reference. With Sentry's Jira integration `issue-sync` enabled this is bidirectional: the Sentry
issue shows the linked Jira issue and the Jira issue shows the Sentry one, and status/assignee sync across.
Use the **numeric group ID** from Step 1 (not the short ID) and `SENTRY_JIRA_INTEGRATION_ID` from CLAUDE.md:

```bash
sentry api groups/<NUMERIC_ID>/integrations/$SENTRY_JIRA_INTEGRATION_ID/ -X PUT -d '{"externalIssue":"<JIRA_KEY>"}'
```

The response echoes the linked issue (key + url) on success. (Preview the resolved request without sending
it with `-n`/`--dry-run`.) This works the same whether `<JIRA_KEY>` was just created (2b) or an existing
issue found in 2a.

If `SENTRY_JIRA_INTEGRATION_ID` is not yet in CLAUDE.md, derive it once (then add it to the config block):

```bash
sentry api "organizations/$SENTRY_ORG/integrations/?provider_key=jira"   # use the integration "id" field
```

**Fallback:** a plain text reference does **not** create the native link — only the `groups/.../integrations/...`
PUT does. If that call fails (wrong integration id, missing scope, etc.), don't lose the trail — add a
cross-reference comment instead and tell the user the native link degraded:

```bash
acli jira workitem comment create \
  --key '<JIRA_KEY>' \
  --body '🔗 **Sentry Issue:** [<SENTRY_ID>](<SENTRY_URL>)

- **Occurrences:** N
- **Users impacted:** N'
```

## Step 3 — Create a Git branch as a worktree

Defer to the repo's own worktree conventions:

1. If `.claude/skills/create-worktree/SKILL.md` exists in this repo, read and follow it (it covers any per-repo venv/`.envrc`, isolated test DB, or `.envs` caveats).
2. Otherwise create a plain worktree off the repo's default branch:

   ```bash
   git fetch origin
   BRANCH="<JIRA_KEY>/bug/<short-description>"
   git worktree add -b "$BRANCH" ".worktrees/$(echo "$BRANCH" | tr '/' '-')" "origin/$DEFAULT_BRANCH"
   ```

Branch naming convention: `<JIRA_KEY>/bug/<short-kebab-description>`

Examples:
- `BAC-6934/bug/dintero-payment-data-double-serialized`
- `BAC-123/bug/invalid-access-token`

The worktree lands at `.worktrees/<branch-name>` with `/` in the branch name replaced by `-` for the directory name, e.g. `.worktrees/BAC-6934-bug-dintero-payment-data-double-serialized`. Note this path as `$WORKTREE_DIR`.

All subsequent steps (4–9) run from `$WORKTREE_DIR` unless stated otherwise.

## Step 4 — Implement the fix

- Navigate to the relevant file(s) in `$WORKTREE_DIR` identified in the Sentry stacktrace.
- Apply the minimal, targeted fix.
- Follow existing code conventions. Read any relevant skills in this repo's `.claude/skills/` that apply to the area you're touching (e.g. `models`, `views`, `urls`, `migrations` in the api repo; the web-admin and flutter-app repos have their own). Skip skills that don't exist.
- Do **not** refactor unrelated code.

## Step 5 — Write tests

Defer to the repo's testing conventions: if `.claude/skills/writing-tests/SKILL.md` exists, read and follow it before writing tests; if `.claude/skills/running-tests/SKILL.md` exists, use it to run them.

- Write at least **1 test** that reproduces the bug and verifies the fix.
- Place the test alongside the code being fixed, following the surrounding test layout.
- Include a docstring/comment referencing the Jira issue, e.g.:

```python
def test_payment_data_not_double_serialized(self):
    """
    Regression test for BAC-6934.
    payment_data must be passed as a dict, not a JSON string,
    when calling the Dintero Google Pay endpoint.
    """
    ...
```

Run the new test (and related tests) to confirm they pass, using the repo's test runner (per its `running-tests` skill). If the repo provides no realistic way to add an automated regression test for this kind of bug, say so explicitly in the PR description instead of skipping silently.

If tests fail, fix the issues before proceeding.

## Step 6 — Commit changes

Stage and commit all changes from within the worktree:

```bash
cd "$WORKTREE_DIR"
git add -A
git commit -m "<JIRA_KEY>: <short description>

<Optional longer description of what was changed and why.>

Fixes <SENTRY_ID>"
```

Example:
```
BAC-6934: Fix double-serialization of payment_data in Dintero Google/Apple Pay

payment_data was being passed through json.dumps() before being added
to the request dict. Since _request() already uses json=data, this
resulted in Dintero receiving a JSON string instead of a JSON object.

Fixes BAC-QCB
```

## Step 7 — Review gate (independent review + CodeRabbit + Codex)

From inside the worktree, run the **`review-gate`** skill. It runs three independent reviewers — an
independent review always (the matt-picks `mattpocock-skills:review` skill, else a cold subagent /
self-review), plus CodeRabbit and Codex when installed locally — against `$DEFAULT_BRANCH`,
aggregates + de-dups their findings, fixes the valid ones (committing each per its own convention),
tracks the skipped ones, and returns a verdict:

- **`PASS`** → keep the gate's notes block (which reviewers ran, findings fixed, findings
  skipped-with-reason) for the PR body, and continue to **Step 8**.
- **`BLOCK: <reason>`** → there is a *disputed* Critical/High finding (or a valid one that isn't safe
  to fix in this change). **Do not push and do not open a PR.** Surface the blocking findings. When
  running unattended, take the escape hatch instead: add a comment on the Jira issue (Step 2) with the
  blocking findings, transition it to **Escalated**, and stop — never open a low-confidence PR.

The gate owns the fix-commit convention and the skipped-findings list, so they live there, not here.

## Step 8 — Push the branch

Push the normal way — see the *Pushing from a worktree* section of the `create-worktree` skill for why no workaround is needed (the pre-push hooks resolve the main repo's `.venv` themselves):

```bash
cd "$WORKTREE_DIR"
git push -u origin <branch-name>
```

## Step 9 — Create a Pull Request

Follow the **`create-pull-request`** skill for the `gh pr create` recipe, the
required-labels-at-creation rule, and Jira-link hygiene. This workflow's body
adds a `## Sentry` section and the review-gate notes block from Step 7:

```
## Summary
<description of the fix>

## Jira
[<JIRA_KEY>]($JIRA_BASE_URL/browse/<JIRA_KEY>)

## Sentry
[<SENTRY_ID>](<SENTRY_URL>)

## Changes
- <bullet point summary of changes>

## Testing
- <describe the test(s) added>

## Code review (review-gate)
Reviewers run: <independent review (mattpocock-skills:review / subagent / self-review), CodeRabbit, Codex — note any skipped as unavailable/error>

### Findings addressed
- <reviewer> · <severity>: <finding> — <what was done>

### Findings not addressed
- <reviewer> · <severity>: <finding> — <reason for skipping>
```

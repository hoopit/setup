---
name: fix-sentry-issue
description: Fix a Sentry issue end-to-end — fetch details, create or link a Jira ticket, branch, fix, test, review, and open a PR. Use then the user links to a sentry issue.
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

Wherever the steps below show `BAC`, `hoopit`, `https://hoopit.atlassian.net`, or
`master`, substitute `$JIRA_PROJECT`, `$SENTRY_ORG`, `$JIRA_BASE_URL`, and
`$DEFAULT_BRANCH`. Resolve the repo from where you are invoked (cwd) and its
CLAUDE.md — not from the Sentry ID prefix.

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

### 2c — Add a comment linking back to Sentry

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

## Step 7 — Code review with CodeRabbit

Read this repo's `.claude/skills/code-review/SKILL.md` and follow its instructions.

Run a review against the repo's default branch from the worktree:

```bash
cd "$WORKTREE_DIR"
coderabbit review --prompt-only --base "$DEFAULT_BRANCH"
```

Group findings by severity (Critical → Warning → Info). For each finding, decide whether to fix or skip it:

- Fix all **Critical** and **Warning** findings.
- Use your judgment on **Info**-level items — skip if trivial or out of scope.

**Commit each fix as a separate commit.** The commit message must not include the Jira key (CodeRabbit findings are not tied to a Jira issue). Instead, write a complete commit message that includes:
- A short subject line summarising the fix (imperative mood)
- A body with the full CodeRabbit finding as reported, and a description of the solution applied

```bash
cd "$WORKTREE_DIR"
git add <affected files>
git commit -m "<short imperative subject line>

CodeRabbit finding (<severity>):
<paste the full finding text as reported by CodeRabbit>

Solution:
<describe exactly what was changed and why>"
```

Examples:
```
Remove unused json import in dintero_client.py

CodeRabbit finding (Warning):
`import json` is imported but never used after removing the json.dumps()
calls from apple_pay() and google_pay().

Solution:
Deleted the unused import to keep the module clean.
```
```
Add return type annotation to google_pay method

CodeRabbit finding (Info):
google_pay() is missing a return type annotation, making the signature
inconsistent with the rest of the client methods.

Solution:
Added `-> GooglePay3dsChallenge` return type annotation to the method signature.
```

**Track every finding you choose NOT to fix** — you will need this list for the PR. For each skipped finding, note:
- The finding (severity + short description)
- Why it was skipped (e.g. out of scope, false positive, acceptable pattern in this codebase)

Re-run the review after fixing. Repeat until only Info-level findings remain (or the review is clean).

## Step 8 — Push the branch

Push the normal way — see the *Pushing from a worktree* section of the `create-worktree` skill for why no workaround is needed (the pre-push hooks resolve the main repo's `.venv` themselves):

```bash
cd "$WORKTREE_DIR"
git push -u origin <branch-name>
```

## Step 9 — Create a Pull Request

Create a PR using the GitHub CLI:

```bash
cd "$WORKTREE_DIR"
gh pr create \
  --title "<branch-name>" \
  --body "## Summary
<description of the fix>

## Jira
[<JIRA_KEY>]($JIRA_BASE_URL/browse/<JIRA_KEY>)

## Sentry
[<SENTRY_ID>](<SENTRY_URL>)

## Changes
- <bullet point summary of changes>

## Testing
- <describe the test(s) added>

## Code review notes

### Findings addressed
- <severity>: <finding> — <what was done>

### Findings not addressed
- <severity>: <finding> — <reason for skipping>" \
  --base "$DEFAULT_BRANCH"
```

Report the PR URL to the user.

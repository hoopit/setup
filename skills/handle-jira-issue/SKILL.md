---
name: handle-jira-issue
description: Handle any Jira issue end-to-end — an ITSM ticket or a project issue (BAC/WEB/FA). Fetch details (from the linked ITSM ticket when one exists), link or create a project issue only when needed, branch, fix, test, review, and open a PR. Use whenever the user links to or names a Jira issue to fix.
---

# Handle Jira Issue Workflow

Triggered when the user says something like "fix this issue" and provides any Jira issue key or link — either an ITSM ticket (e.g. `ITSM-1234`) or a project issue (e.g. `BAC-6934`, `WEB-1234`, `FA-987`), or a full Jira URL (e.g. `https://hoopit.atlassian.net/browse/ITSM-1234`).

## Configuration — read from CLAUDE.md, never hardcode

This skill is project-agnostic. Every Hoopit-specific identifier (Jira keys, the
Jira base URL, the ITSM project key, repo names) comes from the
**`## Agent skills` → `### Workflow skills config`** block in each repo's
`CLAUDE.md`. **Do not hardcode or guess these** — read them from CLAUDE.md. If a
value you need is missing from the relevant repo's CLAUDE.md, **stop and ask the
user to add it** rather than assuming a default.

The repos are sibling directories under a common parent (`HOOPIT_ROOT`); derive
it from the repo this skill is invoked in:

```bash
HOOPIT_ROOT="$(dirname "$(git rev-parse --show-toplevel)")"
```

### Build the Jira-key → repo map dynamically

Do **not** assume a fixed `BAC/WEB/FA` map. For each sibling repo under
`$HOOPIT_ROOT` that has a `CLAUDE.md`, read its declared **Jira project key** from
the Workflow skills config block. That yields the current `Jira key → repo`
mapping, so new projects work without editing this skill:

```bash
# Prints "KEY<TAB>/path/to/repo" for every sibling repo that declares a Jira key.
for repo in "$HOOPIT_ROOT"/*/; do
  cm="$repo/CLAUDE.md"; [ -f "$cm" ] || continue
  key="$(grep -iE '^\s*[-*]\s*\*\*Jira project key:\*\*' "$cm" | grep -oE '`[A-Z][A-Z0-9]+`' | tr -d '`' | head -1)"
  [ -n "$key" ] && printf '%s\t%s\n' "$key" "${repo%/}"
done
```

(At the time of writing that resolves to `BAC → api`, `WEB → web-admin`,
`FA → flutter-app`, but always resolve it from CLAUDE.md.)

Once you know `TARGET_REPO`, read the rest of its Workflow skills config —
**Jira base URL**, **ITSM project key**, **Default branch** — from that repo's
CLAUDE.md and use them in place of the literals below.

Variables used throughout this skill:
- `TARGET_PROJECT` — the Jira project key the fix is tracked under.
- `TARGET_REPO` — the repo whose CLAUDE.md declares `TARGET_PROJECT`.
- `TARGET_KEY` — the project issue key in `TARGET_PROJECT` (e.g. `BAC-6934`). Becomes the working `JIRA_KEY`.
- `JIRA_BASE_URL` — the Jira base URL from `TARGET_REPO`'s CLAUDE.md (e.g. `https://hoopit.atlassian.net`).
- `ITSM_PROJECT` — the ITSM project key from CLAUDE.md (e.g. `ITSM`); ITSM keys look like `<ITSM_PROJECT>-1234`.
- `DEFAULT_BRANCH` — `TARGET_REPO`'s default branch from CLAUDE.md (e.g. `master`).
- `ITSM_ISSUE_KEY` — the linked ITSM ticket, **if one exists**. May be unset.
- `DETAILS_KEY` — the issue you read the bug report / symptoms / attachments from: the **ITSM ticket when one exists**, otherwise the project issue itself.

> Wherever the steps below show `https://hoopit.atlassian.net`, `ITSM`, or
> `master`, substitute `$JIRA_BASE_URL`, `$ITSM_PROJECT`, and `$DEFAULT_BRANCH`
> from CLAUDE.md.

## Determine the scenario

Before anything else, classify the input issue. If a full Jira URL was provided, extract the issue key from it first, then look at the key's prefix:

### Input is an ITSM ticket (`ITSM-…`) — *ITSM-originated*

- `ITSM_ISSUE_KEY` = the input key.
- `DETAILS_KEY` = `ITSM_ISSUE_KEY`.
- `TARGET_PROJECT` / `TARGET_KEY` are resolved in **Step 2** (an existing linked project issue, or a new one you create).

### Input is a project issue (`BAC-…`, `WEB-…`, `FA-…`) — *project-originated*

- `TARGET_KEY` = the input key; `TARGET_PROJECT` = its prefix; `TARGET_REPO` = the matching repo. **No new project issue will ever be created** — the input issue *is* the target.
- Check whether it links to an ITSM ticket by fetching the `issuelinks` field (see the parsing note in Step 2a — inspect both `inwardIssue.key` and `outwardIssue.key`):

  ```bash
  acli jira workitem view <TARGET_KEY> --fields 'issuelinks' --json
  ```

  - **Linked `ITSM-…` issue found** → set `ITSM_ISSUE_KEY` to it; `DETAILS_KEY` = `ITSM_ISSUE_KEY`. (Read details from the ITSM ticket, not the project issue.)
  - **No ITSM link** → leave `ITSM_ISSUE_KEY` unset; `DETAILS_KEY` = `TARGET_KEY`. (Read details from the project issue itself.)

### How to determine `TARGET_PROJECT` (ITSM-originated only)

For project-originated issues the project is already known from the key prefix. For ITSM-originated issues, resolve the target project as follows:

1. **Existing link wins.** After fetching the ITSM issue, if it already links to an issue whose key prefix is `BAC-`, `WEB-`, or `FA-`, that is `TARGET_PROJECT` — no question needed.
2. **Fall back to cwd.** Otherwise, default to whichever repo the current working directory sits inside, and read **that** repo's `Jira project key` from its CLAUDE.md Workflow skills config — that is `TARGET_PROJECT`.
3. **Ask if ambiguous.** If neither rule resolves (e.g. cwd is outside all three repos, or the ITSM issue clearly describes a different layer than the cwd suggests), ask the user which project to target before doing anything else.

## Step 1 — Fetch issue details

Always read the bug report and context from `DETAILS_KEY` — i.e. the linked ITSM ticket when one exists, otherwise the project issue itself. When an ITSM ticket is linked, it is the source of truth for the reported symptoms, repro steps, and attachments; do **not** rely on the project issue for those details.

```bash
acli jira workitem view <DETAILS_KEY> --fields '*all'
```

Extract and note:
- **Summary / title**
- **Description and reported symptoms**
- **Affected component or service** (for ITSM-originated issues, often hints which `TARGET_PROJECT` is appropriate)
- **Priority and impact**
- **Reporter and any additional context**
- **Attachments** — note any attached files, especially HAR (`.har`) files, screenshots, or logs

### Review attached HAR files (if present)

If the issue has attached HAR files, download and review them to get a deeper understanding of the endpoints and payloads involved. HAR files capture the full browser network activity at the time of the bug and often reveal the exact request URLs, headers, request bodies, and response payloads that reproduce the problem.

Download attachments with `acli`:

```bash
acli jira workitem attachment download <DETAILS_KEY> --output-directory /tmp/<DETAILS_KEY>-attachments
```

Then inspect any `.har` file as JSON — focus on:
- **Failing requests** (non-2xx responses, or responses whose body contains error messages matching the reported symptom)
- **Request URL, method, headers, and body** — especially the payload shape and any serialization quirks
- **Response body** — the error message or unexpected data returned
- **Timing and sequence** — which request fired immediately before the failure

Use the findings to narrow down which endpoint, view, component, or screen is involved before starting the investigation.

If the issue cannot be understood or reproduced from the available information, stop and ask the user for clarification.

## Step 2 — Identify or create the target project issue

How this resolves depends on the scenario from *Determine the scenario*:

- **Project-originated** (input was a `BAC`/`WEB`/`FA` issue): `TARGET_KEY` is the input issue itself. **Do not create or link anything** — skip straight to **Step 3**. (Any linked ITSM ticket was already recorded as `ITSM_ISSUE_KEY`.)
- **ITSM-originated** (input was an `ITSM-…` ticket): follow 2a/2b below.

### 2a — Check for an existing linked target issue

**Do NOT use `acli jira workitem link list`** — it only returns `outwardIssueKey` and silently drops `inwardIssue` data. Target issues are typically linked as inward issues ("ITSM ticket is caused by BAC/WEB/FA bug"), so they will appear missing even when they exist.

Instead, fetch the `issuelinks` field directly and parse the JSON:

```bash
acli jira workitem view <ITSM_ISSUE_KEY> --fields 'issuelinks' --json
```

Inspect **both** `inwardIssue.key` and `outwardIssue.key` across all entries in the `fields.issuelinks` array. Look for any linked issue whose key starts with `BAC-`, `WEB-`, or `FA-`.

If such a link exists:
- Set `TARGET_PROJECT` from its prefix and `TARGET_KEY` to that key.
- Skip to **Step 3**.

### 2b — Create a new target issue if none exists

Resolve `TARGET_PROJECT` using the rules in *How to determine `TARGET_PROJECT`* above. Then map the ITSM request type to the destination issue type. The mapping is the same across all three projects:

| ITSM request type | Issue type in `TARGET_PROJECT` |
|-------------------|--------------------------------|
| Problem           | **Bug**                        |
| Feature request   | **Story**                      |
| Anything else     | **Task**                       |

```bash
acli jira workitem create \
  --project "$TARGET_PROJECT" \
  --type '<Bug | Story | Task>' \
  --summary '<concise title>' \
  --description '## Summary
<1-2 sentence description>

## Root cause / background
<technical explanation or context>

## References
- ITSM: [<ITSM_ISSUE_KEY>]($JIRA_BASE_URL/browse/<ITSM_ISSUE_KEY>)'
```

Note the new `TARGET_KEY` printed by the command (e.g. `BAC-6934`, `WEB-1234`, `FA-987`).

Create an **"is caused by"** link from the ITSM ticket to the new issue (i.e. the ITSM issue *is caused by* the target bug).

If unsure of the exact link-type name, list available types first:

```bash
acli jira workitem link type
```

Then create the link:

```bash
acli jira workitem link create \
  --out '<ITSM_ISSUE_KEY>' \
  --in '<TARGET_KEY>' \
  --type 'Causes' \
  --yes
```

> **Note:** The direction matters — `--out` is the outward issue (the effect: ITSM ticket) and `--in` is the inward issue (the cause: target bug). Verify direction with `acli jira workitem link type` if needed.

`TARGET_KEY` is the `JIRA_KEY` used for all subsequent steps.

## Step 3 — Create a Git branch as a worktree

All branch/worktree work happens inside `TARGET_REPO`. From here on, treat `TARGET_REPO` as the working repo — `cd` into it if you aren't already there.

Branch naming convention (same across all three repos): `<JIRA_KEY>/bug/<short-kebab-description>`

Examples:
- `BAC-6934/bug/dintero-payment-data-double-serialized`
- `WEB-1234/bug/club-admin-roster-export-empty`
- `FA-987/bug/login-screen-crash-on-empty-input`

### Defer to the target repo's `create-worktree` skill

Each repo owns its own worktree/venv/test-DB conventions, so **do not** hand-roll the worktree setup here. Instead:

1. Look for `TARGET_REPO/.claude/skills/create-worktree/SKILL.md`.
2. If it exists, read it and follow its instructions to create the branch and worktree. That skill is responsible for things like virtualenv wiring, isolated test DBs, or any other per-repo setup the worktree needs.
3. If it does **not** exist, fall back to a plain worktree:

   ```bash
   cd "$TARGET_REPO"
   git fetch origin
   BRANCH="<JIRA_KEY>/bug/<short-description>"
   WORKTREE_DIR=".worktrees/$(echo $BRANCH | tr '/' '-')"
   git worktree add -b "$BRANCH" "$WORKTREE_DIR" origin/master
   ```

   (Adjust `origin/master` if the repo's default branch is different — check with `git symbolic-ref refs/remotes/origin/HEAD`.)

All subsequent steps (4–9) run from `$WORKTREE_DIR` unless stated otherwise.

## Step 4 — Implement the fix

- Navigate to the relevant file(s) in `$WORKTREE_DIR` identified from the issue description and investigation.
- Apply the minimal, targeted fix.
- Follow existing code conventions. Read any relevant skill files in `$TARGET_REPO/.claude/skills/` that apply to the area you're touching (for example, the api repo has `models`, `views`, `urls`, `migrations` skills; the web-admin repo and flutter-app may have their own). Skip skills that don't exist.
- Do **not** refactor unrelated code.

## Step 5 — Write tests

Defer to the target repo's testing conventions:

1. If `TARGET_REPO/.claude/skills/writing-tests/SKILL.md` exists, read and follow it before writing tests.
2. If `TARGET_REPO/.claude/skills/running-tests/SKILL.md` exists, use its instructions to run tests.

Goal regardless of stack:
- Add at least **1 test** that reproduces the bug and verifies the fix.
- Place the test next to the code being fixed, following the surrounding test layout.
- Include a comment/docstring referencing the Jira issue, e.g.:

```python
def test_payment_data_not_double_serialized(self):
    """
    Regression test for BAC-6934.
    payment_data must be passed as a dict, not a JSON string,
    when calling the Dintero Google Pay endpoint.
    """
```

Run the new test (and any related tests) to confirm they pass. If the repo provides no realistic way to add an automated regression test for this kind of bug (e.g. some flutter-app UI bugs), say so explicitly in the PR description instead of skipping silently.

If tests fail, fix the issues before proceeding.

## Step 6 — Commit changes

Stage and commit all changes from within the worktree. Include the `Refs <ITSM_ISSUE_KEY>` footer **only when an ITSM ticket is linked** — omit it entirely for a project issue with no ITSM link:

```bash
cd "$WORKTREE_DIR"
git add -A
git commit -m "<JIRA_KEY>: <short description>

<Optional longer description of what was changed and why.>

Refs <ITSM_ISSUE_KEY>"
```

Example (ITSM linked):
```
BAC-6934: Fix double-serialization of payment_data in Dintero Google/Apple Pay

payment_data was being passed through json.dumps() before being added
to the request dict. Since _request() already uses json=data, this
resulted in Dintero receiving a JSON string instead of a JSON object.

Refs ITSM-1234
```

## Step 7 — Code review with CodeRabbit

Read `TARGET_REPO/.claude/skills/code-review/SKILL.md` and follow its instructions (all three repos have this skill).

Run a review against the repo's default branch from the worktree:

```bash
cd "$WORKTREE_DIR"
coderabbit review --prompt-only --base "$DEFAULT_BRANCH"
```

(Use `main` instead of `master` if that is the repo's default branch.)

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

**Track every finding you choose NOT to fix** — you will need this list for the PR. For each skipped finding, note:
- The finding (severity + short description)
- Why it was skipped (e.g. out of scope, false positive, acceptable pattern in this codebase)

Re-run the review after fixing. Repeat until only Info-level findings remain (or the review is clean).

## Step 8 — Push the branch

Push normally — including from a worktree, where the pre-push hooks resolve
the main repo's virtualenv on their own:

```bash
cd "$WORKTREE_DIR"
git push -u origin <branch-name>
```

## Step 9 — Create a Pull Request

Create a PR using the GitHub CLI. Include the `## ITSM` section **only when an ITSM ticket is linked** — omit it for a project issue with no ITSM link:

```bash
cd "$WORKTREE_DIR"
gh pr create \
  --title "<branch-name>" \
  --body "## Summary
<description of the fix>

## Jira
[<JIRA_KEY>]($JIRA_BASE_URL/browse/<JIRA_KEY>)

## ITSM
[<ITSM_ISSUE_KEY>]($JIRA_BASE_URL/browse/<ITSM_ISSUE_KEY>)

## Changes
- <bullet point summary of changes>

## Testing
- <describe the test(s) added, or state explicitly that no automated regression test was feasible and why>

## Code review notes

### Findings addressed
- <severity>: <finding> — <what was done>

### Findings not addressed
- <severity>: <finding> — <reason for skipping>" \
  --base "$DEFAULT_BRANCH"
```

(Again, swap `master` for `main` if that's the repo's default branch.)

Report the PR URL to the user.

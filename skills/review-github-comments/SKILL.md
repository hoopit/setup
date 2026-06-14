---
name: review-github-comments
description: Review and resolve all review comments on a GitHub PR — fetch comments, evaluate each one, apply fixes where needed, and reply to resolve them.
---

# GitHub PR Review Comments Workflow

## Prerequisites
- The `gh` CLI must be authenticated.
- You must be in the project repository (or a worktree of it).

## Steps

### 1. Get PR metadata
Ask the user for the PR URL if not provided. Extract the `<owner>/<repo>` and `<pr_number>` from the URL.

### 2. Fetch review comments and thread resolution status

Fetch the raw comments:
```bash
gh api repos/<owner>/<repo>/pulls/<pr_number>/comments --paginate
```

Then check which threads are actually unresolved via GraphQL (the REST comments API has no `resolved` field):
```bash
gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <pr_number>) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              databaseId
            }
          }
        }
      }
    }
  }
}'
```

Cross-reference `databaseId` with the REST comment IDs to build a map of `comment_id → isResolved`. Process only threads where `isResolved: false`.

### 3. For each unresolved comment thread

1. **Read the comment** — understand the reviewer's finding, suggestion, or question.
2. **Locate the relevant code** — use the `path` and `line`/`original_line` fields to find the file and line(s) in the local codebase.
3. **Evaluate the comment** — determine whether:
   - **(a) The issue is valid and actionable** — a real bug, improvement, or style fix that should be applied.
   - **(b) The issue is invalid or not applicable** — the reviewer's suggestion is incorrect, outdated, or doesn't apply to the current context.
   - **(c) Unclear or needs more investigation** — you have findings to share but aren't confident enough to resolve it.

4. **Take action based on evaluation:**
   - **Case (a) — Valid & actionable:** Apply the code fix, then reply to the comment explaining what was changed. **Resolve the thread.**
   - **Case (b) — Invalid / not applicable:** Reply to the comment explaining why the suggestion doesn't apply or is incorrect. **Resolve the thread.**
   - **Case (c) — Uncertain / needs discussion:** Reply to the comment with your findings, analysis, or questions. **Do NOT resolve the thread** — leave it open for further discussion.

### 4. Reply to and resolve comment threads

**Replying to a comment** (works for both replies and disagreements):
```bash
gh api repos/<owner>/<repo>/pulls/<pr_number>/comments \
  --field in_reply_to=<comment_id> \
  --field body="Your reply text here."
```
> Note: `in_reply_to` must be an integer. Do **not** use `-f` (string flag) — use `--field` so it is sent as a number.

**Resolving a thread** requires the GraphQL mutation (the REST API has no resolve endpoint). Use the `id` field from the GraphQL thread query above:
```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: { threadId: "<PRRT_...node_id>" }) {
    thread { isResolved }
  }
}'
```

### 5. Commit and push
After processing all comments:
1. Stage all modified files.
2. Commit with a descriptive message, e.g.:
   ```
   fix: address PR review comments

   Resolved comments from coderabbitai on PR #<pr_number>.
   ```
3. Push to the PR branch.


### 6. Report summary
Print a summary table of all processed comments:

| # | File | Reviewer | Action | Resolved? |
|---|------|----------|--------|-----------|
| 1 | `path/to/file` | coderabbitai | Applied fix | ✅ Yes |
| 2 | `path/to/other` | coderabbitai | Invalid — explained why | ✅ Yes |
| 3 | `path/to/another` | coderabbitai | Shared findings, needs discussion | ❌ No |

## Resolution Rules

> **Only resolve a comment thread if one of the following is true:**
> 1. You implemented a code change that addresses the comment.
> 2. You determined the comment is invalid/not applicable and explained why.
>
> **In all other cases**, reply with your findings but **leave the thread unresolved**.

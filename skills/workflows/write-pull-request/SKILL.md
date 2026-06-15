---
name: write-pull-request
description: Author GitHub PRs with clean Jira issue links — emit only the work-item keys the PR actually delivers so GitHub-for-Jira doesn't attach the PR (and its commits) to unrelated tickets. Use whenever you name a branch, write commit messages, or write a PR title/body in a repo connected to Jira via the GitHub-for-Jira integration.
---

# Write a Pull Request

Guidance for authoring PRs in repos wired to Jira through the
**GitHub-for-Jira** integration. Load this before you name a branch, write
commit messages, or write a PR title/body — the workflow skills
(`handle-jira-issue`, `fix-sentry-issue`) point here at their PR-creation step.

## Keep Jira issue links clean (GitHub-for-Jira)

GitHub-for-Jira links the PR/commits to **every** Jira key (`ABC-123` — letters,
dash, digits) it finds in the **branch name, commit messages, and PR title +
body**. There is no "passive mention": wrapping a key in a markdown link or a
`/browse/` URL does **not** exempt it — the raw key string is still there, so it
still links. (This is the open request in github-for-jira#1031; until it ships,
the emitted text is the only control.)

So the rule is: **emit only the keys for the work items this PR actually
delivers.** Everything else stays out of the four linked surfaces (branch name,
commit messages, PR title, PR body).

### Allowed — link freely

- The **target issue** the PR fixes (the working `JIRA_KEY`).
- The **originating ITSM ticket**, *only when one is linked* — it is the source
  of the work, so the PR *should* surface on it. Keep its `## ITSM` section and
  the `Refs <ITSM_ISSUE_KEY>` commit footer.

### Safe — never matches the pattern

- A **Sentry short ID** (e.g. `BAC-QCB`) has **no digits after the dash**, so it
  does not match the Jira-key pattern and is never linked. Keep the `## Sentry`
  reference and the `Fixes <SENTRY_ID>` footer as-is.

### Forbidden — never write the key in a linked surface

- Any **unrelated work item**: a sibling project's issue (`WEB-…`/`FA-…`), an
  unrelated `BAC-…` task, a "similar to …" aside. Reference related tickets in
  **Jira** (issue link / comment), not in the PR — linkifying them will not stop
  the integration from attaching the PR to them.

## Before you open the PR

Re-read the freeform sections (`## Summary`, `## Changes`, `## Code review
notes`) and every commit body, and confirm no `ABC-123`-shaped key beyond the
allowed set has crept in. If one has, move that reference into Jira instead.

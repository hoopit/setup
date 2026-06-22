#!/usr/bin/env bash
# Prepare/refresh read-only base worktrees for triage analysis.
#
# Triage agents must analyze root cause against the production-equivalent state
# (latest default branch), NOT whatever the developer happens to have checked out
# in the live repos. This creates one git worktree per repo at a FIXED location,
# pinned to origin/<default>, and just refreshes it (fetch + reset --hard) if it
# already exists. Worktrees share the repo's .git, so they're cheap and leave the
# developer's checkout + uncommitted work untouched. Read-only triage needs no
# deps/build, so nothing is installed here.
#
# Prints one `name=path` line per ready repo on stdout (diagnostics on stderr),
# for the orchestrator to pass into workflow.js as repoPaths.

HOOPIT_ROOT="${HOOPIT_ROOT:-$(dirname "$(git rev-parse --show-toplevel)")}"
# Fixed, reused location beside the repos. Dot-prefixed so it stays out of the
# `$HOOPIT_ROOT/*/` repo scan in handle-jira-issue, and outside any tracked tree.
WT_BASE="${TRIAGE_WT_BASE:-$HOOPIT_ROOT/.triage-worktrees}"
REPOS=(api web-admin flutter-app)

mkdir -p "$WT_BASE"

for name in "${REPOS[@]}"; do
  src="$HOOPIT_ROOT/$name"
  wt="$WT_BASE/$name"

  if ! git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
    echo "skip $name: no git repo at $src" >&2
    continue
  fi

  def="$(git -C "$src" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  def="${def:-master}"

  if ! git -C "$src" fetch origin --prune --quiet 2>/dev/null; then
    echo "skip $name: git fetch failed (auth/network?)" >&2
    continue
  fi
  git -C "$src" worktree prune 2>/dev/null

  if [ -e "$wt/.git" ]; then
    # exists → refresh to latest default branch (detached)
    if ! git -C "$wt" reset --hard "origin/$def" --quiet 2>/dev/null; then
      echo "skip $name: could not reset worktree to origin/$def" >&2
      continue
    fi
    git -C "$wt" clean -fd --quiet 2>/dev/null   # drop stray untracked files; keep ignored
  else
    rm -rf "$wt"   # clear any stale/unregistered dir before re-adding
    if ! git -C "$src" worktree add --detach "$wt" "origin/$def" >/dev/null 2>&1; then
      echo "skip $name: git worktree add failed" >&2
      continue
    fi
  fi

  echo "$name=$wt"
done

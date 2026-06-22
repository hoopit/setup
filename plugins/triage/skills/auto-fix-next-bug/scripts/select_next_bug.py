#!/usr/bin/env python3
"""Deterministic selector + claimer for the auto-fix-next-bug loop.

Replaces the old haiku "selector" sub-agent: the selection has no judgment in it
(pick the highest AI: Priority Score, Agent-ready, open, unassigned, undispatched
bug and claim it), so it runs as a plain script — zero LLM tokens, fully testable,
and it prints a single line so the /loop orchestrator's context stays flat.

Contract — prints EXACTLY ONE line to stdout (diagnostics go to stderr):
  KEY=<KEY> | SUMMARY=<summary> | PRIORITY=<priority>   a bug was claimed
  NONE                                                  nothing eligible right now
  ERROR: <reason>                                       could not select (e.g. auth)

Exit code: 0 for KEY/NONE, 1 for ERROR.

Eligibility: project bug, type=Bug, status=Open, unassigned, AI: Agent Suitability
= Agent-ready, AND not already in the dispatch log, AND no local/remote branch
`<KEY>/*`, AND no open PR with <KEY> in the title. Claim = transition to
"In Progress" + append a `dispatched` line to the dispatch log.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import subprocess
import sys
from datetime import UTC
from datetime import datetime

SKILL = "auto-fix-next-bug"


def warn(msg):
    print(msg, file=sys.stderr)


def emit(line, code=0):
    print(line)
    sys.exit(code)


def run(cmd, cwd=None):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


def repo_root():
    cp = run(["git", "rev-parse", "--show-toplevel"])
    return cp.stdout.strip() if cp.returncode == 0 else os.getcwd()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, help="Jira project key (read from the repo's CLAUDE.md; e.g. BAC/WEB/FA)")
    ap.add_argument("--limit", type=int, default=25, help="max candidate rows to scan")
    ap.add_argument(
        "--dry-run", action="store_true", help="show the pick but do not claim (no transition, no log write)"
    )
    args = ap.parse_args()
    root = repo_root()

    log_path = os.path.join(root, ".claude", "local", SKILL, "dispatched.log")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    dispatched = set()
    if os.path.exists(log_path):
        for ln in open(log_path):
            ln = ln.strip()
            if ln:
                dispatched.add(ln.split("\t")[0])

    jql = (
        f"project = {args.project} AND type = Bug AND status = Open AND assignee IS EMPTY "
        f'AND "AI: Agent Suitability" = "Agent-ready" '
        f'ORDER BY "AI: Priority Score" DESC, created ASC'
    )
    cp = run(["acli", "jira", "workitem", "search", "--jql", jql, "--fields", "key,summary,priority", "--csv"])
    if cp.returncode != 0:
        emit(f"ERROR: acli search failed: {cp.stderr.strip()[:200]}", 1)

    rows = list(csv.DictReader(io.StringIO(cp.stdout)))
    if not rows:
        emit("NONE")

    # case-insensitive header lookup
    def col(row, name):
        for k, v in row.items():
            if k and k.strip().lower() == name:
                return (v or "").strip()
        return ""

    for row in rows[: args.limit]:
        key = col(row, "key")
        if not key or key in dispatched:
            continue
        # existing branch?  (handle-jira-issue branches as <KEY>/bug/...)
        br = run(["git", "branch", "-a", "--list", f"{key}/*"], cwd=root)
        if br.stdout.strip():
            warn(f"skip {key}: branch exists")
            continue
        # open PR with the key in the title?
        pr = run(["gh", "pr", "list", "--state", "open", "--search", f"{key} in:title", "--json", "number"], cwd=root)
        if pr.returncode == 0 and pr.stdout.strip() and json.loads(pr.stdout):
            warn(f"skip {key}: open PR exists")
            continue

        # CLAIM (skipped on --dry-run)
        if args.dry_run:
            warn(f"(dry-run) would claim {key} — no transition, no log write")
            emit(f"KEY={key} | SUMMARY={col(row, 'summary')} | PRIORITY={col(row, 'priority')}")
        tr = run(["acli", "jira", "workitem", "transition", "--key", key, "--status", "In Progress", "--yes"])
        if tr.returncode != 0:
            warn(
                f"{key}: transition to In Progress failed (continuing; dispatch log is the backstop): {tr.stderr.strip()[:160]}"
            )
        ts = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(log_path, "a") as f:
            f.write(f"{key}\t{ts}\tdispatched\n")
        emit(f"KEY={key} | SUMMARY={col(row, 'summary')} | PRIORITY={col(row, 'priority')}")

    emit("NONE")


if __name__ == "__main__":
    main()

---
name: curate-memory
description: Review, prune, and promote Claude Code agent memories — delete stale/shipped ones, and move durable team-relevant knowledge into the right shared home (a path-scoped rule, a directory CLAUDE.md, root CLAUDE.md, or leave it a skill). Use when the user wants to evaluate/clean up/prune memories, asks whether memories are redundant or should be shared with the team, or wants memories moved into CLAUDE.md / rules / specific directories.
---

# Curate memory

Agent memory accumulates point-in-time notes. Over time some are stale (the work
shipped, the system was retired, the bug was fixed), some are redundant with docs
that already exist, and some are durable team knowledge trapped in one person's
private memory. This skill turns a memory pile into: a smaller set of genuinely
personal/live notes, plus durable knowledge promoted to where the whole team (and
their agents) will actually see it.

## The memory system (what you're working with)

- Memories live as one-fact-per-file markdown under the memory directory, each with
  `name` / `description` / `metadata.type` frontmatter.
- `MEMORY.md` is the index: **one line per memory**, loaded into context every
  session. Keep it in lockstep with the files — every file has exactly one index
  line, and vice-versa.
- **The memory directory is usually NOT git-tracked**, so deleting a memory is
  irreversible. Confirm before bulk deletion (see "Confirm" below). Check with
  `git -C <memory-dir> rev-parse --is-inside-work-tree`.
- Memories are **point-in-time observations, not live state**. Never act on a
  memory's claim without re-verifying it (see step 2).

## Where knowledge belongs — the routing decision

This is the heart of the skill. For each durable memory, pick the home by the
*nature* of the knowledge, not by topic:

| If the knowledge is… | It belongs in… | Why |
|---|---|---|
| An always-applicable convention for **every file of a type** (every model, migration, view, test) | a **path-scoped rule** `.claude/rules/<x>.md` | Auto-loads whenever a matching file is in context — no reliance on model invocation |
| A gotcha scoped to **one directory's code** (e.g. infra in `cdk/`) | that directory's **`CLAUDE.md`** | Always-on while working in that subtree |
| **Cross-cutting**, always-relevant, touches many files with **no clean path glob** | **root `CLAUDE.md`** | Always-on everywhere; a rule glob can't target it |
| An **on-demand procedure** for a specific, *occasional* task (a how-to you invoke when doing X) | **stays / becomes a skill** | Description-gated, model-invoked by semantic trigger — not loaded on every edit |
| Already **enforced by a test/hook or documented next to the code** (a CI-config comment, a `test_*` that fails) | **just delete** | The point-of-use copy wins; memory is pure duplication |
| **Personal** (your access/secrets setup), **live-ops** state (incidents, alarms, live AWS), or **in-flight** work | **keep as memory** | Not team-doc material; not derivable from the repo |

Rule of thumb for the rule-vs-skill split: a **rule** is relevant on *essentially
every* edit to files of its type; a **skill** is relevant only when you're doing one
*particular* task. "Bump an API version" is a skill; "every view uses `@http`" is a
rule. If converting a skill to a rule would load a long how-to on edits that mostly
*aren't* that task, keep it a skill.

## Workflow

### 1. Survey
List the memory files and read `MEMORY.md`. The index one-liners are enough to
triage most; read full files only for ones you'll promote (to write good prose) or
whose status you must verify.

### 2. Discover the destinations and verify reversibility
- Find the team-knowledge surfaces that already exist: root `CLAUDE.md`, any
  directory `CLAUDE.md` (`find . -name CLAUDE.md`), `.claude/rules/`, `docs/`.
  Match the style/structure already there — extend a section, don't reinvent.
- Confirm whether the memory dir is git-tracked (deletions reversible or not).

### 3. Verify each candidate against ground truth — NEVER trust the memory blindly
- PR/work-tracking memory → `git log --oneline | grep '#<pr>'`. Merged ⇒ the work is
  done; the *tracker* memory is now stale (the durable lesson, if any, lives in a
  skill/doc already — check).
- "We fixed/retired/deleted X" → confirm X is actually gone/fixed before deleting on
  that basis.
- A memory citing `file:line`, a flag, or a construct → confirm it still exists.

### 4. Classify: delete / promote / keep
- **Delete**: shipped work trackers, dead-workflow operational quirks, fixed/obsolete
  quirks, historical tuning logs, and anything redundant with an existing
  point-of-use doc/test.
- **Promote**: durable + team-relevant + maps cleanly to a destination above.
- **Keep**: personal, live-ops, in-flight, or not-team-material.

### 5. Confirm before outward/irreversible actions
Promotion commits content into the **shared repo** (outward-facing) and deletion is
**irreversible** (memory isn't git-tracked). Present the classified plan and get a
green light on (a) which sets to promote and where, and (b) deletion scope —
`AskUserQuestion` with a question per axis works well. Pure "this is stale, remove
it" is within a "prune my memory" request; borderline calls (historical logs, things
you're unsure are dead) should be surfaced, not assumed.

### 6. Execute — promote first, then delete the source
- **Promote before deleting** so you never lose the source text. Condense the memory
  into the destination's voice (rule-first, then mechanism, then file pointers); drop
  the operational war-story detail that doesn't help a teammate.
- When the glob for a rule depends on layout, **verify the layout** first
  (`find -type d -name tests` etc.). Per-app dirs need `**/<name>/**`, not `<name>/**`.
- Keep `MEMORY.md` in sync: remove the deleted lines. Add/maintain a **top pointer
  note** recording where promoted knowledge went, so it isn't re-added to memory
  later (e.g. "CDK gotchas → cdk/CLAUDE.md; test gotchas → the `testing` rule").

### 7. Verify consistency
```bash
# counts match, no dangling refs, no orphan files
ls *.md | grep -vx MEMORY.md | wc -l           # files
grep -c '^- \[' MEMORY.md                       # index entries
grep -oP '\]\(\K[^)]+\.md' MEMORY.md | while read f; do [ -f "$f" ] || echo "MISSING $f"; done
for f in $(ls *.md|grep -vx MEMORY.md); do grep -q "($f)" MEMORY.md || echo "ORPHAN $f"; done
```

### 8. Commit the team-doc changes
- Stage **only the files you changed** — never sweep up the user's unrelated
  in-progress work. Check `git status` and `git add` explicit paths.
- One focused commit per logical move reads best (e.g. "promote X to cdk/CLAUDE.md",
  "move test skills to a path-scoped rule"). Commit/push only when the user asks.

## Path-scoped rules — the format

A rule is `.claude/rules/<name>.md` with a `paths:` frontmatter glob; its body loads
into context only when a matching file is in context.

```markdown
---
paths:
  - "**/tests/**"
  - "**/test_*.py"
  - "**/conftest.py"
---

# Testing
...rule body...
```

Globs support `**`, `*`, and brace expansion (`{ts,tsx}`). Skills support the same
`paths:` field if you want a skill that only surfaces for certain files. Differences:
nested `CLAUDE.md` loads by *directory proximity*; a rule loads by *path glob match*;
a skill loads by *model invocation* (description-gated), optionally narrowed by paths.

## Anti-patterns

- Promoting a one-off incident log or in-flight status into a team doc — those are
  exactly what should stay (or be deleted), not shared.
- Converting an occasional how-to skill into an always-on rule — context bloat on
  every edit for a task that rarely happens.
- Duplicating into a team doc something already enforced by a test/hook or commented
  next to the code — delete the memory instead; point-of-use wins.
- Per-directory `CLAUDE.md` copies for something that lives in many sibling dirs — use
  one path-scoped rule instead of N copies.
- Deleting the source memory before writing the promoted copy.
- Leaving `MEMORY.md` out of sync with the files on disk.

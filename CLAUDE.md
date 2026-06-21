# CLAUDE.md

Guidance for Claude Code when working in this repo. This is a **distribution** of
agent skills, shipped as a Claude Code plugin marketplace (see [README.md](README.md)).
For the skill-authoring conventions, the project-local `create-hoopit-skill` skill
under `.claude/skills/` is the source of truth.

## Workflow

- **Commit most edits straight to `main`.** Routine skill/plugin changes go directly
  on `main` — no feature branch or PR. Skip the usual "branch first on the default
  branch" step here. Reserve a branch for large, risky, or explicitly-requested work.

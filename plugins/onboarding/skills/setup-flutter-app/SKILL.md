---
name: setup-flutter-app
description: Set up a brand-new machine for the Hoopit flutter-app — install tooling (gh, mise/Python, FVM, DCM, Sentry CLIs, acli), clone hoopit/flutter-app as a sibling of the skills repo, bootstrap deps/codegen/l10n/pre-commit, wire up Figma MCP, and run the app. Use when a developer wants to onboard to the Flutter app, set up their flutter-app dev environment, or asks how to get flutter-app building/running locally.
---

# Hoopit flutter-app onboarding

Drive a new machine to a working `flutter-app` checkout. The detailed,
platform-aware walkthrough lives in [ONBOARDING.md](ONBOARDING.md) — read it and
follow it step by step. This file is the orchestration contract.

## How to run this

1. **Read [ONBOARDING.md](ONBOARDING.md) fully before starting.** It is the
   source of truth for every command and verification.
2. **Detect the developer's OS** (macOS / Linux / Windows) and pick the matching
   install command at each step. When in doubt, ask.
3. **Go step by step.** After each step, run the step's verification command and
   report the result before moving on. Do not batch silently.
4. **Pause for anything that needs the user**: `sudo`/admin rights, browser
   logins (GitHub, Atlassian, Figma), or the DCM license. Ask before running it.
5. **Stop and surface blockers** rather than guessing around a failure.

## Critical: where the repo goes

This skill runs from inside the **`skills`** repo. Clone `flutter-app` as a
**sibling of `skills`**, not inside it:

```bash
# from the skills repo root
gh repo clone hoopit/flutter-app ../flutter-app
cd ../flutter-app
```

This yields `…/flutter-app` next to `…/skills`. Run the rest of the bootstrap
(Step 2c onward in ONBOARDING.md) from inside `../flutter-app`.

## Sequence (see ONBOARDING.md for the detail of each)

1. **Step 0** — Claude Code is already installed (you're in it). Skip.
2. **Step 1** — Core CLIs: `gh` (+auth), `mise` (+Python), `FVM`, `DCM` (+license),
   `sentry` & `sentry-cli`, `acli` (+auth).
3. **Step 2** — Clone flutter-app **as a sibling** (above), then `fvm install`,
   `pub get` (app + `packages/hoopit_api` + `packages/network_bloc`),
   build_runner (app **and** API), gen-l10n, and `pre-commit install` (commit
   **and** push hooks).
4. **Step 3** — IDE (Android Studio recommended; VS Code alternative).
5. **Step 4** — Figma MCP server in Claude Code.
6. **Step 5** — Run the app on an emulator with the staging flavor.

Finish by walking the **Final verification checklist** in ONBOARDING.md and
reporting any unchecked item.

## Key conventions to reinforce

- **Always `fvm flutter` / `fvm dart`** — never bare `flutter`/`dart`.
- **Two build_runner watchers**: app (repo root) and **API** (`packages/hoopit_api`).
  Re-run the API watcher/build on every API model change.
- **Localization**: edit ARB files → run gen-l10n; never hand-edit generated files.

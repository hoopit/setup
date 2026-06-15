---
name: setup-api
description: Set up a brand-new machine for the Hoopit Django API — install tooling (gh, mise/Python 3.14, uv, Docker, pre-commit, Sentry CLI, acli, AWS CLI), clone hoopit/api as a sibling of the skills repo, bootstrap deps + supporting services (Postgres/Redis/stripe-mock), migrate, run the server, and run tests. Use when a developer wants to onboard to the API, set up their api/backend dev environment, or asks how to get the Django API running locally.
---

# Hoopit API onboarding

Drive a new machine to a working `api` (Django) checkout. The detailed,
platform-aware walkthrough lives in [ONBOARDING.md](ONBOARDING.md) — read it and
follow it step by step. This file is the orchestration contract.

## How to run this

1. **Read [ONBOARDING.md](ONBOARDING.md) fully before starting.** It is the
   source of truth for every command and verification.
2. **Detect the developer's OS** (macOS / Linux / Windows) and pick the matching
   install command at each step. When in doubt, ask.
3. **Go step by step.** After each step, run the step's verification command and
   report the result before moving on.
4. **Pause for anything that needs the user**: `sudo`/admin rights, browser
   logins (GitHub, Atlassian, AWS), Docker Desktop install.
5. **Stop and surface blockers** rather than guessing around a failure.

## Critical: where the repo goes

This skill runs from inside the **`skills`** repo. Clone `api` as a **sibling of
`skills`**, not inside it:

```bash
# from the skills repo root
gh repo clone hoopit/api ../api
cd ../api
```

This yields `…/api` next to `…/skills`. Run the rest of the bootstrap from inside
`../api`.

## Sequence (see ONBOARDING.md for the detail of each)

1. **Step 0** — Claude Code is already installed (you're in it). Skip.
2. **Step 1** — Core CLIs: `gh` (+auth), `mise` (+Python 3.14), `uv`, **Docker**,
   `sentry`, `acli` (+auth), and `aws` (optional, for staging/prod).
3. **Step 2** — Clone api **as a sibling** (above), `uv sync`, `pre-commit install`
   (commit **+** push **+** post-checkout hooks).
4. **Step 3** — Supporting services: Postgres (the repo's `local.env` expects it
   on `127.0.0.1:5435`), plus optional Redis + stripe-mock for Celery/payments.
5. **Step 4** — `manage-local.py migrate`, then `runserver` on `0.0.0.0:8080`.
6. **Step 5** — Run the test suite via `uv run pytest`.

Finish by walking the **Final verification checklist** in ONBOARDING.md and
reporting any unchecked item.

## Key conventions to reinforce

- **`uv` is the package manager.** Use `uv run …` / `uv sync`, not bare `pip`.
- **Local commands need `DOTENV=local.env`** (or use the `./manage-local.py`
  wrapper, which presets `DJANGO_SETTINGS_MODULE` and `DOTENV`).
- **Format with `ruff format .`**, lint/import-order with `ruff check .`.
- **Staging/prod secrets come from SSM**, not env files — running against those
  needs a valid `aws login` session for the `hoopit-{staging,prod}-developer`
  role.

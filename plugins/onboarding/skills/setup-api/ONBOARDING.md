# Hoopit API — Developer Onboarding

Welcome! This guide takes a brand-new machine to a fully working Hoopit `api`
(Django) checkout that runs, migrates, lints, tests, and commits cleanly.

The philosophy: **install Claude Code first, then let Claude Code do the rest.**
Most steps below are written as prompts you can paste into Claude Code — it will
detect your OS, run the commands, and fix problems as they come up. Commands are
also given verbatim so you can run them by hand if you prefer.

> **You are running this from the `skills` repo.** This onboarding lives in the
> `skills` repo as a Claude Code skill. When you clone `api` (Step 2a), it goes
> **next to** `skills` as a sibling directory (`../api`), not inside it.

> **Platforms.** The team runs **macOS, Linux, and Windows**. Each tool below is
> available on all three; pick the install command that matches your machine, or
> just let Claude Code detect your OS and choose for you.

> **Two ways to run the app.** Either run it **natively** (uv + a local Postgres,
> the PyCharm-style setup the README documents) or via **Docker Compose** (the
> `compose.yaml` path, convenient for Claude Code users). This guide does the
> native path and notes the Compose shortcut where relevant.

---

## At a glance — what you're installing

| Tool | Why this project needs it |
|------|---------------------------|
| **Claude Code** | Your agent for the rest of this setup |
| **GitHub CLI (`gh`)** | Auth + clone the repo |
| **mise** | Provides **Python 3.14**, the version the project pins (`pyproject.toml`) |
| **uv** | The project's package manager (`uv sync`, `uv run`) |
| **Docker** | Runs supporting services locally: Postgres, Redis, stripe-mock |
| **pre-commit** | Git hooks: ruff (lint+format), djhtml, safemigrate, makemigrations, beat-task checks |
| **`sentry`** | Query Sentry issues & the API from the terminal (https://cli.sentry.dev/) |
| **Atlassian CLI (`acli`)** | Jira/Confluence from the terminal |
| **AWS CLI (`aws`)** *(optional)* | Run locally against staging/prod (SSM secrets, IAM DB auth) |

> **Package managers.** No single required one. macOS → **Homebrew** (`brew`),
> Linux → your distro's manager (`apt`, `pacman`, …) or install scripts,
> Windows → **winget** or **scoop**. The prompts below let Claude pick whatever
> you have.

---

## Step 0 — Install Claude Code (do this by hand)

This is the only step you do entirely yourself; everything after can be driven
through Claude Code.

- [ ] Install Claude Code:
  ```bash
  # macOS / Linux
  curl -fsSL https://claude.com/install.sh | bash
  ```
  ```powershell
  # Windows (PowerShell)
  irm https://claude.com/install.ps1 | iex
  ```
- [ ] Start it from the `skills` repo and sign in:
  ```bash
  claude
  ```
  Follow the browser prompt to authenticate.
- [ ] Confirm it runs: type `/status` inside the session.

> From here on, the **▶ Prompt** blocks are text you can paste into Claude Code.

---

## Step 1 — Core CLI tools

### 1a. GitHub CLI + authenticate

▶ **Prompt:**
> Install the GitHub CLI (`gh`) using whatever package manager I have, then run
> `gh auth login` choosing HTTPS and authenticating via browser. Verify with
> `gh auth status`.

Manual:
```bash
brew install gh                 # macOS
sudo apt install gh             # Debian/Ubuntu  (or see cli.github.com)
sudo pacman -S github-cli       # Arch
winget install GitHub.cli       # Windows

gh auth login                   # GitHub.com → HTTPS → login with browser
gh auth status
```

- [ ] `gh auth status` shows you logged in to github.com

### 1b. mise + Python 3.14

The project pins **Python 3.14** (`pyproject.toml: requires-python = ">=3.14,<4.0"`).
We use [mise](https://mise.jdx.dev/) to install and pin it without touching your
system Python.

▶ **Prompt:**
> Install `mise`, hook it into my shell, then use it to install Python 3.14 and
> set it as the global default. Verify `python3 --version` reports 3.14 through
> mise.

Manual:
```bash
brew install mise               # macOS
curl https://mise.run | sh      # Linux
winget install jdx.mise         # Windows

echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec $SHELL   # bash → ~/.bashrc

mise use -g python@3.14
python3 --version               # → 3.14.x
```

- [ ] `mise --version` works
- [ ] `python3 --version` reports 3.14.x

### 1c. uv (package manager)

The project uses [uv](https://docs.astral.sh/uv/) for dependency management and
running commands. Deps are locked in `uv.lock`.

▶ **Prompt:**
> Install `uv` for my OS and verify `uv --version`.

Manual:
```bash
brew install uv                              # macOS
curl -LsSf https://astral.sh/uv/install.sh | sh   # Linux/macOS
winget install astral-sh.uv                  # Windows
uv --version
```

- [ ] `uv --version` works

### 1d. Docker (supporting services)

Local dev needs **Postgres** (always) and optionally **Redis** + **stripe-mock**
(for Celery and Stripe-backed flows). Docker is the easiest way to run them.

▶ **Prompt:**
> Install Docker for my OS (Docker Desktop on macOS/Windows, the Docker Engine on
> Linux), start it, and verify `docker info` works without sudo.

Manual:
```bash
brew install --cask docker          # macOS (Docker Desktop)
winget install Docker.DockerDesktop # Windows
# Linux — install Docker Engine per https://docs.docker.com/engine/install/ and
#         add yourself to the `docker` group
docker info
```

- [ ] `docker info` works

### 1e. Sentry CLI

For querying Sentry issues & the API from the terminal.

▶ **Prompt:**
> Install the `sentry` CLI from https://cli.sentry.dev/getting-started/ for my OS.
> Verify `sentry --version`. Don't log in yet — I'll add auth when I need it.

- [ ] `sentry --version` works

### 1f. Atlassian CLI (`acli`)

For Jira/Confluence — branch/PR names derive from the Jira ticket key.

▶ **Prompt:**
> Install the Atlassian CLI (`acli`) following
> https://developer.atlassian.com/cloud/acli/guides/install-acli/ for my OS,
> then run the login flow. Verify with `acli --version`.

Manual:
```bash
brew tap atlassian/homebrew-acli && brew install acli   # macOS
winget install Atlassian.acli                           # Windows
# Linux — follow the install guide linked above

acli --version
acli jira auth login
```

- [ ] `acli --version` works · `acli jira auth login` succeeds

### 1g. AWS CLI (optional — for staging/prod)

Only needed if you'll run the app **locally against staging/prod**, use the
read-only DB tunnel, or work with infra. Staging/prod secrets are pulled from SSM
at startup, which requires a valid AWS session for the
`hoopit-{staging,prod}-developer` role.

▶ **Prompt:**
> Install the AWS CLI v2 for my OS and verify `aws --version`. Don't configure a
> profile yet.

- [ ] `aws --version` works (skip if you don't need staging/prod access yet)

---

## Step 2 — Clone & bootstrap the project

### 2a. Clone (as a sibling of the skills repo)

The `api` repo must sit **next to** the `skills` repo, not inside it. Run this
from the `skills` repo root so the clone lands at `../api`:

▶ **Prompt:**
> From the `skills` repo, clone `hoopit/api` with `gh` into the parent directory so
> it ends up as a sibling (`../api`), then `cd` into it.

Manual:
```bash
# run from the skills repo root
gh repo clone hoopit/api ../api
cd ../api
```

Resulting layout:
```
…/
├── skills/    # this repo (onboarding skills)
└── api/      # the Django API — sibling, just cloned
```

- [ ] Repo cloned to `../api` and you're inside it

### 2b. Install dependencies

▶ **Prompt:**
> In the api repo, run `uv sync` to create the virtualenv and install all locked
> dependencies. Report any build failures (some native packages compile from
> source).

Manual:
```bash
uv sync
```

> **Native build deps.** Some packages (e.g. `pycairo`) build from source on
> Linux + Python 3.14 and need system libraries — on Debian/Ubuntu:
> `sudo apt install libcairo2-dev pkg-config python3-dev`. Install the equivalent
> for your distro if `uv sync` fails on a C extension.

- [ ] `uv sync` completes; `.venv/` exists

### 2c. Install git hooks (pre-commit)

The repo wires up ruff (lint + format), djhtml/djcss/djjs, django-safemigrate,
and local checks (makemigrations, celery beat tasks) across the commit, push, and
post-checkout stages.

▶ **Prompt:**
> Install this repo's git hooks for the pre-commit, pre-push, and post-checkout
> stages, then run `pre-commit run --all-files` once and help me fix any failures.

Manual:
```bash
uv run pre-commit install --hook-type pre-commit --hook-type pre-push --hook-type post-checkout
uv run pre-commit run --all-files
```

- [ ] Hooks installed for **pre-commit, pre-push, and post-checkout**
- [ ] `pre-commit run --all-files` passes

---

## Step 3 — Supporting services (Postgres, Redis, stripe-mock)

Local config lives in `.envs/local.env` and `.envs/base.env`. By default
`local.env` points the app at a Postgres on **`127.0.0.1:5435`** (db `postgres`,
user `postgres`, trust auth). Personal, non-secret overrides go in the
gitignored `.envs/__local.env`.

### Option A — Docker Compose (recommended)

The repo ships `compose.yaml`. Postgres is the default service; Redis and the
Celery/beat workers are behind profiles.

▶ **Prompt:**
> Start the supporting services for the api repo with Docker Compose: bring up
> Postgres now, and Redis if I'll be running Celery. Map Postgres to the port my
> `local.env` expects.

Manual:
```bash
# Postgres only (maps host 5435 → container 5432 to match local.env)
POSTGRES_PORT=5435 docker compose up -d postgres

# Add Redis when you need Celery
docker compose --profile redis up -d redis
```

> The README's PyCharm flow refers to an "optimized postgres" container and a
> `stripe-mock-latest` container. The optimized Postgres is just a Postgres on
> `:5435`; run `stripe/stripe-mock` separately if you're exercising Stripe flows.

### Option B — your own Postgres

Run any Postgres reachable at `127.0.0.1:5435` with a `postgres` database and
`postgres` user (trust/no password), or override `DB_HOST`/`DB_PORT`/`DB_NAME`/
`DB_USER`/`DB_PASSWORD` in `.envs/__local.env`.

- [ ] A Postgres is reachable at the host/port in `local.env` (default `127.0.0.1:5435`)

---

## Step 4 — Migrate & run the server

`manage-local.py` presets `DJANGO_SETTINGS_MODULE=club_united_api.settings.default`
and `DOTENV=local.env`, so it's the convenient entrypoint for local dev.

▶ **Prompt:**
> In the api repo, apply migrations with `manage-local.py`, then run the dev
> server on `0.0.0.0:8080` and tell me if it boots cleanly.

Manual:
```bash
uv run ./manage-local.py migrate
uv run ./manage-local.py runserver 0.0.0.0:8080
# → http://localhost:8080  (admin at /admin)
```

- [ ] `migrate` applies cleanly
- [ ] `runserver` boots and `http://localhost:8080/admin` loads

---

## Step 5 — Run the tests

Tests run on Postgres via pytest (config in `pytest.ini`: test settings,
`--reuse-db`, env files). They don't need Redis or stripe-mock for the unit
suite.

▶ **Prompt:**
> Run the test suite for the api repo with `uv run pytest`, scoped to a single app
> first to confirm the DB and settings are wired up, then report the result.

Manual:
```bash
# whole suite (the project recommends scoping to app test dirs, not the root)
uv run pytest */tests

# a single app, faster first check
uv run pytest users/tests
```

> If the test DB gets into a bad state, drop `--reuse-db` (or its cached DB) and
> let pytest recreate it. See the project's `running-tests` skill for parallelism
> and DB-reuse details.

- [ ] A scoped test run passes (DB + settings confirmed)

---

## Final verification checklist

- [ ] `claude` runs and is authenticated
- [ ] `gh auth status` ✓ · `acli --version` ✓ · `sentry --version` ✓
- [ ] `python3 --version` reports 3.14 via mise · `uv --version` ✓
- [ ] `api` cloned as a sibling of `skills` (`../api`)
- [ ] `uv sync` completed; `.venv/` present
- [ ] `pre-commit` hooks installed (pre-commit, pre-push, post-checkout) and `--all-files` passes
- [ ] Postgres reachable at the `local.env` host/port (default `127.0.0.1:5435`)
- [ ] `manage-local.py migrate` clean · `runserver` boots on `:8080`
- [ ] A scoped `pytest` run passes
- [ ] *(optional)* `aws --version` ✓ if you need staging/prod access

---

## Pointers & conventions

- **`uv` is the package manager** — `uv run …` / `uv sync`, never bare `pip`.
- **Local commands need `DOTENV=local.env`** — or use `./manage-local.py`, which
  presets it along with `DJANGO_SETTINGS_MODULE`.
- **Format with `ruff format .`**, lint + import-order with `ruff check .`.
- **Prefer early failure** over silently handling unexpected state (see the
  repo's `CLAUDE.md`): no defensive `{}.get()` / `or` / null-guards where a value
  is expected.
- **Staging/prod**: run with `DOTENV=staging.env|prod.env` (or `manage-staging.py`
  / `manage-prod.py`). Secrets are pulled from SSM at startup and require a valid
  `aws login` session for the `hoopit-{staging,prod}-developer` role.
- **Branching/PRs** derive names from the Jira ticket key — query tickets with `acli`.
- The repo's `CLAUDE.md` and its `.claude/skills/` (migrations, models, views,
  running-tests, readonly-db, …) are the day-to-day reference.

---

### Suggested one-shot prompt for Claude Code

> Read this ONBOARDING.md and set up this machine for the Hoopit API. Go step by
> step, detect my OS, install each tool with whatever package manager I have,
> clone `api` as a sibling of the `skills` repo (`../api`), start a local Postgres
> on the port `local.env` expects, run migrations and the dev server, then run a
> scoped pytest. Pause for anything that needs my credentials (GitHub, Atlassian,
> AWS) or `sudo`/admin rights, and after each step run the verification command
> and report the result.

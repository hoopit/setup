# Hoopit flutter-app — Developer Onboarding

Welcome! This guide takes a brand-new machine to a fully working Hoopit
`flutter-app` checkout that builds, runs, lints, and commits cleanly.

The philosophy: **install Claude Code first, then let Claude Code do the rest.**
Most steps below are written as prompts you can paste into Claude Code — it will
detect your OS, run the commands, and fix problems as they come up. Commands are
also given verbatim so you can run them by hand if you prefer.

> **You are running this from the `skills` repo.** This onboarding lives in the
> `skills` repo as a Claude Code skill. When you clone `flutter-app` (Step 2a), it
> goes **next to** `skills` as a sibling directory (`../flutter-app`), not inside
> it.

> **Platforms.** The team runs **macOS, Linux, and Windows**. Each tool below is
> available on all three; pick the install command that matches your machine, or
> just let Claude Code detect your OS and choose for you.
> iOS builds require macOS + Xcode — on Linux/Windows you develop and run the
> Android and web targets.

---

## At a glance — what you're installing

| Tool | Why this project needs it |
|------|---------------------------|
| **Claude Code** | Your agent for the rest of this setup |
| **GitHub CLI (`gh`)** | Auth + clone the repo |
| **mise** | Provides **Python**, which the `pre-commit` framework runs on |
| **FVM** | Pins Flutter to the exact version in `.fvmrc` (**3.44.0**) |
| **DCM (`dcm`)** | Extra static analysis; runs in the pre-commit hook |
| **pre-commit** | Git hooks: format, analyze, gen-l10n, DCM, ARB sort |
| **`sentry`** | Query Sentry issues & the API from the terminal — the one you'll use most in local dev (https://cli.sentry.dev/) |
| **`sentry-cli`** | Release & debug-symbol uploads; matches the `sentry_dart_plugin` in `pubspec.yaml` |
| **Atlassian CLI (`acli`)** | Jira/Confluence from the terminal |
| **Android Studio** *(recommended)* or **VS Code** | IDE, Android SDK, emulators |
| **Figma MCP** | Lets Claude read Figma designs during UI work |

> **Package managers.** There's no single required one. Conventional choices:
> macOS → **Homebrew** (`brew`), Linux → your distro's manager (`apt`, `pacman`, …)
> or the tools' install scripts, Windows → **winget** or **scoop**. The prompts
> below let Claude pick whatever you have.

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
> Claude will detect your OS and run the right commands.

---

## Step 1 — Core CLI tools

### 1a. GitHub CLI + authenticate

You need this before you can clone the repo.

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

### 1b. mise (provides Python for pre-commit)

`pre-commit` is a Python tool, and this repo's git hooks depend on it. We use
[mise](https://mise.jdx.dev/) to install and pin a Python runtime without
touching your system Python.

▶ **Prompt:**
> Install `mise`, hook it into my shell, then use it to install the latest stable
> Python and set it as the global default. Verify `python3 --version` resolves
> through mise.

Manual:
```bash
brew install mise               # macOS
curl https://mise.run | sh      # Linux
winget install jdx.mise         # Windows

# add to your shell rc (zsh shown; use ~/.bashrc for bash)
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec $SHELL

mise use -g python@latest
python3 --version
```

- [ ] `mise --version` works
- [ ] `python3 --version` resolves (needed for `pre-commit`)

### 1c. FVM (Flutter Version Management)

This repo pins Flutter via `.fvmrc` (currently **3.44.0**). FVM installs and
isolates that exact version so you don't fight your system Flutter.

▶ **Prompt:**
> Install FVM following https://fvm.app/documentation/getting-started/installation
> for my OS (use the standalone install script or package manager, not the
> deprecated `flutter pub global` method). Verify `fvm --version`.

Manual:
```bash
brew tap leoafarias/fvm && brew install fvm    # macOS
curl -fsSL https://fvm.app/install.sh | bash   # Linux
choco install fvm                              # Windows (or see docs)

fvm --version
```

- [ ] `fvm --version` works

> FVM downloads the pinned Flutter **after** cloning (Step 2c), via `fvm install`.

### 1d. DCM (Dart Code Metrics)

DCM runs in the pre-commit hook (`dcm analyze`). Install the CLI per the
[official docs](https://dcm.dev/docs/getting-started/for-developers/installation/).

▶ **Prompt:**
> Install the DCM CLI by following
> https://dcm.dev/docs/getting-started/for-developers/installation/ for my OS.
> Verify with `dcm --version`.

Manual:
```bash
brew tap CQLabs/dcm && brew install dcm    # macOS
# Linux / Windows — see the docs link above
dcm --version
```

> **License.** Your DCM license details were sent to your work email. If you
> can't find them, request a license from the team lead. Activate when prompted
> by the CLI.

- [ ] `dcm --version` works
- [ ] DCM license activated (check your email / request one)

### 1e. Sentry CLIs (two different tools)

There are **two** Sentry command-line tools and we use both — don't confuse them:

| Binary | Purpose | Install |
|--------|---------|---------|
| **`sentry`** | Query Sentry **issues & the API** directly. This is the **primary** one for local dev. | https://cli.sentry.dev/getting-started/ |
| **`sentry-cli`** | Upload **releases & debug symbols**; matches the `sentry_dart_plugin` in `pubspec.yaml`. | https://sentry.io/get-cli/ |

▶ **Prompt:**
> Install **both** Sentry CLIs:
> 1. The `sentry` CLI from https://cli.sentry.dev/getting-started/ (issues/API
>    access — the one I use most). Follow that page's install method for my OS and
>    verify `sentry --version`.
> 2. The `sentry-cli` symbol-upload tool. Verify `sentry-cli --version`.
> Don't log either in yet — I'll add auth when I need it.

Manual:
```bash
# sentry (issues/API) — primary for local dev; see
# https://cli.sentry.dev/getting-started/ for the install command for your OS, then:
sentry --version

# sentry-cli (symbol/release uploads)
curl -sL https://sentry.io/get-cli/ | bash    # macOS / Linux
npm install -g @sentry/cli                     # any OS (Node)
winget install Sentry.sentry-cli               # Windows
sentry-cli --version
```

- [ ] `sentry --version` works (primary — issues/API)
- [ ] `sentry-cli --version` works (symbol uploads)

### 1f. Atlassian CLI (`acli`)

For Jira/Confluence from the terminal.

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
acli jira auth login            # follow the prompts
```

- [ ] `acli --version` works
- [ ] `acli jira auth login` succeeds

---

## Step 2 — Clone & bootstrap the project

### 2a. Clone (as a sibling of the skills repo)

The `flutter-app` repo must sit **next to** the `skills` repo, not inside it.
Run this from the `skills` repo root so the clone lands at `../flutter-app`:

▶ **Prompt:**
> From the `skills` repo, clone `hoopit/flutter-app` with `gh` into the parent
> directory so it ends up as a sibling (`../flutter-app`), then `cd` into it.

Manual:
```bash
# run from the skills repo root
gh repo clone hoopit/flutter-app ../flutter-app
cd ../flutter-app
```

Resulting layout:
```
…/
├── skills/          # this repo (onboarding skills)
└── flutter-app/    # the Flutter app — sibling, just cloned
```

- [ ] Repo cloned to `../flutter-app` and you're inside it

### 2b. direnv / FVM env (optional, macOS/Linux)

The repo ships a `.envrc` that sets `FVM_PROJECT_ROOT`. If you use
[direnv](https://direnv.net/):
```bash
brew install direnv        # or your package manager
direnv allow
```

- [ ] `.envrc` allowed (or skipped if you don't use direnv)

### 2c. Install the project Flutter version & dependencies

▶ **Prompt:**
> In the flutter-app repo, run `fvm install` to fetch the pinned Flutter version
> from `.fvmrc`, then `fvm flutter pub get`. Also run `pub get` inside
> `packages/hoopit_api` and `packages/network_bloc`. Then run `fvm flutter doctor`
> and help me resolve anything that isn't a checkmark.

Manual:
```bash
fvm install                      # downloads Flutter 3.44.0 per .fvmrc
fvm flutter pub get
(cd packages/hoopit_api && fvm flutter pub get)
(cd packages/network_bloc && fvm flutter pub get)
fvm flutter doctor
fvm flutter doctor --android-licenses    # accept Android licenses
```

- [ ] `fvm flutter doctor` is clean (Android toolchain + a device/emulator)

> **Always use `fvm flutter` / `fvm dart`** in this repo — never bare
> `flutter`/`dart`.

### 2d. Code generation (build_runner)

`build_runner` generates code in **two** places — the app and the `hoopit_api`
package — and they're watched separately.

▶ **Prompt:**
> Run a one-off `build_runner build` for both the app and the `hoopit_api`
> package so all generated files exist.

Manual — one-off build:
```bash
# app
fvm flutter pub run build_runner build --delete-conflicting-outputs
# API package
(cd packages/hoopit_api && fvm dart run build_runner build --delete-conflicting-outputs)
```

For ongoing work, run the **watchers** (Android Studio run configs, or CLI):

| Run config (IDEA) | Equivalent command | Working dir |
|-------------------|--------------------|-------------|
| **build_runner: watch (app)** | `fvm flutter pub run build_runner watch --delete-conflicting-outputs` | repo root |
| **build_runner: watch (api)** | `fvm dart run build_runner watch --delete-conflicting-outputs` | `packages/hoopit_api` |

> ⚠️ **The API watcher is its own thing.** Whenever you change an API **model**
> in `packages/hoopit_api`, the **build_runner: watch (api)** config must be
> running (or run a one-off build there) — the app watcher does **not** cover the
> package. Keep both watchers running during normal development.

- [ ] One-off build succeeded for app **and** `hoopit_api`
- [ ] No missing `*.g.dart` / generated-file analyzer errors

### 2e. Localization (gen-l10n)

Localization files are generated from the ARB sources. This is the
**generate l8n** run config in Android Studio.

▶ **Prompt:**
> Regenerate the localization files for me.

Manual (matches the **generate l8n** IDEA run config):
```bash
fvm flutter gen-l10n && fvm flutter pub run localizely_sdk:generate
```

> Run this **whenever you add or change `.arb` files** to update the generated
> localization Dart. Don't hand-edit generated files.

- [ ] l10n generated (`app_localizations*.dart` present and up to date)

### 2f. Install git hooks (pre-commit)

This wires up format, analyze, gen-l10n, DCM, and ARB-sort hooks. Requires the
Python from Step 1b and DCM from Step 1d.

▶ **Prompt:**
> Install `pre-commit` (via pipx or pip), then install this repo's hooks for both
> commit and push stages using `.pre-commit-config.yaml`. Run
> `pre-commit run --all-files` once and help me fix any failures.

Manual:
```bash
pipx install pre-commit        # or: pip install pre-commit
pre-commit install --hook-type pre-commit --hook-type pre-push
pre-commit run --all-files     # warms caches; fix anything that fails
```

- [ ] Hooks installed for **both** pre-commit and pre-push
- [ ] `pre-commit run --all-files` passes (DCM, dart-format, analyze, sort-arb)

---

## Step 3 — IDE

Pick one. **Android Studio is recommended** because it manages the Android SDK
and emulators for you, and it ships the run configs referenced above
(build_runner watchers, generate l8n, the flavor launch configs).

### Android Studio (recommended)

▶ **Prompt:**
> Install Android Studio for my OS, then tell me the exact in-app steps to:
> install the Flutter & Dart plugins, point the Flutter SDK at this repo's FVM
> path (`.fvm/flutter_sdk`), and create an Android emulator.

Manual:
```bash
brew install --cask android-studio    # macOS
winget install Google.AndroidStudio   # Windows
# Linux — download from https://developer.android.com/studio
```
Then inside Android Studio:
- Install **Flutter** + **Dart** plugins (Settings → Plugins).
- Set Flutter SDK path to `<repo>/.fvm/flutter_sdk`.
- Create a virtual device (Device Manager → Add a device).
- The shared run configs (build_runner watchers, generate l8n, flavor launchers)
  appear in the run-config dropdown automatically.

- [ ] Flutter & Dart plugins installed
- [ ] Flutter SDK points at `.fvm/flutter_sdk`
- [ ] An emulator/device boots

### VS Code (alternative)

▶ **Prompt:**
> Install VS Code and the Flutter + Dart extensions, then make it use this repo's
> FVM SDK (`dart.flutterSdkPath` = `.fvm/flutter_sdk`).

Manual:
```bash
brew install --cask visual-studio-code        # macOS
winget install Microsoft.VisualStudioCode     # Windows
code --install-extension Dart-Code.flutter
```
Add to workspace `.vscode/settings.json`:
```json
{ "dart.flutterSdkPath": ".fvm/flutter_sdk" }
```
(The repo already ships `flutter-app.code-workspace` and a `.vscode/` folder.)

- [ ] Flutter & Dart extensions installed
- [ ] `dart.flutterSdkPath` set to `.fvm/flutter_sdk`

---

## Step 4 — Figma MCP (for UI work)

UI tasks start by reading the Figma design, so wire up the Figma MCP server in
Claude Code. We use the **default (hosted) Figma MCP server** — *not* the local
Dev Mode desktop server.

▶ **Prompt:**
> Add the default hosted Figma MCP server to Claude Code and authenticate it.
> Then verify the `mcp__Figma__get_design_context` tool is available.

Manual:
```bash
claude mcp add --transport http figma https://mcp.figma.com/mcp
```
- Restart Claude Code, run `/mcp`, and complete the Figma sign-in for the
  `figma` server.

- [ ] `figma` MCP server connected (check `/mcp`)
- [ ] `mcp__Figma__get_design_context` / `get_screenshot` callable

---

## Step 5 — Run the app

The project uses **flavors**; each has its own entrypoint under `lib/`:

| Entrypoint | Use |
|------------|-----|
| `lib/main_staging.dart` | Staging backend (default for most dev) |
| `lib/main_staging_local.dart` | Staging build against a local API on `localhost:8080` |
| `lib/main_prod.dart` | Production backend |
| `*_ngrok.dart` | Backend tunneled via ngrok |

In Android Studio these map to run configs like **remote_staging**,
**local_staging**, **remote_prod**, etc.

▶ **Prompt:**
> Launch the app on my emulator using the staging flavor and tell me if the build
> fails for any reason.

Manual — emulator/device:
```bash
fvm flutter run -t lib/main_staging.dart
```

Manual — web preview (needs a local API on `localhost:8080`):
```bash
fvm flutter run -d web-server --web-port 3000 --web-hostname localhost \
  -t lib/main_staging_local.dart
# → http://localhost:3000
```

- [ ] App builds and launches on a device/emulator

---

## Final verification checklist

- [ ] `claude` runs and is authenticated
- [ ] `gh auth status` ✓ · `acli --version` ✓
- [ ] `flutter-app` cloned as a sibling of `skills` (`../flutter-app`)
- [ ] `fvm flutter doctor` clean (Android licenses accepted)
- [ ] `dcm --version` ✓ and license activated
- [ ] `sentry --version` ✓ (issues/API — primary) · `sentry-cli --version` ✓ (symbol uploads)
- [ ] `python3 --version` via mise ✓ · `pre-commit` hooks installed (commit **and** push)
- [ ] `fvm flutter pub get` + build_runner (app **and** API) + gen-l10n all succeed
- [ ] `pre-commit run --all-files` passes
- [ ] IDE runs the app on an emulator with the staging flavor
- [ ] Figma MCP connected in Claude Code

---

## Pointers & conventions

- **Always `fvm flutter` / `fvm dart`** — never bare `flutter`/`dart`.
- **Two build_runner watchers**: app (repo root) and **API** (`packages/hoopit_api`).
  Run the API watcher / one-off build on **every API model change**.
- **Localization**: edit ARB files, then run the **generate l8n** config
  (`fvm flutter gen-l10n && fvm flutter pub run localizely_sdk:generate`).
- **Branching/PRs** derive names from the Jira ticket key — query tickets with `acli`.
- Team docs: the [Wiki](https://github.com/hoopit/flutter-app/wiki).

---

### Suggested one-shot prompt for Claude Code

> Read this ONBOARDING.md and set up this machine for the Hoopit flutter-app. Go
> step by step, detect my OS, install each tool with whatever package manager I
> have, clone `flutter-app` as a sibling of the `skills` repo (`../flutter-app`),
> pause for anything that needs my credentials (GitHub, Atlassian, Figma, DCM
> license), and after each step run the verification command and report the
> result. Stop and ask me before any step that needs `sudo`, admin rights, or a
> browser login.

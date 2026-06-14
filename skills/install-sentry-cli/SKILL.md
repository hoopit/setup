---
name: install-sentry-cli
description: Install the Sentry CLI (the `sentry` binary from cli.sentry.dev) and authenticate it. Use when a developer needs to install the Sentry CLI, set up `sentry` for the first time, run `sentry auth login`, or fix a missing/unauthenticated `sentry` command. This is the install/auth bootstrap — for using the CLI once it's set up, see the `sentry-cli` skill.
---

# Install the Sentry CLI

Bootstrap the `sentry` CLI on a developer's machine: install it, log in, and
verify. Based on https://cli.sentry.dev/getting-started/.

> This installs the **`sentry`** binary (issues / API access — the one used most
> in local dev). It's distinct from `sentry-cli` (the release/symbol-upload tool).
> Don't confuse the two.

## 1. Install

Detect the OS and pick the matching method. Verify with `sentry --version` after.

**macOS / Linux (primary — curl script):**
```bash
curl https://cli.sentry.dev/install -fsS | bash
```

**Homebrew (macOS):**
```bash
brew install getsentry/tools/sentry
```

**Windows:** run the curl command above inside **Git Bash**, **MSYS2**, or **WSL**.
Or, on any OS with Node.js 22.15+:
```bash
npm install -g sentry        # or: pnpm add -g sentry / yarn global add sentry / bun add -g sentry
```

Supported platforms: macOS (x64/arm64), Linux (x64/arm64, glibc & musl), Windows (x64).

- [ ] `sentry --version` prints a version

> If the freshly installed `sentry` isn't found, the install script printed a line
> to add it to your `PATH` (e.g. `~/.local/bin`) — apply it and re-open the shell.

## 2. Authenticate

Use the OAuth device flow (recommended) — it opens a browser URL with a code to authorize:
```bash
sentry auth login
```

> **This step needs the user.** It launches a browser sign-in — pause and let the
> developer complete it; don't try to automate the browser flow.

Non-interactive / CI alternative (token from Sentry account settings → Auth Tokens):
```bash
sentry auth login --token YOUR_SENTRY_API_TOKEN
```

## 3. Verify authentication (required to finish)

```bash
sentry auth status
```

**Do not report this skill complete until `sentry auth status` confirms an
authenticated session** (it lists the signed-in org/user). If it reports *not
authenticated* or errors, the setup is **not** done — return to step 2, re-run
`sentry auth login`, and check again. Loop until it confirms.

- [ ] `sentry auth status` shows you authenticated (org/user listed)

To sign out later: `sentry auth logout`.

## Notes

- **Self-hosted Sentry:** point at a custom instance with `SENTRY_URL`.
- **Pin a version** (CI/containers): set `SENTRY_VERSION` before the install script,
  or `... | bash -s -- --version nightly` for nightly builds.

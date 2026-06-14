---
name: install-coderabbit-cli
description: Install the CodeRabbit CLI, authenticate it, and wire up its Claude Code plugin (the `/coderabbit:review` slash command). Use when a developer needs to install CodeRabbit, set up `coderabbit` for the first time, run `coderabbit auth login`, or enable CodeRabbit reviews inside Claude Code. This is the install/auth bootstrap — for running reviews once it's set up, use the `code-review` skill.
---

# Install the CodeRabbit CLI

Bootstrap CodeRabbit on a developer's machine: install the CLI, log in, and
install its Claude Code plugin. Based on
https://docs.coderabbit.ai/cli/claude-code-integration.

> **Prerequisites:** Claude Code installed and working. **Windows users need WSL**
> (Windows Subsystem for Linux) — run everything below inside WSL.

## 1. Install the CLI

Detect the OS and pick a method, then verify.

**macOS / Linux / WSL (primary — install script):**
```bash
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
```

**Homebrew (macOS):**
```bash
brew install coderabbit
```

- [ ] `coderabbit --version` prints a version (re-open the shell first if the
  installer added it to your `PATH`)

## 2. Authenticate

Opens a browser window to complete sign-in:
```bash
coderabbit auth login
```

> **This step needs the user.** It launches a browser sign-in — pause and let the
> developer finish it; don't try to drive the browser flow.

Verify (required to finish):
```bash
coderabbit auth status
```

**Do not report this skill complete until `coderabbit auth status` confirms a
signed-in session.** If it reports *not authenticated* or errors, the setup is
**not** done — re-run `coderabbit auth login` and check again. Loop until it
confirms.

- [ ] `coderabbit auth status` shows you signed in

## 3. Install the Claude Code plugin

From inside Claude Code:
```
/plugin install coderabbit
```

Or from the command line:
```bash
claude plugin install coderabbit
```

The plugin auto-verifies the CLI install and auth on first use.

## 4. Verify the integration

In Claude Code, run:
```
/coderabbit:review
```

- [ ] `/coderabbit:review` runs a review without complaining about CLI/auth

## Usage cheatsheet (once set up)

Slash command (in Claude Code):
```
/coderabbit:review                 # all changes
/coderabbit:review committed       # committed changes only
/coderabbit:review uncommitted     # uncommitted changes only
/coderabbit:review --base main     # against a specific branch
```

Direct CLI output modes:
```bash
coderabbit --agent         # structured JSON (for agents)
coderabbit --plain         # human-readable terminal output
coderabbit --interactive   # terminal UI for manual review
```

Natural-language triggers also work inside Claude Code ("review my code",
"check for security issues"). For the day-to-day review workflow, see the
`code-review` skill.

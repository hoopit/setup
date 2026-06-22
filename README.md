# Hoopit — `skills`

Hoopit's **agent skills**, distributed as a
[Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces).
Each plugin lives under [`plugins/<group>/`](plugins/) and bundles its skills.

## Install

Everything below runs from your shell — no need to open Claude Code first. Add the
marketplace once, then install the plugin(s) you want:

```bash
claude plugin marketplace add hoopit/skills
```

Install `hoopit-dev` **in-project** (`--scope project` commits it to the repo's
`.claude/settings.json`, so everyone on the project gets it):

```bash
claude plugin install hoopit-dev@hoopit-skills --scope project
```

Install `hoopit-misc` **globally** (default `user` scope, available across all your
projects):

```bash
claude plugin install hoopit-misc@hoopit-skills
```

To manually pull the latest, update the marketplace and then the plugins:

```bash
claude plugin marketplace update hoopit-skills
claude plugin update hoopit-dev@hoopit-skills
claude plugin update hoopit-misc@hoopit-skills
```

> These are also available inside Claude Code as the `/plugin` slash commands
> (e.g. `/plugin install hoopit-misc@hoopit-skills`).

### Plugins

| Plugin | What's in it |
|--------|--------------|
| `hoopit-onboarding` | Take a fresh machine to a working `hoopit/api` or `hoopit/flutter-app` checkout, plus the supporting CLIs |
| `hoopit-dev` | Day-to-day dev workflows and CLIs: Jira/Sentry issues, PR review, Atlassian, CircleCI |
| `hoopit-misc` | Odds and ends: status line |
| `hoopit-product` | Product work: stress-test plans and ideas against the domain model, sharpen terminology, and produce a PRD |
| `hoopit-matt-picks` | A curated set of [mattpocock/skills](https://github.com/mattpocock/skills), tracking upstream |

For the exact skills inside each plugin, browse its
[`plugins/<group>/skills/`](plugins/) directory. The onboarding skills clone their
project repo as a **sibling** of wherever you run them (e.g. `../api`,
`../flutter-app`).

`hoopit-matt-picks` is sourced from Matt's repo, so it picks up his latest when you
run the update commands above.

## How it works

The marketplace is declared in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json). Each Hoopit
plugin is a self-contained directory under `plugins/<group>/` with its own
`.claude-plugin/plugin.json` and a `skills/` folder; the marketplace entry just
points `source` at that directory. Skills are auto-discovered from the plugin's
own `skills/` folder, so a plugin exposes **only** its own skills — this is why
each group gets its own directory rather than a shared top-level `skills/` (a
single shared folder would leak every skill into every plugin).

`hoopit-matt-picks` is the exception: it uses a `github` source pointing at
`mattpocock/skills` with `strict: true` and an explicit `skills` array listing
the specific skill paths to surface (a marketplace can list a plugin fetched from
a different repo). `strict: true` makes that curated list authoritative, so it
overrides the upstream plugin's own manifest instead of conflicting with it.

> **Adding or removing a Hoopit skill?** When working in this repo, Claude has a
> project-local `create-hoopit-skill` skill (under `.claude/skills/`) that
> documents the procedure and the files to keep in sync.

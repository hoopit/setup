---
name: create-hoopit-skill
description: Conventions for authoring skills in the hoopit/skills repo — keep skills project-agnostic and put each skill in the right plugin directory. Use when adding, editing, or removing a skill in this repo.
---

# Authoring skills in hoopit/skills

This repo is a **distribution** of skills, shipped as a Claude Code plugin
marketplace: one skill is installed into many different Hoopit repos (`api`,
`flutter-app`, …). A skill written here runs in all of them, so it must not assume
it's running in any one of them.

Layout: each plugin is a self-contained directory `plugins/<group>/` with its own
`.claude-plugin/plugin.json` and a `skills/` folder. A skill lives at
`plugins/<group>/skills/<name>/SKILL.md`. Skills are auto-discovered from the
plugin's own `skills/` folder, so a plugin exposes exactly the skills in its
directory — **never** point multiple plugins at one shared `skills/` folder, or
every plugin leaks every skill.

> This skill itself is **not** distributed — it lives in the repo's `.claude/skills/`,
> which no plugin's `source` points at, so the marketplace never picks it up. It
> exists only to guide authoring while working in this repo.

## Rule 1 — skills must be project-agnostic

**Never bake a project-specific term into a skill.** No repo slugs, service
names, env-file names, role names, paths, ticket prefixes, URLs, queue names —
nothing that is true for one repo but not another.

Instead:

- **Derive it at runtime** when you can. E.g. an org/repo that's already present
  in a URL or in `git remote` — parse it, don't hard-code it.
- **Defer to `CLAUDE.md`** otherwise. Anything project-specific the skill needs
  belongs in the `CLAUDE.md` of *every* repo the skill is installed into. The
  skill should say "check the current repo's `CLAUDE.md` for X" rather than
  naming X. Keeping those facts in `CLAUDE.md` is part of shipping the skill —
  if you add a skill that needs a new fact, add that fact to each target repo's
  `CLAUDE.md`.

❌ `The org/repo for this project is hoopit/api.`
✅ `Parse the org/repo from the URL; if absent, see the repo's CLAUDE.md.`

Skill content should read identically useful whether Claude is in `api`,
`flutter-app`, or a repo that doesn't exist yet.

## Rule 2 — put the skill in the right plugin

Because skills are auto-discovered from each plugin's `skills/` folder, the common
cases are simple:

- **Add a skill to an existing group**: create
  `plugins/<group>/skills/<name>/SKILL.md` (plus any bundled resources). That's
  it — no `marketplace.json` edit, it's auto-discovered.
- **Remove a skill**: delete its directory.
- **Move a skill between groups**: move its directory to the other plugin's
  `skills/`.

`marketplace.json` only changes when the set of **plugins (groups)** changes. To
add a new group:

1. Create `plugins/<group>/.claude-plugin/plugin.json` (`name` + `description`)
   and a `plugins/<group>/skills/` folder with the skills.
2. Add a plugin entry to `.claude-plugin/marketplace.json` — `name` +
   `"source": "./plugins/<group>"`. Don't drop the top-level `owner`; Claude Code
   refuses to parse the file without it. Validate the JSON.
3. Add a row to the README's plugin table.

The `README.md` does **not** list individual skills (deliberately — it was a
maintenance burden), so adding a skill needs no README change.

`hoopit-matt-picks` is special: it has a `github` source pointing at
`mattpocock/skills` with `strict: true` and an explicit `skills` array, so its
skills resolve against *that* repo. `strict: true` is required because the
upstream plugin ships its own manifest; it makes our `skills` list authoritative
instead of conflicting with theirs. To curate it, edit only its `skills` array in
the manifest.

## Checklist

- [ ] Skill body contains no project-specific terms (Rule 1)
- [ ] Any project-specific facts it relies on are added to each target repo's `CLAUDE.md`
- [ ] Skill lives at `plugins/<group>/skills/<name>/SKILL.md`
- [ ] `marketplace.json` touched only if a plugin/group was added or removed (valid JSON)

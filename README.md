# Hoopit — `setup`

The first repo a new Hoopit developer clones. It ships **Claude Code onboarding
skills** that take a brand-new machine to a working checkout of each Hoopit
project — installing tooling, cloning the project repo **as a sibling of this
one**, and bootstrapping it until it builds, runs, and tests cleanly.

## How to use it

1. Install Claude Code (see any skill's Step 0):
   ```bash
   curl -fsSL https://claude.com/install.sh | bash   # macOS / Linux
   ```
2. Clone this repo and start Claude Code **from inside it** so the skills load:
   ```bash
   gh repo clone hoopit/setup
   cd setup
   claude
   ```
3. Ask for the onboarding you want — Claude picks up the matching skill:
   - *"Onboard me to the Flutter app"* → **flutter-onboarding**
   - *"Set up the API / backend"* → **api-onboarding**

Each skill goes step by step, detects your OS, installs tooling with whatever
package manager you have, pauses for credential/`sudo` steps, and verifies as it
goes.

## Why repos land as siblings

The skills clone each project **next to** `setup`, never inside it:

```
…/
├── setup/          # this repo (onboarding skills)
├── flutter-app/    # cloned by flutter-onboarding
└── api/            # cloned by api-onboarding
```

This keeps the onboarding repo separate from the project checkouts and matches
the team's conventional `…/Hoopit/<repo>` layout.

## Skills

| Skill | Onboards | Detail |
|-------|----------|--------|
| `flutter-onboarding` | `hoopit/flutter-app` | [SKILL.md](.claude/skills/flutter-onboarding/SKILL.md) · [ONBOARDING.md](.claude/skills/flutter-onboarding/ONBOARDING.md) |
| `api-onboarding` | `hoopit/api` | [SKILL.md](.claude/skills/api-onboarding/SKILL.md) · [ONBOARDING.md](.claude/skills/api-onboarding/ONBOARDING.md) |

Each skill is a `SKILL.md` (the orchestration contract Claude reads) plus a
detailed, platform-aware `ONBOARDING.md` it follows step by step. The
`ONBOARDING.md` files also stand alone if you'd rather follow them by hand.

## Adding a new project's onboarding

1. Create `.claude/skills/<project>-onboarding/`.
2. Write `SKILL.md` (a concise driver: how to run it, where the repo goes as a
   sibling, the step sequence, key conventions) and `ONBOARDING.md` (the detailed
   walkthrough with ▶ prompts, manual commands, and verification checkboxes).
3. Make the clone step target `../<project>` so it lands as a sibling.
4. Add a row to the table above.

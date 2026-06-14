#!/usr/bin/env bash
#
# Hoopit skills installer.
#
# Installs the curated Hoopit skill set into your coding agent(s) using the
# Vercel `skills` CLI (https://skills.sh). It installs two things:
#
#   1. A curated subset of mattpocock/skills — pulled straight from his repo, so
#      `npx skills update` keeps them current automatically. His other skills are
#      intentionally NOT installed (no manual picker — the subset is fixed below).
#   2. Hoopit's own skills from hoopit/setup, organized into groups (see below).
#
# Re-run any time; it is safe to repeat. To update later: `npx skills update`.
#
# Usage:
#   ./install.sh                                        # all groups, Claude Code, global
#   SKILL_GROUPS="onboarding" ./install.sh              # only the onboarding group
#   SKILL_GROUPS="onboarding,integrations" ./install.sh # several groups
#   EXCLUDE_GROUPS="misc" ./install.sh                  # everything except misc
#   AGENTS="claude-code,universal" ./install.sh    # also the generic ~/.config/agents/skills
#   AGENTS="" ./install.sh                          # pick agents interactively (TTY only)
#   SCOPE=-p ./install.sh                           # project-local instead of global
#   curl -fsSL https://raw.githubusercontent.com/hoopit/setup/main/install.sh | bash
#
set -euo pipefail

# Install scope: -g (global, user-level) by default; set SCOPE=-p for project.
SCOPE="${SCOPE:--g}"

# Agent target(s). Default: Claude Code only.
#   - Override with a comma-separated list of agent keys, e.g.
#       AGENTS="claude-code,universal"   (valid keys: see `npx skills add <repo> -h`)
#   - Set AGENTS="" to choose interactively. NOTE: an interactive picker needs a
#     real terminal, so it does NOT work through the `curl | bash` one-liner —
#     use a pinned list (or run install.sh from a checkout) in that case.
# Using `${AGENTS-claude-code}` (single dash) so an explicit empty value is kept
# as "interactive", while leaving it unset falls back to the default.
AGENTS="${AGENTS-claude-code}"

# --- Hoopit skill groups -----------------------------------------------------
# The groups below mirror .claude-plugin/marketplace.json (which is what makes
# the groups show up in the `skills` interactive picker). Keep the two in sync.
# The `skills` CLI has no native --group / --exclude flags, so this installer
# expands groups into a `-s` skill list itself.
GROUP_ONBOARDING="api-onboarding flutter-onboarding install-sentry-cli install-coderabbit-cli"
GROUP_INTEGRATIONS="atlassian-cli handle-jira-issue"
GROUP_MISC="setup-statusline grill-my-idea"
ALL_GROUPS="onboarding integrations misc"

# Which groups to install / exclude (comma or space separated).
# NB: not named GROUPS — that's a reserved bash variable (user group IDs).
SKILL_GROUPS="${SKILL_GROUPS:-$ALL_GROUPS}"
EXCLUDE_GROUPS="${EXCLUDE_GROUPS:-}"

# Resolve a group name to its skill list (via indirect expansion).
group_skills() {
	local g key var
	g="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
	var="GROUP_${g%_}"
	printf '%s' "${!var-__UNKNOWN__}"
}

# Build the space-separated skill list from GROUPS minus EXCLUDE_GROUPS.
selected_skills=""
exclude_norm=" $(printf '%s' "$EXCLUDE_GROUPS" | tr ',' ' ') "
for g in $(printf '%s' "$SKILL_GROUPS" | tr ',' ' '); do
	case "$exclude_norm" in *" $g "*) continue ;; esac
	s="$(group_skills "$g")"
	if [ "$s" = "__UNKNOWN__" ]; then
		echo "warning: unknown group '$g' (known: $ALL_GROUPS) — skipping" >&2
		continue
	fi
	selected_skills="$selected_skills $s"
done
# Trim + comma-join for `-s`.
HOOPIT_SKILLS="$(printf '%s' "$selected_skills" | tr -s ' ' '\n' | sed '/^$/d' | paste -sd, -)"

# --- Curated subset of mattpocock/skills -------------------------------------
# Edit this list to change which of Matt's skills the team gets. Listing them
# explicitly with `-s` skips the interactive picker entirely and never surfaces
# his other skills.
MATT_SKILLS="caveman,write-a-skill,zoom-out,grill-with-docs,handoff"

# add_skills <package> <comma,separated,skills|*>
add_skills() {
	local pkg="$1" skills="$2"
	if [ -n "$AGENTS" ]; then
		# Deterministic: fixed agents, no prompts.
		npx -y skills@latest add "$pkg" -s "$skills" "$SCOPE" -a "$AGENTS" -y
	else
		# Interactive agent selection. Scope (-g/-p) and skills (-s) stay fixed,
		# so the only prompt is which agents to install to.
		npx -y skills@latest add "$pkg" -s "$skills" "$SCOPE"
	fi
}

echo "==> Agents: ${AGENTS:-<interactive>}   Scope: ${SCOPE}"
echo "==> Installing curated mattpocock skills: ${MATT_SKILLS}"
add_skills mattpocock/skills "$MATT_SKILLS"

if [ -z "$HOOPIT_SKILLS" ]; then
	echo "==> No Hoopit groups selected (GROUPS='${SKILL_GROUPS}', EXCLUDE_GROUPS='${EXCLUDE_GROUPS}') — skipping hoopit/setup"
else
	echo "==> Installing Hoopit skills: ${HOOPIT_SKILLS}"
	add_skills hoopit/setup "$HOOPIT_SKILLS"
fi

echo
echo "Done. Manage your skills with:"
echo "  npx skills list           # see what's installed and where"
echo "  npx skills update         # refresh all skills to latest (prompts to remove any deleted upstream)"
echo "  npx skills remove <name>  # remove a skill"

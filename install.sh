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
#   SKILL_GROUPS="onboarding,workflows" ./install.sh # several groups
#   EXCLUDE_GROUPS="misc" ./install.sh                  # everything except misc
#   AGENTS="claude-code,universal" ./install.sh    # also the generic ~/.config/agents/skills
#   AGENTS="" ./install.sh                          # pick agents interactively (TTY only)
#   SCOPE=-p ./install.sh                           # project-local instead of global
#   gh api repos/hoopit/setup/contents/install.sh -H "Accept: application/vnd.github.raw" | bash  # private repo: fetch with gh, not raw curl
#
set -euo pipefail

# Install scope: -g (global, user-level) by default; set SCOPE=-p for project.
SCOPE="${SCOPE:--g}"

# Agent target(s). Default: Claude Code + universal.
#   - We include `universal` so skills are symlinked rather than copied: the CLI
#     keeps one real copy in ~/.agents/skills and points ~/.claude/skills/<skill>
#     at it. With a single agent there's no shared store, so it writes copies.
#   - Override with a comma-separated list of agent keys, e.g.
#       AGENTS="claude-code"             (Claude Code only — copies, no symlinks)
#       AGENTS="claude-code,universal"   (valid keys: see `npx skills add <repo> -h`)
#   - Set AGENTS="" to choose interactively. NOTE: an interactive picker needs a
#     real terminal, so it does NOT work through the `curl | bash` one-liner —
#     use a pinned list (or run install.sh from a checkout) in that case.
# Using `${AGENTS-...}` (single dash) so an explicit empty value is kept as
# "interactive", while leaving it unset falls back to the default.
AGENTS="${AGENTS-claude-code,universal}"

# --- Hoopit skill groups -----------------------------------------------------
# The groups below mirror .claude-plugin/marketplace.json (which is what makes
# the groups show up in the `skills` interactive picker). Keep the two in sync.
# The `skills` CLI has no native --group / --exclude flags, so this installer
# expands groups into a `-s` skill list itself.
GROUP_ONBOARDING="api-onboarding flutter-onboarding install-sentry-cli install-coderabbit-cli"
GROUP_WORKFLOWS="handle-jira-issue fix-sentry-issue review-github-comments"
GROUP_TOOLS="atlassian-cli"
GROUP_MISC="setup-statusline grill-my-idea"
ALL_GROUPS="onboarding workflows tools misc"

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
	local pkg="$1" skills="$2" s
	# The `skills` CLI matches each `-s` value as ONE skill name — a comma- or
	# space-separated list is treated as a single literal name and matches
	# nothing. So expand our comma list into a repeated `-s <name>` flag per
	# skill. The "*" wildcard is passed through unchanged as a single value.
	local sflags=()
	if [ "$skills" = "*" ]; then
		sflags=(-s '*')
	else
		for s in $(printf '%s' "$skills" | tr ',' ' '); do
			[ -n "$s" ] && sflags+=(-s "$s")
		done
	fi
	if [ -n "$AGENTS" ]; then
		# Deterministic: fixed agents, no prompts. `-a` no longer splits a comma
		# list either (same as `-s`), so expand AGENTS into one `-a` per agent.
		local aflags=() a
		for a in $(printf '%s' "$AGENTS" | tr ',' ' '); do
			[ -n "$a" ] && aflags+=(-a "$a")
		done
		npx -y skills@latest add "$pkg" "${sflags[@]}" "$SCOPE" "${aflags[@]}" -y
	else
		# Interactive agent selection. Scope (-g/-p) and skills (-s) stay fixed,
		# so the only prompt is which agents to install to.
		npx -y skills@latest add "$pkg" "${sflags[@]}" "$SCOPE"
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

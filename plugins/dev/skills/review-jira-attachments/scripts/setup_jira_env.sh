#!/usr/bin/env bash
# Set up / verify the Jira env file used by the review-jira-attachments skill.
#
# The file holds the two values needed for REST Basic auth:
#   JIRA_EMAIL       — your Atlassian login (auto-filled from acli)
#   JIRA_API_TOKEN   — an Atlassian API token (you must supply this; acli keeps
#                      its own secret encrypted in the keyring and never exposes
#                      a reusable Basic-auth token, so it cannot be pulled out)
#
# Usage:
#   setup_jira_env.sh check                    # verify current config; exit 0 if it authenticates
#   setup_jira_env.sh write <API_TOKEN> [EMAIL]  # write the env file (email/URL from acli) and verify
#
# Override the target path with JIRA_ENV_FILE (defaults to ~/.config/hoopit/jira.env).
set -euo pipefail

ENV_FILE="${JIRA_ENV_FILE:-$HOME/.config/hoopit/jira.env}"

# Read a field from `acli jira auth status`, stripping any ANSI colour codes.
acli_field() {
  acli jira auth status 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | awk -F': *' -v k="$1" '$0 ~ k {print $2; exit}'
}

# probe EMAIL TOKEN BASE_URL -> exit 0 if /myself returns 200
probe() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' -u "$1:$2" \
        -H 'Accept: application/json' "$3/rest/api/3/myself")" = "200" ]
}

case "${1:-check}" in
  check)
    if [ ! -f "$ENV_FILE" ]; then
      echo "MISSING: $ENV_FILE does not exist"; exit 1
    fi
    set -a; . "$ENV_FILE"; set +a
    if [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
      echo "INCOMPLETE: $ENV_FILE must define both JIRA_EMAIL and JIRA_API_TOKEN"; exit 1
    fi
    BASE="${JIRA_BASE_URL:-https://$(acli_field Site)}"
    if [ "$BASE" = "https://" ]; then
      echo "NO_BASE_URL: set JIRA_BASE_URL, or run 'acli jira auth login' so the site can be read"; exit 1
    fi
    if probe "$JIRA_EMAIL" "$JIRA_API_TOKEN" "$BASE"; then
      echo "OK: authenticated as $JIRA_EMAIL at $BASE"; exit 0
    fi
    echo "INVALID: credentials in $ENV_FILE were rejected by $BASE (401/403)"; exit 1
    ;;

  write)
    TOKEN="${2:-}"
    if [ -z "$TOKEN" ]; then
      echo "usage: setup_jira_env.sh write <API_TOKEN> [EMAIL]"; exit 2
    fi
    EMAIL="${3:-$(acli_field Email)}"
    SITE="$(acli_field Site)"
    if [ -z "$EMAIL" ]; then
      echo "No email: acli is not logged in — pass it explicitly: write <TOKEN> you@hoopit.io"; exit 1
    fi
    if [ -z "$SITE" ]; then
      echo "No site: acli is not logged in — run 'acli jira auth login' first"; exit 1
    fi
    BASE="https://$SITE"
    if ! probe "$EMAIL" "$TOKEN" "$BASE"; then
      echo "Token rejected by $BASE for $EMAIL — re-check it was copied in full"; exit 1
    fi
    mkdir -p "$(dirname "$ENV_FILE")"
    ( umask 077; printf 'JIRA_API_TOKEN=%s\nJIRA_EMAIL=%s\n' "$TOKEN" "$EMAIL" > "$ENV_FILE" )
    chmod 600 "$ENV_FILE"
    echo "OK: wrote $ENV_FILE for $EMAIL at $BASE"
    ;;

  *)
    echo "usage: setup_jira_env.sh [check | write <API_TOKEN> [EMAIL]]"; exit 2
    ;;
esac

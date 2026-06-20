# --- claude account switcher ---
# Source this file from your ~/.zshrc:
#   source ~/Documents/"My Projects"/claude-account-switcher/claude-switch.sh
#
# Tokens are stored in the macOS Keychain under service "claude-oauth-<profile>".
# Each launch sets CLAUDE_CODE_OAUTH_TOKEN only for that process, so different
# terminals can run different accounts at the same time. The ~/.claude config
# (CLAUDE.md, settings.json, commands, agents) stays shared across all profiles.

# Run claude under a profile: cl personal | cl work
cl() {
  local profile="$1"; shift
  if [[ -z "$profile" ]]; then
    echo "usage: cl <profile> [claude args...]" >&2
    echo "profiles:" >&2
    cl-list >&2
    return 1
  fi
  local token
  token=$(security find-generic-password -s "claude-oauth-$profile" -a "$USER" -w 2>/dev/null)
  if [[ -z "$token" ]]; then
    echo "No token for profile '$profile'. Add one with: cl-add $profile" >&2
    return 1
  fi
  CLAUDE_CODE_OAUTH_TOKEN="$token" command claude "$@"
}

# Save a profile token into the Keychain: cl-add personal
# Get the token first with: claude setup-token (log in with the target account)
cl-add() {
  local profile="$1"
  [[ -z "$profile" ]] && { echo "usage: cl-add <profile>" >&2; return 1; }
  echo "Get a token first: claude setup-token  (log in with the '$profile' account)"
  # disable bracketed paste so pasted tokens aren't wrapped/duplicated with escape bytes
  print -n '\e[?2004l' 2>/dev/null
  local token
  read -rs "token?OAuth token for '$profile': "; echo
  print -n '\e[?2004h' 2>/dev/null
  # sanitize: drop bracketed-paste markers, cut at first control char, strip whitespace
  token="${token#$'\e[200~'}"
  token="${token%$'\e[201~'}"
  token=$(printf '%s' "$token" | LC_ALL=C sed 's/[[:cntrl:]].*//' | tr -d '[:space:]')
  [[ -z "$token" ]] && { echo "Empty token, aborted." >&2; return 1; }
  security add-generic-password -U -s "claude-oauth-$profile" -a "$USER" -w "$token" \
    && echo "Saved profile '$profile' (${#token} chars)."
}

# Remove a profile: cl-rm personal
cl-rm() {
  local profile="$1"
  [[ -z "$profile" ]] && { echo "usage: cl-rm <profile>" >&2; return 1; }
  security delete-generic-password -s "claude-oauth-$profile" -a "$USER" >/dev/null 2>&1 \
    && echo "Removed profile '$profile'." \
    || echo "No profile '$profile'." >&2
}

# List saved profiles
cl-list() {
  security dump-keychain 2>/dev/null \
    | grep '"svce"<blob>="claude-oauth-' \
    | sed 's/.*claude-oauth-/  /; s/"$//' \
    | sort -u
}

# Explicit convenience commands
alias claude-personal='cl personal'
alias claude-work='cl work'

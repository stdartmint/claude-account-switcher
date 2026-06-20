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
  # overwrite cleanly: drop any existing entry first, then store fresh (never duplicates)
  security delete-generic-password -s "claude-oauth-$profile" -a "$USER" >/dev/null 2>&1
  security add-generic-password -s "claude-oauth-$profile" -a "$USER" -w "$token" \
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

# Probe one profile: prints org-id (uniquely identifies the account).
# setup-token tokens lack profile scope, so email isn't available — org-id is
# the reliable discriminator (different ids = different accounts).
_cl_whoami_one() {
  local profile="$1"
  local tok; tok=$(security find-generic-password -s "claude-oauth-$profile" -a "$USER" -w 2>/dev/null)
  [[ -z "$tok" ]] && { echo "$profile: no token saved"; return 1; }
  local org
  org=$(curl -s -m 20 -D - -o /dev/null https://api.anthropic.com/v1/messages \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
    2>/dev/null | grep -i '^anthropic-organization-id:' | tr -d '\r' | awk '{print $2}')
  [[ -z "$org" ]] && { echo "$profile: auth FAILED (token invalid or expired)"; return 1; }
  echo "$profile: ok, org-id $org"
}

# Verify which account profiles map to: cl-whoami [profile]
# With no argument, checks every saved profile. Each check is a tiny (1-token) call.
cl-whoami() {
  if [[ -n "$1" ]]; then _cl_whoami_one "$1"; return $?; fi
  local profiles
  profiles=$(security dump-keychain 2>/dev/null \
    | grep '"svce"<blob>="claude-oauth-' \
    | sed 's/.*claude-oauth-//; s/"$//' | sort -u)
  [[ -z "$profiles" ]] && { echo "No profiles saved. Add one with: cl-add <profile>" >&2; return 1; }
  local p
  for p in ${(f)profiles}; do _cl_whoami_one "$p"; done
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

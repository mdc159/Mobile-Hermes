#!/usr/bin/env bash
# secrets-sync.sh — read desktop .env, filter to allowlist, emit phone .env.
# Never logs values, only key names.

SECRETS_ALLOWLIST=(
  OPENROUTER_API_KEY
  OPENAI_API_KEY
  GROQ_API_KEY
  ELEVENLABS_API_KEY
  TELEGRAM_BOT_TOKEN
  HONCHO_AUTH_TOKEN
  OPENROUTER_PRIMARY_MODEL
  OPENAI_FALLBACK_MODEL
)

declare -a _SECRETS_SYNCED=()
declare -a _SECRETS_ABSENT=()

_is_allowlisted() {
  local key="$1" k
  for k in "${SECRETS_ALLOWLIST[@]}"; do
    [ "$k" = "$key" ] && return 0
  done
  return 1
}

filter_to_phone_env() {
  local src="$1"
  _SECRETS_SYNCED=()
  _SECRETS_ABSENT=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      if _is_allowlisted "$key"; then
        if [ -n "$val" ]; then
          printf '%s=%s\n' "$key" "$val"
          _SECRETS_SYNCED+=("$key")
        else
          _SECRETS_ABSENT+=("$key")
        fi
      fi
    fi
  done < "$src"
}

append_phone_specific_env() {
  local out="$1"
  : "${HONCHO_BASE_URL:?HONCHO_BASE_URL not set}"
  : "${HONCHO_WORKSPACE:?HONCHO_WORKSPACE not set}"
  {
    printf 'HONCHO_BASE_URL=%s\n' "$HONCHO_BASE_URL"
    printf 'HONCHO_WORKSPACE=%s\n' "$HONCHO_WORKSPACE"
  } >> "$out"
}

summary_log() {
  printf '[secrets-sync] synced: %s\n' "${_SECRETS_SYNCED[*]:-<none>}" >&2
  printf '[secrets-sync] absent: %s\n' "${_SECRETS_ABSENT[*]:-<none>}" >&2
}

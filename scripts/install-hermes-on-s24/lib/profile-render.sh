#!/usr/bin/env bash
# profile-render.sh — substitute %%KEY%% placeholders in profile templates
# from environment variables. Fails fast if any placeholder has no value.

render_profile() {
  local template="$1"
  [ -f "$template" ] || { echo "template not found: $template" >&2; return 1; }

  local content
  content=$(cat "$template")

  # Find all %%KEY%% placeholders.
  local placeholders
  placeholders=$(grep -oE '%%[A-Z_][A-Z0-9_]*%%' "$template" | sort -u || true)

  for ph in $placeholders; do
    local key="${ph#%%}"; key="${key%%%%}"
    local val="${!key:-}"
    if [ -z "$val" ]; then
      echo "missing env value for placeholder $ph" >&2
      return 1
    fi
    content=${content//"$ph"/"$val"}
  done

  printf '%s\n' "$content"
}

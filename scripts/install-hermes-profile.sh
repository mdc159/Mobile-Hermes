#!/usr/bin/env bash
# install-hermes-profile.sh
# ---------------------------------------------------------------------------
# Install a fresh, isolated Hermes Agent profile bound to an existing local
# Honcho instance. Idempotent: re-runnable safely.
#
# What it does:
#   1. Run upstream Hermes installer with HERMES_HOME pinned (skip wizard)
#   2. Move bundled skills out of ~/.hermes/ if installer leaks them there
#   3. Replace the auto-created ~/.local/bin/hermes symlink with a wrapper
#      that pins HERMES_HOME, optionally under a custom command name
#   4. Write $HERMES_HOME/honcho.json with isolated workspace + peer + ai-peer
#   5. Activate honcho as memory.provider in config.yaml
#   6. Pre-create the Honcho workspace + peers (idempotent get-or-create)
#   7. Sanity-check via `<command> doctor` and `<command> memory status`
#
# Usage:
#   install-hermes-profile.sh [options]
#
# Options (all optional, defaults shown):
#   --hermes-home PATH         Profile dir       (default: $HOME/.hermes-paperclip)
#   --command NAME             Wrapper name      (default: hermes-paperclip)
#   --honcho-base-url URL      Honcho /v3 URL    (default: http://127.0.0.1:18000/v3)
#   --honcho-api-key KEY       API key           (default: local-no-auth)
#   --honcho-workspace NAME    Workspace name    (default: paperclip)
#   --honcho-peer NAME         Human peer        (default: $USER)
#   --honcho-ai-peer NAME      AI peer           (default: <command>)
#   --session-strategy KIND    per-directory|global (default: per-directory)
#   --also-link-hermes         Add ~/.local/bin/hermes -> wrapper symlink
#   -h, --help                 Show this help
#
# Prereqs: curl, uv (Astral), python3, jq optional. Honcho must be reachable
# at the given base URL.
# ---------------------------------------------------------------------------
set -euo pipefail

HERMES_HOME_DEFAULT="$HOME/.hermes-paperclip"
COMMAND_DEFAULT="hermes-paperclip"
BASE_URL_DEFAULT="http://127.0.0.1:18000/v3"
API_KEY_DEFAULT="local-no-auth"
WORKSPACE_DEFAULT="paperclip"
PEER_DEFAULT="$USER"
SESSION_STRATEGY_DEFAULT="per-directory"
ALSO_LINK_HERMES=false

HERMES_HOME=""
COMMAND_NAME=""
BASE_URL=""
API_KEY=""
WORKSPACE=""
PEER=""
AI_PEER=""
SESSION_STRATEGY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hermes-home)        HERMES_HOME="$2"; shift 2 ;;
        --command)            COMMAND_NAME="$2"; shift 2 ;;
        --honcho-base-url)    BASE_URL="$2"; shift 2 ;;
        --honcho-api-key)     API_KEY="$2"; shift 2 ;;
        --honcho-workspace)   WORKSPACE="$2"; shift 2 ;;
        --honcho-peer)        PEER="$2"; shift 2 ;;
        --honcho-ai-peer)     AI_PEER="$2"; shift 2 ;;
        --session-strategy)   SESSION_STRATEGY="$2"; shift 2 ;;
        --also-link-hermes)   ALSO_LINK_HERMES=true; shift ;;
        -h|--help)            sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

HERMES_HOME="${HERMES_HOME:-$HERMES_HOME_DEFAULT}"
COMMAND_NAME="${COMMAND_NAME:-$COMMAND_DEFAULT}"
BASE_URL="${BASE_URL:-$BASE_URL_DEFAULT}"
API_KEY="${API_KEY:-$API_KEY_DEFAULT}"
WORKSPACE="${WORKSPACE:-$WORKSPACE_DEFAULT}"
PEER="${PEER:-$PEER_DEFAULT}"
AI_PEER="${AI_PEER:-$COMMAND_NAME}"
SESSION_STRATEGY="${SESSION_STRATEGY:-$SESSION_STRATEGY_DEFAULT}"

WRAPPER="$HOME/.local/bin/$COMMAND_NAME"
HERMES_BIN="$HERMES_HOME/hermes-agent/venv/bin/hermes"
HONCHO_JSON="$HERMES_HOME/honcho.json"
HONCHO_API_BASE="${BASE_URL%/v3}"   # strip trailing /v3 for workspace API calls

log() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m⚠\033[0m %s\n' "$*" >&2; }

require() { command -v "$1" >/dev/null || { echo "missing prereq: $1" >&2; exit 1; }; }
require curl; require uv; require python3

# ---------------------------------------------------------------------------
# 1. Run upstream installer (idempotent: skips clone if already present)
# ---------------------------------------------------------------------------
mkdir -p "$HERMES_HOME"
if [[ -x "$HERMES_BIN" ]]; then
    ok "Hermes already installed at $HERMES_HOME (skipping clone)"
else
    log "Installing Hermes Agent into $HERMES_HOME ..."
    HERMES_HOME="$HERMES_HOME" \
        curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
        | bash -s -- --skip-setup --hermes-home "$HERMES_HOME"
fi

# ---------------------------------------------------------------------------
# 2. Move installer-leaked skills out of ~/.hermes/ into the new profile
# ---------------------------------------------------------------------------
if [[ -d "$HOME/.hermes/skills" && ! -d "$HOME/.hermes/skills/.user-owned" ]]; then
    log "Relocating installer-bundled skills from ~/.hermes/skills/ → $HERMES_HOME/skills/ ..."
    mkdir -p "$HERMES_HOME/skills"
    # mv contents (incl. dotfiles) without globbing surprises
    ( shopt -s dotglob nullglob
      for entry in "$HOME/.hermes/skills/"*; do
          mv -n "$entry" "$HERMES_HOME/skills/" 2>/dev/null || true
      done )
    rmdir "$HOME/.hermes/skills" 2>/dev/null || true
    ok "Skills relocated"
fi

# ---------------------------------------------------------------------------
# 3. Replace the auto-created symlink with a HERMES_HOME-pinning wrapper
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
# If installer dropped ~/.local/bin/hermes pointing at this install, kill it
# and create the named wrapper instead. (We do NOT clobber an unrelated
# existing $WRAPPER without checking.)
if [[ -L "$HOME/.local/bin/hermes" ]]; then
    target=$(readlink -f "$HOME/.local/bin/hermes" 2>/dev/null || true)
    if [[ "$target" == "$HERMES_BIN" ]]; then
        rm -f "$HOME/.local/bin/hermes"
    fi
fi
cat > "$WRAPPER" <<EOF
#!/bin/bash
export HERMES_HOME="$HERMES_HOME"
exec "$HERMES_BIN" "\$@"
EOF
chmod +x "$WRAPPER"
ok "Wrapper installed at $WRAPPER"

if [[ "$ALSO_LINK_HERMES" == true && ! -e "$HOME/.local/bin/hermes" ]]; then
    ln -s "$COMMAND_NAME" "$HOME/.local/bin/hermes"
    ok "Linked ~/.local/bin/hermes → $COMMAND_NAME"
fi

# ---------------------------------------------------------------------------
# 4. Write the per-profile Honcho client config
# ---------------------------------------------------------------------------
log "Writing $HONCHO_JSON ..."
python3 - "$HONCHO_JSON" "$BASE_URL" "$API_KEY" "$WORKSPACE" "$PEER" "$AI_PEER" "$SESSION_STRATEGY" <<'PY'
import json, sys
path, base_url, api_key, ws, peer, ai_peer, strategy = sys.argv[1:8]
cfg = {
    "endpoint":         {"baseUrl": base_url},
    "apiKey":           api_key,
    "workspace":        ws,
    "peerName":         peer,
    "aiPeer":           ai_peer,
    "sessionStrategy":  strategy,
    "enabled":          True,
    "observation": {
        "user": {"observeMe": True,  "observeOthers": False},
        "ai":   {"observeMe": True,  "observeOthers": True},
    },
}
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
ok "Honcho client config written"

# ---------------------------------------------------------------------------
# 5. Activate honcho as the memory provider (idempotent)
# ---------------------------------------------------------------------------
log "Activating honcho memory provider ..."
"$WRAPPER" config set memory.provider honcho >/dev/null
ok "memory.provider = honcho"

# ---------------------------------------------------------------------------
# 6. Pre-create workspace + peers in Honcho (idempotent get-or-create)
# ---------------------------------------------------------------------------
log "Ensuring workspace '$WORKSPACE' and peers '$PEER', '$AI_PEER' exist ..."
curl -fsS -X POST "$HONCHO_API_BASE/v3/workspaces" \
    -H 'content-type: application/json' \
    -d "$(printf '{"name":"%s"}' "$WORKSPACE")" >/dev/null
for p in "$PEER" "$AI_PEER"; do
    curl -fsS -X POST "$HONCHO_API_BASE/v3/workspaces/$WORKSPACE/peers" \
        -H 'content-type: application/json' \
        -d "$(printf '{"name":"%s"}' "$p")" >/dev/null
done
ok "Honcho namespace ready"

# ---------------------------------------------------------------------------
# 7. Sanity check
# ---------------------------------------------------------------------------
log "Doctor:"
"$WRAPPER" doctor 2>&1 | grep -E '(Configuration Files|API key|config\.yaml|✓|✗|⚠)' | head -10 || true
echo
log "Memory status:"
"$WRAPPER" memory status 2>&1 | head -10 || true

cat <<EOF

──────────────────────────────────────────────────────────────
✓ Done. Try:  $COMMAND_NAME setup    # pick model, login providers
              $COMMAND_NAME chat     # start using it
HERMES_HOME = $HERMES_HOME
Honcho      = $BASE_URL  (workspace=$WORKSPACE, peer=$PEER, ai=$AI_PEER)
──────────────────────────────────────────────────────────────
EOF

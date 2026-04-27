#!/usr/bin/env bash
# uninstall-tier2.sh --module=<name> — reverse a single tier 2 module.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MODULE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --module=*) MODULE="${1#--module=}" ;;
    -h|--help)
      echo "Usage: uninstall-tier2.sh --module=local-llm|persistence|voice|edge-gallery|telegram|browser"
      exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift
done
[ -n "$MODULE" ] || die "specify --module=<name>"

case "$MODULE" in
  local-llm)
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.hermes/bin/llama-server-qwen3.sh ~/.hermes/bin/llama-server-hermes3.sh ~/.hermes/bin/start-local-llm'
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/llama.cpp/models/Qwen3-4B-Q4_K_M.gguf'
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.hermes/.install-state/tier2-local-llm'
    ;;
  persistence)
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.termux/boot/00-hermes-startup.sh'
    # shellcheck disable=SC2016  # remote-side pipeline; expansions happen on phone
    run_remote '(crontab -l 2>/dev/null | grep -v "respawn-sshd") | crontab - || true'
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.hermes/.install-state/tier2-persistence'
    ;;
  voice)
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.hermes/.install-state/tier2-voice'
    log_info "voice: nothing to uninstall (built-in stt.provider; toggle in profile config)"
    ;;
  edge-gallery)
    log_info "edge-gallery: uninstall AI Edge Gallery via Android Settings -> Apps."
    ;;
  telegram)
    # shellcheck disable=SC2016  # ~ and sed expansions happen on phone
    run_remote 'sed -i "/^HERMES_GATEWAY_AUTOSTART=/d" ~/.hermes/.env'
    # shellcheck disable=SC2016  # remote-side pkill
    run_remote 'pkill -f "hermes.*gateway" || true'
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.hermes/.install-state/tier2-telegram'
    ;;
  browser)
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -rf ~/hermes-agent/node_modules ~/hermes-agent/package-lock.json'
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote 'rm -f ~/.hermes/.install-state/tier2-browser'
    ;;
  *) die "unknown module: $MODULE" ;;
esac
log_info "uninstall-tier2 ($MODULE): done"

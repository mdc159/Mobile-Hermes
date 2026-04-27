#!/usr/bin/env bash
# uninstall-tier1.sh — reverse Tier 1. Destructive on the phone.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

main() {
  log_warn "uninstall-tier1: removing ~/hermes-agent and ~/.hermes on the phone."
  if [ "${DRY_RUN:-0}" != "1" ]; then
    read -r -p "Type 'yes' to confirm: " ans
    [ "$ans" = "yes" ] || die "aborted"
  fi
  # shellcheck disable=SC2016  # $PREFIX expands on the remote phone, not locally
  run_remote 'rm -f "$PREFIX/bin/hermes" || true'
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'rm -rf ~/hermes-agent ~/.hermes'
  log_info "uninstall-tier1: done. To re-install, run install.sh."
  log_warn "Note: Termux packages and the Python venv build cache remain. Run 'pkg uninstall <list>' manually if desired."
}

main "$@"

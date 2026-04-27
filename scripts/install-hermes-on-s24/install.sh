#!/usr/bin/env bash
# install.sh — top-level orchestrator: prereqs-check, tier1, optional tier2.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/honcho-bind.sh
source "$SCRIPT_DIR/lib/honcho-bind.sh"
# shellcheck source=lib/tailscale-discover.sh
source "$SCRIPT_DIR/lib/tailscale-discover.sh"

TIER1_ONLY=0
RESUME=0
TIER2_ARGS=()

usage() {
  cat <<EOF
Usage: install.sh [flags] [-- tier2-flags...]
Flags:
  --tier1-only        skip tier 2 entirely
  --resume            re-run, skipping phases marked done
  --dry-run           print all SSH/SCP commands without executing
  -h, --help          show this help

Anything after '--' is forwarded to tier2-bootstrap.sh.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier1-only) TIER1_ONLY=1 ;;
    --resume)     RESUME=1 ;;
    --dry-run)    export DRY_RUN=1 ;;
    --) shift; TIER2_ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) log_err "unknown flag: $1"; usage; exit 1 ;;
  esac
  shift
done

main() {
  log_info "install.sh starting (tier1-only=$TIER1_ONLY resume=$RESUME dry-run=${DRY_RUN:-0})"

  # Step A: prereqs (forward --tier1-only so G0b can be relaxed there)
  if [ "$TIER1_ONLY" = "1" ]; then
    "$SCRIPT_DIR/prereqs-check.sh" --tier1-only
  else
    "$SCRIPT_DIR/prereqs-check.sh"
  fi

  # Step B: Honcho bind recommendation (printed; user must apply manually)
  log_info "Printing Honcho exposure recommendation; apply manually before continuing."
  local desktop_ip
  desktop_ip=$(tailscale status --json | discover_desktop_ipv4 || echo "?.?.?.?")
  print_recommendation "$desktop_ip" "$PHONE_HOST"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "(dry-run) skipping Honcho exposure confirmation prompt"
  elif [ ! -t 0 ]; then
    log_warn "stdin is not a TTY; auto-acknowledging Honcho exposure step. Verify manually if G6 fails."
  else
    read -r -p "Press ENTER once Honcho exposure is configured (or Ctrl-C to abort): " _
  fi
  log_gate G6c "Honcho exposure step acknowledged"

  # Step C: Tier 1
  "$SCRIPT_DIR/tier1-bootstrap.sh"

  # Step D: Tier 2 (optional)
  if [ "$TIER1_ONLY" = "1" ]; then
    log_info "tier1-only: stopping after tier 1"
  else
    "$SCRIPT_DIR/tier2-bootstrap.sh" "${TIER2_ARGS[@]}"
  fi

  log_info "install.sh: done. Daily-log entry suggested in /mnt/data/Documents/repos/hermaper/claude.md."
}

main "$@"

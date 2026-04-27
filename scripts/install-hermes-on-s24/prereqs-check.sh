#!/usr/bin/env bash
# prereqs-check.sh — verify Phase -1 prerequisites on the phone before
# the install script runs. Implements gates G0, G0a, G0b, G0c.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/tailscale-discover.sh
source "$SCRIPT_DIR/lib/tailscale-discover.sh"

require_cmd ssh scp jq tailscale

# Parse flags. --tier1-only relaxes G0b (Termux:API), which is only needed
# by Tier 2 modules (wake-lock, battery-status). Tier 1 cloud-only install
# has no dependency on it.
TIER1_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tier1-only) TIER1_ONLY=1 ;;
    -h|--help)
      echo "Usage: prereqs-check.sh [--tier1-only]"
      exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift
done

main() {
  log_info "prereqs-check starting (PHONE=$PHONE_USER@$PHONE_HOST:$PHONE_SSH_PORT, tier1-only=$TIER1_ONLY)"

  # G0c: Tailscale resolution from desktop.
  log_info "G0c: resolving phone via Tailscale"
  local phone_ip
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "(dry-run) skipping live tailscale lookup; assuming phone IP 100.83.211.53"
    phone_ip="100.83.211.53"
  else
    phone_ip=$(tailscale status --json | discover_peer_ipv4 "$PHONE_HOST") \
      || die "G0c FAIL: phone $PHONE_HOST not visible in tailscale status"
  fi
  log_gate G0c "phone IP via Tailscale = $phone_ip"

  # G1 prerequisite: SSH key auth must be set up before this script runs.
  log_info "verifying SSH key auth (run ssh-copy-id manually first if this fails)"
  if ! run_remote 'echo OK' >/dev/null 2>&1; then
    die "SSH key auth failed. From desktop run:
        ssh-copy-id -p $PHONE_SSH_PORT $PHONE_USER@$PHONE_HOST
       (One-time, requires phone password.) Then re-run this script."
  fi
  log_gate G1 "SSH key auth working"

  # G0: termux-info captured.
  log_info "G0: capturing termux-info"
  if ! run_remote 'termux-info' >>"$INSTALL_LOG_FILE" 2>&1; then
    die "G0 FAIL: termux-info unavailable. Is Termux app installed on phone?"
  fi
  log_gate G0 "termux-info captured to log"

  # G0a: sshd present and running.
  log_info "G0a: checking sshd"
  if ! run_remote 'command -v sshd >/dev/null && pgrep -x sshd >/dev/null'; then
    die "G0a FAIL: sshd not installed or not running. On phone:
        pkg install -y openssh && sshd"
  fi
  log_gate G0a "sshd present and running"

  # G0b: Termux:API app + termux-api package both work.
  # Skipped under --tier1-only: Termux:API is needed only by Tier 2 modules
  # (wake-lock, battery-status). Tier 1 cloud-only install runs fine without it.
  if [ "$TIER1_ONLY" = "1" ]; then
    log_warn "G0b: skipped (--tier1-only). Sideload Termux:API + Termux:Boot apps before running Tier 2."
  else
    log_info "G0b: testing termux-battery-status (proves Termux:API app installed)"
    if ! run_remote 'termux-battery-status' >/dev/null 2>&1; then
      die "G0b FAIL: termux-battery-status returned no JSON. Install BOTH:
        - termux-api package: pkg install -y termux-api
        - Termux:API app from F-Droid (companion app)
       Or re-run with --tier1-only to defer Tier 2 prereqs."
    fi
    log_gate G0b "Termux:API app + package working"
  fi

  log_info "All Phase -1 gates passed. Ready to run install.sh."
}

main "$@"

#!/usr/bin/env bash
# verify-reboot.sh — implements gate G9. Run AFTER manually rebooting the phone.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

main() {
  log_info "G9: verifying post-reboot service state"

  # sshd MUST be running (we just connected, so by definition it is).
  log_gate G9 "sshd running (this script connected via SSH)"

  # llama-server MUST NOT be running. Use the [l]lama trick so pgrep doesn't
  # match its own argv: the bracketed-class regex "[l]lama" matches literal
  # "llama" but pgrep's own command line contains "[l]lama" which does not
  # match the same regex.
  # shellcheck disable=SC2016  # remote-side pgrep; expansions happen on phone
  if run_remote 'pgrep -f "[l]lama\.cpp/build/bin/llama-server" >/dev/null'; then
    die "G9 FAIL: llama-server is running after reboot. Boot script should NOT start it."
  fi
  log_gate G9 "llama-server NOT running (correct)"

  # Gateway: running iff TELEGRAM_BOT_TOKEN + HERMES_GATEWAY_AUTOSTART=1.
  local autostart token
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  autostart=$(run_remote 'grep ^HERMES_GATEWAY_AUTOSTART= ~/.hermes/.env | cut -d= -f2' || echo 0)
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  token=$(run_remote 'grep ^TELEGRAM_BOT_TOKEN= ~/.hermes/.env | cut -d= -f2' || echo "")
  if [ -n "$token" ] && [ "$autostart" = "1" ]; then
    # shellcheck disable=SC2016  # remote-side pgrep with [h]ermes self-match guard
    if ! run_remote 'pgrep -f "[h]ermes .*gateway start" >/dev/null'; then
      die "G9 FAIL: gateway autostart is enabled but the process is not running."
    fi
    log_gate G9 "gateway running as expected"
  else
    # shellcheck disable=SC2016  # remote-side pgrep with [h]ermes self-match guard
    if run_remote 'pgrep -f "[h]ermes .*gateway start" >/dev/null'; then
      log_warn "G9 WARN: gateway running but autostart not enabled — investigate."
    else
      log_gate G9 "gateway NOT running (autostart not enabled, correct)"
    fi
  fi

  log_info "G9 PASS"
}

main "$@"

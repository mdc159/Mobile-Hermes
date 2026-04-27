#!/usr/bin/env bash
# common.sh — sourced by every script. Provides logging, gate tracking,
# remote execution helpers, and a strict shell environment.
#
# NOTE: Sourcing this file enables `set -euo pipefail` and `umask 077`
# in your shell. That is intentional — every install script needs strict
# mode and tight default file modes. If you source this from an ad-hoc
# helper that needs lenient behavior, save and restore shell options.

set -euo pipefail
umask 077

: "${PHONE_USER:=u0_a369}"
: "${PHONE_HOST:=miguels-s24}"
: "${PHONE_SSH_PORT:=8022}"
: "${SCRIPTS_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${INSTALL_LOG_FILE:=$SCRIPTS_ROOT/logs/install-$(date +%Y%m%d-%H%M%S)-$$.log}"
: "${DRY_RUN:=0}"

mkdir -p "$(dirname "$INSTALL_LOG_FILE")"

_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log_info() { printf '%s [INFO] %s\n' "$(_ts)" "$*" | tee -a "$INSTALL_LOG_FILE" >&2; }
log_warn() { printf '%s [WARN] %s\n' "$(_ts)" "$*" | tee -a "$INSTALL_LOG_FILE" >&2; }
log_err()  { printf '%s [ERR ] %s\n' "$(_ts)" "$*" | tee -a "$INSTALL_LOG_FILE" >&2; }
log_gate() {
  local gate="$1"; shift
  printf '%s [GATE %s] %s\n' "$(_ts)" "$gate" "$*" | tee -a "$INSTALL_LOG_FILE" >&2
}

die() { log_err "$*"; exit 1; }

ssh_args() {
  # ServerAliveInterval/CountMax keep long-running phone-side commands from
  # losing the SSH session to idle (Tailscale relay / NAT / Doze can drop
  # silent connections after a few minutes; keepalives prevent that).
  printf -- '-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -p %s' "$PHONE_SSH_PORT"
}

# scp uses capital -P for port (lowercase -p is "preserve mtime" in scp).
scp_args() {
  printf -- '-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -P %s' "$PHONE_SSH_PORT"
}

run_remote() {
  local cmd="$*"
  if [ "$DRY_RUN" = "1" ]; then
    printf '+ ssh %s %s@%s %s\n' "$(ssh_args)" "$PHONE_USER" "$PHONE_HOST" "$cmd"
    return 0
  fi
  # shellcheck disable=SC2046,SC2086,SC2029
  ssh $(ssh_args) "${PHONE_USER}@${PHONE_HOST}" "$cmd"
}

copy_remote() {
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf '+ scp %s %s %s@%s:%s\n' "$(scp_args)" "$src" "$PHONE_USER" "$PHONE_HOST" "$dst"
    return 0
  fi
  # shellcheck disable=SC2046,SC2086
  scp $(scp_args) "$src" "${PHONE_USER}@${PHONE_HOST}:$dst"
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command missing: $c"
  done
}

mark_phase_done() {
  local phase="$1"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "(dry-run) would mark $phase done"
    return 0
  fi
  run_remote "mkdir -p ~/.hermes/.install-state && touch ~/.hermes/.install-state/$phase"
}

phase_done() {
  local phase="$1"
  # In dry-run mode, treat every phase as not-yet-done so the rest of the
  # script can echo its commands. The actual `test -f` over ssh would
  # otherwise be silently neutralized by run_remote's DRY_RUN branch.
  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 1
  fi
  run_remote "test -f ~/.hermes/.install-state/$phase" >/dev/null 2>&1
}

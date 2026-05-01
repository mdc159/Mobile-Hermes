#!/usr/bin/env bash
# verify-grid-readiness.sh — redacted, non-mutating Studio54 mobile-edge readiness report.
#
# Default behavior is local-only. It inspects this repo's templates/docs and
# desktop SSH alias metadata without connecting to the phone. It does not run
# ssh, adb, package managers, services, gateways, local LLMs, Moshi/mosh hooks,
# or Honcho mutations unless a future explicitly approved mode adds that.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CANDIDATE="Android"
MODE="local-only"
SSH_ALIAS="${MOBILE_HERMES_SSH_ALIAS:-android}"
SAMPLE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: verify-grid-readiness.sh [--sample] [--dry-run] [--candidate Android|Termux]

Emit a redacted Studio54 mobile-edge readiness YAML report.

Safety:
  - local-only by default
  - no SSH/ADB execution against the phone
  - no installs, services, firewall, gateway, Honcho, Moshi/mosh, or LLM changes
  - no hostnames, Tailnet IPs, SSH key paths, tokens, .env, or raw logs printed
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sample)
      SAMPLE=1
      MODE="sample"
      ;;
    --dry-run)
      DRY_RUN=1
      MODE="dry-run"
      ;;
    --candidate)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --candidate" >&2; exit 2; }
      CANDIDATE="$1"
      case "$CANDIDATE" in
        Android|Termux) ;;
        *) echo "candidate must be Android or Termux" >&2; exit 2 ;;
      esac
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

bool_file() {
  if [ -e "$1" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

ssh_alias_configured() {
  if [ "$SAMPLE" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    printf 'unknown'
    return 0
  fi
  if ! command -v ssh >/dev/null 2>&1; then
    printf 'unknown'
    return 0
  fi

  # `ssh -G` can synthesize defaults for any name. Treat the alias as configured
  # only when a non-default hostname/user/port differs from the alias/defaults.
  local cfg hostname user port
  cfg="$(ssh -G "$SSH_ALIAS" 2>/dev/null || true)"
  hostname="$(printf '%s\n' "$cfg" | awk '$1 == "hostname" {print $2; exit}')"
  user="$(printf '%s\n' "$cfg" | awk '$1 == "user" {print $2; exit}')"
  port="$(printf '%s\n' "$cfg" | awk '$1 == "port" {print $2; exit}')"
  if [ -n "$cfg" ] && { [ "${hostname:-$SSH_ALIAS}" != "$SSH_ALIAS" ] || [ "${user:-$USER}" != "$USER" ] || [ "${port:-22}" != "22" ]; }; then
    printf 'true'
  else
    printf 'false'
  fi
}

profile_present() {
  local profile="$1"
  if [ -f "$SCRIPT_DIR/profiles/${profile}.yaml" ]; then
    printf '%s' "$profile"
  else
    printf 'missing'
  fi
}

termux_boot_present="$(bool_file "$SCRIPT_DIR/phone/boot/00-hermes-startup.sh")"
attach_template_present="$(bool_file "$SCRIPT_DIR/phone/bin/mobile-hermes-attach.template")"

if [ "$SAMPLE" = "1" ]; then
  ssh_alias="unknown"
  tailscale="unknown"
  termux_present="unknown"
  hermes_present="unknown"
  tmux_present="unknown"
else
  ssh_alias="$(ssh_alias_configured)"
  tailscale="unknown"
  termux_present="unknown"
  hermes_present="unknown"
  tmux_present="unknown"
fi

cat <<EOF
candidate: $CANDIDATE
mode: $MODE
transport:
  ssh_alias_configured: $ssh_alias
  tailscale_reachable: $tailscale
  ssh_port: redacted-or-default
  host_details_redacted: true
runtime:
  termux_present: $termux_present
  hermes_present: $hermes_present
  cloud_profile: $(profile_present s24-cloud)
  local_profile: $(profile_present s24-local)
  tmux_present: $tmux_present
  attach_wrapper_present: $attach_template_present
persistence:
  termux_boot_present: $termux_boot_present
  sshd_on_boot: documented
  gateway_autostart: opt-in
  local_llm_autostart: false
mobile_constraints:
  battery_unrestricted: unknown
  tailscale_reconnect_after_reboot: unknown
  wake_lock_policy: documented
  local_llm_residency: on-demand-only
safety:
  secrets_printed: false
  raw_runtime_logs_preserved: false
  installs_performed: false
  services_changed: false
  phone_remote_commands_executed: false
  adb_executed: false
  moshi_or_mosh_changes: false
next_action: keep Studio54 Android/Termux disabled; collect explicit transport evidence before any live probe
EOF

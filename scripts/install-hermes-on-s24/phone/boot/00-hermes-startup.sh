#!/data/data/com.termux/files/usr/bin/bash
# shellcheck shell=bash
# 00-hermes-startup.sh — Termux:Boot entrypoint.
# Starts ONLY sshd and acquires a wake lock. llama-server is on-demand;
# the gateway is started only when explicitly opted in.

set -euo pipefail
export PATH="$PREFIX/bin:$HOME/.hermes/bin:$PATH"
mkdir -p "$HOME/.hermes/logs"

LOG="$HOME/.hermes/logs/boot.log"
exec >>"$LOG" 2>&1
echo "[$(date -Iseconds)] boot script start"

termux-wake-lock || true
pgrep -x sshd >/dev/null || sshd

# Optional gateway autostart (Tier 7e). Reads a token from the env file.
if [ -f "$HOME/.hermes/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$HOME/.hermes/.env"
  set +a
fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ "${HERMES_GATEWAY_AUTOSTART:-0}" = "1" ]; then
  echo "[$(date -Iseconds)] starting hermes gateway"
  nohup hermes -p s24-cloud gateway start >>"$HOME/.hermes/logs/gateway.log" 2>&1 &
fi

echo "[$(date -Iseconds)] boot script done"

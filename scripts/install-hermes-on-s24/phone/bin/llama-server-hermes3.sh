#!/data/data/com.termux/files/usr/bin/bash
# shellcheck shell=bash
# llama-server-hermes3.sh — alt launcher for the already-on-disk Hermes-3-3B.
# Runs on :8081 to avoid clashing with the qwen3 launcher on :8080.

set -euo pipefail

MODEL="$HOME/llama.cpp/models/Hermes-3-Llama-3.2-3B.Q4_K_M.gguf"
BIN="$HOME/llama.cpp/build/bin/llama-server"

[ -x "$BIN" ] || { echo "llama-server not built at $BIN"; exit 1; }
[ -f "$MODEL" ] || { echo "model missing: $MODEL"; exit 1; }

exec "$BIN" \
  -m "$MODEL" \
  --jinja \
  -c "${CTX:-8192}" \
  -n "${MAX_NEW:-1024}" \
  -np 1 \
  --host 127.0.0.1 \
  --port 8081

#!/data/data/com.termux/files/usr/bin/bash
# shellcheck shell=bash
# llama-server-qwen3.sh — launches Qwen3-4B locally on :8080 with --jinja.
#
# Memory budget on an 8 GB S24:
#   model (Q4_K_M)            ~2.5 GB
#   KV cache @ -c 16384, q4   ~0.6 GB  (q4 KV cache halves memory vs fp16)
#   Termux + Hermes + system  ~2.0 GB
#   total                     ~5.1 GB  (comfortable)
#
# Bumping -c above 16384 or using fp16 KV cache risks OOM-killing Termux.
# Hermes Agent profile claims context_length: 65536 to clear its 64K floor;
# the actual practical ceiling is whatever -c says here.

set -euo pipefail

MODEL="$HOME/llama.cpp/models/Qwen3-4B-Q4_K_M.gguf"
BIN="$HOME/llama.cpp/build/bin/llama-server"

[ -x "$BIN" ] || { echo "llama-server not built at $BIN"; exit 1; }
[ -f "$MODEL" ] || { echo "model missing: $MODEL"; exit 1; }

exec "$BIN" \
  -m "$MODEL" \
  --jinja \
  -c "${CTX:-16384}" \
  -n "${MAX_NEW:-1024}" \
  -np 1 \
  --cache-type-k "${KV_TYPE:-q4_0}" \
  --cache-type-v "${KV_TYPE:-q4_0}" \
  --host 127.0.0.1 \
  --port 8080

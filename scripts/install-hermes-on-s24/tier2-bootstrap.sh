#!/usr/bin/env bash
# tier2-bootstrap.sh — modular experimental layer.
# Default-on:  local-llm install (no autostart), boot script
# Opt-in:      voice, edge-gallery (instructions), telegram, browser

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WITH_LOCAL_LLM=1
WITH_PERSISTENCE=1
WITH_VOICE=0
WITH_EDGE_GALLERY=0
WITH_TELEGRAM=0
WITH_BROWSER=0

QWEN3_REPO_URL="https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main"
QWEN3_FILE="Qwen3-4B-Q4_K_M.gguf"
# Pin the SHA256 of Qwen3-4B-Q4_K_M.gguf. Fetched 2026-04-26 from the HF
# LFS pointer at https://huggingface.co/Qwen/Qwen3-4B-GGUF/raw/main/Qwen3-4B-Q4_K_M.gguf.
# Update this constant if upstream re-quantizes; the install will refuse a
# mismatched hash. File size at pin time: 2,497,280,256 bytes (~2.5 GB).
QWEN3_SHA256="7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5"

usage() {
  cat <<EOF
Usage: tier2-bootstrap.sh [flags]
Default-on flags (use --no-X to disable):
  --no-local-llm       skip Qwen3 download + launchers
  --no-persistence     skip Termux:Boot script install
Opt-in flags:
  --with-voice         validate Hermes built-in stt.provider
  --with-edge-gallery  print AI Edge Gallery install instructions
  --with-telegram      enable HERMES_GATEWAY_AUTOSTART (token must be in .env)
  --with-browser       attempt nodejs-lts + npm install
  --all                turn on every opt-in flag
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-local-llm)      WITH_LOCAL_LLM=0 ;;
    --no-persistence)    WITH_PERSISTENCE=0 ;;
    --with-voice)        WITH_VOICE=1 ;;
    --with-edge-gallery) WITH_EDGE_GALLERY=1 ;;
    --with-telegram)     WITH_TELEGRAM=1 ;;
    --with-browser)      WITH_BROWSER=1 ;;
    --all)               WITH_VOICE=1; WITH_EDGE_GALLERY=1; WITH_TELEGRAM=1; WITH_BROWSER=1 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_err "unknown flag: $1"; usage; exit 1 ;;
  esac
  shift
done

module_local_llm() {
  [ "$WITH_LOCAL_LLM" = "1" ] || { log_info "local-llm: skipped"; return 0; }
  if phase_done tier2-local-llm; then log_info "local-llm: already done, skipping"; return 0; fi

  log_info "local-llm: verifying llama-server build"
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'test -x ~/llama.cpp/build/bin/llama-server' \
    || die "llama-server binary missing at ~/llama.cpp/build/bin/llama-server. Build llama.cpp on phone first."

  log_info "local-llm: ensuring models dir exists"
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'mkdir -p ~/llama.cpp/models'

  log_info "local-llm: downloading $QWEN3_FILE (~2.5 GB) if absent"
  run_remote "if [ ! -f ~/llama.cpp/models/$QWEN3_FILE ]; then \
      curl -fL --retry 3 -o ~/llama.cpp/models/$QWEN3_FILE.partial \
        '$QWEN3_REPO_URL/$QWEN3_FILE?download=true' && \
      mv ~/llama.cpp/models/$QWEN3_FILE.partial ~/llama.cpp/models/$QWEN3_FILE; \
    fi"

  log_info "local-llm: verifying SHA256"
  if [ "$QWEN3_SHA256" = "REPLACE_WITH_REAL_SHA256_FROM_HF_MODEL_CARD" ]; then
    log_warn "QWEN3_SHA256 placeholder still present — skipping verification. Pin the real hash before production use."
  else
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote "cd ~/llama.cpp/models && echo '$QWEN3_SHA256  $QWEN3_FILE' | sha256sum -c -" \
      || die "QWEN3 SHA256 mismatch. Refusing to use the downloaded file."
  fi

  log_info "local-llm: installing launchers"
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'mkdir -p ~/.hermes/bin'
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$SCRIPT_DIR/phone/bin/llama-server-qwen3.sh"   '~/.hermes/bin/llama-server-qwen3.sh'
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$SCRIPT_DIR/phone/bin/llama-server-hermes3.sh" '~/.hermes/bin/llama-server-hermes3.sh'
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$SCRIPT_DIR/phone/bin/start-local-llm"         '~/.hermes/bin/start-local-llm'
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'chmod +x ~/.hermes/bin/*.sh ~/.hermes/bin/start-local-llm'

  mark_phase_done tier2-local-llm
  log_info "local-llm: done. Run 'start-local-llm' on the phone, then 'hermes -p s24-local'."

  # Verification gates G7/G8 require a running llama-server. Since boot does
  # NOT auto-start it, prompt the user to start it manually on the phone.
  log_info "local-llm verify: please run 'start-local-llm' in a Termux session on the phone, then press ENTER."
  if [ "${DRY_RUN:-0}" = "1" ]; then
    : # dry-run: skip prompt
  elif [ ! -t 0 ]; then
    log_warn "stdin not a TTY; auto-starting llama-server via nohup so gates can probe."
    # Skip nohup-start if already running (G8b would otherwise spawn a duplicate).
    # shellcheck disable=SC2016  # remote-side pgrep with self-match guard
    if ! run_remote 'pgrep -f "[l]lama\.cpp/build/bin/llama-server" >/dev/null'; then
      # Use setsid + full stream redirection so ssh disconnects immediately.
      # Plain `nohup ... &` over ssh hangs because ssh keeps stdout/stderr open
      # waiting for the background child to close them.
      # shellcheck disable=SC2016  # ~ expands on phone
      run_remote 'mkdir -p ~/.hermes/logs && setsid sh -c "nohup ~/.hermes/bin/start-local-llm >> ~/.hermes/logs/llama-server.log 2>&1 </dev/null &" </dev/null >/dev/null 2>&1'
      log_info "  waiting for llama-server :8080 to come up (max 60s)..."
      local i=0
      until run_remote 'curl -fsS http://127.0.0.1:8080/v1/models >/dev/null 2>&1'; do
        i=$((i+1))
        [ "$i" -ge 30 ] && die "local-llm: llama-server did not bind :8080 within 60s — see ~/.hermes/logs/llama-server.log"
        sleep 2
      done
      log_info "  llama-server is up."
    else
      log_info "  llama-server already running; skipping nohup-start."
    fi
  else
    read -r _
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    run_remote 'curl -fsS http://127.0.0.1:8080/v1/models'
    log_gate G7 "(dry-run) would verify llama-server returns qwen3"
    run_remote 'curl -fsS http://127.0.0.1:8080/props'
    log_gate G8 "(dry-run) would verify /props chat_template"
    log_info "G8b: (dry-run) skipped tool-call smoke test"
    log_info "G8c: (dry-run) airplane-mode test is manual"
    return 0
  fi

  # G7: /v1/models returns Qwen3.
  # shellcheck disable=SC2016  # 127.0.0.1 is the phone's loopback
  if ! run_remote 'curl -fsS http://127.0.0.1:8080/v1/models' | tee -a "$INSTALL_LOG_FILE" | grep -qi 'qwen3'; then
    die "G7 FAIL: llama-server did not return qwen3 in /v1/models. Is start-local-llm running?"
  fi
  log_gate G7 "llama-server /v1/models OK"

  # G8: /props contains chat_template (proves --jinja worked).
  local props
  # shellcheck disable=SC2016  # 127.0.0.1 is the phone's loopback
  props=$(run_remote 'curl -fsS http://127.0.0.1:8080/props')
  printf '%s\n' "$props" >> "$INSTALL_LOG_FILE"
  if ! echo "$props" | jq -e '.chat_template != null and .chat_template != ""' >/dev/null 2>&1; then
    die "G8 FAIL: /props has no chat_template. Re-launch llama-server with --jinja."
  fi
  log_gate G8 "/props has chat_template (--jinja confirmed)"

  # G8b: real tool call executes under s24-local.
  log_info "G8b: running a tool-call smoke test under s24-local"
  local tool_out
  tool_out=$(run_remote "hermes -p s24-local chat --once 'Use the time tool and return the current ISO timestamp only.'" 2>&1) || true
  printf '%s\n' "$tool_out" >> "$INSTALL_LOG_FILE"
  if ! echo "$tool_out" | grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T'; then
    log_warn "G8b WARN: tool call did not return an ISO timestamp. Local model may be too weak; check log."
  else
    log_gate G8b "local tool call executed end-to-end"
  fi

  # G8c: airplane-mode test is manual.
  log_info "G8c (manual): put the phone in airplane mode, run 'hermes -p s24-local chat', confirm a response. Mark in claude.md daily log."
}

module_persistence() {
  [ "$WITH_PERSISTENCE" = "1" ] || { log_info "persistence: skipped"; return 0; }
  if phase_done tier2-persistence; then log_info "persistence: already done, skipping"; return 0; fi

  log_info "persistence: ensuring Termux:Boot is installed (manual step on phone)"
  log_warn "  If the Termux:Boot app is not installed, install it AND launch it ONCE before continuing."
  if [ "${DRY_RUN:-0}" = "1" ]; then
    : # dry-run: skip the prompt
  elif [ ! -t 0 ]; then
    log_warn "  stdin not a TTY; auto-acknowledging — verify Termux:Boot was launched once on the phone."
  else
    log_warn "  Press ENTER to confirm done."
    read -r _
  fi

  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'mkdir -p ~/.termux/boot'
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$SCRIPT_DIR/phone/boot/00-hermes-startup.sh" '~/.termux/boot/00-hermes-startup.sh'
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'chmod +x ~/.termux/boot/00-hermes-startup.sh'

  log_info "persistence: installing sshd respawn cron"
  # shellcheck disable=SC2016  # remote-side pipeline; expansions happen on phone
  run_remote '(crontab -l 2>/dev/null | grep -v "respawn-sshd" ; \
               echo "*/15 * * * * pgrep -x sshd >/dev/null || sshd # respawn-sshd") | crontab -'

  mark_phase_done tier2-persistence
  log_warn "persistence: REMINDER — disable battery optimization for Termux and Termux:Boot"
  log_warn "  in Android Settings -> Apps -> <app> -> Battery -> Unrestricted."
}

module_voice() {
  [ "$WITH_VOICE" = "1" ] || { log_info "voice: skipped (use --with-voice)"; return 0; }
  if phase_done tier2-voice; then log_info "voice: already done, skipping"; return 0; fi

  log_info "voice: validating Hermes built-in stt.provider"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    run_remote 'ffmpeg -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 ~/.hermes/test-silence.wav 2>/dev/null'
    run_remote 'hermes -p s24-cloud voice transcribe ~/.hermes/test-silence.wav'
    run_remote 'rm -f ~/.hermes/test-silence.wav'
    log_info "voice: (dry-run) would validate stt.provider response"
    mark_phase_done tier2-voice
    return 0
  fi

  # Generate a tiny silent WAV on the phone (1 second of silence) to confirm
  # the STT call path works end-to-end. We do not transcribe real audio here
  # because that would require microphone capture; we only verify Hermes
  # accepts the request and reaches the configured provider.
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'ffmpeg -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 ~/.hermes/test-silence.wav 2>/dev/null'

  # Cleanup the test WAV on every exit path. Inline at each branch (rather
  # than a trap RETURN, which is global in bash and would re-fire on every
  # subsequent function return) so no path leaves the file on the phone.
  local _wav_rm_cmd='rm -f ~/.hermes/test-silence.wav'

  local out
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  out=$(run_remote 'hermes -p s24-cloud voice transcribe ~/.hermes/test-silence.wav 2>&1' || true)
  printf '%s\n' "$out" >> "$INSTALL_LOG_FILE"

  if echo "$out" | grep -qiE 'authentication|api key'; then
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote "$_wav_rm_cmd" || true
    die "voice: STT provider auth failed. Check GROQ_API_KEY (or OPENAI_API_KEY)."
  fi
  if echo "$out" | grep -qiE 'unsupported|not.*found|missing.*provider'; then
    log_warn "voice: built-in stt.provider not available under .[termux]. Document and skip."
    # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
    run_remote "$_wav_rm_cmd" || true
    mark_phase_done tier2-voice
    return 0
  fi

  log_info "voice: provider responded (silence likely transcribes to empty/near-empty string — that's OK)."
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote "$_wav_rm_cmd" || true
  mark_phase_done tier2-voice
}

module_edge_gallery() {
  [ "$WITH_EDGE_GALLERY" = "1" ] || { log_info "edge-gallery: skipped (use --with-edge-gallery)"; return 0; }

  cat <<'EOF' | tee -a "$INSTALL_LOG_FILE"
==========================================================================
AI Edge Gallery — manual install (NOT wired into Hermes)
==========================================================================

This module prints instructions only. Perform on the phone:

  1. Install AI Edge Gallery from one of:
       - GitHub releases: https://github.com/google-ai-edge/gallery/releases
       - Play Store search "AI Edge Gallery" (Google AI, official publisher)
  2. Open the app, sign in if prompted, accept model EULA.
  3. Browse to "Gemma 4 E2B-it (LiteRT-LM)" (~2.58 GB).
     E4B (~3.65 GB) is acceptable on 12 GB devices but tight on the 8 GB S24.
  4. Download the model inside the app. It is loaded by AI Edge Gallery
     directly; Hermes does not see this model.
  5. Disable battery optimization for AI Edge Gallery if you plan to use
     it offline regularly.

This is your phone-native multimodal stack — separate from Hermes.
==========================================================================
EOF
  log_info "edge-gallery: instructions printed."
}

module_telegram() {
  [ "$WITH_TELEGRAM" = "1" ] || { log_info "telegram: skipped (use --with-telegram)"; return 0; }
  if phase_done tier2-telegram; then log_info "telegram: already done, skipping"; return 0; fi

  log_info "telegram: enabling HERMES_GATEWAY_AUTOSTART in phone .env"

  # Check the phone .env has TELEGRAM_BOT_TOKEN set.
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  if ! run_remote 'grep -q "^TELEGRAM_BOT_TOKEN=." ~/.hermes/.env'; then
    die "telegram: TELEGRAM_BOT_TOKEN missing or empty in phone .env. Add it to the desktop .env, re-run secrets-sync (tier1 phase 6), then re-run this module."
  fi

  # shellcheck disable=SC2016  # ~ and remote-side expansions happen on phone
  run_remote '(grep -v "^HERMES_GATEWAY_AUTOSTART=" ~/.hermes/.env 2>/dev/null; \
              echo "HERMES_GATEWAY_AUTOSTART=1") > ~/.hermes/.env.new && \
              mv ~/.hermes/.env.new ~/.hermes/.env && \
              chmod 600 ~/.hermes/.env'

  log_info "telegram: starting gateway now (and on next boot) — guarded by pgrep"
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  run_remote 'pgrep -f "hermes -p s24-cloud gateway start" >/dev/null || \
              nohup hermes -p s24-cloud gateway start >> ~/.hermes/logs/gateway.log 2>&1 &'

  mark_phase_done tier2-telegram
}

module_browser() {
  [ "$WITH_BROWSER" = "1" ] || { log_info "browser: skipped (use --with-browser)"; return 0; }
  if phase_done tier2-browser; then log_info "browser: already done, skipping"; return 0; fi

  log_info "browser: installing nodejs-lts and running npm install (best-effort)"
  # shellcheck disable=SC2016  # ~ expands on the remote phone, not locally
  if ! run_remote 'pkg install -y nodejs-lts && cd ~/hermes-agent && npm install'; then
    log_warn "browser: install failed. Skipping (nothing depends on it)."
    mark_phase_done tier2-browser
    return 0
  fi

  log_info "browser: smoke testing 'hermes tools browser --help'"
  if ! run_remote 'hermes tools browser --help' >/dev/null 2>&1; then
    log_warn "browser: tool not available. Marking skipped."
  else
    log_info "browser: tool present (full headless run not validated)."
  fi

  mark_phase_done tier2-browser
}

main() {
  log_info "tier2-bootstrap starting (local-llm=$WITH_LOCAL_LLM persistence=$WITH_PERSISTENCE voice=$WITH_VOICE edge=$WITH_EDGE_GALLERY tg=$WITH_TELEGRAM browser=$WITH_BROWSER)"
  module_local_llm
  module_persistence
  module_voice
  module_edge_gallery
  module_telegram
  module_browser
  log_info "tier2-bootstrap: complete"
}

main "$@"

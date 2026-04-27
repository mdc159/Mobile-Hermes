#!/usr/bin/env bash
# tier1-bootstrap.sh — runs phases 1-10 of Tier 1 over SSH against the phone.
# Each phase is idempotent and writes a marker under ~/.hermes/.install-state.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/secrets-sync.sh
source "$SCRIPT_DIR/lib/secrets-sync.sh"
# shellcheck source=lib/tailscale-discover.sh
source "$SCRIPT_DIR/lib/tailscale-discover.sh"
# shellcheck source=lib/profile-render.sh
source "$SCRIPT_DIR/lib/profile-render.sh"

PKG_LIST="git python clang rust make pkg-config libffi openssl nodejs ripgrep ffmpeg openssh termux-api jq cronie"

phase_pkg_install() {
  if phase_done phase1-pkg; then log_info "phase1-pkg: already done, skipping"; return 0; fi
  log_info "phase1-pkg: installing Termux packages"
  run_remote "pkg update -y && pkg install -y $PKG_LIST"
  mark_phase_done phase1-pkg
  log_gate G2 "phase1-pkg complete"
}

phase_clone_repo() {
  if phase_done phase2-clone; then log_info "phase2-clone: already done, skipping"; return 0; fi
  log_info "phase2-clone: cloning hermes-agent"
  run_remote 'if [ ! -d ~/hermes-agent/.git ]; then
    git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git ~/hermes-agent
  else
    cd ~/hermes-agent && git submodule update --init --recursive
  fi'
  mark_phase_done phase2-clone
  log_gate G2 "phase2-clone complete"
}

phase_create_venv() {
  if phase_done phase3-venv; then log_info "phase3-venv: already done, skipping"; return 0; fi
  log_info "phase3-venv: creating Python venv"
  run_remote 'cd ~/hermes-agent && python -m venv venv && \
    . venv/bin/activate && pip install --upgrade pip setuptools wheel'
  mark_phase_done phase3-venv
}

phase_pip_install() {
  if phase_done phase4-pip; then log_info "phase4-pip: already done, skipping"; return 0; fi
  log_info "phase4-pip: installing .[termux] (this takes ~15-25 min, plug in USB)"
  # shellcheck disable=SC2016  # $ vars expand on the remote phone, not locally
  run_remote 'cd ~/hermes-agent && \
    export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk)" && \
    . venv/bin/activate && \
    pip install -e .[termux] -c constraints-termux.txt'
  mark_phase_done phase4-pip
  log_gate G3 "phase4-pip complete (hermes installed)"
}

phase_symlink() {
  if phase_done phase5-symlink; then log_info "phase5-symlink: already done, skipping"; return 0; fi
  log_info "phase5-symlink: linking hermes into PATH"
  # shellcheck disable=SC2016  # $PREFIX expands on the remote phone, not locally
  run_remote 'ln -sf ~/hermes-agent/venv/bin/hermes "$PREFIX/bin/hermes"'
  mark_phase_done phase5-symlink
}

phase_secrets_sync() {
  if phase_done phase6-secrets; then log_info "phase6-secrets: already done, skipping"; return 0; fi
  log_info "phase6-secrets: syncing filtered .env to phone"

  : "${DESKTOP_ENV_FILE:=/home/hammer/Documents/repos/hermaper/.env}"
  [ -f "$DESKTOP_ENV_FILE" ] || die "Desktop .env not found at $DESKTOP_ENV_FILE; copy env/.env.bootstrap.example there and fill it in"

  local desktop_ts_name
  desktop_ts_name=$(tailscale status --json | discover_desktop_hostname) \
    || die "could not discover desktop tailscale hostname"
  HONCHO_BASE_URL="http://${desktop_ts_name}:18000"
  HONCHO_WORKSPACE="hermes-s24"

  local tmp; tmp=$(mktemp)
  filter_to_phone_env "$DESKTOP_ENV_FILE" > "$tmp"
  HONCHO_BASE_URL="$HONCHO_BASE_URL" HONCHO_WORKSPACE="$HONCHO_WORKSPACE" append_phone_specific_env "$tmp"
  summary_log

  run_remote 'mkdir -p ~/.hermes && chmod 700 ~/.hermes'
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$tmp" '~/.hermes/.env'
  run_remote 'chmod 600 ~/.hermes/.env'

  # Inline cleanup (see phase_profiles for why we avoid `trap ... RETURN`).
  rm -f "$tmp"

  mark_phase_done phase6-secrets
  log_info "phase6-secrets: complete (HONCHO_BASE_URL=$HONCHO_BASE_URL)"
}

phase_honcho_json() {
  if phase_done phase7-honcho-json; then log_info "phase7-honcho-json: already done, skipping"; return 0; fi
  log_info "phase7-honcho-json: writing ~/.hermes/honcho.json"
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$SCRIPT_DIR/phone/honcho.json" '~/.hermes/honcho.json'
  run_remote 'chmod 600 ~/.hermes/honcho.json'
  mark_phase_done phase7-honcho-json
}

phase_profiles() {
  if phase_done phase8-profiles; then log_info "phase8-profiles: already done, skipping"; return 0; fi
  log_info "phase8-profiles: creating s24-cloud and s24-local"

  # Source the synced phone .env locally to obtain model-name placeholders.
  # We re-read the desktop file (canonical) since the phone copy is filtered the same way.
  : "${DESKTOP_ENV_FILE:=/home/hammer/Documents/repos/hermaper/.env}"
  if [ -f "$DESKTOP_ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$DESKTOP_ENV_FILE"
    set +a
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    # Use sample placeholders so render_profile and downstream scp can be
    # exercised without requiring a populated .env.
    : "${OPENROUTER_PRIMARY_MODEL:=anthropic/claude-3.5-sonnet}"
    : "${OPENAI_FALLBACK_MODEL:=gpt-4o-mini}"
    export OPENROUTER_PRIMARY_MODEL OPENAI_FALLBACK_MODEL
  else
    : "${OPENROUTER_PRIMARY_MODEL:?OPENROUTER_PRIMARY_MODEL not set in $DESKTOP_ENV_FILE}"
    : "${OPENAI_FALLBACK_MODEL:?OPENAI_FALLBACK_MODEL not set in $DESKTOP_ENV_FILE}"
  fi

  local cloud_tmp local_tmp
  cloud_tmp=$(mktemp); local_tmp=$(mktemp)

  render_profile "$SCRIPT_DIR/profiles/s24-cloud.yaml" > "$cloud_tmp"
  render_profile "$SCRIPT_DIR/profiles/s24-local.yaml" > "$local_tmp"

  # Create profiles via hermes CLI (idempotent: if a profile already exists,
  # `profile create --clone` errors; tolerate that and overwrite the config).
  run_remote 'hermes profile create s24-cloud --clone || true'
  run_remote 'hermes profile create s24-local --clone || true'

  # Hermes profiles live under ~/.hermes/profiles/<name>/config.yaml
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$cloud_tmp" '~/.hermes/profiles/s24-cloud/config.yaml'
  # shellcheck disable=SC2088  # ~ expands on the remote phone, not locally
  copy_remote "$local_tmp" '~/.hermes/profiles/s24-local/config.yaml'

  # Cleanup tmp files inline (avoid bash `trap RETURN` which is shell-global
  # and fires on every subsequent function return — including after main exits).
  rm -f "$cloud_tmp" "$local_tmp"

  mark_phase_done phase8-profiles
}

phase_doctor() {
  if phase_done phase9-doctor; then log_info "phase9-doctor: already done, skipping"; return 0; fi
  log_info "phase9-doctor: running 'hermes -p s24-cloud doctor'"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    run_remote 'hermes -p s24-cloud doctor'
    log_gate G4 "(dry-run) would verify hermes doctor clean"
    mark_phase_done phase9-doctor
    return 0
  fi

  local doctor_out rc=0
  doctor_out=$(run_remote 'hermes -p s24-cloud doctor' 2>&1) || rc=$?
  printf '%s\n' "$doctor_out" >> "$INSTALL_LOG_FILE"

  # Tolerate Docker/voice warnings; halt on anything else (including non-zero
  # ssh/hermes exit codes that didn't print a tolerated keyword).
  if [ "$rc" -ne 0 ]; then
    if ! echo "$doctor_out" | grep -qiE 'docker|voice|faster-whisper|ctranslate2'; then
      die "G4 FAIL: hermes doctor exited $rc with non-tolerated error. See log."
    fi
    log_warn "phase9-doctor: hermes doctor exited $rc but only tolerated warnings present; continuing"
  elif echo "$doctor_out" | grep -qiE 'error|fail' \
       && ! echo "$doctor_out" | grep -qiE 'docker|voice|faster-whisper|ctranslate2'; then
    die "G4 FAIL: hermes doctor reported a non-Docker/voice error. See log."
  fi
  mark_phase_done phase9-doctor
  log_gate G4 "hermes doctor exits clean (Docker/voice warnings tolerated)"
}

phase_smoke_test() {
  if phase_done phase10-smoke; then log_info "phase10-smoke: already done, skipping"; return 0; fi
  log_info "phase10-smoke: cloud round-trip + memory status"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    run_remote "hermes -p s24-cloud -z 'Reply with the single word: pong.'"
    log_gate G5 "(dry-run) would verify cloud round-trip"
    run_remote 'hermes -p s24-cloud memory status'
    log_gate G6 "(dry-run) would verify honcho memory active"
    run_remote "jq -e '.hosts.hermes.recallMode == \"tools\"' ~/.hermes/honcho.json"
    log_gate G6b "(dry-run) would verify honcho.json fields"
    mark_phase_done phase10-smoke
    return 0
  fi

  # G5: one-shot cloud round-trip via OpenRouter. -z is hermes's one-shot prompt flag.
  run_remote "hermes -p s24-cloud -z 'Reply with the single word: pong.'" \
    | tee -a "$INSTALL_LOG_FILE" | grep -qiE '(^|[^a-z])pong([^a-z]|$)' \
    || die "G5 FAIL: cloud round-trip did not return 'pong'. Check OPENROUTER_API_KEY."
  log_gate G5 "cloud round-trip OK"

  # G6: Honcho reachable and active (use -p so we hit the s24-cloud profile config).
  local mem_status
  mem_status=$(run_remote 'hermes -p s24-cloud memory status' 2>&1)
  printf '%s\n' "$mem_status" >> "$INSTALL_LOG_FILE"
  echo "$mem_status" | grep -qi 'honcho' || die "G6 FAIL: hermes memory status does not mention honcho"
  echo "$mem_status" | grep -qiE 'active|connected|ok' \
    || die "G6 FAIL: honcho not reported as active. Check Honcho bind/auth/ACL."
  log_gate G6 "honcho memory active and reachable"

  # G6b: honcho.json on phone has expected workspace + recallMode.
  run_remote "jq -e '.hosts.hermes.recallMode == \"tools\"' ~/.hermes/honcho.json" >/dev/null \
    || die "G6b FAIL: honcho.json recallMode not 'tools'"
  log_gate G6b "honcho.json fields verified"

  mark_phase_done phase10-smoke
}

main() {
  log_info "tier1-bootstrap starting"
  phase_pkg_install
  phase_clone_repo
  phase_create_venv
  phase_pip_install
  phase_symlink
  phase_secrets_sync
  phase_honcho_json
  phase_profiles
  phase_doctor
  phase_smoke_test
  log_info "tier1-bootstrap: ALL PHASES COMPLETE"
}

main "$@"

#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIXTURES="$SCRIPT_DIR/tests/fixtures"
  source "$SCRIPT_DIR/lib/secrets-sync.sh"
  OUT="$(mktemp)"
}

teardown() {
  rm -f "$OUT"
}

@test "filter_to_phone_env emits only allowlisted keys" {
  filter_to_phone_env "$FIXTURES/desktop.env.sample" > "$OUT"
  grep -q '^OPENROUTER_API_KEY=sk-or-v1-DESKTOP-KEY$' "$OUT"
  grep -q '^OPENAI_API_KEY=sk-DESKTOP-KEY$' "$OUT"
  grep -q '^GROQ_API_KEY=gsk_DESKTOP$' "$OUT"
  grep -q '^ELEVENLABS_API_KEY=eleven-DESKTOP$' "$OUT"
}

@test "filter_to_phone_env drops unknown keys" {
  filter_to_phone_env "$FIXTURES/desktop.env.sample" > "$OUT"
  ! grep -q 'PRIVATE_DESKTOP_SECRET' "$OUT"
  ! grep -q 'GITHUB_TOKEN' "$OUT"
  ! grep -q 'DATABASE_URL' "$OUT"
}

@test "filter_to_phone_env drops empty allowlisted keys" {
  filter_to_phone_env "$FIXTURES/desktop.env.sample" > "$OUT"
  ! grep -q '^TELEGRAM_BOT_TOKEN=$' "$OUT"
}

@test "append_phone_specific_env injects HONCHO_BASE_URL and workspace" {
  filter_to_phone_env "$FIXTURES/desktop.env.sample" > "$OUT"
  HONCHO_BASE_URL='http://hammer-desktop:18000' HONCHO_WORKSPACE='hermes-s24' append_phone_specific_env "$OUT"
  grep -q '^HONCHO_BASE_URL=http://hammer-desktop:18000$' "$OUT"
  grep -q '^HONCHO_WORKSPACE=hermes-s24$' "$OUT"
}

@test "summary_log lists synced and absent keys without values" {
  filter_to_phone_env "$FIXTURES/desktop.env.sample" >"$OUT"
  log="$(summary_log 2>&1)"
  [[ "$log" == *"synced: OPENROUTER_API_KEY"* ]]
  [[ "$log" == *"absent: TELEGRAM_BOT_TOKEN"* ]]
  ! echo "$log" | grep -q 'sk-or-v1'
  ! echo "$log" | grep -q 'sk-DESKTOP'
}

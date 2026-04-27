#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$SCRIPT_DIR/lib/profile-render.sh"
  OUT="$(mktemp)"
}

teardown() {
  rm -f "$OUT"
}

@test "render_profile substitutes %%KEY%% placeholders" {
  OPENROUTER_PRIMARY_MODEL='anthropic/claude-3.5-sonnet' \
  OPENAI_FALLBACK_MODEL='gpt-4o-mini' \
  render_profile "$SCRIPT_DIR/profiles/s24-cloud.yaml" > "$OUT"
  grep -q 'default: anthropic/claude-3.5-sonnet' "$OUT"
  grep -q 'model: gpt-4o-mini' "$OUT"
  ! grep -q '%%' "$OUT"
}

@test "render_profile fails if a placeholder has no value" {
  unset OPENROUTER_PRIMARY_MODEL OPENAI_FALLBACK_MODEL
  run render_profile "$SCRIPT_DIR/profiles/s24-cloud.yaml"
  [ "$status" -ne 0 ]
}

@test "render_profile passes through s24-local unchanged (no placeholders)" {
  render_profile "$SCRIPT_DIR/profiles/s24-local.yaml" > "$OUT"
  diff -q "$SCRIPT_DIR/profiles/s24-local.yaml" "$OUT"
}

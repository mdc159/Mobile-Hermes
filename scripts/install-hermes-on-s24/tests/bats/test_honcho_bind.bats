#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$SCRIPT_DIR/lib/honcho-bind.sh"
  OUT="$(mktemp)"
}

teardown() {
  rm -f "$OUT"
}

@test "print_recommendation includes both preferred and acceptable paths" {
  print_recommendation 100.64.10.42 miguels-s24 > "$OUT"
  grep -q 'PREFERRED' "$OUT"
  grep -q 'AUTH_USE_AUTH=true' "$OUT"
  grep -q 'ACCEPTABLE FALLBACK' "$OUT"
  grep -q 'tailscale0' "$OUT"
}

@test "print_recommendation references the desktop IP and phone hostname" {
  print_recommendation 100.64.10.42 miguels-s24 > "$OUT"
  grep -q '100.64.10.42' "$OUT"
  grep -q 'miguels-s24' "$OUT"
}

@test "print_recommendation references Tailscale Serve as alternative" {
  print_recommendation 100.64.10.42 miguels-s24 > "$OUT"
  grep -qi 'tailscale serve' "$OUT"
}

@test "print_recommendation never modifies any system file" {
  before="$(find /tmp -maxdepth 1 -newer /tmp -not -path "$OUT" 2>/dev/null | wc -l)"
  print_recommendation 100.64.10.42 miguels-s24 > "$OUT"
  after="$(find /tmp -maxdepth 1 -newer /tmp -not -path "$OUT" 2>/dev/null | wc -l)"
  [ "$before" = "$after" ]
}

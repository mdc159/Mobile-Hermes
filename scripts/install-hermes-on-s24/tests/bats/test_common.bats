#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$SCRIPT_DIR/lib/common.sh"
  TMPLOG="$(mktemp)"
  export INSTALL_LOG_FILE="$TMPLOG"
}

teardown() {
  rm -f "$TMPLOG"
}

@test "log_info writes timestamp and INFO to log file" {
  log_info "hello"
  grep -q '\[INFO\] hello' "$TMPLOG"
}

@test "log_gate writes GATE marker" {
  log_gate "G1" "ssh works"
  grep -q '\[GATE G1\] ssh works' "$TMPLOG"
}

@test "run_remote in DRY_RUN echoes command, doesn't execute" {
  DRY_RUN=1 run_remote "echo should-not-run" >"$TMPLOG.out" 2>&1
  grep -q '+ ssh.*echo should-not-run' "$TMPLOG.out"
  ! grep -q '^should-not-run$' "$TMPLOG.out"
}

@test "die exits non-zero with message" {
  run bash -c 'source '"$SCRIPT_DIR"'/lib/common.sh; INSTALL_LOG_FILE='"$TMPLOG"'; die "kaboom"'
  [ "$status" -ne 0 ]
  grep -q 'kaboom' "$TMPLOG"
}

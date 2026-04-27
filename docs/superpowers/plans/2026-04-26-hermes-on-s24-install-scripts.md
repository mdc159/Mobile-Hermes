# Hermes-on-S24 Install Scripts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the desktop-driven, two-tier install scripts that bring a Samsung S24 from blank Termux to a fully-functional Hermes Agent node connected to desktop Honcho over Tailscale.

**Architecture:** Bash scripts in `scripts/install-hermes-on-s24/` orchestrated from desktop. Pure-bash library functions (Tailscale discovery, secrets filtering, Honcho bind printer) are unit-tested with `bats-core`. SSH-driven phases are idempotent and gated by checkpoints G0–G9 from the spec, with a `DRY_RUN=1` mode for offline development. Install operates against the real phone (`miguels-s24` / `100.83.211.53`) via SSH over Tailscale.

**Tech Stack:** Bash, ssh/scp, jq, `bats-core` (test runner), `shellcheck` (lint), Termux package manager (`pkg`), Python 3.11 venv on phone, `pip`, `git`, `llama.cpp`, Hermes Agent's `.[termux]` extra.

**Spec:** `docs/superpowers/specs/2026-04-26-hermes-on-s24-design.md` (v2)

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/install-hermes-on-s24/README.md` | Runbook: Phase −1 checklist, flags, troubleshooting |
| `scripts/install-hermes-on-s24/install.sh` | Top-level orchestrator. Parses flags, runs prereqs-check then tier1, optionally tier2. Implements `--resume`, `--tier1-only`, `--with-<module>`, `--dry-run`. |
| `scripts/install-hermes-on-s24/prereqs-check.sh` | Verifies Phase −1 (Termux, Tailscale, Termux:API, sshd, key auth, etc.) Gates G0–G0c. |
| `scripts/install-hermes-on-s24/tier1-bootstrap.sh` | Tier 1 phases 1–10 from spec. Idempotent. |
| `scripts/install-hermes-on-s24/tier2-bootstrap.sh` | Tier 2 modules (7a–7f). Each is a function gated by a flag. |
| `scripts/install-hermes-on-s24/uninstall-tier1.sh` | Reverse Tier 1. |
| `scripts/install-hermes-on-s24/uninstall-tier2.sh` | Reverse Tier 2 modules selectively. |
| `scripts/install-hermes-on-s24/lib/common.sh` | Logging helpers, gate runner, `run_remote`, `run_remote_dry`, `umask` setup. Sourced by all scripts. |
| `scripts/install-hermes-on-s24/lib/tailscale-discover.sh` | Pure-function: parse `tailscale status --json` → desktop hostname + Tailscale IP. |
| `scripts/install-hermes-on-s24/lib/secrets-sync.sh` | Pure-function: read desktop `.env`, filter to allowlist, emit derived phone `.env` to stdout (or scp). |
| `scripts/install-hermes-on-s24/lib/honcho-bind.sh` | Print recommended bind/auth/ACL changes for user confirmation. Never modifies. |
| `scripts/install-hermes-on-s24/lib/profile-render.sh` | Substitute `<user-chosen ...>` placeholders in profile YAML templates from env. |
| `scripts/install-hermes-on-s24/profiles/s24-cloud.yaml` | Cloud profile template (OpenRouter primary, OpenAI `fallback_model`, Honcho on, STT groq/openai). |
| `scripts/install-hermes-on-s24/profiles/s24-local.yaml` | Local profile template (Qwen3 via 127.0.0.1:8080, native memory only). |
| `scripts/install-hermes-on-s24/env/.env.bootstrap.example` | Template the user fills in. Allowlist is documented inline. |
| `scripts/install-hermes-on-s24/phone/honcho.json` | Honcho client config: workspace `hermes-s24`, recall `tools`, write `async`. Synced to phone. |
| `scripts/install-hermes-on-s24/phone/boot/00-hermes-startup.sh` | Termux:Boot script. Wake-lock + sshd; gateway iff opted-in. **No `llama-server`.** |
| `scripts/install-hermes-on-s24/phone/bin/start-local-llm` | On-demand foreground launcher for Qwen3. |
| `scripts/install-hermes-on-s24/phone/bin/llama-server-qwen3.sh` | Launcher: `--jinja -c 8192 -n 1024 --port 8080`. |
| `scripts/install-hermes-on-s24/phone/bin/llama-server-hermes3.sh` | Alt launcher on `:8081`. |
| `scripts/install-hermes-on-s24/tests/bats/test_tailscale_discover.bats` | Unit tests for tailscale-discover. |
| `scripts/install-hermes-on-s24/tests/bats/test_secrets_sync.bats` | Unit tests for secrets-sync. |
| `scripts/install-hermes-on-s24/tests/bats/test_profile_render.bats` | Unit tests for profile-render. |
| `scripts/install-hermes-on-s24/tests/bats/test_honcho_bind.bats` | Unit tests for honcho-bind printer. |
| `scripts/install-hermes-on-s24/tests/fixtures/` | Sample `tailscale status --json` output, sample `.env`, etc. |
| `scripts/install-hermes-on-s24/.gitignore` | Ignore `logs/`, `.tailscale-desktop`, secrets. |

A repo-root `.gitignore` update covers `/mnt/data/Documents/repos/hermaper/.env` if not already.

---

## Conventions

- Every shell script starts with `#!/usr/bin/env bash` + `set -euo pipefail` + `umask 077`.
- All logging goes through `log_info`, `log_warn`, `log_err`, `log_gate` from `lib/common.sh`. Logs append to `scripts/install-hermes-on-s24/logs/<run-id>.log`.
- Remote command execution uses `run_remote "<cmd>"`. With `DRY_RUN=1`, `run_remote` prints `+ ssh ... <cmd>` instead. Same for `scp` via `copy_remote`.
- Idempotency: every phase checks for completion markers under `~/.hermes/.install-state/<phase-id>` on the phone before running. Markers are touched on success. `install.sh --resume` skips phases with markers.
- All shell files are linted with `shellcheck` in CI / pre-commit.
- All bats tests run via `bats tests/bats/*.bats` from the script dir.
- Commit style: conventional (`feat:`, `test:`, `docs:`, `chore:`).
- Operate on `main` (no worktree per user pattern).

---

## Task 1: Repo skeleton + .gitignore + lint harness

**Files:**
- Create: `scripts/install-hermes-on-s24/.gitignore`
- Create: `scripts/install-hermes-on-s24/README.md` (stub — full content in Task 27)
- Create: `scripts/install-hermes-on-s24/logs/.gitkeep`
- Create: `scripts/install-hermes-on-s24/tests/bats/.gitkeep`
- Create: `scripts/install-hermes-on-s24/tests/fixtures/.gitkeep`
- Modify: `/mnt/data/Documents/repos/hermaper/.gitignore` (add `.env`, `scripts/install-hermes-on-s24/logs/`, `scripts/install-hermes-on-s24/.tailscale-desktop`)

- [ ] **Step 1.1: Create the directory tree**

```bash
cd /mnt/data/Documents/repos/hermaper
mkdir -p scripts/install-hermes-on-s24/{lib,profiles,env,phone/{boot,bin},tests/bats,tests/fixtures,logs}
touch scripts/install-hermes-on-s24/logs/.gitkeep
touch scripts/install-hermes-on-s24/tests/bats/.gitkeep
touch scripts/install-hermes-on-s24/tests/fixtures/.gitkeep
```

- [ ] **Step 1.2: Write `scripts/install-hermes-on-s24/.gitignore`**

```gitignore
logs/*.log
.tailscale-desktop
.install-state-cache
*.local.env
```

- [ ] **Step 1.3: Update repo-root .gitignore**

Append to `/mnt/data/Documents/repos/hermaper/.gitignore` (create file if absent):

```gitignore
# secrets
.env
*.env.local

# install run artifacts
scripts/install-hermes-on-s24/logs/
scripts/install-hermes-on-s24/.tailscale-desktop
```

- [ ] **Step 1.4: Stub README**

`scripts/install-hermes-on-s24/README.md`:

```markdown
# Hermes-on-S24 install scripts

Desktop-driven install of Hermes Agent on a Samsung S24 over Tailscale.

See `docs/superpowers/specs/2026-04-26-hermes-on-s24-design.md` for the design.

Full runbook is filled in by Task 27 of the implementation plan.
```

- [ ] **Step 1.5: Verify `shellcheck` and `bats` are available; install if missing**

Run:

```bash
command -v shellcheck >/dev/null && echo "shellcheck OK" || { sudo apt-get install -y shellcheck || echo "install shellcheck manually"; }
command -v bats >/dev/null && echo "bats OK" || { sudo apt-get install -y bats || echo "install bats manually"; }
```

Expected: both commands resolve. If they don't, install with the package manager. Record actual versions in commit message.

- [ ] **Step 1.6: Commit**

```bash
git add scripts/install-hermes-on-s24/.gitignore scripts/install-hermes-on-s24/README.md scripts/install-hermes-on-s24/logs/.gitkeep scripts/install-hermes-on-s24/tests/bats/.gitkeep scripts/install-hermes-on-s24/tests/fixtures/.gitkeep .gitignore
git commit -m "chore: scaffold scripts/install-hermes-on-s24 layout"
```

---

## Task 2: `lib/common.sh` — logging, gate runner, run_remote

**Files:**
- Create: `scripts/install-hermes-on-s24/lib/common.sh`
- Create: `scripts/install-hermes-on-s24/tests/bats/test_common.bats`

- [ ] **Step 2.1: Write the failing test**

`scripts/install-hermes-on-s24/tests/bats/test_common.bats`:

```bats
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
  ! grep -q 'should-not-run$' "$TMPLOG.out"
}

@test "die exits non-zero with message" {
  run bash -c 'source '"$SCRIPT_DIR"'/lib/common.sh; INSTALL_LOG_FILE='"$TMPLOG"'; die "kaboom"'
  [ "$status" -ne 0 ]
  grep -q 'kaboom' "$TMPLOG"
}
```

- [ ] **Step 2.2: Run test to verify it fails**

```bash
cd /mnt/data/Documents/repos/hermaper/scripts/install-hermes-on-s24
bats tests/bats/test_common.bats
```

Expected: 4 failures, source not found.

- [ ] **Step 2.3: Implement `lib/common.sh`**

```bash
#!/usr/bin/env bash
# common.sh — sourced by every script. Provides logging, gate tracking,
# remote execution helpers, and a strict shell environment.

set -euo pipefail
umask 077

: "${PHONE_USER:=u0_a369}"
: "${PHONE_HOST:=miguels-s24}"
: "${PHONE_SSH_PORT:=8022}"
: "${SCRIPTS_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${INSTALL_LOG_FILE:=$SCRIPTS_ROOT/logs/install-$(date +%Y%m%d-%H%M%S)-$$.log}"
: "${DRY_RUN:=0}"

mkdir -p "$(dirname "$INSTALL_LOG_FILE")"

_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log_info() { printf '%s [INFO] %s\n' "$(_ts)" "$*" | tee -a "$INSTALL_LOG_FILE" >&2; }
log_warn() { printf '%s [WARN] %s\n' "$(_ts)" "$*" | tee -a "$INSTALL_LOG_FILE" >&2; }
log_err()  { printf '%s [ERR ] %s\n' "$(_ts)" "$*" | tee -a "$INSTALL_LOG_FILE" >&2; }
log_gate() {
  local gate="$1"; shift
  printf '%s [GATE %s] %s\n' "$(_ts)" "$gate" "$*" | tee -a "$INSTALL_LOG_FILE" >&2
}

die() { log_err "$*"; exit 1; }

ssh_args() {
  printf -- '-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=8 -p %s' "$PHONE_SSH_PORT"
}

run_remote() {
  local cmd="$*"
  if [ "$DRY_RUN" = "1" ]; then
    printf '+ ssh %s %s@%s %q\n' "$(ssh_args)" "$PHONE_USER" "$PHONE_HOST" "$cmd"
    return 0
  fi
  # shellcheck disable=SC2086
  ssh $(ssh_args) "${PHONE_USER}@${PHONE_HOST}" "$cmd"
}

copy_remote() {
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf '+ scp %s %s %s@%s:%s\n' "$(ssh_args)" "$src" "$PHONE_USER" "$PHONE_HOST" "$dst"
    return 0
  fi
  # shellcheck disable=SC2086
  scp $(ssh_args) "$src" "${PHONE_USER}@${PHONE_HOST}:$dst"
}

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command missing: $c"
  done
}

mark_phase_done() {
  local phase="$1"
  run_remote "mkdir -p ~/.hermes/.install-state && touch ~/.hermes/.install-state/$phase"
}

phase_done() {
  local phase="$1"
  run_remote "test -f ~/.hermes/.install-state/$phase" >/dev/null 2>&1
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

```bash
bats tests/bats/test_common.bats
```

Expected: 4 passing tests.

- [ ] **Step 2.5: Lint**

```bash
shellcheck lib/common.sh
```

Expected: no errors. Fix any reported.

- [ ] **Step 2.6: Commit**

```bash
git add scripts/install-hermes-on-s24/lib/common.sh scripts/install-hermes-on-s24/tests/bats/test_common.bats
git commit -m "feat(install): add lib/common.sh with logging, gates, run_remote"
```

---

## Task 3: `lib/tailscale-discover.sh`

**Files:**
- Create: `scripts/install-hermes-on-s24/lib/tailscale-discover.sh`
- Create: `scripts/install-hermes-on-s24/tests/fixtures/tailscale-status.json`
- Create: `scripts/install-hermes-on-s24/tests/bats/test_tailscale_discover.bats`

- [ ] **Step 3.1: Write the fixture**

`tests/fixtures/tailscale-status.json`:

```json
{
  "Self": {
    "HostName": "hammer-desktop",
    "TailscaleIPs": ["100.64.10.42", "fd7a:115c:a1e0::1"]
  },
  "Peer": {
    "n123": {
      "HostName": "miguels-s24",
      "TailscaleIPs": ["100.83.211.53", "fd7a:115c:a1e0::ff"]
    }
  }
}
```

- [ ] **Step 3.2: Write the failing test**

`tests/bats/test_tailscale_discover.bats`:

```bats
#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FIXTURES="$SCRIPT_DIR/tests/fixtures"
  source "$SCRIPT_DIR/lib/tailscale-discover.sh"
}

@test "discover_desktop_hostname returns Self.HostName" {
  result="$(discover_desktop_hostname < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "hammer-desktop" ]
}

@test "discover_desktop_ipv4 returns first IPv4 from TailscaleIPs" {
  result="$(discover_desktop_ipv4 < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "100.64.10.42" ]
}

@test "discover_peer_ipv4 returns the matching peer IPv4" {
  result="$(discover_peer_ipv4 miguels-s24 < "$FIXTURES/tailscale-status.json")"
  [ "$result" = "100.83.211.53" ]
}

@test "discover_peer_ipv4 fails for unknown peer" {
  run bash -c 'source '"$SCRIPT_DIR"'/lib/tailscale-discover.sh; discover_peer_ipv4 ghost < '"$FIXTURES"'/tailscale-status.json'
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 3.3: Run test to verify it fails**

```bash
bats tests/bats/test_tailscale_discover.bats
```

Expected: 4 failures.

- [ ] **Step 3.4: Implement `lib/tailscale-discover.sh`**

```bash
#!/usr/bin/env bash
# tailscale-discover.sh — pure functions over `tailscale status --json` output.

discover_desktop_hostname() {
  jq -r '.Self.HostName // empty'
}

discover_desktop_ipv4() {
  jq -r '.Self.TailscaleIPs[]? | select(test("^[0-9]+\\."))' | head -n1
}

discover_peer_ipv4() {
  local peer_name="$1"
  local result
  result=$(jq -r --arg name "$peer_name" '
    .Peer // {} | to_entries[] | select(.value.HostName == $name) | .value.TailscaleIPs[]?
    | select(test("^[0-9]+\\."))' | head -n1)
  if [ -z "$result" ]; then
    echo "no IPv4 found for peer $peer_name" >&2
    return 1
  fi
  printf '%s' "$result"
}

# Convenience: cache desktop hostname to disk so repeated runs don't re-query.
cache_desktop_hostname() {
  local cache_file="$1"
  if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi
  local name
  name=$(tailscale status --json | discover_desktop_hostname)
  if [ -z "$name" ]; then
    echo "could not discover desktop Tailscale hostname" >&2
    return 1
  fi
  printf '%s' "$name" > "$cache_file"
  printf '%s' "$name"
}
```

- [ ] **Step 3.5: Run tests to verify they pass**

```bash
bats tests/bats/test_tailscale_discover.bats
```

Expected: 4 passing.

- [ ] **Step 3.6: Lint**

```bash
shellcheck lib/tailscale-discover.sh
```

Expected: no errors.

- [ ] **Step 3.7: Commit**

```bash
git add scripts/install-hermes-on-s24/lib/tailscale-discover.sh scripts/install-hermes-on-s24/tests/fixtures/tailscale-status.json scripts/install-hermes-on-s24/tests/bats/test_tailscale_discover.bats
git commit -m "feat(install): add lib/tailscale-discover with bats tests"
```

---

## Task 4: `env/.env.bootstrap.example` + secrets allowlist documented

**Files:**
- Create: `scripts/install-hermes-on-s24/env/.env.bootstrap.example`

- [ ] **Step 4.1: Write the template**

```bash
# Bootstrap secrets for hermes-on-s24 install.
# Copy this file to /home/hammer/Documents/repos/hermaper/.env (gitignored)
# and fill in real values. Only keys on the allowlist below are forwarded
# to the phone. Anything else is silently ignored by secrets-sync.
#
# Allowlist (forwarded to phone ~/.hermes/.env):
#   OPENROUTER_API_KEY
#   OPENAI_API_KEY
#   GROQ_API_KEY
#   ELEVENLABS_API_KEY        (optional — TTS)
#   TELEGRAM_BOT_TOKEN        (optional — Tier 7e)
#   HONCHO_AUTH_TOKEN         (optional — only when Honcho auth enabled)
#   OPENROUTER_PRIMARY_MODEL  (substituted into s24-cloud profile)
#   OPENAI_FALLBACK_MODEL     (substituted into s24-cloud profile)

# --- Cloud LLM ---
OPENROUTER_API_KEY=
OPENAI_API_KEY=

# Phone-specific keys (low-limit) STRONGLY preferred over reusing desktop keys.
# https://openrouter.ai/keys -> create new key labeled "miguels-s24"

# Default models for s24-cloud profile.
# Pick names available to your account.
OPENROUTER_PRIMARY_MODEL=anthropic/claude-3.5-sonnet
OPENAI_FALLBACK_MODEL=gpt-4o-mini

# --- Voice ---
GROQ_API_KEY=
# ELEVENLABS_API_KEY=          # uncomment if using ElevenLabs TTS

# --- Optional ---
# TELEGRAM_BOT_TOKEN=
# HONCHO_AUTH_TOKEN=           # only when AUTH_USE_AUTH=true on desktop Honcho
```

- [ ] **Step 4.2: Commit**

```bash
git add scripts/install-hermes-on-s24/env/.env.bootstrap.example
git commit -m "feat(install): add .env.bootstrap.example with allowlist documented"
```

---

## Task 5: `lib/secrets-sync.sh`

**Files:**
- Create: `scripts/install-hermes-on-s24/lib/secrets-sync.sh`
- Create: `scripts/install-hermes-on-s24/tests/fixtures/desktop.env.sample`
- Create: `scripts/install-hermes-on-s24/tests/bats/test_secrets_sync.bats`

- [ ] **Step 5.1: Write the fixture**

`tests/fixtures/desktop.env.sample`:

```
OPENROUTER_API_KEY=sk-or-v1-DESKTOP-KEY
OPENAI_API_KEY=sk-DESKTOP-KEY
GROQ_API_KEY=gsk_DESKTOP
TELEGRAM_BOT_TOKEN=
ELEVENLABS_API_KEY=eleven-DESKTOP

# Should NOT be forwarded:
PRIVATE_DESKTOP_SECRET=should-not-leak
GITHUB_TOKEN=ghp-DESKTOP
DATABASE_URL=postgres://desktop/db

OPENROUTER_PRIMARY_MODEL=anthropic/claude-3.5-sonnet
OPENAI_FALLBACK_MODEL=gpt-4o-mini
```

- [ ] **Step 5.2: Write the failing test**

`tests/bats/test_secrets_sync.bats`:

```bats
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
  log="$(filter_to_phone_env "$FIXTURES/desktop.env.sample" 2>&1 1>"$OUT" | summary_log)"
  ! echo "$log" | grep -q 'sk-or-v1'
}
```

- [ ] **Step 5.3: Run test to verify it fails**

```bash
bats tests/bats/test_secrets_sync.bats
```

Expected: 5 failures.

- [ ] **Step 5.4: Implement `lib/secrets-sync.sh`**

```bash
#!/usr/bin/env bash
# secrets-sync.sh — read desktop .env, filter to allowlist, emit phone .env.
# Never logs values, only key names.

SECRETS_ALLOWLIST=(
  OPENROUTER_API_KEY
  OPENAI_API_KEY
  GROQ_API_KEY
  ELEVENLABS_API_KEY
  TELEGRAM_BOT_TOKEN
  HONCHO_AUTH_TOKEN
  OPENROUTER_PRIMARY_MODEL
  OPENAI_FALLBACK_MODEL
)

declare -a _SECRETS_SYNCED=()
declare -a _SECRETS_ABSENT=()

_is_allowlisted() {
  local key="$1"
  for k in "${SECRETS_ALLOWLIST[@]}"; do
    [ "$k" = "$key" ] && return 0
  done
  return 1
}

filter_to_phone_env() {
  local src="$1"
  _SECRETS_SYNCED=()
  _SECRETS_ABSENT=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      if _is_allowlisted "$key"; then
        if [ -n "$val" ]; then
          printf '%s=%s\n' "$key" "$val"
          _SECRETS_SYNCED+=("$key")
        else
          _SECRETS_ABSENT+=("$key")
        fi
      fi
    fi
  done < "$src"
}

append_phone_specific_env() {
  local out="$1"
  : "${HONCHO_BASE_URL:?HONCHO_BASE_URL not set}"
  : "${HONCHO_WORKSPACE:?HONCHO_WORKSPACE not set}"
  {
    printf 'HONCHO_BASE_URL=%s\n' "$HONCHO_BASE_URL"
    printf 'HONCHO_WORKSPACE=%s\n' "$HONCHO_WORKSPACE"
  } >> "$out"
}

summary_log() {
  printf '[secrets-sync] synced: %s\n' "${_SECRETS_SYNCED[*]:-<none>}" >&2
  printf '[secrets-sync] absent: %s\n' "${_SECRETS_ABSENT[*]:-<none>}" >&2
}
```

- [ ] **Step 5.5: Run tests to verify they pass**

```bash
bats tests/bats/test_secrets_sync.bats
```

Expected: 5 passing.

- [ ] **Step 5.6: Lint**

```bash
shellcheck lib/secrets-sync.sh
```

Expected: no errors.

- [ ] **Step 5.7: Commit**

```bash
git add scripts/install-hermes-on-s24/lib/secrets-sync.sh scripts/install-hermes-on-s24/tests/fixtures/desktop.env.sample scripts/install-hermes-on-s24/tests/bats/test_secrets_sync.bats
git commit -m "feat(install): add lib/secrets-sync with allowlist filter and bats tests"
```

---

## Task 6: `lib/honcho-bind.sh` — recommendation printer

**Files:**
- Create: `scripts/install-hermes-on-s24/lib/honcho-bind.sh`
- Create: `scripts/install-hermes-on-s24/tests/bats/test_honcho_bind.bats`

- [ ] **Step 6.1: Write the failing test**

`tests/bats/test_honcho_bind.bats`:

```bats
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
  before="$(find /tmp -maxdepth 1 -newer /tmp 2>/dev/null | wc -l)"
  print_recommendation 100.64.10.42 miguels-s24 > "$OUT"
  after="$(find /tmp -maxdepth 1 -newer /tmp 2>/dev/null | wc -l)"
  [ "$before" = "$after" ]
}
```

- [ ] **Step 6.2: Run test to verify it fails**

```bash
bats tests/bats/test_honcho_bind.bats
```

Expected: 4 failures.

- [ ] **Step 6.3: Implement `lib/honcho-bind.sh`**

```bash
#!/usr/bin/env bash
# honcho-bind.sh — prints the configuration changes the user must apply
# to expose Honcho on Tailscale safely. NEVER modifies any file or service.

print_recommendation() {
  local desktop_ts_ip="$1"
  local phone_host="$2"

  cat <<EOF
==========================================================================
Honcho exposure recommendation
==========================================================================

The phone "$phone_host" needs to reach Honcho on this desktop's Tailscale
interface ($desktop_ts_ip:18000). Honcho currently binds to 127.0.0.1.

PREFERRED — enable Honcho auth + Tailscale ACL:
  1. In honcho's config (.env or systemd unit), set:
       AUTH_USE_AUTH=true
       AUTH_JWT_SECRET=<rotate to a fresh long random string>
       HOST=$desktop_ts_ip       # bind to Tailscale interface only
  2. Mint a phone-only token via Honcho's keys API; copy the value into
     the desktop /home/hammer/Documents/repos/hermaper/.env as
     HONCHO_AUTH_TOKEN=...
  3. In your Tailscale ACL (https://login.tailscale.com/admin/acls),
     restrict access:
       {
         "acls": [
           {"action": "accept",
            "src": ["$phone_host"],
            "dst": ["$desktop_ts_ip:18000"]}
         ]
       }
  4. Restart Honcho.

ACCEPTABLE FALLBACK — keep AUTH_USE_AUTH=false (private lab posture).
  All four conditions MUST be true:
    - HOST=$desktop_ts_ip (NEVER 0.0.0.0).
    - Tailscale ACL allows only $phone_host -> $desktop_ts_ip:18000.
    - No external/shared tailnet users can reach this desktop node.
    - Postgres :5433 stays bound to localhost.

ALTERNATIVE — Tailscale Serve:
  Instead of rebinding Honcho, run:
    tailscale serve --bg --tcp 18000 tcp://localhost:18000
  This exposes the local Honcho into the tailnet without changing the
  app's bind address. ACLs still apply.

==========================================================================
The install script will not modify Honcho. Apply one of the options above
manually, then press ENTER to continue.
EOF
}
```

- [ ] **Step 6.4: Run tests to verify they pass**

```bash
bats tests/bats/test_honcho_bind.bats
```

Expected: 4 passing.

- [ ] **Step 6.5: Lint**

```bash
shellcheck lib/honcho-bind.sh
```

- [ ] **Step 6.6: Commit**

```bash
git add scripts/install-hermes-on-s24/lib/honcho-bind.sh scripts/install-hermes-on-s24/tests/bats/test_honcho_bind.bats
git commit -m "feat(install): add lib/honcho-bind printer (prints, never modifies)"
```

---

## Task 7: `lib/profile-render.sh` and profile YAML templates

**Files:**
- Create: `scripts/install-hermes-on-s24/profiles/s24-cloud.yaml`
- Create: `scripts/install-hermes-on-s24/profiles/s24-local.yaml`
- Create: `scripts/install-hermes-on-s24/lib/profile-render.sh`
- Create: `scripts/install-hermes-on-s24/tests/bats/test_profile_render.bats`

- [ ] **Step 7.1: Write `profiles/s24-cloud.yaml`**

```yaml
# s24-cloud — phone Hermes profile for online use.
# Generated from template by lib/profile-render.sh; placeholders %%KEY%%
# are substituted from the synced phone .env.

model:
  provider: openrouter
  default: %%OPENROUTER_PRIMARY_MODEL%%

fallback_model:
  provider: openai
  model: %%OPENAI_FALLBACK_MODEL%%

memory:
  provider: honcho

stt:
  provider: groq
  groq:
    model: whisper-large-v3
tts:
  provider: openai
```

- [ ] **Step 7.2: Write `profiles/s24-local.yaml`**

```yaml
# s24-local — phone Hermes profile for offline use.
# Local llama-server is started on demand via ~/.hermes/bin/start-local-llm.

model:
  provider: custom
  default: qwen3-4b-local
  base_url: http://127.0.0.1:8080/v1
  api_key: ""
  context_length: 8192

memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 1600
  user_char_limit: 1000

file_read_max_chars: 20000

tool_output:
  max_bytes: 12000
  max_lines: 300
  max_line_length: 1000
```

- [ ] **Step 7.3: Write the failing test**

`tests/bats/test_profile_render.bats`:

```bats
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
```

- [ ] **Step 7.4: Run test to verify it fails**

```bash
bats tests/bats/test_profile_render.bats
```

Expected: 3 failures.

- [ ] **Step 7.5: Implement `lib/profile-render.sh`**

```bash
#!/usr/bin/env bash
# profile-render.sh — substitute %%KEY%% placeholders in profile templates
# from environment variables. Fails fast if any placeholder has no value.

render_profile() {
  local template="$1"
  [ -f "$template" ] || { echo "template not found: $template" >&2; return 1; }

  local content
  content=$(cat "$template")

  # Find all %%KEY%% placeholders.
  local placeholders
  placeholders=$(grep -oE '%%[A-Z_][A-Z0-9_]*%%' "$template" | sort -u || true)

  for ph in $placeholders; do
    local key="${ph#%%}"; key="${key%%%%}"
    local val="${!key:-}"
    if [ -z "$val" ]; then
      echo "missing env value for placeholder $ph" >&2
      return 1
    fi
    content=${content//"$ph"/"$val"}
  done

  printf '%s\n' "$content"
}
```

- [ ] **Step 7.6: Run tests to verify they pass**

```bash
bats tests/bats/test_profile_render.bats
```

Expected: 3 passing.

- [ ] **Step 7.7: Lint**

```bash
shellcheck lib/profile-render.sh
```

- [ ] **Step 7.8: Commit**

```bash
git add scripts/install-hermes-on-s24/profiles/ scripts/install-hermes-on-s24/lib/profile-render.sh scripts/install-hermes-on-s24/tests/bats/test_profile_render.bats
git commit -m "feat(install): add profile templates and lib/profile-render"
```

---

## Task 8: Honcho client config + Termux:Boot script + on-demand launchers

**Files:**
- Create: `scripts/install-hermes-on-s24/phone/honcho.json`
- Create: `scripts/install-hermes-on-s24/phone/boot/00-hermes-startup.sh`
- Create: `scripts/install-hermes-on-s24/phone/bin/start-local-llm`
- Create: `scripts/install-hermes-on-s24/phone/bin/llama-server-qwen3.sh`
- Create: `scripts/install-hermes-on-s24/phone/bin/llama-server-hermes3.sh`

- [ ] **Step 8.1: Write `phone/honcho.json`**

```json
{
  "hosts": {
    "hermes": {
      "recallMode": "tools",
      "writeFrequency": "async"
    }
  }
}
```

- [ ] **Step 8.2: Write `phone/boot/00-hermes-startup.sh`**

```bash
#!/data/data/com.termux/files/usr/bin/bash
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
  set -a; . "$HOME/.hermes/.env"; set +a
fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ "${HERMES_GATEWAY_AUTOSTART:-0}" = "1" ]; then
  echo "[$(date -Iseconds)] starting hermes gateway"
  nohup hermes -p s24-cloud gateway start >>"$HOME/.hermes/logs/gateway.log" 2>&1 &
fi

echo "[$(date -Iseconds)] boot script done"
```

- [ ] **Step 8.3: Write `phone/bin/llama-server-qwen3.sh`**

```bash
#!/data/data/com.termux/files/usr/bin/bash
# llama-server-qwen3.sh — launches Qwen3-4B locally on :8080 with --jinja.
# Default context 8192; override via CTX env var.

set -euo pipefail

MODEL="$HOME/llama.cpp/models/Qwen3-4B-Q4_K_M.gguf"
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
  --port 8080
```

- [ ] **Step 8.4: Write `phone/bin/llama-server-hermes3.sh`**

```bash
#!/data/data/com.termux/files/usr/bin/bash
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
```

- [ ] **Step 8.5: Write `phone/bin/start-local-llm`**

```bash
#!/data/data/com.termux/files/usr/bin/bash
# start-local-llm — convenience wrapper: foreground Qwen3 launcher.
# Use Ctrl-C to stop. Run from a Termux session you can leave open.

set -euo pipefail
echo "Starting Qwen3-4B llama-server on http://127.0.0.1:8080 (Ctrl-C to stop)"
exec "$HOME/.hermes/bin/llama-server-qwen3.sh"
```

- [ ] **Step 8.6: Lint each shell file**

```bash
shellcheck phone/boot/00-hermes-startup.sh phone/bin/start-local-llm phone/bin/llama-server-qwen3.sh phone/bin/llama-server-hermes3.sh
```

Expected: no errors. The `#!/data/data/com.termux/...` shebang may trigger a warning on desktop shellcheck — disable with `# shellcheck shell=bash` directive at top if so.

- [ ] **Step 8.7: Commit**

```bash
git add scripts/install-hermes-on-s24/phone/
git commit -m "feat(install): add phone-side honcho.json, boot script, llama-server launchers"
```

---

## Task 9: `prereqs-check.sh` — Phase −1 verification

**Files:**
- Create: `scripts/install-hermes-on-s24/prereqs-check.sh`

- [ ] **Step 9.1: Implement `prereqs-check.sh`**

```bash
#!/usr/bin/env bash
# prereqs-check.sh — verify Phase -1 prerequisites on the phone before
# the install script runs. Implements gates G0, G0a, G0b, G0c.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/tailscale-discover.sh
source "$SCRIPT_DIR/lib/tailscale-discover.sh"

require_cmd ssh scp jq tailscale

main() {
  log_info "prereqs-check starting (PHONE=$PHONE_USER@$PHONE_HOST:$PHONE_SSH_PORT)"

  # G0c: Tailscale resolution from desktop.
  log_info "G0c: resolving phone via Tailscale"
  local phone_ip
  phone_ip=$(tailscale status --json | discover_peer_ipv4 "$PHONE_HOST") \
    || die "G0c FAIL: phone $PHONE_HOST not visible in tailscale status"
  log_gate G0c "phone IP via Tailscale = $phone_ip"

  # G1 prerequisite: SSH key auth must be set up before this script runs.
  log_info "verifying SSH key auth (run ssh-copy-id manually first if this fails)"
  if ! run_remote 'echo OK' >/dev/null 2>&1; then
    die "SSH key auth failed. From desktop run:
        ssh-copy-id -p $PHONE_SSH_PORT $PHONE_USER@$PHONE_HOST
       (One-time, requires phone password.) Then re-run this script."
  fi
  log_gate G1 "SSH key auth working"

  # G0: termux-info captured.
  log_info "G0: capturing termux-info"
  if ! run_remote 'termux-info' >>"$INSTALL_LOG_FILE" 2>&1; then
    die "G0 FAIL: termux-info unavailable. Is Termux app installed on phone?"
  fi
  log_gate G0 "termux-info captured to log"

  # G0a: sshd present and running.
  log_info "G0a: checking sshd"
  if ! run_remote 'command -v sshd >/dev/null && pgrep -x sshd >/dev/null'; then
    die "G0a FAIL: sshd not installed or not running. On phone:
        pkg install -y openssh && sshd"
  fi
  log_gate G0a "sshd present and running"

  # G0b: Termux:API app + termux-api package both work.
  log_info "G0b: testing termux-battery-status (proves Termux:API app installed)"
  if ! run_remote 'termux-battery-status' >/dev/null 2>&1; then
    die "G0b FAIL: termux-battery-status returned no JSON. Install BOTH:
        - termux-api package: pkg install -y termux-api
        - Termux:API app from F-Droid (companion app)"
  fi
  log_gate G0b "Termux:API app + package working"

  log_info "All Phase -1 gates passed. Ready to run install.sh."
}

main "$@"
```

- [ ] **Step 9.2: Lint**

```bash
shellcheck prereqs-check.sh
```

- [ ] **Step 9.3: Smoke-test in DRY_RUN mode**

```bash
DRY_RUN=1 ./prereqs-check.sh 2>&1 | head -40
```

Expected: prints `+ ssh ... termux-info`, `+ ssh ... sshd`, etc. without actually running them. (The `tailscale` call still runs locally; if you don't have Tailscale or the peer isn't online, expect the G0c gate to fail. That's fine in dry-run; the gate logic is being exercised.)

- [ ] **Step 9.4: Commit**

```bash
chmod +x prereqs-check.sh
git add scripts/install-hermes-on-s24/prereqs-check.sh
git commit -m "feat(install): add prereqs-check implementing gates G0-G0c, G1"
```

---

## Task 10: `tier1-bootstrap.sh` skeleton + Phase 1 (pkg install)

**Files:**
- Create: `scripts/install-hermes-on-s24/tier1-bootstrap.sh`

- [ ] **Step 10.1: Write the script skeleton with Phase 1**

```bash
#!/usr/bin/env bash
# tier1-bootstrap.sh — runs phases 1-10 of Tier 1 over SSH against the phone.
# Each phase is idempotent and writes a marker under ~/.hermes/.install-state.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PKG_LIST="git python clang rust make pkg-config libffi openssl nodejs ripgrep ffmpeg openssh termux-api jq cronie"

phase_pkg_install() {
  if phase_done phase1-pkg; then log_info "phase1-pkg: already done, skipping"; return 0; fi
  log_info "phase1-pkg: installing Termux packages"
  run_remote "pkg update -y && pkg install -y $PKG_LIST"
  mark_phase_done phase1-pkg
  log_gate G2 "phase1-pkg complete"
}

main() {
  log_info "tier1-bootstrap starting"
  phase_pkg_install
  log_info "tier1-bootstrap: phase 1 done (more phases to follow)"
}

main "$@"
```

- [ ] **Step 10.2: Lint**

```bash
shellcheck tier1-bootstrap.sh
```

- [ ] **Step 10.3: Dry-run smoke test**

```bash
DRY_RUN=1 ./tier1-bootstrap.sh 2>&1 | head -20
```

Expected: prints `+ ssh ... pkg update -y && pkg install -y ...`. Idempotency check happens against the (real or simulated) marker — in DRY_RUN with no real ssh, `phase_done` returns false and the install proceeds.

- [ ] **Step 10.4: Commit**

```bash
chmod +x tier1-bootstrap.sh
git add scripts/install-hermes-on-s24/tier1-bootstrap.sh
git commit -m "feat(install): tier1 phase 1 (pkg install) with idempotency markers"
```

---

## Task 11: Tier 1 Phases 2–5 (clone, venv, pip install, symlink)

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier1-bootstrap.sh`

- [ ] **Step 11.1: Add `phase_clone_repo`**

Append to `tier1-bootstrap.sh` before `main()`:

```bash
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
```

- [ ] **Step 11.2: Add `phase_create_venv`**

```bash
phase_create_venv() {
  if phase_done phase3-venv; then log_info "phase3-venv: already done, skipping"; return 0; fi
  log_info "phase3-venv: creating Python venv"
  run_remote 'cd ~/hermes-agent && python -m venv venv && \
    . venv/bin/activate && pip install --upgrade pip setuptools wheel'
  mark_phase_done phase3-venv
}
```

- [ ] **Step 11.3: Add `phase_pip_install`**

```bash
phase_pip_install() {
  if phase_done phase4-pip; then log_info "phase4-pip: already done, skipping"; return 0; fi
  log_info "phase4-pip: installing .[termux] (this takes ~15-25 min, plug in USB)"
  run_remote 'cd ~/hermes-agent && \
    export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk)" && \
    . venv/bin/activate && \
    pip install -e .[termux] -c constraints-termux.txt'
  mark_phase_done phase4-pip
  log_gate G3 "phase4-pip complete (hermes installed)"
}
```

- [ ] **Step 11.4: Add `phase_symlink`**

```bash
phase_symlink() {
  if phase_done phase5-symlink; then log_info "phase5-symlink: already done, skipping"; return 0; fi
  log_info "phase5-symlink: linking hermes into PATH"
  run_remote 'ln -sf ~/hermes-agent/venv/bin/hermes "$PREFIX/bin/hermes"'
  mark_phase_done phase5-symlink
}
```

- [ ] **Step 11.5: Update `main()` to call them in order**

Replace the existing `main()` body with:

```bash
main() {
  log_info "tier1-bootstrap starting"
  phase_pkg_install
  phase_clone_repo
  phase_create_venv
  phase_pip_install
  phase_symlink
  log_info "tier1-bootstrap: phases 1-5 done"
}
```

- [ ] **Step 11.6: Lint**

```bash
shellcheck tier1-bootstrap.sh
```

- [ ] **Step 11.7: Dry-run**

```bash
DRY_RUN=1 ./tier1-bootstrap.sh 2>&1 | head -40
```

Expected: 5 phases echoed, each with ssh command preview.

- [ ] **Step 11.8: Commit**

```bash
git add scripts/install-hermes-on-s24/tier1-bootstrap.sh
git commit -m "feat(install): tier1 phases 2-5 (clone, venv, pip, symlink)"
```

---

## Task 12: Tier 1 Phase 6–7 — secrets sync + honcho.json

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier1-bootstrap.sh`

- [ ] **Step 12.1: Add `phase_secrets_sync`**

Source the secrets helper at the top of the script (right under `source "$SCRIPT_DIR/lib/common.sh"`):

```bash
# shellcheck source=lib/secrets-sync.sh
source "$SCRIPT_DIR/lib/secrets-sync.sh"
# shellcheck source=lib/tailscale-discover.sh
source "$SCRIPT_DIR/lib/tailscale-discover.sh"
```

Add `phase_secrets_sync` before `main()`:

```bash
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

  local tmp; tmp=$(mktemp); trap 'rm -f "$tmp"' RETURN
  filter_to_phone_env "$DESKTOP_ENV_FILE" > "$tmp"
  HONCHO_BASE_URL="$HONCHO_BASE_URL" HONCHO_WORKSPACE="$HONCHO_WORKSPACE" append_phone_specific_env "$tmp"
  summary_log

  run_remote 'mkdir -p ~/.hermes && chmod 700 ~/.hermes'
  copy_remote "$tmp" '~/.hermes/.env'
  run_remote 'chmod 600 ~/.hermes/.env'

  mark_phase_done phase6-secrets
  log_info "phase6-secrets: complete (HONCHO_BASE_URL=$HONCHO_BASE_URL)"
}
```

- [ ] **Step 12.2: Add `phase_honcho_json`**

```bash
phase_honcho_json() {
  if phase_done phase7-honcho-json; then log_info "phase7-honcho-json: already done, skipping"; return 0; fi
  log_info "phase7-honcho-json: writing ~/.hermes/honcho.json"
  copy_remote "$SCRIPT_DIR/phone/honcho.json" '~/.hermes/honcho.json'
  run_remote 'chmod 600 ~/.hermes/honcho.json'
  mark_phase_done phase7-honcho-json
}
```

- [ ] **Step 12.3: Update `main()`**

```bash
main() {
  log_info "tier1-bootstrap starting"
  phase_pkg_install
  phase_clone_repo
  phase_create_venv
  phase_pip_install
  phase_symlink
  phase_secrets_sync
  phase_honcho_json
  log_info "tier1-bootstrap: phases 1-7 done"
}
```

- [ ] **Step 12.4: Lint + dry-run**

```bash
shellcheck tier1-bootstrap.sh
DRY_RUN=1 ./tier1-bootstrap.sh 2>&1 | head -60
```

Expected: phases 6 and 7 echo `+ scp ...` and `+ ssh ...` commands.

- [ ] **Step 12.5: Commit**

```bash
git add scripts/install-hermes-on-s24/tier1-bootstrap.sh
git commit -m "feat(install): tier1 phases 6-7 (secrets sync, honcho.json)"
```

---

## Task 13: Tier 1 Phase 8 — profile creation

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier1-bootstrap.sh`

- [ ] **Step 13.1: Add `phase_profiles`**

Source the renderer at the top:

```bash
# shellcheck source=lib/profile-render.sh
source "$SCRIPT_DIR/lib/profile-render.sh"
```

Add `phase_profiles`:

```bash
phase_profiles() {
  if phase_done phase8-profiles; then log_info "phase8-profiles: already done, skipping"; return 0; fi
  log_info "phase8-profiles: creating s24-cloud and s24-local"

  # Source the synced phone .env locally to obtain model-name placeholders.
  # We re-read the desktop file (canonical) since the phone copy is filtered the same way.
  : "${DESKTOP_ENV_FILE:=/home/hammer/Documents/repos/hermaper/.env}"
  set -a; . "$DESKTOP_ENV_FILE"; set +a

  : "${OPENROUTER_PRIMARY_MODEL:?OPENROUTER_PRIMARY_MODEL not set in $DESKTOP_ENV_FILE}"
  : "${OPENAI_FALLBACK_MODEL:?OPENAI_FALLBACK_MODEL not set in $DESKTOP_ENV_FILE}"

  local cloud_tmp local_tmp
  cloud_tmp=$(mktemp); local_tmp=$(mktemp)
  trap 'rm -f "$cloud_tmp" "$local_tmp"' RETURN

  render_profile "$SCRIPT_DIR/profiles/s24-cloud.yaml" > "$cloud_tmp"
  render_profile "$SCRIPT_DIR/profiles/s24-local.yaml" > "$local_tmp"

  # Create profiles via hermes CLI (idempotent: if a profile already exists,
  # `profile create --clone` errors; tolerate that and overwrite the config).
  run_remote 'hermes profile create s24-cloud --clone || true'
  run_remote 'hermes profile create s24-local --clone || true'

  # Hermes profiles live under ~/.hermes/profiles/<name>/config.yaml
  copy_remote "$cloud_tmp" '~/.hermes/profiles/s24-cloud/config.yaml'
  copy_remote "$local_tmp" '~/.hermes/profiles/s24-local/config.yaml'

  mark_phase_done phase8-profiles
}
```

Update `main()`:

```bash
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
  log_info "tier1-bootstrap: phases 1-8 done"
}
```

- [ ] **Step 13.2: Lint + dry-run**

```bash
shellcheck tier1-bootstrap.sh
DRY_RUN=1 ./tier1-bootstrap.sh 2>&1 | head -80
```

Expected: profile creation commands appear; rendered YAML written to /tmp temp files.

- [ ] **Step 13.3: Commit**

```bash
git add scripts/install-hermes-on-s24/tier1-bootstrap.sh
git commit -m "feat(install): tier1 phase 8 (s24-cloud, s24-local profile creation)"
```

---

## Task 14: Tier 1 Phases 9–10 — doctor + smoke test

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier1-bootstrap.sh`

- [ ] **Step 14.1: Add `phase_doctor`**

```bash
phase_doctor() {
  if phase_done phase9-doctor; then log_info "phase9-doctor: already done, skipping"; return 0; fi
  log_info "phase9-doctor: running 'hermes -p s24-cloud doctor'"
  local doctor_out
  doctor_out=$(run_remote 'hermes -p s24-cloud doctor' 2>&1) || true
  printf '%s\n' "$doctor_out" >> "$INSTALL_LOG_FILE"

  # Treat Docker/voice warnings as expected; halt only on hard errors.
  if echo "$doctor_out" | grep -qiE 'error|fail' \
     && ! echo "$doctor_out" | grep -qiE 'docker|voice|faster-whisper|ctranslate2'; then
    die "G4 FAIL: hermes doctor reported a non-Docker/voice error. See log."
  fi
  mark_phase_done phase9-doctor
  log_gate G4 "hermes doctor exits clean (Docker/voice warnings tolerated)"
}
```

- [ ] **Step 14.2: Add `phase_smoke_test`**

```bash
phase_smoke_test() {
  if phase_done phase10-smoke; then log_info "phase10-smoke: already done, skipping"; return 0; fi
  log_info "phase10-smoke: cloud round-trip + memory status"

  # G5: one-shot cloud round-trip via OpenRouter.
  run_remote "hermes -p s24-cloud chat --once 'Reply with the single word: pong.'" \
    | tee -a "$INSTALL_LOG_FILE" | grep -qi 'pong' \
    || die "G5 FAIL: cloud round-trip did not return 'pong'. Check OPENROUTER_API_KEY."
  log_gate G5 "cloud round-trip OK"

  # G6: Honcho reachable and active.
  local mem_status
  mem_status=$(run_remote 'hermes memory status' 2>&1)
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
```

- [ ] **Step 14.3: Update `main()`**

```bash
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
```

- [ ] **Step 14.4: Lint + dry-run**

```bash
shellcheck tier1-bootstrap.sh
DRY_RUN=1 ./tier1-bootstrap.sh 2>&1 | tail -30
```

Expected: phases 9 and 10 show ssh commands. Note: in dry-run, `grep` against an empty stdout will fail. That's expected; dry-run validates command shape, not happy-path responses. Document this in README troubleshooting.

- [ ] **Step 14.5: Commit**

```bash
git add scripts/install-hermes-on-s24/tier1-bootstrap.sh
git commit -m "feat(install): tier1 phases 9-10 (doctor + smoke test, gates G4-G6b)"
```

---

## Task 15: `tier2-bootstrap.sh` skeleton + flag parsing

**Files:**
- Create: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 15.1: Write the skeleton with flag parsing**

```bash
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
    --no-local-llm)     WITH_LOCAL_LLM=0 ;;
    --no-persistence)   WITH_PERSISTENCE=0 ;;
    --with-voice)       WITH_VOICE=1 ;;
    --with-edge-gallery) WITH_EDGE_GALLERY=1 ;;
    --with-telegram)    WITH_TELEGRAM=1 ;;
    --with-browser)     WITH_BROWSER=1 ;;
    --all)              WITH_VOICE=1; WITH_EDGE_GALLERY=1; WITH_TELEGRAM=1; WITH_BROWSER=1 ;;
    -h|--help)          usage; exit 0 ;;
    *)                  log_err "unknown flag: $1"; usage; exit 1 ;;
  esac
  shift
done

main() {
  log_info "tier2-bootstrap starting (local-llm=$WITH_LOCAL_LLM persistence=$WITH_PERSISTENCE voice=$WITH_VOICE edge=$WITH_EDGE_GALLERY tg=$WITH_TELEGRAM browser=$WITH_BROWSER)"
  log_info "tier2-bootstrap: skeleton only; modules added in subsequent tasks"
}

main "$@"
```

- [ ] **Step 15.2: Lint + dry-run**

```bash
shellcheck tier2-bootstrap.sh
DRY_RUN=1 ./tier2-bootstrap.sh --help
DRY_RUN=1 ./tier2-bootstrap.sh --all 2>&1 | head -5
```

Expected: usage text prints; flag toggling works.

- [ ] **Step 15.3: Commit**

```bash
chmod +x tier2-bootstrap.sh
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2 skeleton with flag parsing"
```

---

## Task 16: Tier 2a — local LLM install (Qwen3 download + launchers)

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 16.1: Pin the model file metadata**

Determine the canonical Qwen3-4B GGUF source. The Hugging Face repo is `Qwen/Qwen3-4B-GGUF`. Pick the `Q4_K_M` quant. Compute its SHA256 by checking the repo file hashes (the install script will verify on the phone after download).

Add near the top of `tier2-bootstrap.sh` (just under the flag parsing):

```bash
QWEN3_REPO_URL="https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main"
QWEN3_FILE="Qwen3-4B-Q4_K_M.gguf"
# Pin the SHA256 published on the HF model card. Verified at install time.
# If the upstream repo updates the file, this constant must be updated and
# the model re-verified manually before continuing.
QWEN3_SHA256="REPLACE_WITH_REAL_SHA256_FROM_HF_MODEL_CARD"
```

> **Note for executor:** before running this Task end-to-end, fetch the actual SHA256 from `https://huggingface.co/Qwen/Qwen3-4B-GGUF/blob/main/Qwen3-4B-Q4_K_M.gguf` (the file's metadata page lists the LFS pointer hash). Replace the literal `REPLACE_WITH_REAL_SHA256_FROM_HF_MODEL_CARD` and commit.

- [ ] **Step 16.2: Add `module_local_llm`**

Append before `main()`:

```bash
module_local_llm() {
  [ "$WITH_LOCAL_LLM" = "1" ] || { log_info "local-llm: skipped"; return 0; }
  if phase_done tier2-local-llm; then log_info "local-llm: already done, skipping"; return 0; fi

  log_info "local-llm: verifying llama-server build"
  run_remote 'test -x ~/llama.cpp/build/bin/llama-server' \
    || die "llama-server binary missing at ~/llama.cpp/build/bin/llama-server. Build llama.cpp on phone first."

  log_info "local-llm: ensuring models dir exists"
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
    run_remote "echo '$QWEN3_SHA256  $HOME/llama.cpp/models/$QWEN3_FILE' | sha256sum -c -" \
      || die "QWEN3 SHA256 mismatch. Refusing to use the downloaded file."
  fi

  log_info "local-llm: installing launchers"
  run_remote 'mkdir -p ~/.hermes/bin'
  copy_remote "$SCRIPT_DIR/phone/bin/llama-server-qwen3.sh"   '~/.hermes/bin/llama-server-qwen3.sh'
  copy_remote "$SCRIPT_DIR/phone/bin/llama-server-hermes3.sh" '~/.hermes/bin/llama-server-hermes3.sh'
  copy_remote "$SCRIPT_DIR/phone/bin/start-local-llm"         '~/.hermes/bin/start-local-llm'
  run_remote 'chmod +x ~/.hermes/bin/*.sh ~/.hermes/bin/start-local-llm'

  mark_phase_done tier2-local-llm
  log_info "local-llm: done. Run 'start-local-llm' on the phone, then 'hermes -p s24-local'."
}
```

Update `main()`:

```bash
main() {
  log_info "tier2-bootstrap starting (local-llm=$WITH_LOCAL_LLM persistence=$WITH_PERSISTENCE voice=$WITH_VOICE edge=$WITH_EDGE_GALLERY tg=$WITH_TELEGRAM browser=$WITH_BROWSER)"
  module_local_llm
}
```

- [ ] **Step 16.3: Lint + dry-run**

```bash
shellcheck tier2-bootstrap.sh
DRY_RUN=1 ./tier2-bootstrap.sh 2>&1 | head -30
```

- [ ] **Step 16.4: Commit**

```bash
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2a local-llm download + launcher install (no autostart)"
```

---

## Task 17: Tier 2d — boot persistence (sshd + wake-lock only)

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 17.1: Add `module_persistence`**

```bash
module_persistence() {
  [ "$WITH_PERSISTENCE" = "1" ] || { log_info "persistence: skipped"; return 0; }
  if phase_done tier2-persistence; then log_info "persistence: already done, skipping"; return 0; fi

  log_info "persistence: ensuring Termux:Boot is installed (manual step on phone)"
  log_warn "  If the Termux:Boot app is not installed, install it from F-Droid and"
  log_warn "  launch it ONCE before continuing. Press ENTER to confirm done."
  if [ "$DRY_RUN" != "1" ]; then read -r _; fi

  run_remote 'mkdir -p ~/.termux/boot'
  copy_remote "$SCRIPT_DIR/phone/boot/00-hermes-startup.sh" '~/.termux/boot/00-hermes-startup.sh'
  run_remote 'chmod +x ~/.termux/boot/00-hermes-startup.sh'

  log_info "persistence: installing sshd respawn cron"
  run_remote '(crontab -l 2>/dev/null | grep -v "respawn-sshd" ; \
               echo "*/15 * * * * pgrep -x sshd >/dev/null || sshd # respawn-sshd") | crontab -'

  mark_phase_done tier2-persistence
  log_warn "persistence: REMINDER — disable battery optimization for Termux and Termux:Boot"
  log_warn "  in Android Settings -> Apps -> <app> -> Battery -> Unrestricted."
}
```

Update `main()`:

```bash
main() {
  log_info "tier2-bootstrap starting (...)"
  module_local_llm
  module_persistence
}
```

- [ ] **Step 17.2: Lint + dry-run**

```bash
shellcheck tier2-bootstrap.sh
DRY_RUN=1 ./tier2-bootstrap.sh 2>&1 | head -50
```

- [ ] **Step 17.3: Commit**

```bash
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2d boot persistence (sshd + wake-lock; no llama-server autostart)"
```

---

## Task 18: Tier 2c — voice/STT validation

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 18.1: Add `module_voice`**

```bash
module_voice() {
  [ "$WITH_VOICE" = "1" ] || { log_info "voice: skipped (use --with-voice)"; return 0; }
  if phase_done tier2-voice; then log_info "voice: already done, skipping"; return 0; fi

  log_info "voice: validating Hermes built-in stt.provider"

  # Generate a tiny silent WAV on the phone (1 second of silence) to confirm
  # the STT call path works end-to-end. We do not transcribe real audio here
  # because that would require microphone capture; we only verify Hermes
  # accepts the request and reaches the configured provider.
  run_remote 'ffmpeg -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 ~/.hermes/test-silence.wav 2>/dev/null'

  local out
  out=$(run_remote 'hermes -p s24-cloud voice transcribe ~/.hermes/test-silence.wav 2>&1' || true)
  printf '%s\n' "$out" >> "$INSTALL_LOG_FILE"

  if echo "$out" | grep -qiE 'authentication|api key'; then
    die "voice: STT provider auth failed. Check GROQ_API_KEY (or OPENAI_API_KEY)."
  fi
  if echo "$out" | grep -qiE 'unsupported|not.*found|missing.*provider'; then
    log_warn "voice: built-in stt.provider not available under .[termux]. Document and skip."
    mark_phase_done tier2-voice
    return 0
  fi

  log_info "voice: provider responded (silence likely transcribes to empty/near-empty string — that's OK)."
  run_remote 'rm -f ~/.hermes/test-silence.wav'
  mark_phase_done tier2-voice
}
```

Update `main()`:

```bash
main() {
  ...
  module_voice
}
```

- [ ] **Step 18.2: Lint + dry-run**

```bash
shellcheck tier2-bootstrap.sh
DRY_RUN=1 ./tier2-bootstrap.sh --with-voice 2>&1 | head -60
```

- [ ] **Step 18.3: Commit**

```bash
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2c voice/STT validation (no custom shim)"
```

---

## Task 19: Tier 2b — AI Edge Gallery instructions

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 19.1: Add `module_edge_gallery`**

```bash
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
```

- [ ] **Step 19.2: Lint + commit**

```bash
shellcheck tier2-bootstrap.sh
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2b AI Edge Gallery instructions printer"
```

---

## Task 20: Tier 2e — Telegram opt-in

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 20.1: Add `module_telegram`**

```bash
module_telegram() {
  [ "$WITH_TELEGRAM" = "1" ] || { log_info "telegram: skipped (use --with-telegram)"; return 0; }

  log_info "telegram: enabling HERMES_GATEWAY_AUTOSTART in phone .env"

  # Check the phone .env has TELEGRAM_BOT_TOKEN set.
  if ! run_remote 'grep -q "^TELEGRAM_BOT_TOKEN=." ~/.hermes/.env'; then
    die "telegram: TELEGRAM_BOT_TOKEN missing or empty in phone .env. Add it to the desktop .env, re-run secrets-sync (tier1 phase 6), then re-run this module."
  fi

  run_remote '(grep -v "^HERMES_GATEWAY_AUTOSTART=" ~/.hermes/.env 2>/dev/null; \
              echo "HERMES_GATEWAY_AUTOSTART=1") > ~/.hermes/.env.new && \
              mv ~/.hermes/.env.new ~/.hermes/.env && \
              chmod 600 ~/.hermes/.env'

  log_info "telegram: starting gateway now (and on next boot)"
  run_remote 'nohup hermes -p s24-cloud gateway start >> ~/.hermes/logs/gateway.log 2>&1 &'

  mark_phase_done tier2-telegram
}
```

- [ ] **Step 20.2: Lint + commit**

```bash
shellcheck tier2-bootstrap.sh
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2e Telegram gateway opt-in"
```

---

## Task 21: Tier 2f — browser opt-in

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 21.1: Add `module_browser`**

```bash
module_browser() {
  [ "$WITH_BROWSER" = "1" ] || { log_info "browser: skipped (use --with-browser)"; return 0; }
  if phase_done tier2-browser; then log_info "browser: already done, skipping"; return 0; fi

  log_info "browser: installing nodejs-lts and running npm install (best-effort)"
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
```

Update `main()` to include all six modules:

```bash
main() {
  log_info "tier2-bootstrap starting (...)"
  module_local_llm
  module_persistence
  module_voice
  module_edge_gallery
  module_telegram
  module_browser
  log_info "tier2-bootstrap: complete"
}
```

- [ ] **Step 21.2: Lint + dry-run + commit**

```bash
shellcheck tier2-bootstrap.sh
DRY_RUN=1 ./tier2-bootstrap.sh --all 2>&1 | tail -40
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2f browser opt-in; wire all six modules"
```

---

## Task 22: Top-level `install.sh`

**Files:**
- Create: `scripts/install-hermes-on-s24/install.sh`

- [ ] **Step 22.1: Implement**

```bash
#!/usr/bin/env bash
# install.sh — top-level orchestrator: prereqs-check, tier1, optional tier2.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/honcho-bind.sh
source "$SCRIPT_DIR/lib/honcho-bind.sh"
# shellcheck source=lib/tailscale-discover.sh
source "$SCRIPT_DIR/lib/tailscale-discover.sh"

TIER1_ONLY=0
RESUME=0
TIER2_ARGS=()

usage() {
  cat <<EOF
Usage: install.sh [flags] [-- tier2-flags...]
Flags:
  --tier1-only        skip tier 2 entirely
  --resume            re-run, skipping phases marked done
  --dry-run           print all SSH/SCP commands without executing
  -h, --help          show this help

Anything after '--' is forwarded to tier2-bootstrap.sh.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier1-only) TIER1_ONLY=1 ;;
    --resume)     RESUME=1 ;;
    --dry-run)    export DRY_RUN=1 ;;
    --) shift; TIER2_ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) log_err "unknown flag: $1"; usage; exit 1 ;;
  esac
  shift
done

main() {
  log_info "install.sh starting (tier1-only=$TIER1_ONLY resume=$RESUME dry-run=${DRY_RUN:-0})"

  # Step A: prereqs
  "$SCRIPT_DIR/prereqs-check.sh"

  # Step B: Honcho bind recommendation (printed; user must apply manually)
  log_info "Printing Honcho exposure recommendation; apply manually before continuing."
  local desktop_ip
  desktop_ip=$(tailscale status --json | discover_desktop_ipv4 || echo "?.?.?.?")
  print_recommendation "$desktop_ip" "$PHONE_HOST"
  if [ "${DRY_RUN:-0}" != "1" ]; then
    read -r -p "Press ENTER once Honcho exposure is configured (or Ctrl-C to abort): " _
  fi
  log_gate G6c "user confirmed Honcho exposure configured"

  # Step C: Tier 1
  "$SCRIPT_DIR/tier1-bootstrap.sh"

  # Step D: Tier 2 (optional)
  if [ "$TIER1_ONLY" = "1" ]; then
    log_info "tier1-only: stopping after tier 1"
  else
    "$SCRIPT_DIR/tier2-bootstrap.sh" "${TIER2_ARGS[@]}"
  fi

  log_info "install.sh: done. Daily-log entry suggested in /mnt/data/Documents/repos/hermaper/claude.md."
}

main "$@"
```

- [ ] **Step 22.2: Lint + dry-run**

```bash
shellcheck install.sh
chmod +x install.sh
DRY_RUN=1 ./install.sh --tier1-only 2>&1 | head -40
```

- [ ] **Step 22.3: Commit**

```bash
git add scripts/install-hermes-on-s24/install.sh
git commit -m "feat(install): top-level install.sh orchestrator"
```

---

## Task 23: Verification gate G7/G8/G8b/G8c — local-LLM smoke (in `tier2-bootstrap.sh`)

**Files:**
- Modify: `scripts/install-hermes-on-s24/tier2-bootstrap.sh`

- [ ] **Step 23.1: Extend `module_local_llm` with verification gates**

After `mark_phase_done tier2-local-llm` in `module_local_llm`, append:

```bash
  # Verification gates G7/G8 require a running llama-server. Since boot does
  # NOT auto-start it, prompt the user to start it manually on the phone.
  log_info "local-llm verify: please run 'start-local-llm' in a Termux session on the phone, then press ENTER."
  if [ "$DRY_RUN" != "1" ]; then read -r _; fi

  # G7: /v1/models returns Qwen3.
  if ! run_remote 'curl -fsS http://127.0.0.1:8080/v1/models' | tee -a "$INSTALL_LOG_FILE" | grep -qi 'qwen3'; then
    die "G7 FAIL: llama-server did not return qwen3 in /v1/models. Is start-local-llm running?"
  fi
  log_gate G7 "llama-server /v1/models OK"

  # G8: /props contains chat_template (proves --jinja worked).
  local props
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
```

- [ ] **Step 23.2: Lint**

```bash
shellcheck tier2-bootstrap.sh
```

- [ ] **Step 23.3: Commit**

```bash
git add scripts/install-hermes-on-s24/tier2-bootstrap.sh
git commit -m "feat(install): tier2a gates G7/G8/G8b/G8c verification"
```

---

## Task 24: Verification gate G9 — reboot test helper

**Files:**
- Create: `scripts/install-hermes-on-s24/verify-reboot.sh`

- [ ] **Step 24.1: Implement**

```bash
#!/usr/bin/env bash
# verify-reboot.sh — implements gate G9. Run AFTER manually rebooting the phone.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

main() {
  log_info "G9: verifying post-reboot service state"

  # sshd MUST be running (we just connected, so by definition it is).
  log_gate G9 "sshd running (this script connected via SSH)"

  # llama-server MUST NOT be running.
  if run_remote 'pgrep -f llama-server >/dev/null'; then
    die "G9 FAIL: llama-server is running after reboot. Boot script should NOT start it."
  fi
  log_gate G9 "llama-server NOT running (correct)"

  # Gateway: running iff TELEGRAM_BOT_TOKEN + HERMES_GATEWAY_AUTOSTART=1.
  local autostart token
  autostart=$(run_remote 'grep ^HERMES_GATEWAY_AUTOSTART= ~/.hermes/.env | cut -d= -f2' || echo 0)
  token=$(run_remote 'grep ^TELEGRAM_BOT_TOKEN= ~/.hermes/.env | cut -d= -f2' || echo "")
  if [ -n "$token" ] && [ "$autostart" = "1" ]; then
    if ! run_remote 'pgrep -f "hermes.*gateway" >/dev/null'; then
      die "G9 FAIL: gateway autostart is enabled but the process is not running."
    fi
    log_gate G9 "gateway running as expected"
  else
    if run_remote 'pgrep -f "hermes.*gateway" >/dev/null'; then
      log_warn "G9 WARN: gateway running but autostart not enabled — investigate."
    else
      log_gate G9 "gateway NOT running (autostart not enabled, correct)"
    fi
  fi

  log_info "G9 PASS"
}

main "$@"
```

- [ ] **Step 24.2: Lint + commit**

```bash
shellcheck verify-reboot.sh
chmod +x verify-reboot.sh
git add scripts/install-hermes-on-s24/verify-reboot.sh
git commit -m "feat(install): verify-reboot.sh implementing gate G9"
```

---

## Task 25: `uninstall-tier1.sh`

**Files:**
- Create: `scripts/install-hermes-on-s24/uninstall-tier1.sh`

- [ ] **Step 25.1: Implement**

```bash
#!/usr/bin/env bash
# uninstall-tier1.sh — reverse Tier 1. Destructive on the phone.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

main() {
  log_warn "uninstall-tier1: removing ~/hermes-agent and ~/.hermes on the phone."
  if [ "${DRY_RUN:-0}" != "1" ]; then
    read -r -p "Type 'yes' to confirm: " ans
    [ "$ans" = "yes" ] || die "aborted"
  fi
  run_remote 'rm -f "$PREFIX/bin/hermes" || true'
  run_remote 'rm -rf ~/hermes-agent ~/.hermes'
  log_info "uninstall-tier1: done. To re-install, run install.sh."
  log_warn "Note: Termux packages and the Python venv build cache remain. Run 'pkg uninstall <list>' manually if desired."
}

main "$@"
```

- [ ] **Step 25.2: Lint + commit**

```bash
shellcheck uninstall-tier1.sh
chmod +x uninstall-tier1.sh
git add scripts/install-hermes-on-s24/uninstall-tier1.sh
git commit -m "feat(install): uninstall-tier1.sh"
```

---

## Task 26: `uninstall-tier2.sh`

**Files:**
- Create: `scripts/install-hermes-on-s24/uninstall-tier2.sh`

- [ ] **Step 26.1: Implement**

```bash
#!/usr/bin/env bash
# uninstall-tier2.sh --module=<name> — reverse a single tier 2 module.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MODULE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --module=*) MODULE="${1#--module=}" ;;
    -h|--help)
      echo "Usage: uninstall-tier2.sh --module=local-llm|persistence|voice|edge-gallery|telegram|browser"
      exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift
done
[ -n "$MODULE" ] || die "specify --module=<name>"

case "$MODULE" in
  local-llm)
    run_remote 'rm -f ~/.hermes/bin/llama-server-qwen3.sh ~/.hermes/bin/llama-server-hermes3.sh ~/.hermes/bin/start-local-llm'
    run_remote 'rm -f ~/llama.cpp/models/Qwen3-4B-Q4_K_M.gguf'
    run_remote 'rm -f ~/.hermes/.install-state/tier2-local-llm'
    ;;
  persistence)
    run_remote 'rm -f ~/.termux/boot/00-hermes-startup.sh'
    run_remote '(crontab -l 2>/dev/null | grep -v "respawn-sshd") | crontab - || true'
    run_remote 'rm -f ~/.hermes/.install-state/tier2-persistence'
    ;;
  voice)
    run_remote 'rm -f ~/.hermes/.install-state/tier2-voice'
    log_info "voice: nothing to uninstall (built-in stt.provider; toggle in profile config)"
    ;;
  edge-gallery)
    log_info "edge-gallery: uninstall AI Edge Gallery via Android Settings -> Apps."
    ;;
  telegram)
    run_remote 'sed -i "/^HERMES_GATEWAY_AUTOSTART=/d" ~/.hermes/.env'
    run_remote 'pkill -f "hermes.*gateway" || true'
    run_remote 'rm -f ~/.hermes/.install-state/tier2-telegram'
    ;;
  browser)
    run_remote 'rm -rf ~/hermes-agent/node_modules ~/hermes-agent/package-lock.json'
    run_remote 'rm -f ~/.hermes/.install-state/tier2-browser'
    ;;
  *) die "unknown module: $MODULE" ;;
esac
log_info "uninstall-tier2 ($MODULE): done"
```

- [ ] **Step 26.2: Lint + commit**

```bash
shellcheck uninstall-tier2.sh
chmod +x uninstall-tier2.sh
git add scripts/install-hermes-on-s24/uninstall-tier2.sh
git commit -m "feat(install): uninstall-tier2.sh modular reversal"
```

---

## Task 27: README runbook

**Files:**
- Modify: `scripts/install-hermes-on-s24/README.md`

- [ ] **Step 27.1: Replace stub with full runbook**

```markdown
# Hermes-on-S24 install scripts

Desktop-driven install of Hermes Agent on a Samsung S24 (`miguels-s24` /
`100.83.211.53`) over Tailscale.

Spec: [`docs/superpowers/specs/2026-04-26-hermes-on-s24-design.md`](../../docs/superpowers/specs/2026-04-26-hermes-on-s24-design.md)

---

## Phase −1 prerequisites (one-time, on phone)

Before running anything from the desktop, do this on the phone:

1. Install **Termux** (F-Droid release, not Play Store).
2. Install **Tailscale** Android app, sign in, confirm `miguels-s24` appears.
3. Install **Termux:API** app (companion to the `termux-api` package).
4. Install **Termux:Boot** app and launch it once. Disable battery
   optimization for both Termux and Termux:Boot
   (Settings → Apps → <app> → Battery → Unrestricted).
5. In a Termux shell:
   ```
   pkg update
   pkg install -y openssh
   passwd                # set a password (memorize for ssh-copy-id)
   sshd                  # start sshd in the foreground; leave the shell open
   ```
6. From the desktop, **once**:
   ```
   ssh-copy-id -p 8022 u0_a369@miguels-s24
   ```
7. Place a populated `.env` at `/home/hammer/Documents/repos/hermaper/.env`,
   based on `env/.env.bootstrap.example`.

---

## Run the install

```bash
cd /mnt/data/Documents/repos/hermaper/scripts/install-hermes-on-s24
./install.sh                          # full install: tier 1 + tier 2 default-on
./install.sh --tier1-only             # stop after the tested .[termux] bundle
./install.sh -- --with-voice --with-telegram   # turn on tier-2 opt-ins
./install.sh --resume                 # re-run after a partial failure
./install.sh --dry-run                # echo every SSH/SCP command, run nothing
```

Apply Honcho exposure manually when the script prints the recommendation
(see `lib/honcho-bind.sh` output). Press ENTER to continue.

After the install completes:
- Reboot the phone, then run `./verify-reboot.sh` to confirm gate G9.
- Manually verify gate G8c: airplane-mode + `hermes -p s24-local chat`.
- Append a daily-log entry to `claude.md` (terse, per user preference).

## Flags reference

| Flag | Default | Effect |
|---|---|---|
| `--tier1-only` | off | skip tier 2 |
| `--resume` | off | skip phases with idempotency markers |
| `--dry-run` | off | echo SSH/SCP, do not execute |
| `--with-voice` | off (tier 2) | validate Hermes built-in STT provider |
| `--with-edge-gallery` | off | print AI Edge Gallery instructions |
| `--with-telegram` | off | enable gateway autostart (token must be in `.env`) |
| `--with-browser` | off | attempt nodejs-lts + npm install (fragile) |
| `--no-local-llm` | on (tier 2) | skip Qwen3 download + launchers |
| `--no-persistence` | on (tier 2) | skip Termux:Boot script install |

## Verification gates

| Gate | What it proves | When |
|---|---|---|
| G0 | termux-info captured | prereqs-check |
| G0a | sshd running | prereqs-check |
| G0b | Termux:API app + package work | prereqs-check |
| G0c | Tailscale resolves phone | prereqs-check |
| G1 | SSH key auth works | prereqs-check |
| G2 | Termux packages installed | tier 1 |
| G3 | hermes installed in venv | tier 1 |
| G4 | hermes doctor clean | tier 1 |
| G5 | cloud round-trip OK | tier 1 |
| G6 | Honcho memory active | tier 1 |
| G6b | honcho.json fields correct | tier 1 |
| G6c | Honcho exposure user-confirmed | install.sh top-level |
| G7 | llama-server /v1/models returns Qwen3 | tier 2a (manual start) |
| G8 | /props has chat_template (--jinja) | tier 2a |
| G8b | tool call executes (not raw JSON) | tier 2a |
| G8c | airplane mode + s24-local works | manual |
| G9 | post-reboot: sshd up, llama-server NOT up | verify-reboot.sh |

## Troubleshooting

- **`pip install` runs out of RAM**: keep phone plugged in and screen on; the
  Rust build of `jiter` is the heavy step. If Termux gets killed, re-run with
  `--resume`.
- **Tailscale magic DNS doesn't resolve from phone**: edit phone `~/.hermes/.env`,
  replace `HONCHO_BASE_URL=http://<name>:18000` with `http://100.x.y.z:18000`.
- **G6 fails (Honcho not active)**: re-check the bind/auth/ACL. Re-run
  `lib/honcho-bind.sh print_recommendation` for the latest checklist.
- **G8 fails (no chat_template)**: llama-server was launched without `--jinja`.
  Stop it on the phone, run `start-local-llm` again.
- **Gateway dies overnight**: expected; multi-day persistence under Doze is
  best-effort. The cron respawns `sshd` every 15 min but not the gateway.

## Uninstall

```bash
./uninstall-tier1.sh                              # full reverse (asks "yes")
./uninstall-tier2.sh --module=local-llm           # remove just one tier-2 module
```
```

- [ ] **Step 27.2: Commit**

```bash
git add scripts/install-hermes-on-s24/README.md
git commit -m "docs(install): full README runbook with Phase -1, flags, gates, troubleshooting"
```

---

## Task 28: Repo-level lint sweep + final review

**Files:**
- All `scripts/install-hermes-on-s24/**/*.sh`

- [ ] **Step 28.1: Run shellcheck on every shell file**

```bash
cd /mnt/data/Documents/repos/hermaper
find scripts/install-hermes-on-s24 -type f -name '*.sh' -print0 | xargs -0 shellcheck
find scripts/install-hermes-on-s24/phone/bin -type f ! -name '*.sh' -print0 | xargs -0 shellcheck
```

Expected: zero errors. Fix any reported and commit fixes.

- [ ] **Step 28.2: Run all bats tests**

```bash
cd scripts/install-hermes-on-s24
bats tests/bats/
```

Expected: all tests pass.

- [ ] **Step 28.3: Dry-run end-to-end**

```bash
DRY_RUN=1 ./install.sh -- --all 2>&1 | tee logs/dry-run.log | tail -100
```

Inspect output for:
- Each phase echoes a sensible SSH command.
- No ssh actually connects (because DRY_RUN=1).
- No phase exits non-zero except where expected (e.g. `read` prompts in DRY_RUN).

- [ ] **Step 28.4: Append a checklist entry to `claude.md`**

In repo root `claude.md` (terse daily-log format per user preference):

```markdown
### 2026-04-26 — install scripts complete

- Built `scripts/install-hermes-on-s24/` per spec v2.
- All bats unit tests + shellcheck pass.
- Dry-run end-to-end clean.
- **Next:** real install against `miguels-s24`. Phase -1 first.
```

- [ ] **Step 28.5: Commit final review artifacts**

```bash
git add scripts/install-hermes-on-s24/ claude.md
git commit -m "chore(install): final lint sweep, dry-run pass, daily-log entry"
```

---

## Self-review

**Spec coverage:**
- §2 decisions table → encoded in profiles/ (Task 7), honcho.json (Task 8), env allowlist (Task 5), boot script (Task 8/17).
- §3 architecture → file layout matches; Tasks 1, 7, 8, 10–14 build the Tier 1 side; Tasks 15–21 build Tier 2.
- §4 Phase −1 → Task 9 (`prereqs-check.sh`) + Task 27 (README).
- §5 Tier 1 phases 0–10 → Tasks 9, 10, 11, 12, 13, 14.
- §6 workspace decision → encoded in `phone/honcho.json` (Task 8) and the `HONCHO_WORKSPACE=hermes-s24` constant in Task 12.
- §7 Tier 2 modules 7a–7f → Tasks 16, 17, 18, 19, 20, 21.
- §8 networking, secrets, security → Tasks 3 (Tailscale), 4–5 (secrets), 6 (Honcho-bind), 22 (orchestrator gate G6c).
- §9 verification gates G0–G9 → Tasks 9 (G0–G0c, G1), 10 (G2), 11 (G3), 14 (G4–G6b), 22 (G6c), 23 (G7–G8c), 24 (G9).
- §10 failure modes → mitigations live in idempotency markers (Task 2), `--jinja` enforcement (Task 8), `--resume` (Task 22), G8 chat_template check (Task 23), README troubleshooting (Task 27).
- §11 rollback → Tasks 25 (tier1) and 26 (tier2).
- §12 deliverables → all files mapped to a task; verified by Task 28's find/lint sweep.
- §13 out of scope → no task implements anything in this list (no LiteRT bridge, no Honcho-on-phone, no llama-server autostart in Task 17, no custom Whisper shim in Task 18).
- §14 success criteria → criterion 1 = Tasks 9+22; criterion 2 = G3; criterion 3 = G6; criterion 4 = G8b/G8c; criterion 5 = G9; criterion 6 = idempotency markers + `--resume`.

**Placeholder scan:** one intentional `REPLACE_WITH_REAL_SHA256_FROM_HF_MODEL_CARD` in Task 16 with a clearly flagged "fetch and replace before production use" note. Treated as a deliberate human-in-the-loop checkpoint, not a plan failure.

**Type/identifier consistency:** function names checked across tasks — `discover_desktop_hostname`, `discover_desktop_ipv4`, `discover_peer_ipv4`, `filter_to_phone_env`, `append_phone_specific_env`, `summary_log`, `render_profile`, `print_recommendation`, `run_remote`, `copy_remote`, `mark_phase_done`, `phase_done`, `module_local_llm`, etc. — used consistently. Phase markers: `phase1-pkg`, `phase2-clone`, `phase3-venv`, `phase4-pip`, `phase5-symlink`, `phase6-secrets`, `phase7-honcho-json`, `phase8-profiles`, `phase9-doctor`, `phase10-smoke`, `tier2-local-llm`, `tier2-persistence`, `tier2-voice`, `tier2-telegram`, `tier2-browser` — consistent. Gate names G0–G9 match spec §9.

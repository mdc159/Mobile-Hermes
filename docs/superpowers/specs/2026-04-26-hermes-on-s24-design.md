# Hermes Agent on Samsung S24 — Design (v2)

**Date:** 2026-04-26
**Status:** Spec — v2 incorporating `review-01.md`, awaiting user review
**Source:** Brainstormed from `hermes-on-android.md`, refined against `phone-llm.md` and `review-01.md`

---

## 1. Goal

Install Hermes Agent on the Samsung S24 with **maximum realistic functionality** for an Android phone, driven from the desktop so the phone is touched as little as possible. Phone becomes a Hermes node: cloud-backed by default, locally-capable when offline, and connected to the desktop's Honcho memory instance over Tailscale.

## 2. Constraints and decisions (locked)

| Decision | Choice | Source |
|---|---|---|
| Scope | Push everything realistic — tested `.[termux]` plus modular experimental layers | User |
| Model backend | Hybrid: cloud (OpenRouter primary, OpenAI as `fallback_model`) + local llama-server fallback | User + review |
| Local fallback model | **Qwen3-4B-Q4_K_M GGUF** via `llama-server --jinja`. Repo + filename + SHA256 pinned in download script. Hermes-3-3B kept as alt (already on disk). | review-01 |
| Phone-native multimodal | AI Edge Gallery + Gemma-4-E2B-it LiteRT-LM, **separate from Hermes**, manual install (opt-in) | phone-llm.md |
| Profile model | **Two explicit Hermes profiles:** `s24-cloud` and `s24-local`. Switch with `hermes -p <profile>` or `hermes profile use`. | review-01 |
| Honcho topology | Phone connects to desktop Honcho via Tailscale. **Separate workspace `hermes-s24`** (isolation chosen over cross-device continuity — see §6). Falls back to native Hermes memory when offline. | User + review |
| Honcho recall | `recallMode: tools` (no auto-injection; agent calls Honcho tools explicitly). `writeFrequency: async`. The `contextTokens`/`dialecticCadence`/`dialecticDepth` knobs are inert in tools mode and omitted. | review-01 |
| Memory provider activation | `memory.provider: honcho` set explicitly in `s24-cloud` profile config. | review-01 |
| Voice / STT | Hermes's built-in `stt.provider: groq` (or `openai`) — no custom shim. Validated under `.[termux]` before scripted. | review-01 |
| Telegram gateway | Code installed, not configured initially. Add token + start on demand. | User |
| Install execution | Two-tier scripted install, desktop-driven over SSH | User |
| Control channel | SSH over Tailscale. Phone plugged into USB during install for power and wake. | User |
| Secrets source | `/home/hammer/Documents/repos/hermaper/.env` on desktop. Sync filters phone-relevant keys only. Phone-specific low-limit keys preferred. | User + review |
| Phone Tailscale | `miguels-s24` / `100.83.211.53` | User |
| Boot behavior | Termux:Boot starts **only `sshd` + `termux-wake-lock`** (and gateway when configured). **No auto-start of `llama-server`.** | review-01 |

## 3. Architecture

```
DESKTOP (23 GiB, daily driver)
├── scripts/install-hermes-on-s24/        ← orchestrator, runs locally
│   ├── install.sh                         entrypoint
│   ├── prereqs-check.sh                   verifies Phase -1 done
│   ├── tier1-bootstrap.sh                 phone-side: tested install
│   ├── tier2-bootstrap.sh                 phone-side: experimental layers
│   ├── lib/{ssh-helpers,tailscale-discover,secrets-sync,honcho-bind}.sh
│   ├── profiles/{s24-cloud,s24-local}.yaml
│   └── env/.env.bootstrap.example
├── /home/hammer/Documents/repos/hermaper/.env   ← secrets source (gitignored)
└── Honcho on tailscale0:18000
    └── Postgres :5433 (database "honcho")

       │ Tailscale (encrypted, ACL-gated)
       ▼
S24 — Termux  (miguels-s24, 100.83.211.53, 8–12 GiB)
├── ~/hermes-agent/                        editable install + venv
├── ~/.hermes/                             config + state + secrets (mode 700)
│   ├── .env                               synced from desktop (mode 600)
│   ├── honcho.json                        workspace=hermes-s24, tools-mode
│   └── profiles/
│       ├── s24-cloud/config.yaml          OpenRouter primary, OpenAI fallback_model, Honcho on
│       └── s24-local/config.yaml          custom provider → 127.0.0.1:8080, native memory only
├── ~/.hermes/bin/
│   ├── start-local-llm                    on-demand launcher (Qwen3 by default)
│   └── llama-server-{qwen3,hermes3}.sh    individual launchers
├── ~/llama.cpp/models/                    GGUFs (Qwen3-4B + Hermes-3-3B)
└── ~/.termux/boot/00-hermes-startup.sh    sshd + wake-lock only

Memory layering:
  s24-cloud  → Honcho (desktop, Tailscale) + native Hermes memory (built-in, additive)
  s24-local  → native Hermes memory only (Honcho off; airplane-mode safe)
```

## 4. Phase −1 — prerequisites (one-time, on phone)

Before any desktop script runs, the phone needs:

1. **Termux installed** — F-Droid release preferred (Play Store version is outdated and signed differently from the F-Droid build).
2. **Tailscale Android app installed** and signed in to your tailnet (`miguels-s24` already exists, so this is presumably done).
3. **Termux:API app** installed (companion to the `termux-api` package — required for `termux-wake-lock`, `termux-battery-status`, etc.).
4. **Termux:Boot app** installed and **launched once** (registers boot receiver). Battery optimization disabled for both Termux and Termux:Boot in Android Settings → Apps.
5. **Inside Termux**, run:
   ```bash
   pkg update
   pkg install -y openssh
   passwd                # set the password from hermes-on-android.md
   sshd                  # start sshd once
   ```
6. From the desktop, run **once**:
   ```bash
   ssh-copy-id -p 8022 u0_a369@miguels-s24
   ```
7. After key auth verified, the desktop install script will set `PasswordAuthentication no` in `~/.ssh/sshd_config` on the phone.

`scripts/install-hermes-on-s24/prereqs-check.sh` checks each of these and prints a clear pass/fail before letting `install.sh` proceed.

## 5. Tier 1 — tested `.[termux]` install (phases)

| Phase | Action | Where |
|---|---|---|
| 0 | Phase −1 verified by `prereqs-check.sh` | desktop |
| 1 | `pkg install -y git python clang rust make pkg-config libffi openssl nodejs ripgrep ffmpeg openssh termux-api jq` | phone |
| 2 | `git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git ~/hermes-agent` | phone |
| 3 | `python -m venv ~/hermes-agent/venv` + `pip install --upgrade pip setuptools wheel` | phone |
| 4 | `export ANDROID_API_LEVEL=$(getprop ro.build.version.sdk)` then `pip install -e '.[termux]' -c constraints-termux.txt` | phone |
| 5 | `ln -sf ~/hermes-agent/venv/bin/hermes $PREFIX/bin/hermes` | phone |
| 6 | Sync `~/.hermes/.env` from filtered desktop `.env` (mode 600). `chmod 700 ~/.hermes`. `umask 077` for the session. | desktop → phone |
| 7 | Write `~/.hermes/honcho.json` (workspace `hermes-s24`, `recallMode: tools`, `writeFrequency: async`). | desktop → phone |
| 8 | `hermes profile create s24-cloud --clone` and `hermes profile create s24-local --clone`. Overlay each profile's `config.yaml` from `scripts/profiles/`. | phone |
| 9 | `hermes -p s24-cloud doctor` and capture output to desktop log | phone |
| 10 | `hermes -p s24-cloud chat` smoke test (one round-trip via OpenRouter, plus `hermes memory status` showing Honcho active) | phone |

**Profile contents (Tier 1 writes both, but `s24-local` model backend is dormant until Tier 7a). Model names in angle brackets are install-time config — supplied via `.env.bootstrap` keys `OPENROUTER_PRIMARY_MODEL` / `OPENAI_FALLBACK_MODEL` and substituted by the install script:**

`s24-cloud/config.yaml`:
```yaml
model:
  provider: openrouter
  default: <user-chosen primary OpenRouter model>

fallback_model:
  provider: openai
  model: <user-chosen secondary OpenAI model>

memory:
  provider: honcho

stt:
  provider: groq
  groq:
    model: whisper-large-v3
tts:
  provider: openai
```

`s24-local/config.yaml`:
```yaml
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

End-of-Tier-1 state: `hermes -p s24-cloud` works against OpenRouter with Honcho memory over Tailscale. `hermes -p s24-local` configured but local server not yet present.

## 6. Workspace decision (isolation vs. continuity) — explicit trade-off

Two valid Honcho topologies were considered:

- **A. Same workspace as desktop, separate `aiPeer: hermes-s24`** — phone shares the same knowledge graph as desktop daily-driver Hermes. Cross-device continuity ("agent remembers what the desktop learned"). Honcho's recommended idiom for multi-device single-identity setups.
- **B. Separate workspace `hermes-s24`** — phone gets isolated memory, no cross-pollination with desktop. Safer during install validation; explicit choice if the user runs many Hermes instances and there is no canonical "primary" desktop instance to sync with.

**Decision: B (separate workspace).** Rationale: user runs ~8 Hermes instances; no canonical primary to sync with; isolation is the safer first-install posture. Cross-device continuity can be migrated later by changing `honcho.json` workspace to a shared one and re-creating peers — non-destructive change.

## 7. Tier 2 — experimental layer (modular, mostly opt-in)

Each module is a flag in `tier2-bootstrap.sh`. **Default-on flags are conservative**; the rest require `--with-<module>`.

### 7a. Local LLM launcher (Qwen3-4B) — DEFAULT ON, install only, **not autostart**
- Verify `~/llama.cpp/build/bin/llama-server` present (already built per `hermes-on-android.md`).
- Download `Qwen3-4B-Q4_K_M.gguf` from `Qwen/Qwen3-4B-GGUF`. **Pin filename + SHA256** in `tier2-bootstrap.sh`; reject mismatch.
- Write launchers:
  - `~/.hermes/bin/llama-server-qwen3.sh` (port 8080, `--jinja -c 8192 -n 1024`).
  - `~/.hermes/bin/llama-server-hermes3.sh` (port 8081, alt; uses already-on-disk model).
  - `~/.hermes/bin/start-local-llm` — convenience wrapper that runs the qwen3 launcher in foreground.
- **Not started at boot.** User runs `start-local-llm` on demand from a Termux shell, then `hermes -p s24-local`.
- Increase `-c` to 12288 manually only after 8192 is stable.
- **Only one local model resident at a time.**

### 7b. Phone-native multimodal — AI Edge Gallery — OPT-IN (`--with-edge-gallery`)
- Print instructions for installing AI Edge Gallery and downloading **Gemma-4-E2B-it LiteRT-LM** (~2.58 GB) inside the app.
- E4B (~3.65 GB) noted as manual experiment only; not part of the scripted path on 8 GB.
- Not wired into Hermes. Used by the human for offline vision/audio.

### 7c. Voice / STT validation — OPT-IN (`--with-voice`)
- No custom shim. Test Hermes's built-in `stt.provider: groq` (default) with a 30-second WAV under `.[termux]` to confirm it works without `faster-whisper`. If not, fall back to `openai` provider.
- Document any limitations found.
- TTS via `openai` (default) tested same way.

### 7d. Boot persistence — DEFAULT ON, conservative
- `~/.termux/boot/00-hermes-startup.sh`:
  ```bash
  #!/data/data/com.termux/files/usr/bin/bash
  set -euo pipefail
  export PATH="$PREFIX/bin:$PATH"
  mkdir -p "$HOME/.hermes/logs"
  termux-wake-lock || true
  pgrep -x sshd >/dev/null || sshd
  # llama-server is NOT started here — run start-local-llm on demand.
  # Gateway started only when TELEGRAM_BOT_TOKEN is present and HERMES_GATEWAY_AUTOSTART=1.
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ "${HERMES_GATEWAY_AUTOSTART:-0}" = "1" ]; then
    nohup hermes -p s24-cloud gateway start >> "$HOME/.hermes/logs/gateway.log" 2>&1 &
  fi
  ```
- Belt-and-suspenders cron `*/15 * * * *` respawns `sshd` only — not the local LLM.
- Honest SLA: covers reboot + screen-off; multi-day persistence under Doze remains best-effort.

### 7e. Telegram gateway — OPT-IN (`--with-telegram`)
- Add `TELEGRAM_BOT_TOKEN` to desktop `.env`, re-run `secrets-sync.sh`, set `HERMES_GATEWAY_AUTOSTART=1` in `.env`. Boot script picks it up.

### 7f. Browser tooling (Playwright) — OPT-IN (`--with-browser`)
- `pkg install nodejs-lts && cd ~/hermes-agent && npm install`. Smoke test only. If fail, log "skipped". Nothing depends on it.

**Tier 2 install order** when `--all` (still opt-in flags applied): 7a → 7d → 7c → 7b → 7e → 7f.

## 8. Networking, secrets, security

**Tailscale topology:**
- Phone: `miguels-s24` / `100.83.211.53`.
- Desktop: detected via `tailscale status --json | jq -r '.Self.HostName'`, cached in `scripts/install-hermes-on-s24/.tailscale-desktop` (gitignored).
- Phone reaches Honcho at `http://<desktop-tailscale-name>:18000`, IP fallback documented in `.env`.

**Honcho exposure on desktop — preferred path:**
- **Enable Honcho auth** (set `AUTH_USE_AUTH=true`, mint a token). Sync the token to phone `.env`.
- Bind Honcho to `tailscale0` interface only.
- Tailscale ACL restricts `miguels-s24 → desktop:18000` only.

**Acceptable fallback (private lab posture):**
- `AUTH_USE_AUTH=false` only when **all** of:
  - Honcho binds to `tailscale0` IP only (never `0.0.0.0`),
  - Tailscale ACL allows only `miguels-s24 → desktop:18000`,
  - No shared/external tailnet users can reach the desktop node,
  - Postgres (`:5433`) bound to localhost only.
- **Tailscale Serve** considered as cleaner alternative — exposes localhost service to tailnet without app-level rebind.

`lib/honcho-bind.sh` prints the exact one-line config change and **waits for user confirmation** before applying. ACL update is **printed for the user to apply** — never modified by the script.

**Secrets sync:**
- `lib/secrets-sync.sh` filters phone-relevant keys only (`OPENROUTER_API_KEY`, `OPENAI_API_KEY`, `GROQ_API_KEY`, optional `TELEGRAM_BOT_TOKEN`, `HONCHO_AUTH_TOKEN` if auth enabled). Refuses to sync any key not on the allowlist.
- Phone-specific low-limit keys are preferred over reusing desktop keys. Documented in install README.
- Adds at sync time: `HONCHO_BASE_URL`, `HONCHO_WORKSPACE=hermes-s24`.
- `chmod 600 ~/.hermes/.env`, `chmod 700 ~/.hermes`. Sync script logs only "key X synced" / "key Y absent" — never values.
- After key auth verified, install script sets `PasswordAuthentication no` on phone `sshd`.

## 9. Verification gates

Halts at first failed gate, leaves clear log. `install.sh --resume` skips passing gates.

| Gate | Tier | Check | On fail |
|---|---|---|---|
| G0 | −1 | `termux-info` captured to log | halt — phone not ready |
| G0a | −1 | `command -v sshd && pgrep sshd` | halt |
| G0b | −1 | `termux-battery-status` returns JSON (proves Termux:API app installed) | halt |
| G0c | −1 | Tailscale name **and** IP both resolve from desktop | halt |
| G1 | 1 | SSH key auth works; password auth disabled after | halt |
| G2 | 1 | `pkg list-installed` shows all required packages | re-run |
| G3 | 1 | `~/hermes-agent/venv/bin/hermes --version` works | dump pip log, halt |
| G4 | 1 | `hermes -p s24-cloud doctor` exits 0 (Docker/voice warnings ignored) | halt only on errors |
| G5 | 1 | `hermes -p s24-cloud chat` round-trip succeeds via OpenRouter | halt — `.env` issue |
| G6 | 1 | `hermes memory status` shows Honcho active and reachable | halt — Honcho bind/auth/ACL issue |
| G6b | 1 | `~/.hermes/honcho.json` has intended `workspace` and recall mode | halt |
| G6c | 1 | Desktop Honcho not reachable from unauthorized tailnet nodes (or ACL documented as unrestricted) | warn or halt per security posture |
| G7 | 7a | `curl http://127.0.0.1:8080/v1/models` returns Qwen3 (after manual `start-local-llm`) | halt local-LLM only |
| G8 | 7a | `curl http://127.0.0.1:8080/props \| jq .chat_template` returns non-empty (proves `--jinja` worked) | halt local-LLM only |
| G8b | 7a | One MCP tool call **executes** (not echoed as raw JSON) under `s24-local` | halt local-LLM only |
| G8c | 7a | Airplane mode + `hermes -p s24-local chat` produces a response | warn — degraded but expected if 8b/8 marginal |
| G9 | 7d | After phone reboot: `sshd` running, `llama-server` **not** running, gateway running iff Telegram opt-in | halt persistence module only |

## 10. Failure modes and mitigations

| Risk | Mitigation |
|---|---|
| `jiter`/maturin build fails (Rust + Android ABI) | `ANDROID_API_LEVEL` exported before pip install |
| `pip install` runs out of RAM during compile | install with phone plugged in, screen on; chunk install if needed |
| Tailscale magic DNS doesn't resolve from phone | fall back to IP, both documented in `.env` |
| Honcho deriver overloaded by phone writes | `writeFrequency: async`; monitor first week |
| Half-state from prior failed run | every phase idempotent; `--resume` |
| Local LLM context too aggressive → OOM/thermal | start at `-c 8192`, raise only after stable |
| `--jinja` missing → tool calls become raw JSON | G8 catches via `/props` chat_template check |
| Termux:API app missing | G0b catches; clear instruction to install app |
| Battery optimization re-enabled by Android | documented in README; G9 partial pass |
| AI Edge Gallery model download fails | manual sideload from GitHub release, opt-in only |
| Browser/Playwright headless fails on Android | logged "skipped"; no dependency |
| Honcho exposed to wider tailnet than intended | preferred path enables Honcho auth; G6c verifies |
| Stale desktop API key leaked via sync | allowlist filter; phone-specific low-limit keys recommended |

## 11. Rollback

- **Tier 1:** `uninstall-tier1.sh` → `rm -rf ~/hermes-agent ~/.hermes`, `pkg uninstall <list>`. Re-enable password auth if user wants to re-run.
- **Tier 2:** `uninstall-tier2.sh --module=local-llm|persistence|voice|edge-gallery|telegram|browser`. Each module independent.
- **Honcho desktop bind change:** documented revert from `tailscale0` back to `127.0.0.1`; auth-disable revert.

## 12. Repo deliverables

```
docs/superpowers/specs/2026-04-26-hermes-on-s24-design.md   ← this file
docs/superpowers/specs/review-01.md                          ← review (already in repo)
scripts/install-hermes-on-s24/
├── install.sh
├── prereqs-check.sh
├── tier1-bootstrap.sh
├── tier2-bootstrap.sh
├── uninstall-tier1.sh
├── uninstall-tier2.sh
├── lib/
│   ├── ssh-helpers.sh
│   ├── tailscale-discover.sh
│   ├── secrets-sync.sh
│   └── honcho-bind.sh
├── profiles/
│   ├── s24-cloud.yaml
│   └── s24-local.yaml
├── env/.env.bootstrap.example
├── logs/                              (gitignored)
└── README.md                          runbook + flags + troubleshooting + Phase −1 checklist
```

After install completes, append a terse daily-log entry to `claude.md` per user preference.

## 13. Out of scope (explicit)

- Running Honcho on the phone (deriver too heavy for mobile).
- LiteRT-LM ↔ OpenAI-compatible bridge.
- Hermes vision through local model (cloud only).
- Multi-day gateway persistence guarantees (best-effort under Doze).
- Docker on phone.
- Local `faster-whisper`.
- Wiring AI Edge Gallery's Gemma 4 into Hermes.
- Auto-starting `llama-server` at boot.
- Custom Whisper shim (use Hermes's built-in `stt.provider`).

## 14. Success criteria

1. From the desktop, `prereqs-check.sh` passes, then `install.sh` brings the phone from blank Termux (after Phase −1) to a fully-functional Hermes node with cloud LLM, Honcho memory over Tailscale (separate `hermes-s24` workspace), and on-demand offline llama-server fallback.
2. `hermes -p s24-cloud` works in any Termux shell on the phone.
3. `hermes memory status` shows connection to desktop workspace `hermes-s24`.
4. After running `start-local-llm`, with phone in airplane mode, `hermes -p s24-local chat` still works against local Qwen3-4B (degraded but functional, native memory layer active, real tool calls executed).
5. After phone reboot, `sshd` and (if Telegram opted-in) gateway come back automatically. `llama-server` does **not** auto-start.
6. Re-running `install.sh` after a partial failure resumes cleanly without duplicating work.

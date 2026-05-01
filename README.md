# hermaper — Hermes on the S24

This monorepo's reason for existing right now is **running Hermes Agent on a
Samsung Galaxy S24** (`miguels-s24`, reachable over Tailscale), backed by the
desktop's local Honcho memory layer.

The other top-level dirs (`hermes-agent/`, `paperclip/`, `honcho/`) are the
upstream source trees they were vendored from; everything S24-specific lives
under `scripts/install-hermes-on-s24/`.

---

## TL;DR — daily-driver cheat sheet

You unlocked your phone. You want to talk to Hermes. Tap a home-screen widget,
or open Termux and type one of these:

| Alias | What it runs | Profile | Backend |
|-------|--------------|---------|---------|
| `hcc` | `hermes -p s24-cloud chat` | s24-cloud | OpenRouter (Sonnet 4.6) + Honcho |
| `hct` | `hermes -p s24-cloud` (TUI) | s24-cloud | same |
| `hlc` | `hermes -p s24-local chat` | s24-local | local llama-server :8081 |
| `hlt` | `hermes -p s24-local` (TUI) | s24-local | same |
| `lls` | `~/.hermes/bin/start-local-llm` | — | spawns Qwen3-4B on :8080 (foreground) |

`hcc` / `hct` are what you'll use 95% of the time. `hlc` / `hlt` only work
**after** you've started a local llama-server — either `lls` (Qwen3 on :8080)
or `~/.hermes/bin/llama-server-hermes3.sh` (Hermes-3-3B on :8081, the one
`s24-local.yaml` actually points at). Don't leave it running; the 8 GB phone
will OOM-kill Termux if you do.

Home-screen widgets (Termux:Widget) call the same things via `~/.shortcuts/`:
`hermes-cloud-tui`, `hermes-cloud-chat`, `hermes-local-chat`, `start-local-llm`.

Honcho workspace for the phone is `hermes-s24` (kept separate from the
desktop's daily-driver instances on purpose).

---

## What's installed on the phone

After running the desktop installer, the S24 has:

**Apps (sideloaded from F-Droid / GitHub releases, not Play Store):**

- Termux 0.118+ (F-Droid build — Play Store version is dead)
- Termux:API 0.53.0
- Termux:Boot 0.8.1
- Termux:Widget (SHA256 `780ae459…`)
- Tailscale (Play Store is fine)

**Termux packages:** openssh, python, rust, build-essential, ffmpeg,
termux-api (the package, not the app — both are required), plus the chain of
deps that `hermes-agent[termux]` pulls in.

**Filesystem layout on the phone:**

```
$HOME/                         # /data/data/com.termux/files/home
├── .hermes/
│   ├── config.yaml            # main Hermes config; honcho memory provider
│   ├── honcho.json            # workspace=hermes-s24, peer/ai-peer config
│   ├── .env                   # API keys, HONCHO_BASE_URL, optional bot tokens
│   ├── bin/
│   │   ├── start-local-llm           # → llama-server-qwen3.sh (Qwen3 on :8080)
│   │   ├── llama-server-qwen3.sh     # Qwen3-4B-Q4_K_M, --jinja, -c 16384, q4 KV
│   │   └── llama-server-hermes3.sh   # Hermes-3-3B Q4_K_M on :8081, -c 8192
│   ├── logs/                  # boot.log, llama-server.log, gateway.log
│   └── profiles/
│       ├── s24-cloud.yaml     # rendered from template; OpenRouter + Honcho
│       └── s24-local.yaml     # custom provider → 127.0.0.1:8081/v1
├── .shortcuts/                # Termux:Widget targets
│   ├── hermes-cloud-tui
│   ├── hermes-cloud-chat
│   ├── hermes-local-chat
│   └── start-local-llm
├── .termux/boot/
│   └── 00-hermes-startup.sh   # acquires wake-lock, starts sshd; gateway opt-in
├── llama.cpp/                 # built natively on phone (~10 min compile)
│   ├── build/bin/llama-server
│   └── models/
│       ├── Qwen3-4B-Q4_K_M.gguf                  # 2.5 GB, sha256 7485fe6f…
│       └── Hermes-3-Llama-3.2-3B.Q4_K_M.gguf
└── .local/bin/                # on PATH via .bashrc; .bash_profile sources .bashrc
    └── hermes -> …            # the venv's hermes wrapper
```

The old `alias hermes=…` from a prior llama.cpp setup was renamed to
`hermes-llama-direct` to stop colliding with the venv binary. If a fresh
`hermes` invocation gives you raw llama output instead of the agent CLI,
that alias is back — `unalias hermes` and re-source `.bashrc`.

---

## Profiles

### `s24-cloud` (default driver)

`scripts/install-hermes-on-s24/profiles/s24-cloud.yaml` is templated; the
installer renders `%%OPENROUTER_PRIMARY_MODEL%%` etc. from the desktop `.env`.

- Primary: OpenRouter, currently `anthropic/claude-sonnet-4.6`
  (OpenRouter retired `claude-3.5-sonnet` — don't put it back)
- Fallback: OpenAI
- Memory: Honcho, workspace `hermes-s24`
- STT: Groq Whisper-large-v3
- TTS: OpenAI

### `s24-local` (offline / on-demand)

`profiles/s24-local.yaml`. Points Hermes at `http://127.0.0.1:8081/v1` —
**Hermes-3-3B**, not Qwen3, despite `start-local-llm` defaulting to Qwen3.
This is deliberate: Qwen3-4B + Hermes Python + Termux + Android system
OOM-kills Termux on 8 GB even with RAM Plus 8 (11 GB swap), because Android's
lowmem-killer fires before kernel OOM. Hermes-3-3B has the smaller working
set and survives.

If you want Qwen3 anyway: `lls` to start it on :8080, then edit `s24-local.yaml`
to flip `base_url` to `:8080`. Practical ceiling either way is `-c 16384`
with q4 KV cache. Run a query, kill the server.

The profile claims `context_length: 65536` on primary + every auxiliary
(compression / summary / classification) to clear Hermes's hard 64K floor;
the actual server is launched at `-c 16384`. This is a known workaround,
inline-documented in the YAML.

---

## Honcho exposure (the bit that breaks after every desktop reboot)

Honcho runs on the desktop bound to `127.0.0.1:18000`. The phone reaches it
over Tailscale via a small desktop-side `socat` forwarder bound to the
desktop's Tailnet interface:

```bash
# Replace <desktop-tailnet-ip> with the desktop's Tailscale address.
socat TCP-LISTEN:18000,bind=<desktop-tailnet-ip>,fork,reuseaddr TCP:127.0.0.1:18000 &
```

This is **not persistent across desktop reboot.** If the phone says memory
isn't working, this is the first thing to check. Permanent fix is to wrap it
in a systemd user unit; not done yet.

Phone's `~/.hermes/.env` has `HONCHO_BASE_URL=http://<desktop-tailnet-ip>:18000`.
If Tailscale MagicDNS resolves reliably from the phone, you can use the desktop
name instead, but the Tailnet interface address is the reliable fallback.

`AUTH_USE_AUTH=false` on the local Honcho — no API key required.

---

## Persistence — what survives a phone reboot, what doesn't

`~/.termux/boot/00-hermes-startup.sh` runs on Android boot via Termux:Boot
and does **only**:

1. `termux-wake-lock`
2. start `sshd` if not running
3. (optional, if `HERMES_GATEWAY_AUTOSTART=1` in `~/.hermes/.env`)
   start `hermes -p s24-cloud gateway start`

It deliberately does **not** start `llama-server`. Local LLM is on-demand;
that's gate G9 (`./verify-reboot.sh` confirms sshd up, llama-server down).

**Tailscale auto-reconnect on Samsung is unreliable** — the OS battery
manager kills the Android service before it can reconnect. After a reboot,
open the Tailscale app once. Permanent fix: pin Tailscale, Termux, and
Termux:Boot to "Never sleeping" in Settings → Apps → <app> → Battery →
Background usage limits → Unrestricted. Not yet applied on this phone.

---

## Reaching the phone from the desktop

```bash
ssh -p 8022 u0_a369@miguels-s24
```

Defined in `lib/common.sh` as `PHONE_USER=u0_a369`, `PHONE_HOST=miguels-s24`.
SSH config has `ServerAliveInterval=15 ServerAliveCountMax=8` — without it,
long Hermes calls drop the session.

For one-shot remote commands the install scripts use:
```bash
setsid sh -c 'cmd </dev/null >/dev/null 2>&1 &' </dev/null
```
plain `nohup … &` over ssh hangs because ssh holds the remote stdout open.

---

## Running the installer

```bash
cd /mnt/data/Documents/repos/hermaper/scripts/install-hermes-on-s24

./install.sh                         # full: tier 1 cloud + tier 2 local
./install.sh --tier1-only            # cloud-only (the tested .[termux] bundle)
./install.sh --resume                # re-run after a partial failure
./install.sh --dry-run               # echo every ssh/scp, run nothing
./install.sh -- --with-telegram      # turn on tier-2 opt-ins
```

Key flags (full list in `scripts/install-hermes-on-s24/README.md`):
`--with-voice`, `--with-edge-gallery`, `--with-telegram`, `--with-browser`,
`--no-local-llm`, `--no-persistence`.

After install completes, reboot the phone and run `./verify-reboot.sh` to
confirm gate G9.

### Verification gates (G0–G9)

| Gate | Proves | Where |
|---|---|---|
| G0 / G0a–c | termux-info, sshd, Termux:API, Tailscale all sane | `prereqs-check.sh` |
| G1 | SSH key auth works | prereqs-check |
| G2 | Termux packages installed | tier 1 |
| G3 | hermes installed in venv (`pip install -e .[termux]`) | tier 1 |
| G4 | `hermes doctor` clean | tier 1 |
| G5 | cloud round-trip OK ("pong" from Sonnet) | tier 1 |
| G6 / G6b | Honcho memory active, honcho.json fields correct | tier 1 |
| G6c | Honcho exposure (socat) user-confirmed | install.sh |
| G7 / G8 / G8b | llama-server up, `--jinja` chat_template, tool call works | tier 2a |
| G8c | airplane-mode + `hermes -p s24-local chat` | manual |
| G9 | post-reboot: sshd up, llama-server **not** up | `verify-reboot.sh` |

---

## Status (as of 2026-04-26)

- **Tier 1 (cloud Hermes):** live and stable. Daily driver.
- **Tier 2 (local Hermes):** llama.cpp built native aarch64 (v8938), Qwen3-4B
  and Hermes-3-3B on disk and SHA256-pinned. Runs on demand only; do not
  leave resident.
- **Persistence (G9):** PASS — verified across real reboot.
- **Termux:Widget shortcuts:** installed; one-tap from home screen.
- **Tailscale post-reboot:** still requires manual app open; pin to "Never
  sleeping" to fix.

---

## Documents

- `scripts/install-hermes-on-s24/README.md` — installer spec and phase-minus-1 prereqs
- `docs/mobile-hermes-grid-readiness.md` — Studio54/mobile-edge onboarding contract
- `docs/superpowers/specs/2026-04-26-hermes-on-s24-design.md` — full design
- `phone-llm.md`, `hermes-on-android.md` — design notes that fed the spec
- `claude.md` — Claude Code workflow rules + daily log of install progress

---

## Common problems

- **Memory not working from phone** → desktop probably rebooted. Re-run the
  socat command above.
- **`hermes` gives raw llama output** → the old `alias hermes=` is back.
  `unalias hermes` and re-source `~/.bashrc`.
- **`hcc` says "command not found"** → `~/.local/bin` not on PATH. Open a
  fresh Termux session, or `source ~/.bashrc`.
- **Local LLM crashes Termux** → you started Qwen3 (`lls`) instead of
  Hermes-3-3B. Either run `~/.hermes/bin/llama-server-hermes3.sh` or accept
  that Qwen3 is one-query-then-kill on 8 GB.
- **G6 fails** → bind/auth/ACL on Honcho. Re-run
  `lib/honcho-bind.sh print_recommendation` for the current checklist.
- **G8 fails** → llama-server launched without `--jinja`. Stop it on the
  phone, run `start-local-llm` again.
- **`hermes memory status` errors out** → forgot the profile flag; needs
  `-p s24-cloud` (or `s24-local`).
- **Hermes one-shot syntax** → it's `hermes -z` (top-level) or
  `hermes chat -q` (subcommand). `--once` is fictional.

---

## Uninstall

```bash
./uninstall-tier1.sh                       # full reverse, prompts "yes"
./uninstall-tier2.sh --module=local-llm    # remove just one tier-2 module
```

# Hermes-on-S24 install scripts

Desktop-driven install of Hermes Agent on a Samsung S24 (`miguels-s24`) over
Tailscale.

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
- **Tailscale MagicDNS doesn't resolve from phone**: edit phone `~/.hermes/.env`,
  replace `HONCHO_BASE_URL=http://<desktop-name>:18000` with the desktop's
  current Tailnet interface address on port `18000`.
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

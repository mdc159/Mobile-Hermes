# Mobile Hermes Grid Readiness

This note translates the Samsung S24 / Termux Hermes install into the Studio54
remote-persona grid language.

The phone is not a tiny VPS. Treat it as a **mobile-edge candidate** with tighter
battery, network, Android process-lifecycle, and local-LLM constraints.

## Current role

```text
Persona / tab: Android or Termux, final name still pending
Device class: Samsung phone / Termux / mobile edge
Runtime: Hermes Agent in Termux
Primary mode: cloud Hermes profile, backed by desktop Honcho over Tailscale
Local mode: on-demand llama.cpp server only, not resident
Grid state: candidate only; keep disabled until discovery/probe passes from Donna
```

## Known working pieces from this repo

- Termux-based Hermes install scripts exist under `scripts/install-hermes-on-s24/`.
- `s24-cloud` is the daily-driver profile.
- `s24-local` exists for offline/local testing, but the local model server is
  constrained and should be started manually.
- Termux:Boot starts `sshd` and keeps the phone awake; it deliberately does not
  auto-start local llama-server.
- Termux:Widget shortcuts expose common Hermes launch paths for human use.
- The phone-specific Honcho workspace is separate from desktop/VPS personas.

## Known weak points

- Desktop-side Honcho exposure currently depends on a manual `socat` forwarder.
  If the desktop reboots, phone memory can appear broken until the forwarder is
  restored.
- Tailscale reconnect after phone reboot is not guaranteed unless Android battery
  settings keep Tailscale, Termux, and Termux:Boot unrestricted.
- Long SSH calls need keepalive options; silent links can drop through Android,
  Tailscale, or carrier/Wi-Fi behavior.
- Termux `sshd` should be treated as a phone lifecycle dependency, not a normal
  VPS service. Debug-mode `sshd -ddd` is useful for auth diagnosis but can exit
  after a single attempt; restart normal daemon mode before declaring the route
  broken.
- Local LLM mode is on-demand only. Do not treat the phone as a permanently
  resident inference server.
- The repo contains operational examples. Keep Tailnet IPs, hostnames, usernames,
  tokens, `.env` content, SSH key paths, and raw runtime logs out of future PRs
  and ledger comments.

## Lessons from the first Donna-to-phone SSH validation

The first live Donna-to-phone route is validated at the bounded readiness layer:
Donna can SSH to the phone through the local alias and receive `SAM_AUTH_OK` plus
non-sensitive tool probes. Keep this as a transport milestone, not topology
enablement.

Operational lessons:

- A public key must appear in `authorized_keys` as one physical line. Mobile paste
  wrapping can make permissions and sshd config look correct while the expected
  key is still absent.
- Verify key acceptance by fingerprinting `authorized_keys`, then confirm from the
  caller side with a `BatchMode` probe. Do not paste private keys or raw key files
  into ledgers.
- Check bootstrap docs/scripts for stale public keys before changing sshd policy.
  If Donna's private key was rotated but an older phone bootstrap snippet still
  seeds `authorized_keys`, sshd will correctly reject the new offered key.
- `permission_denied` after `Offering public key` usually means the route and
  sshd listener are alive but the key is not accepted by Termux.
- `connection_refused` after a debug attempt often means debug-mode `sshd` exited;
  restart normal daemon mode and re-check the listener before changing topology.
- The phone currently has Python available for bounded probes. Do not assume
  `tmux`, attach wrappers, boot persistence, or grid-worker readiness until the
  readiness report proves those fields.
- Direct repair access is useful because the phone is mobile and flaky. Keep
  repairs bounded: auth/listener/package checks are acceptable when approved;
  secrets, raw session stores, local-LLM autostart, and topology enablement remain
  out of scope without explicit approval.

## Studio54 onboarding contract

Before enabling the phone in Studio54 topology, collect a redacted discovery
report with these fields:

```yaml
candidate: Android | Termux
transport:
  ssh_alias_configured: true | false
  tailscale_reachable: true | false
  ssh_port: redacted-or-default
  host_details_redacted: true
runtime:
  termux_present: true | false
  hermes_present: true | false
  cloud_profile: s24-cloud
  local_profile: s24-local
  tmux_present: true | false
  attach_wrapper_present: true | false
persistence:
  termux_boot_present: true | false
  sshd_on_boot: true | false
  gateway_autostart: true | false
  local_llm_autostart: false
mobile_constraints:
  battery_unrestricted: true | false | unknown
  tailscale_reconnect_after_reboot: true | false | unknown
  wake_lock_policy: documented | missing
  local_llm_residency: on-demand-only
safety:
  secrets_printed: false
  raw_runtime_logs_preserved: false
  installs_performed: false
  services_changed: false
next_action: string
```

## Phase A discovery artifacts

This repo now carries the first non-mutating Phase A artifacts for Donna / Studio54:

- `scripts/install-hermes-on-s24/verify-grid-readiness.sh` emits a redacted YAML
  readiness report. Default behavior is local-only: no SSH, ADB, install,
  service, firewall, gateway, Honcho, Moshi/mosh, or local-LLM mutation.
- `scripts/install-hermes-on-s24/phone/bin/mobile-hermes-attach.template` is an
  attach-only wrapper template. It attaches to an existing `tmux` session/window
  and refuses missing sessions instead of creating them.

Run the report safely from a desktop checkout:

```bash
cd scripts/install-hermes-on-s24
./verify-grid-readiness.sh --dry-run
./verify-grid-readiness.sh --sample
```

Do not enable Android or Termux in Studio54 from this output alone. The report is
an evidence scaffold for the next explicit transport validation, not live attach
authorization.

## Minimum probe ladder

1. **Discovery only**
   - Confirm intended final tab name: `Android`, `Termux`, or both.
   - Confirm SSH alias and transport without printing hostnames/IPs/key paths.
   - Confirm whether `tmux` and an attach wrapper exist on the phone.
   - Use `verify-grid-readiness.sh` as the redacted report shape.

2. **Topology stub**
   - Keep the Studio54 entry disabled.
   - Mark kind as `pending-mobile-edge`.
   - Store only redacted/generic notes in Studio54.

3. **Phone-side wrapper**
   - Prefer a stable host-side wrapper, e.g. `mobile-hermes-attach`, that attaches
     to an existing Termux/tmux/Hermes session.
   - The wrapper should not create sessions, install packages, start local LLMs,
     or mutate secrets unless explicitly invoked for that purpose.

4. **Dry-run attach**
   - `./bin/hermes-grid attach <tab> --dry-run` must show the intended command.
   - Disabled tabs must refuse before executing anything.

5. **Bounded live smoke**
   - Use an explicit timeout.
   - Do not preserve raw pane/session output.
   - Record only pass/fail, command family, and safety boundaries.

## Suggested first PRs

1. **Mobile-Hermes PR: documentation hygiene and grid readiness**
   - Redact Tailnet IP examples.
   - Add this readiness contract.
   - Keep functional defaults unchanged until the active phone path is confirmed.

2. **Studio54 PR: disabled mobile-edge topology refinement**
   - Link to this repo/doc from the Android/Termux candidate notes.
   - Keep `enabled: false`.

3. **Mobile-Hermes PR: attach wrapper and verification script**
   - Add a read-only `verify-grid-readiness.sh` script.
   - Add a phone-side attach wrapper template.
   - Add tests for redaction and no-runtime-mutation behavior.

## Do not do yet

- Do not enable the phone tab in Studio54.
- Do not auto-start the local LLM.
- Do not install or pair Moshi/Mosh hooks.
- Do not expose Tailnet IPs, SSH key paths, `.env`, API keys, raw Hermes session
  databases, memory stores, or raw tmux panes.
- Do not assume desktop Honcho reachability proves phone-side memory is durable;
  verify the forwarder and phone profile explicitly.

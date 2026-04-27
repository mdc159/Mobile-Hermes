I reviewed the design. Overall, the architecture is sensible: Hermes stays API-backed for serious agent work, the phone gets a small GGUF text fallback, AI Edge Gallery/Gemma stays separate for phone-native multimodal use, and Honcho runs off-phone over Tailscale. That split is the right basic shape for an 8 GB S24. The parts I would change are mostly around startup behavior, Honcho assumptions, security boundaries, and exact model/runtime wiring. 

## Main critique

The biggest practical issue is **auto-starting `llama-server` at boot**. On the base S24, I would not keep Qwen3 resident all the time. Qwen3-4B Q4_K_M is about 2.5 GB just for the GGUF file, and context/KV cache plus Hermes, Python, Termux, Android, Tailscale, and any gateway process will eat the remaining RAM quickly. Hermes’ own local-model guidance warns that llama.cpp can allocate too much KV cache when context is not explicitly capped; your spec does cap it, but `-c 12288` is still aggressive for an 8 GB phone. I would install the launcher, but start it on demand, not from Termux:Boot. ([Hugging Face][1])

Use this as the first local fallback profile:

```bash
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

MODEL="$HOME/llama.cpp/models/Qwen3-4B-Q4_K_M.gguf"

exec "$HOME/llama.cpp/build/bin/llama-server" \
  -m "$MODEL" \
  --jinja \
  -c "${CTX:-8192}" \
  -n "${MAX_NEW:-1024}" \
  -np 1 \
  --host 127.0.0.1 \
  --port 8080
```

Then test `12288` only after the 8k version is stable. The Hermes docs are clear that `--jinja` is required for llama-server tool calling; without it, tool calls tend to come back as raw JSON text rather than executed tool calls. ([Hermes Agent][2])

The second issue is **model identity and filename precision**. The spec says `Qwen3-4B-Instruct-Q4_K_M.gguf`, but that exact filename should not be treated as canonical. The official `Qwen/Qwen3-4B-GGUF` repo lists Q4_K_M as 2.5 GB and supports llama.cpp/Ollama-style local use, while `Qwen/Qwen3-4B-Instruct-2507` is a different repo with very long context and documented OpenAI-compatible serving paths, but the GGUFs you’ll likely use for that variant are community quants unless you convert them yourself. I would pin the repo, filename, and SHA256 in the script rather than searching by loose name. ([Hugging Face][1])

The third issue is **profile separation**. The spec says “Switch profiles with `hermes model`,” but `hermes model` configures model providers; Hermes profiles are managed with `hermes profile create`, `hermes profile use`, or `hermes -p <profile>`. I would create two explicit phone profiles: `s24-cloud` and `s24-local`. `s24-cloud` uses OpenRouter/OpenAI plus Honcho. `s24-local` uses `http://127.0.0.1:8080/v1`, disables the external memory provider, and relies on built-in Hermes memory. This makes the airplane-mode success criterion testable instead of depending on whatever model happens to be active. ([Hermes Agent][3])

A workable structure would be:

```bash
hermes profile create s24-cloud --clone
hermes profile create s24-local --clone
```

For `s24-cloud`:

```yaml
model:
  provider: openrouter
  default: your-primary-openrouter-model

fallback_model:
  provider: openai
  model: your-secondary-openai-model

memory:
  provider: honcho
```

For `s24-local`:

```yaml
model:
  provider: custom
  default: qwen3-4b-local
  base_url: http://127.0.0.1:8080/v1
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

Hermes documents `fallback_model`, so the cloud profile should use that instead of treating OpenAI secondary as only an environment-variable convention. ([Hermes Agent][2])

## Honcho critique

The Honcho plan is mostly good, but one part is misleading: in `recallMode: tools`, `contextTokens`, `dialecticCadence`, and `dialecticDepth` do **not** limit automatic context injection because there is no automatic context injection in tools mode. In tools mode, the model has to explicitly call Honcho tools such as `honcho_search`, `honcho_context`, or `honcho_reasoning`. `writeFrequency: async` still matters, but the cadence and token-budget knobs mainly matter for `hybrid` or `context` mode. ([Hermes Agent][4])

The spec should also explicitly set:

```yaml
memory:
  provider: honcho
```

Writing `honcho.json` alone may not activate Honcho as the external memory provider. Hermes’ memory-provider docs say built-in memory remains active alongside an external provider, and the external provider is additive, but only one external provider can be active at a time. ([Hermes Agent][5])

The separate workspace `hermes-s24` is defensible for testing, but it means the phone is not truly sharing the same Honcho workspace/user model as the desktop agent. Honcho’s profile model is designed around a shared workspace with separate AI peers. For actual cross-device continuity, I would use the same workspace as the desktop and set a distinct `aiPeer`, such as `hermes-s24`. For isolation and safety during first install, keep `workspace: hermes-s24`. The design should say which goal wins: isolation or shared memory. ([Hermes Agent][5])

## Security critique

The statement “`AUTH_USE_AUTH=false` is acceptable on Tailscale because the tailnet is the auth boundary” is too broad. It is acceptable only if the tailnet ACL/grant policy limits access to the Honcho port to the S24 and perhaps your desktop account. Tailscale’s access-control docs emphasize least privilege, and the ACL docs note that a newly created tailnet’s default policy may allow all devices to talk to each other. Honcho’s self-hosting docs treat `AUTH_USE_AUTH=false` as local-development configuration, while production guidance says to enable authentication and HTTPS. ([Tailscale][6])

I would revise the security section to one of these two positions:

```text
Preferred:
Enable Honcho auth and restrict access with Tailscale ACLs.

Acceptable for private lab:
AUTH_USE_AUTH=false only when:
  - Honcho binds only to localhost or the Tailscale IP,
  - Tailscale ACLs allow only miguels-s24 -> desktop:18000,
  - no shared/external tailnet users can access the desktop node,
  - Postgres remains bound to localhost only.
```

Using Tailscale Serve is also worth considering: it can expose a localhost service within the tailnet without binding the application itself to `0.0.0.0`, and ACLs still apply. ([Tailscale][7])

Also, do not copy broad desktop API keys to the phone. Generate phone-specific OpenRouter/OpenAI/Groq keys with low limits where possible. The script should set `umask 077`, make `~/.hermes` mode `700`, make `.env` mode `600`, and never sync unrelated keys from the desktop `.env`.

## Termux/bootstrap critique

The install sequence has a bootstrapping gap. Phase 0 uses:

```bash
ssh-copy-id -p 8022 u0_a369@miguels-s24
```

but a blank Termux install will not already have `openssh`, a password, or `sshd` running. The design needs a “Phase -1” phone-touch prerequisite:

```text
1. Install Termux from a consistent source, preferably F-Droid.
2. Install Tailscale app and join tailnet.
3. In Termux:
   pkg update
   pkg install -y openssh
   passwd
   sshd
4. From desktop:
   ssh-copy-id -p 8022 <termux-user>@miguels-s24
5. Disable password auth after key auth works.
```

The spec installs the `termux-api` package but does not mention the **Termux:API app**, which is required for Termux API commands to function. That matters because `termux-wake-lock` is used later. Termux:Boot also requires the Termux:Boot app to be launched once, scripts placed in `~/.termux/boot/`, executable permissions, and battery optimization disabled for Termux and Termux:Boot. ([wiki.termux.com][8])

Android Doze remains a real limitation. The spec’s SLA language is good, but the implementation should not rely on cron alone. Android can defer background CPU/network work in Doze and App Standby, so the boot script should be conservative and should not keep a local model alive indefinitely. ([Android Developers][9])

Recommended boot script behavior:

```bash
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

export PATH="$PREFIX/bin:$PATH"
mkdir -p "$HOME/.hermes/logs"

termux-wake-lock || true

# Start sshd if not running.
pgrep -x sshd >/dev/null || sshd

# Do not auto-start llama-server by default.
# Start gateway only when TELEGRAM_BOT_TOKEN is present and explicitly enabled.
```

Then add a separate command:

```bash
~/.hermes/bin/start-local-llm
```

for on-demand local inference.

## Voice/STT critique

The custom `cloud-whisper` shim is probably unnecessary. Hermes’ current Voice & TTS docs already show STT providers for `local`, `groq`, `openai`, and `mistral`, with OpenAI accepting `whisper-1`, `gpt-4o-mini-transcribe`, and `gpt-4o-transcribe`. The Termux docs still say the Android-tested path excludes the full `voice` extra because `faster-whisper -> ctranslate2` lacks Android wheels, so the action item is not “write a shim first”; it is “test whether cloud STT works under `.[termux]` with the existing `stt:` config.” ([Hermes Agent][10])

Use this first:

```yaml
stt:
  provider: "groq"
  groq:
    model: "whisper-large-v3"

tts:
  provider: "openai"
```

or:

```yaml
stt:
  provider: "openai"
  openai:
    model: "gpt-4o-mini-transcribe"
```

OpenAI’s speech-to-text endpoint has a 25 MB upload limit, and Groq documents `whisper-large-v3` with a 100 MB max file size and listed per-hour pricing, so the spec should remove the phrase “Groq’s free Whisper-large-v3 endpoint” unless you have a confirmed free-tier quota. ([OpenAI Platform][11])

## AI Edge / Gemma critique

The AI Edge Gallery / Gemma separation is right. `Gemma-4-E2B-it LiteRT-LM` is a strong phone-native offline multimodal choice, and keeping it outside Hermes avoids needing a LiteRT-LM-to-OpenAI-compatible bridge. The E2B LiteRT-LM package is 2.58 GB and is explicitly packaged for Android/iOS/desktop/edge use; it also loads vision and audio models as needed, which helps memory pressure. ([Hugging Face][12])

I would keep E4B as a manual experiment only. The E4B LiteRT-LM package is 3.65 GB and its Android CPU benchmark reports much higher memory use than E2B under the same short benchmark conditions. On an 8 GB S24, E4B may run, but I would not make it part of the scripted install or any automatic startup path. ([Hugging Face][13])

The spec’s “not wired into Hermes” decision should remain locked. Gemma 4’s small models are built for mobile/edge and have audio/image support, but the Hermes local fallback path is currently cleaner through an OpenAI-compatible endpoint such as llama-server, Ollama, vLLM, or SGLang. ([Google AI for Developers][14])

## Browser/Playwright critique

Keep browser tooling as an optional experiment, not “default all on.” Hermes’ Termux docs explicitly say the Android-tested path skips automatic browser/Playwright bootstrap and treats browser/WhatsApp tooling as experimental. On this phone, Playwright is more likely to consume time and storage than produce reliable value. ([Hermes Agent][15])

I would change Tier 2 defaults to:

```text
Default on:
  - local LLM launcher installation, but not autostart
  - Honcho config validation
  - Termux:Boot script for sshd/gateway only

Manual/opt-in:
  - AI Edge Gallery model download
  - cloud STT/TTS
  - Telegram gateway
  - browser tooling
  - E4B testing
```

## Verification changes

Your verification table is good, but I would add or alter these gates:

```text
G0: termux-info captured to log.
G0a: command -v sshd and pgrep sshd.
G0b: Termux:API app works: termux-battery-status returns JSON.
G0c: Tailscale name and IP both work from desktop.
G1: SSH key auth works, then password auth disabled or documented.
G5: cloud profile round-trip succeeds.
G6: hermes memory status shows Honcho active.
G6b: honcho.json has the intended workspace and aiPeer.
G6c: desktop Honcho is not reachable from unauthorized tailnet nodes, or ACL is documented.
G7: local llama-server /v1/models works.
G8: http://127.0.0.1:8080/props contains chat_template.
G8b: actual local tool call executes; raw JSON output is failure.
G8c: airplane mode + s24-local profile works.
G9: reboot test confirms sshd/gateway only; local LLM remains off until manually started.
```

Hermes also recommends checking `/props` for `chat_template` when validating llama-server tool support, so that should be in the local-model gate. ([Hermes Agent][2])

## Bottom line

I would approve the design after four changes:

1. Use explicit `s24-cloud` and `s24-local` Hermes profiles.
2. Do not auto-start `llama-server`; start it on demand and begin with 8k context.
3. Treat `AUTH_USE_AUTH=false` as acceptable only with Tailscale ACLs or enable Honcho auth.
4. Replace the custom cloud-Whisper shim with Hermes’ built-in `stt.provider` path unless testing proves it unavailable in the Termux bundle.

With those changes, the spec becomes a realistic S24 install plan rather than a desktop-style agent stack squeezed onto a phone.

[1]: https://huggingface.co/Qwen/Qwen3-4B-GGUF?utm_source=chatgpt.com "Qwen/Qwen3-4B-GGUF · Hugging Face"
[2]: https://hermes-agent.nousresearch.com/docs/integrations/providers "AI Providers | Hermes Agent"
[3]: https://hermes-agent.nousresearch.com/docs/user-guide/profiles/?utm_source=chatgpt.com "Profiles: Running Multiple Agents | Hermes Agent"
[4]: https://hermes-agent.nousresearch.com/docs/user-guide/features/honcho "Honcho Memory | Hermes Agent"
[5]: https://hermes-agent.nousresearch.com/docs/user-guide/features/memory-providers "Memory Providers | Hermes Agent"
[6]: https://tailscale.com/docs/features/access-control?utm_source=chatgpt.com "Access control · Tailscale Docs"
[7]: https://tailscale.com/docs/features/tailscale-serve?utm_source=chatgpt.com "Tailscale Serve · Tailscale Docs"
[8]: https://wiki.termux.com/wiki/Termux%3AAPI?lang=en&utm_source=chatgpt.com "Termux:API - Termux Wiki"
[9]: https://developer.android.com/training/monitoring-device-state/doze-standby?utm_source=chatgpt.com "Optimize for Doze and App Standby  |  App quality  |  Android Developers"
[10]: https://hermes-agent.nousresearch.com/docs/user-guide/features/tts?utm_source=chatgpt.com "Voice & TTS | Hermes Agent"
[11]: https://platform.openai.com/docs/guides/speech-to-text?lang=javascript&utm_source=chatgpt.com "Speech to text | OpenAI API"
[12]: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm "litert-community/gemma-4-E2B-it-litert-lm · Hugging Face"
[13]: https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm?utm_source=chatgpt.com "litert-community/gemma-4-E4B-it-litert-lm · Hugging Face"
[14]: https://ai.google.dev/gemma/docs/core "Gemma 4 model overview  |  Google AI for Developers"
[15]: https://hermes-agent.nousresearch.com/docs/getting-started/termux "Android / Termux | Hermes Agent"

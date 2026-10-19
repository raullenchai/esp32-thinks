<p align="center">
  <img width="340" alt="esp32-thinks" src="https://github.com/user-attachments/assets/ee7031ee-0ad3-4559-ad28-30c26c858a9c" />
</p>

# esp32-thinks

<p align="center">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-green"></a>
  <img alt="ESP-IDF v6.0.x" src="https://img.shields.io/badge/ESP--IDF-v6.0.x-blue">
  <img alt="board" src="https://img.shields.io/badge/board-SenseCAP%20Watcher-black">
  <a href="https://github.com/raullenchai/esp32-thinks/tree/v0.2.12"><img alt="v0.2.12" src="https://img.shields.io/badge/status-v0.2.12-orange"></a>
  <a href="https://github.com/raullenchai/esp32-thinks/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/raullenchai/esp32-thinks/actions/workflows/ci.yml/badge.svg"></a>
</p>

**A multi-model Muse — a personal AI assistant on ESP32, talking out of the box.**

Think of it as a Muse that thinks with **your** models: say **"Hi, ESP"** (or press the knob), ask anything, and it answers **out loud** — streaming sentence-by-sentence while the model is still writing, in English, Chinese or Korean, on a small gadget with a mic, a speaker and a round display.

No vendor lock on the brain: **speech, transcription and chat are three independent endpoints**, each pointed at any OpenAI-compatible server — one provider for all three, or a different one per task. Run it bare against QuickSilver, or put the in-repo **openmuse** agent in front to give it location, weather, time and memory.

- ESP32-S3 · built on Meta's open-source [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) · [license notices](THIRD-PARTY-NOTICES.md)
- Models: **OpenAI**, **QuickSilver**, a local agent, or any mix — presets for the common ones, fully custom for the rest

## Why

Cloud assistants rent you a brain: one vendor's models, one vendor's pricing, one vendor's uptime, and your voice on their servers. The gadget hardware is fine — the lock is in the firmware.

esp32-thinks flips that. The device runs **your** stack: pick the cheapest transcription, the smartest chat model, the voice you like — per task, changeable in one config line and a rebuild. The implementation is a reviewable patch against a pinned open-source SDK, so you can read it, change it, or point it at a local server. The optional openmuse agent keeps the extra context (location, memory, tools) on **your** machine too.

## What you get

- **Wake word + button** — say "Hi, ESP" (esp-sr WakeNet10, runs on-chip) or hold the knob; both start a turn. Wake turns end on a voice-activity timer; the button works exactly like before.
- **Bring your own brain** — three independent OpenAI-compatible endpoints (STT / chat / TTS) in one config file. Mix providers freely; presets: `openai`, `quicksilver`, `openmuse`, `custom`.
- **Optional agent layer** — the in-repo `openmuse/` adds location, clock, weather, persistent memory and optional web search, owns the system prompt, and proxies STT so STT + chat share one TLS session. TTS still goes straight to your provider.
- **Streaming voice replies** — the chat stream is parsed at sentence boundaries (ASCII + CJK); each sentence is synthesized the moment it lands and appended to the audio already playing. First word arrives while the model is still generating.
- **Long-lived brain connection** — TLS is prepared before you ask, probed every 180 s while idle, and resumed with session tickets after an idle close. A failed probe triggers background preparation; a disconnect between probes may still need turn-time reconnection.
- **Barge-in** — press the knob while Muse is speaking: the reply stops mid-sentence, in-flight requests are cancelled, and your next words start a fresh turn immediately.
- **Silence guard** — a quiet recording (interrupted turn, pocket press) is discarded instead of becoming a hallucinated answer.
- **Automatic stall recovery** — outstanding I2S or LCD work gets a 20 s deadline, followed by a zero-allocation task dump and reboot; a wedged I2C expander (v0.2.11+) reboots after a minute of solid failure. Normal sleep and slow cloud responses don't count as stalls.
- **Language following** — answer in the user's language, defaulting to English when unclear. English, Chinese and Korean are tested; STT detects language automatically. Replies aim for one or two sentences, about 40 words or 60 Chinese characters.
- **Language-aware voice** — Chinese and Korean reply text selects the optional multilingual TTS model. The QuickSilver preset uses qwen3-tts for these replies and chatterbox-turbo for English.
- **Headless provisioning** — put your Wi-Fi in the config; the device self-provisions on boot. No app, no BLE dance, no vendor account needed.
- **Typed turns exercise chat and TTS** — the serial console path runs the same inference and decoding pipeline without microphone capture.

## Quick start

```bash
# 0) One-time: ESP-IDF v6.0.x for esp32s3 (docs/REFERENCE.md §Prerequisites)

git clone https://github.com/facebookincubator/muse-gadget-sdk.git
git -C muse-gadget-sdk checkout 812c46f
git clone https://github.com/raullenchai/esp32-thinks.git
cd esp32-thinks

# 1) Back up the factory NVS once — your restore path if anything goes sideways
./scripts/backup-nvs.sh ../muse-gadget-sdk /dev/ttyACM1   # use your port: ACM0 or ACM1

# 2) Apply the patch + configure your brain (pick a preset)
./apply.sh ../muse-gadget-sdk --preset quicksilver   # or openai / openmuse / custom

# 3) Build + flash (CH342-safe pacing; allow several minutes)
./build-and-flash.sh ../muse-gadget-sdk /dev/ttyACM1
```

With a preset + headless Wi-Fi in step 2, that's the whole setup: unplug, re-plug, and talk — press the knob, or just say "Hi, ESP".

| Command | Does |
|---|---|
| `./scripts/backup-nvs.sh <sdk> [port]` | Dump the factory NVS partition (0x9000, 0x32000) — do this once |
| `./apply.sh <sdk> [--preset ...]` | Copy pinned CAs, apply `patches/muse-brain.patch`, generate `provider_config.h` (asks for keys, Wi-Fi, wake word) |
| `./build-and-flash.sh <sdk> [port]` | `idf.py build` + paced flash (firmware + wake-word model); never interrupt it |
| `python3 scripts/tts_probe.py <sdk> [port] ["question"]` | Typed chat/TTS probe; opens a serial reader and resets the device |
| `./openmuse/run.sh [--funnel]` | Optional agent: Docker or Node, `--funnel` exposes HTTPS via Tailscale |

## Own brain: openmuse (optional)

QuickSilver alone is the fastest path. If you want the gadget to know your city
and time, answer weather questions, and remember things across turns, run the
agent that ships in this repo:

```bash
./openmuse/run.sh              # first run writes openmuse/.env, then exits
$EDITOR openmuse/.env          # set UPSTREAM_API_KEY + OPENMUSE_TOKEN
./openmuse/run.sh --funnel     # Docker or Node; --funnel exposes HTTPS via Tailscale
./apply.sh ../muse-gadget-sdk --preset openmuse
#   chat URL: https://<host>/v1
#   token:    OPENMUSE_TOKEN
```

openmuse sits between the device and any OpenAI-compatible LLM: it owns the
system prompt, adds location/clock/weather/memory tools, proxies STT (one TLS
session for STT + chat), and streams the reply through untouched. TTS still goes
directly to QuickSilver. It needs no domain — a Tailscale Funnel gives it a real
Let's Encrypt certificate. Memory lives in `openmuse/data/memories.json`.
Details: **[openmuse/README.md](openmuse/README.md)**. For the protocol, the
CopilotKit/OpenMuse boundary, and troubleshooting, see
**[docs/OPENMUSE.md](docs/OPENMUSE.md)**.

## Performance (measured on device)

QuickSilver preset, typed warm turns: **2.2–2.5 s** for English/Korean and about
**6.8 s** for Chinese (longer text, slower synthesis). The nightly soak on
2026-10-19 measured **2.2 s / 6.8 s / 2.8 s** (EN/CN/KO). Voice turns add
recording/VAD: roughly 3–5 s from end of speech to first sound.

With the openmuse agent in front, add one hop and tool work: typed warm turns
measured **~3.9 s**, a voice turn **~4.7 s**; the first turn after boot can be
slower while DNS/TLS warm up. These are individual samples, not latency
guarantees — provider load and reply length dominate.

See [REFERENCE](docs/REFERENCE.md) for historical measurements and configuration,
and [docs/SOAK.md](docs/SOAK.md) for the nightly stability check.

## How a turn flows

```
 "Hi, ESP" / knob ──▶ record (pre-roll holds the last second)
                        │  ends: voice VAD (~1.4 s silence) or knob release
                        ▼
              trim to speech ──▶ POST WAV/ADPCM ─▶ STT endpoint (or openmuse proxy)
                        │                         (¼-size upload, keep-alive)
                        ▼
              POST /chat/completions (SSE) ──────────────▶ chat endpoint (or openmuse)
                        │  split at sentence boundaries (ASCII + 。！？…)
                        ▼
              per sentence: POST /audio/speech ─▶ MP3 appends to the buffer
                        │                          already decoding + playing
                        ▼
                 first word out loud while the model is still writing
```

- **Connection care is off the critical path**: the first TLS handshake happens after Wi-Fi comes up (and before a recording if needed), a HEAD probe re-checks the client every 180 s while idle, and tickets enable TLS 1.3 resumption. A keep-alive FIN surfaces as an empty 200 and gets one transparent retry before any reply data has started.
- **Short replies** (≤ 128 UTF-8 bytes) reuse the completed chat connection for speech; longer replies stream sentences on a separate speech connection. Each endpoint pins its own root CA, and tickets never cross origins.
- On-device the screen follows the turn: **listening** (mic accent + level meter) → **thinking** (ring spinner, caption shows the transcript) → **speaking** (level follows the audio, caption follows the text).

Connection preparation starts after Wi-Fi comes up. A first question can still pay connection costs if preparation has not finished, or when a longer reply needs a separate speech connection. See [REFERENCE](docs/REFERENCE.md) for historical measurements and connection behavior.

## At a glance

| | |
|---|---|
| Device | Seeed SenseCAP Watcher W1-B (ESP32-S3, 1.45" 412×412 round LCD, ES8311 speaker codec, ES7243E mic, PTT knob) — more boards the SDK supports are candidates |
| Base firmware | [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) @ `812c46f` (2026-10-09) + `patches/muse-brain.patch` (see [what's theirs, what's ours](#built-on-muse-gadget-sdk)) |
| ESP-IDF | v6.0.x (CI pins `espressif/idf:v6.0.3`) |
| Brain | Any OpenAI-compatible servers: STT (`/audio/transcriptions`), chat (`/chat/completions`, SSE streaming), speech (`/audio/speech`) |
| Presets | `openai` (all three) · `quicksilver` (qwen3.7-flash + whisper-large-v3-turbo + chatterbox/qwen3-tts) · `openmuse` (in-repo agent for STT + chat, QuickSilver TTS) · `custom` |
| Wake word | esp-sr WakeNet10 `wn10_hiesp` ("Hi, ESP", on-chip, `model` flash partition) — custom phrases trainable via Espressif's TTS Pipeline V3 |
| Build host | Linux or macOS with ESP-IDF v6.0.x |

## Serial console

The USB serial port is a full console, handy for bench testing. Ports can
renumber on replug — use the one that answers `>status` (`/dev/ttyACM0` or
`/dev/ttyACM1`):

| Input | Does |
|---|---|
| hold knob / `d`…`u` | simulate PTT down/up |
| `k` | audible self-test: plays the wake phrase through the speaker, then a full voice turn |
| `>chat=hello?` | typed turn — same chat/TTS pipeline |
| `>tasks` | dump every task backtrace (works even while wedged) |
| `>status` | heartbeats: Wi-Fi, heap, DMA, tunnel, firmware version |
| `z` / `w` | sleep / wake |
| `p` | screenshot over serial |

Use `>chat=` for routine checks and `d`/`u` for silent PTT input. Reserve `k` for a deliberate acoustic wake check; avoid loops that repeatedly play the wake phrase.

## Built on muse-gadget-sdk

Credit where it's due — and clarity about the split:

**The SDK provides** the device framework, LVGL UI and round-LCD drivers, audio stack (codec, resampler, minimp3), input/console plumbing, OTA and partitioning. The patch also wraps peripheral I/O to monitor stalls. This recipe targets a pinned SDK commit so patches apply cleanly.

**Ours** (`patches/muse-brain.patch`): the brain session (`muse_chat_session.cpp` — three-endpoint config, SSE sentence streaming, TTS pipeline, connection warm-up + idle probes, turn cancellation), the wake-word integration (`muse_voice.c` — direct WakeNet10 on idle chunks, wake→PTT synthesis, VAD end-of-turn, quiet-recording guard, stall coroner), the I2C expander watchdog, the `model` flash partition and the esp-dl kernel fix, plus the tooling (`apply.sh`, `build-and-flash.sh`, NVS backup, probes) and the optional `openmuse/` agent.

Nothing else from the Muse cloud is required: the vendor agent works as an optional fallback (its token is optional), and with headless provisioning the device never contacts it.

## Configuration

Everything lives in `esp32/components/muse/provider_config.h` (written by `apply.sh`):

| Setting | What |
|---|---|
| `TTS_URL` / `TTS_MODEL` / `TTS_VOICE` | Speech endpoint, model, voice |
| `TTS_MODEL_CJK` | Optional second speech model, selected for Chinese/Korean reply text |
| `BRAIN_STT_WAV_ADPCM` | `1` uploads IMA ADPCM WAV at about one quarter of PCM size; enabled for the verified `quicksilver` and `openmuse` presets, `0` otherwise |
| `TTS_API_KEY` / `TTS_CA` | Its key and pinned root (`OPENAI_CA` or `ISRG_CA`) |
| `BRAIN_STT_URL` / `BRAIN_STT_MODEL` | Transcription endpoint (shares the chat key); `openmuse` points this at the agent's `/audio/transcriptions` proxy |
| `BRAIN_STT_LANG` / `BRAIN_STT_PROMPT` | Empty by default: omit both fields and auto-detect language; optionally pin an ISO 639-1 language or provide a prompt |
| `BRAIN_CHAT_URL` / `BRAIN_CHAT_KEY` / `BRAIN_MODEL` | Chat endpoint; leave the URL empty to use the Muse cloud agent. `openmuse` uses the agent URL and token |
| `BRAIN_CHAT_EXTRA` | Extra JSON merged into the chat body (provider quirks, e.g. DeepSeek's `reasoning.exclude`) |
| `BRAIN_SYSTEM` | Language-following persona; one or two sentences, ~40 words / 60 Chinese characters; greeting-only input returns `Please ask.` (openmuse replaces this with its own prompt) |
| `WAKE_WORD` | `1` = "Hi, ESP" wake word + button; `0` = button only |
| `WAKE_VAD_DB` | End-of-turn silence threshold for wake turns (raise toward -35 if it keeps recording after you stop) |
| `DEV_WIFI_SSID` / `DEV_WIFI_PASS` | Headless provisioning; empty = normal BLE setup |

Presets: `openai`, `quicksilver`, `openmuse` (STT + chat through the in-repo [openmuse](openmuse/README.md) agent — location, weather, time, memory — with QuickSilver for TTS), and `custom`.

Changed a define? Re-run `./build-and-flash.sh` — it rebuilds and reflashes.

## Security notes

- **API keys are compiled into the firmware.** This is a hobby recipe, not a multi-tenant product — don't flash keys you aren't comfortable with into a device that leaves your bench, and don't commit `provider_config.h` (it's generated; `apply.sh` keeps it out of the repo).
- **`openmuse/.env` holds its keys too** and is gitignored; only `openmuse/.env.example` is tracked.
- Each endpoint pins its root CA (`files/*.pem`); the ESP cert bundle alone doesn't carry them (the v0.1 story — see [REFERENCE](docs/REFERENCE.md#security) — now with a second root for Let's Encrypt hosts).
- Voice is recorded only during a turn (button held, or after the wake word until the VAD closes it). With a headless token placeholder the Muse cloud is never contacted.

## Roadmap

- More boards the SDK supports (Waveshare, M5Stack…).
- Full-duplex speech-to-speech models (e.g. QuickSilver's qwen3.8-omni); openmuse already accepts any OpenAI-compatible upstream, and LAN HTTP support would remove the public tunnel.
- Custom wake phrases ("Hey Mica") via Espressif's TTS Pipeline V3.
- Echo-proof wake word (speaker audio must never re-trigger the device), and a root-cause fix for the rare DMA event loss behind the stall reboot.
- openmuse: nightly memory distillation (turn logs → stable profile facts), plus calendar/contacts connectors.
- Vision mode (Watcher camera → multimodal model), local timers, music/radio, and MCP/Home Assistant tools. See [docs/IDEAS.md](docs/IDEAS.md) for the community survey and a prioritized list.

Build details and historical receipts: **[docs/REFERENCE.md](docs/REFERENCE.md)**. For contributing and validation, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

Top four (full checklist in [REFERENCE](docs/REFERENCE.md#troubleshooting)):

- **No reply at all?** Check the console for `brain heard:` (transcription worked) and `TTS ok:` — quiet recordings are normally discarded with `DIDN'T CATCH THAT`. `BRAIN STT FAILED` can also indicate transport or response errors; inspect the HTTP log before changing credentials.
- **It rebooted by itself** — look for `coroner:` (a 20 s peripheral stall) or `expander wedged` (v0.2.11+) just before `rst:`. The `Wi-Fi ... reason=8` line right before the reset is the shutdown side-effect, not the cause; see [issue #5](https://github.com/raullenchai/esp32-thinks/issues/5).
- **`device reports readiness to read but returned no data`** — two processes fighting over the same `/dev/ttyACM*` (monitor + probe). One at a time.
- **Garbled flash / boot loop** — you used plain `esptool` at high baud. The CH342 bridge drops whole packets; the recipe uses `paced_esptool` at 115200 for a reason.

## Getting help

- **Questions, setups, provider picks, "look at my build"** — [Discussions](https://github.com/raullenchai/esp32-thinks/discussions).
- **Bugs** — [open an issue](https://github.com/raullenchai/esp32-thinks/issues/new/choose). Include the serial log: the `version:` line from `>status`, the turn that failed, and `>tasks` if the device froze (or the lines just before `rst:` if it rebooted).
- **Contributions** — [CONTRIBUTING.md](CONTRIBUTING.md); issues labeled `good first issue` are scoped to be self-contained.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) and the [releases page](https://github.com/raullenchai/esp32-thinks/releases).

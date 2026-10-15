<p align="center">
  <img width="340" alt="esp32-thinks" src="https://github.com/user-attachments/assets/ee7031ee-0ad3-4559-ad28-30c26c858a9c" />
</p>

# esp32-thinks

<p align="center">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-green"></a>
  <img alt="ESP-IDF v6.0.1" src="https://img.shields.io/badge/ESP--IDF-v6.0.1-blue">
  <img alt="board" src="https://img.shields.io/badge/board-SenseCAP%20Watcher-black">
  <a href="https://github.com/raullenchai/esp32-thinks/tree/v0.2.10"><img alt="v0.2.10" src="https://img.shields.io/badge/status-v0.2.10-orange"></a>
</p>

**A multi-model Muse — a personal AI assistant on ESP32, talking out of the box.**

Think of it as a Muse that thinks with **your** models: say **"Hi, ESP"** (or press the knob), ask anything, and it answers **out loud** — streaming sentence-by-sentence while the model is still writing, in English, Chinese or Korean, on a small gadget with a mic, a speaker and a round display.

No vendor lock on the brain: **speech, transcription and chat are three independent endpoints**, each pointed at any OpenAI-compatible server — one provider for all three, or a different one per task.

- ESP32-S3 · built on Meta's open-source [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) · [license notices](THIRD-PARTY-NOTICES.md)
- Models: **OpenAI**, **QuickSilver**, or any mix — presets for the common ones, fully custom for the rest

## Why

Cloud assistants rent you a brain: one vendor's models, one vendor's pricing, one vendor's uptime, and your voice on their servers. The gadget hardware is fine — the lock is in the firmware.

esp32-thinks flips that. The device runs **your** stack: pick the cheapest transcription, the smartest chat model, the voice you like — per task, changeable in one config line and a rebuild. The implementation is a reviewable patch against a pinned open-source SDK, so you can read it, change it, or point it at a local server.

## Performance (measured on device)

QuickSilver preset: qwen3.7-flash chat, whisper-large-v3-turbo STT and chatterbox-turbo / qwen3-tts speech. v0.2.10 allows one or two natural sentences, rather than the old 15-character answers. Longer replies take longer to synthesize.

| Pre-release language check | SDK turn duration |
|---|---:|
| English | 3.9 s |
| Chinese | 8.7 s |
| Korean, fresh history | 3.2 s |

These are individual samples, not latency guarantees. The final flashed firmware returned a 29-word English answer in 7.1 s, 72 Chinese characters in 15.1 s and 76 Korean characters in 10.3 s. A greeting took 1.7 s and an immediate post-wake question took 1.9 s. The Chinese sample contained 66 Han characters: the prompt’s approximate length bound can be exceeded. Typed timings include chat, speech fetch and decoding; **the console drains audio without playing it through the speaker**. They do not measure voice-to-first-sound latency.

See [v0.2.10 validation and known limits](RELEASE-NOTES-BLOCKERS.md) for exact test coverage, and [REFERENCE](docs/REFERENCE.md) for the configuration and historical latency receipts. Earlier 2–3 s figures used much shorter replies and should not be applied to the new default persona.

## What you get

- **Wake word + button** — say "Hi, ESP" (esp-sr WakeNet10, runs on-chip) or hold the knob; both start a turn. Wake turns end on a voice-activity timer; the button works exactly like before.
- **Bring your own brain** — three independent OpenAI-compatible endpoints (STT / chat / TTS) in one config file. Mix providers freely; presets: `openai`, `quicksilver`, `custom`.
- **Streaming voice replies** — the chat stream is parsed at sentence boundaries (ASCII + CJK); each sentence is synthesized the moment it lands and appended to the audio already playing. First word arrives while the model is still generating.
- **Long-lived brain connection** — TLS is prepared before you ask, probed every 180 s while idle, and resumed with session tickets after an idle close. A failed probe triggers background preparation; a disconnect between probes may still need turn-time reconnection.
- **Barge-in** — press the knob while Muse is speaking: the reply stops mid-sentence, in-flight requests are cancelled, and your next words start a fresh turn immediately.
- **Silence guard** — a quiet recording (interrupted turn, pocket press) is discarded instead of becoming a hallucinated answer.
- **Automatic stall recovery** — outstanding I2S or LCD work gets a 20 s deadline, followed by a zero-allocation task dump and reboot. Normal sleep and slow cloud responses don't count as stalls.
- **Language following** — answer in the user’s language, defaulting to English when unclear. English, Chinese and Korean are tested; STT detects language automatically. Replies aim for one or two sentences, about 40 words or 60 Chinese characters.
- **Language-aware voice** — Chinese and Korean reply text selects the optional multilingual TTS model. The QuickSilver preset uses qwen3-tts for these replies and chatterbox-turbo for English.
- **Headless provisioning** — put your Wi-Fi in the config; the device self-provisions on boot. No app, no BLE dance, no vendor account needed.
- **Typed turns exercise chat and TTS** — the serial console path runs the same inference and decoding pipeline without microphone capture.

## At a glance

| | |
|---|---|
| Device | Seeed SenseCAP Watcher W1-B (ESP32-S3, 1.45" 412×412 round LCD, ES8311 speaker codec, ES7243E mic, PTT knob) — more boards the SDK supports are candidates |
| Base firmware | [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) @ `812c46f` (2026-10-09) + `patches/muse-brain.patch` (see [what's theirs, what's ours](#built-on-muse-gadget-sdk)) |
| ESP-IDF | v6.0.1 (esp32s3 target) |
| Brain | Any OpenAI-compatible servers: STT (`/audio/transcriptions`), chat (`/chat/completions`, SSE streaming), speech (`/audio/speech`) |
| Presets | `openai` (all three) · `quicksilver` (qwen3.7-flash + whisper-large-v3-turbo + chatterbox/qwen3-tts) · `custom` — multilingual STT, language-following replies, Chinese/Korean TTS routing |
| Wake word | esp-sr WakeNet10 `wn10_hiesp` ("Hi, ESP", on-chip, `model` flash partition) — custom phrases trainable via Espressif's TTS Pipeline V3 |
| Build host | Linux or macOS with ESP-IDF v6.x |

## Quick start

```bash
# 0) One-time: ESP-IDF v6.x for esp32s3 (docs/REFERENCE.md §Prerequisites)

git clone https://github.com/facebookincubator/muse-gadget-sdk.git
git -C muse-gadget-sdk checkout 812c46f
git clone https://github.com/raullenchai/esp32-thinks.git
cd esp32-thinks

# 1) Back up the factory NVS once — your restore path if anything goes sideways
./scripts/backup-nvs.sh ../muse-gadget-sdk /dev/ttyACM1

# 2) Apply the patch + configure your brain (pick a preset)
./apply.sh ../muse-gadget-sdk --preset quicksilver   # or openai / custom

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

## How a turn flows

```
 "Hi, ESP" / knob ──▶ record (pre-roll holds the last second)
                        │  ends: voice VAD (~1.4 s silence) or knob release
                        ▼
              trim to speech ──▶ POST WAV/ADPCM ─▶ STT endpoint
                        │                         (¼-size upload, keep-alive)
                        ▼
              POST /chat/completions (SSE) ──────────────▶ chat endpoint
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

## Serial console

The USB serial port (`/dev/ttyACM1`) is a full console, handy for bench testing:

| Input | Does |
|---|---|
| hold knob / `d`…`u` | simulate PTT down/up |
| `k` | audible self-test: plays the wake phrase through the speaker, then a full voice turn |
| `>chat=hello?` | typed turn — same chat/TTS pipeline |
| `>tasks` | dump every task backtrace (works even while wedged) |
| `>status` | heartbeats: Wi-Fi, heap, DMA, tunnel |
| `z` / `w` | sleep / wake |
| `p` | screenshot over serial |

Use `>chat=` for routine checks and `d`/`u` for silent PTT input. Reserve `k` for a deliberate acoustic wake check; avoid loops that repeatedly play the wake phrase.

## Built on muse-gadget-sdk

Credit where it's due — and clarity about the split:

**The SDK provides** the device framework, LVGL UI and round-LCD drivers, audio stack (codec, resampler, minimp3), input/console plumbing, OTA and partitioning. The patch also wraps peripheral I/O to monitor stalls. This recipe targets a pinned SDK commit so patches apply cleanly.

**Ours** (`patches/muse-brain.patch`): the brain session (`muse_chat_session.cpp` — three-endpoint config, SSE sentence streaming, TTS pipeline, connection warm-up + idle probes, turn cancellation), the wake-word integration (`muse_voice.c` — direct WakeNet10 on idle chunks, wake→PTT synthesis, VAD end-of-turn, quiet-recording guard, stall coroner), the `model` flash partition and the esp-dl kernel fix, plus the tooling (`apply.sh`, `build-and-flash.sh`, NVS backup, probes).

Nothing else from the Muse cloud is required: the vendor agent works as an optional fallback (its token is optional), and with headless provisioning the device never contacts it.

## Configuration

Everything lives in `esp32/components/muse/provider_config.h` (written by `apply.sh`):

| Setting | What |
|---|---|
| `TTS_URL` / `TTS_MODEL` / `TTS_VOICE` | Speech endpoint, model, voice |
| `TTS_MODEL_CJK` | Optional second speech model, selected for Chinese/Korean reply text |
| `BRAIN_STT_WAV_ADPCM` | `1` uploads IMA ADPCM WAV at about one quarter of PCM size; enabled for the verified QuickSilver preset, `0` for other presets |
| `TTS_API_KEY` / `TTS_CA` | Its key and pinned root (`OPENAI_CA` or `ISRG_CA`) |
| `BRAIN_STT_URL` / `BRAIN_STT_MODEL` | Transcription endpoint (shares the chat key) |
| `BRAIN_STT_LANG` / `BRAIN_STT_PROMPT` | Empty by default: omit both fields and auto-detect language; optionally pin an ISO 639-1 language or provide a prompt |
| `BRAIN_CHAT_URL` / `BRAIN_CHAT_KEY` / `BRAIN_MODEL` | Chat endpoint; leave the URL empty to use the Muse cloud agent |
| `BRAIN_CHAT_EXTRA` | Extra JSON merged into the chat body (provider quirks, e.g. DeepSeek's `reasoning.exclude`) |
| `BRAIN_SYSTEM` | Language-following persona; one or two sentences, ~40 words / 60 Chinese characters; greeting-only input returns `Please ask.` |
| `WAKE_WORD` | `1` = "Hi, ESP" wake word + button; `0` = button only |
| `WAKE_VAD_DB` | End-of-turn silence threshold for wake turns (raise toward -35 if it keeps recording after you stop) |
| `DEV_WIFI_SSID` / `DEV_WIFI_PASS` | Headless provisioning; empty = normal BLE setup |

Changed a define? Re-run `./build-and-flash.sh` — it rebuilds and reflashes.

## Security notes

- **API keys are compiled into the firmware.** This is a hobby recipe, not a multi-tenant product — don't flash keys you aren't comfortable with into a device that leaves your bench, and don't commit `provider_config.h` (it's generated; `apply.sh` keeps it out of the repo).
- Each endpoint pins its root CA (`files/*.pem`); the ESP cert bundle alone doesn't carry them (the v0.1 story — see [REFERENCE](docs/REFERENCE.md#security) — now with a second root for Let's Encrypt hosts).
- Voice is recorded only during a turn (button held, or after the wake word until the VAD closes it). With a headless token placeholder the Muse cloud is never contacted.

## Roadmap

- More boards the SDK supports (Waveshare, M5Stack…).
- Full-duplex speech-to-speech models (e.g. QuickSilver's qwen3.8-omni) and local LLMs on your LAN — the brain is just three URLs.
- Custom wake phrases ("Hey Mica") via Espressif's TTS Pipeline V3.
- Echo-proof wake word (speaker audio must never re-trigger the device), and a root-cause fix for the rare DMA event loss behind the stall reboot.

Build details and historical receipts: **[docs/REFERENCE.md](docs/REFERENCE.md)**. For contributing and validation, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

Top three (full checklist in [REFERENCE](docs/REFERENCE.md#troubleshooting)):

- **No reply at all?** Check the console for `brain heard:` (transcription worked) and `TTS ok:` — quiet recordings are normally discarded with `DIDN'T CATCH THAT`. `BRAIN STT FAILED` can also indicate transport or response errors; inspect the HTTP log before changing credentials.
- **`device reports readiness to read but returned no data`** — two processes fighting over `/dev/ttyACM1` (monitor + probe). One at a time.
- **Garbled flash / boot loop** — you used plain `esptool` at high baud. The CH342 bridge drops whole packets; the recipe uses `paced_esptool` at 115200 for a reason.

<p align="center">
  <img width="340" alt="esp32-thinks" src="https://github.com/user-attachments/assets/ee7031ee-0ad3-4559-ad28-30c26c858a9c" />
</p>

# esp32-thinks

<p align="center">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-green"></a>
  <img alt="ESP-IDF v6.0.1" src="https://img.shields.io/badge/ESP--IDF-v6.0.1-blue">
  <img alt="board" src="https://img.shields.io/badge/board-SenseCAP%20Watcher-black">
  <a href="https://github.com/raullenchai/esp32-thinks/pull/2"><img alt="v0.2" src="https://img.shields.io/badge/status-v0.2.1-orange"></a>
</p>

**A multi-model Muse — a personal AI assistant on ESP32, talking out of the box.**

Think of it as a Muse that thinks with **your** models: say **"Hi, ESP"** (or press the knob), ask anything, and it answers **out loud** — streaming sentence-by-sentence while the model is still writing, in English or Chinese, on a $50 gadget with a mic, a speaker and a round display.

No vendor lock on the brain: **speech, transcription and chat are three independent endpoints**, each pointed at any OpenAI-compatible server — one provider for all three, or a different one per task.

- ESP32-S3 · built on Meta's open-source [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) · MIT
- Models: **OpenAI**, **QuickSilver**, or any mix — presets for the common ones, fully custom for the rest

## Why

Cloud assistants rent you a brain: one vendor's models, one vendor's pricing, one vendor's uptime, and your voice on their servers. The gadget hardware is fine — the lock is in the firmware.

esp32-thinks flips that. The device runs **your** stack: pick the cheapest transcription, the smartest chat model, the voice you like — per task, changeable in one config line and a rebuild. The whole pipeline is ~1,600 lines of patch against a stock open-source SDK, so it stays yours to read, tweak, or point at a local server.

## What you get

- **Wake word + button** — say "Hi, ESP" (esp-sr WakeNet10, runs on-chip) or hold the knob; both start a turn. Wake turns end on a voice-activity timer; the button works exactly like before.
- **Bring your own brain** — three independent OpenAI-compatible endpoints (STT / chat / TTS) in one config file. Mix providers freely; presets: `openai`, `quicksilver`, `custom`.
- **Streaming voice replies** — the chat stream is parsed at sentence boundaries (ASCII + CJK); each sentence is synthesized the moment it lands and appended to the audio already playing. First word arrives while the model is still generating.
- **Faster answers** — voice reply starts **≈ 3.4 s after recording**, typed turns finish **2.2–2.6 s**. Connections prepare after Wi-Fi is ready; [v0.2.4 receipts](docs/LATENCY-v0.2.4.md) include first-after-boot and warm samples.
- **Automatic stall recovery** — outstanding I2S or LCD work gets a 20 s deadline, followed by the existing task dump and reboot. Normal sleep and cloud response time do not use that deadline. [Stability checks](docs/STABILITY-v0.2.5.md).
- **Language-aware voice** — Chinese turns can use a different (better) TTS model than English ones, picked automatically from the transcript.
- **Headless provisioning** — put your Wi-Fi in the config; the device self-provisions on boot. No app, no BLE dance, no vendor account needed.
- **Silence-trimmed uploads** — recordings are trimmed to speech before upload, shaving ~0.5 s off transcription.
- **Typed turns speak too** — the serial console path gets the same treatment (useful for testing without talking).

## At a glance

| | |
|---|---|
| Device | Seeed SenseCAP Watcher W1-B (ESP32-S3, 1.45" 412×412 round LCD, ES8311 speaker codec, ES7243E mic, PTT knob) — more boards the SDK supports are candidates |
| Base firmware | [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) @ `812c46f` (2026-10-09) + `patches/muse-brain.patch` (see [what's theirs, what's ours](#built-on-muse-gadget-sdk)) |
| ESP-IDF | v6.0.1 (esp32s3 target) |
| Brain | Any OpenAI-compatible servers: STT (`/audio/transcriptions`), chat (`/chat/completions`, SSE streaming), speech (`/audio/speech`) |
| Presets | `openai` (all three) · `quicksilver` (qwen3.7-flash + whisper-large-v3-turbo + chatterbox/qwen3-tts) · `custom` |
| Wake word | esp-sr WakeNet10 `wn10_hiesp` ("Hi, ESP", on-chip, `model` flash partition) — custom phrases trainable via Espressif's TTS Pipeline V3 |
| Cost | ~fractions of a cent per reply (QuickSilver TTS $1.5–25/1M chars, OpenAI $15/1M) |
| Build host | Linux or macOS with ESP-IDF v6.x |

## Quick start

```bash
# 0) One-time: ESP-IDF v6.x for esp32s3 (docs/REFERENCE.md §Prerequisites)

git clone https://github.com/facebookincubator/muse-gadget-sdk.git
git clone https://github.com/raullenchai/esp32-thinks.git
cd esp32-thinks

# 1) Back up the factory NVS once — your restore path if anything goes sideways
./scripts/backup-nvs.sh ../muse-gadget-sdk /dev/ttyACM1

# 2) Apply the patch + configure your brain (pick a preset)
./apply.sh ../muse-gadget-sdk --preset quicksilver   # or openai / custom

# 3) Build + flash (CH342-safe pacing, ~2 min)
./build-and-flash.sh ../muse-gadget-sdk /dev/ttyACM1
```

With a preset + headless Wi-Fi in step 2, that's the whole setup: unplug, re-plug, and talk — press the knob, or just say "Hi, ESP".

| Command | Does |
|---|---|
| `./scripts/backup-nvs.sh <sdk> [port]` | Dump the factory NVS partition (0x9000, 0x32000) — do this once |
| `./apply.sh <sdk> [--preset ...]` | Copy pinned CAs, apply `patches/muse-brain.patch`, generate `provider_config.h` (asks for keys, Wi-Fi, wake word) |
| `./build-and-flash.sh <sdk> [port]` | `idf.py build` + paced flash (firmware + wake-word model); never interrupt it |
| `python3 scripts/tts_probe.py <sdk> [port] ["question"]` | End-to-end test over the serial console |

## Built on muse-gadget-sdk

Credit where it's due — and clarity about the split:

**Theirs** (upstream, untouched behavior): the device framework, LVGL UI and round-LCD drivers, audio stack (codec, resampler, minimp3), input/console plumbing, OTA and partitioning. This recipe targets the SDK at a pinned commit so patches apply cleanly.

**Ours** (`patches/muse-brain.patch`): the brain session (`muse_chat_session.cpp` — three-endpoint config, SSE sentence streaming, TTS pipeline, keep-alive TLS), the wake-word integration (`muse_voice.c` — direct WakeNet10 on idle chunks, wake→PTT synthesis, VAD end-of-turn, cooldown), the `model` flash partition and the esp-dl kernel fix, plus the tooling (`apply.sh`, `build-and-flash.sh`, NVS backup, probes).

Nothing else from the Muse cloud is required: the vendor agent works as an optional fallback (its token is optional), and with headless provisioning the device never contacts it.

## Configuration

Everything lives in `esp32/components/muse/provider_config.h` (written by `apply.sh`):

| Setting | What |
|---|---|
| `TTS_URL` / `TTS_MODEL` / `TTS_VOICE` | Speech endpoint, model, voice |
| `TTS_MODEL_CJK` | Optional second speech model, auto-selected for Chinese turns |
| `BRAIN_STT_WAV_ADPCM` | `1` uploads IMA ADPCM WAV at about one quarter of PCM size; enabled for the verified QuickSilver preset, `0` for other presets |
| `TTS_API_KEY` / `TTS_CA` | Its key and pinned root (`OPENAI_CA` or `ISRG_CA`) |
| `BRAIN_STT_URL` / `BRAIN_STT_MODEL` | Transcription endpoint (shares the chat key) |
| `BRAIN_CHAT_URL` / `BRAIN_CHAT_KEY` / `BRAIN_MODEL` | Chat endpoint; leave the URL empty to use the Muse cloud agent |
| `BRAIN_CHAT_EXTRA` | Extra JSON merged into the chat body (provider quirks, e.g. DeepSeek's `reasoning.exclude`) |
| `BRAIN_SYSTEM` | The assistant's persona / system prompt |
| `WAKE_WORD` | `1` = "Hi, ESP" wake word + button; `0` = button only |
| `WAKE_VAD_DB` | End-of-turn silence threshold for wake turns (raise toward -35 if it keeps recording after you stop) |
| `DEV_WIFI_SSID` / `DEV_WIFI_PASS` | Headless provisioning; empty = normal BLE setup |

Changed a define? Re-run `./build-and-flash.sh` — it rebuilds and reflashes.

## How a turn flows

1. **Wake or press** → "Hi, ESP" (or the knob) starts recording; the pre-buffer already holds the last second of audio. A wake turn ends after ~1.4 s of silence; a button turn ends on release.
2. **You stop talking** → the recording is trimmed to speech and POSTed as multipart WAV to the transcription endpoint (keep-alive).
3. **The transcript opens an SSE chat stream** → the parser splits the reply at sentence boundaries (`.!?` and CJK `。！？…`), so Chinese works too.
4. **Each sentence POSTs to the speech endpoint** → the MP3 is appended to the audio buffer already being decoded and played. A reserved message slot lets captions and speech interleave with the stream.
5. **Completed short replies reuse the chat connection for speech** when provider origin and root trust match. Replies up to 128 UTF-8 bytes are synthesized together; longer replies stream on a separate speech connection. A HEAD request prepares the first TLS connection after Wi-Fi is ready, and before a voice recording when needed. An idle HEAD probe every 180 seconds checks the same client while Wi-Fi stays up; failure triggers background preparation with bounded backoff. Battery Wi-Fi nap pauses probes. Clients retain keep-alive connections and save TLS 1.3 tickets after reading headers, so an idle-close reconnect can resume the session.

Latency receipts (warm, measured on device, QuickSilver preset): transcription 3.4 s, first spoken word ≈ 5–7 s after you stop; the text caption shows at ~2–3 s. Cold adds ~1.5 s. See [REFERENCE](docs/REFERENCE.md) for the full breakdown and every gotcha.

## Security notes

- **API keys are compiled into the firmware.** This is a hobby recipe, not a multi-tenant product — don't flash keys you aren't comfortable with into a device that leaves your bench, and don't commit `provider_config.h` (it's generated; `apply.sh` keeps it out of the repo).
- Each endpoint pins its root CA (`files/*.pem`); the ESP cert bundle alone doesn't carry them (the v0.1 story — see [REFERENCE](docs/REFERENCE.md#security) — now with a second root for Let's Encrypt hosts).
- Voice is recorded only during a turn (button held, or after the wake word until the VAD closes it). With a headless token placeholder the Muse cloud is never contacted.

## Roadmap

- More boards the SDK supports (Waveshare, M5Stack…).
- Full-duplex speech-to-speech models (e.g. QuickSilver's qwen3.8-omni) and local LLMs on your LAN — the brain is just three URLs.
- Custom wake phrases ("Hey Mica") via Espressif's TTS Pipeline V3.

Full story, exact code paths and every gotcha found the hard way: **[docs/REFERENCE.md](docs/REFERENCE.md)**.

## Troubleshooting

Top three (full checklist in [REFERENCE](docs/REFERENCE.md#troubleshooting)):

- **No reply at all?** Check the console for `brain heard:` (transcription worked) and `TTS ok:` — a `BRAIN STT FAILED` in a quiet room is normal (whisper returns empty); in a real conversation it means the key/URL is wrong.
- **`device reports readiness to read but returned no data`** — two processes fighting over `/dev/ttyACM1` (monitor + probe). One at a time.
- **Garbled flash / boot loop** — you used plain `esptool` at high baud. The CH342 bridge drops whole packets; the recipe uses `paced_esptool` at 115200 for a reason.

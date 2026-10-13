<p align="center">
  <img width="340" alt="esp32-thinks" src="https://github.com/user-attachments/assets/ee7031ee-0ad3-4559-ad28-30c26c858a9c" />
</p>

# esp32-thinks

**A multi-model AI voice assistant on ESP32 — bring your own brain.** Push-to-talk in, spoken replies out — on hardware that already has a mic, a speaker and a round display.

Recipe #1: **Seeed SenseCAP Watcher W1-B** on Meta's open-source [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk).

- ESP32-S3 · muse-gadget-sdk · any OpenAI-compatible brain · MIT
- Works with **OpenAI**, **QuickSilver**, or any mix — speech, transcription and chat are three independent endpoints you point wherever you want.

## Why

Muse gadget firmware is a thin client for a cloud voice agent: your voice goes in, the reply comes back as **captions on the screen — paced by deliberately generated silence**. The SDK's own comment says it plainly: *"Muse doesn't speak gadget replies"* — and documents the `start_tts` hook you're supposed to wire up yourself. Nobody did, so every Muse gadget on the market is silent (unless you count a chirp).

v0.1 wired the hook to OpenAI TTS. **v0.2 goes further: the gadget gets its own brain.** Your voice is transcribed on-device-picked servers, answered by the chat model *you* choose, and spoken back sentence-by-sentence **while that model is still writing the next sentence**. No Muse cloud in the loop (it still works as a fallback if you want it).

## What you get

- **Bring your own brain** — STT, chat and TTS are three independent OpenAI-compatible endpoints, configured in one file. Same provider for all three, or mix (e.g. QuickSilver whisper + deepseek, OpenAI voice).
- **Streaming voice replies** — the chat stream is parsed sentence-by-sentence; each sentence is synthesized the moment it lands and appended to the audio already playing. First word arrives while the model is still generating.
- **Warm connections** — persistent TLS sessions to both servers; a kept-alive turn skips the ~1.5 s handshake.
- **Fast by construction** — warm voice turn ≈ **5–7 s** end-to-end (whisper-turbo ≈ 3.4 s of it), text caption shows at ~2–3 s.
- **Headless provisioning** — put your Wi-Fi in the config and the device self-provisions on boot. No app, no BLE dance, no Muse account needed.
- **Silence-trimmed uploads** — the recording is trimmed to speech before upload, shaving ~0.5 s off transcription.
- **Typed turns speak too** — the serial console path gets the same treatment.
- **Language-aware voice** — Chinese turns can use a different (better) TTS model than English ones, picked automatically from the transcript.

## At a glance

| | |
|---|---|
| Device | Seeed SenseCAP Watcher W1-B (ESP32-S3, 1.45" 412×412 round LCD, ES8311 speaker codec, ES7243E mic, PTT knob) |
| Firmware | [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) @ `812c46f` (2026-10-09) + `patches/muse-brain.patch` |
| ESP-IDF | v6.0.1 (esp32s3 target) |
| Brain | Any OpenAI-compatible servers: STT (`/audio/transcriptions`), chat (`/chat/completions`, SSE streaming), speech (`/audio/speech`) |
| Presets | `openai` (all three) · `quicksilver` (deepseek-v4.1-flash + whisper-large-v3-turbo + chatterbox/qwen3-tts) · `custom` |
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

With a preset + headless Wi-Fi in step 2, that's the whole setup: press the knob, talk, and it answers in its own voice — or just say **"Hi ESP"** (wake word, optional in step 2; the button always works too). No Muse app unless you want the cloud agent as a fallback.

| Command | Does |
|---|---|
| `./scripts/backup-nvs.sh <sdk> [port]` | Dump the factory NVS partition (0x9000, 0x32000) — do this once |
| `./apply.sh <sdk> [--preset ...]` | Copy pinned CAs, apply `patches/muse-brain.patch`, generate `provider_config.h` |
| `./build-and-flash.sh <sdk> [port]` | `idf.py build` + paced flash; never interrupt it |
| `python3 scripts/tts_probe.py <sdk> [port] ["question"]` | End-to-end test over the serial console |

## Configuration

Everything lives in `esp32/components/muse/provider_config.h` (written by `apply.sh`):

| Setting | What |
|---|---|
| `TTS_URL` / `TTS_MODEL` / `TTS_VOICE` | Speech endpoint, model, voice |
| `TTS_MODEL_CJK` | Optional second speech model, auto-selected for Chinese turns |
| `TTS_API_KEY` / `TTS_CA` | Its key and pinned root (`OPENAI_CA` or `ISRG_CA`) |
| `BRAIN_STT_URL` / `BRAIN_STT_MODEL` | Transcription endpoint (shares the chat key) |
| `BRAIN_CHAT_URL` / `BRAIN_CHAT_KEY` / `BRAIN_MODEL` | Chat endpoint; leave the URL empty to use the Muse cloud agent |
| `BRAIN_CHAT_EXTRA` | Extra JSON merged into the chat body (provider quirks, e.g. DeepSeek's `reasoning.exclude`) |
| `DEV_WIFI_SSID` / `DEV_WIFI_PASS` | Headless provisioning; empty = normal BLE setup |

Changed a define? Re-run `./build-and-flash.sh` — it rebuilds and reflashes.

## How the streaming brain works

1. **You release the knob** → the recording is trimmed to speech and POSTed as multipart WAV to the transcription endpoint (keep-alive).
2. **The transcript opens an SSE chat stream** → the parser splits the reply at sentence boundaries (`.!?` and CJK `。！？…`), so Chinese works too.
3. **Each sentence POSTs to the speech endpoint** → the MP3 is appended to the audio buffer already being decoded and played. A reserved message slot lets captions and speech interleave with the stream.
4. **Both TLS connections stay open** for the next turn; the first turn after boot pays one handshake each (~1.5 s), the rest pay none.

Latency receipts (warm, measured on device): transcription 3.4 s, first sentence + first audio ≈ 2–3 s after that. Cold adds ~1.5 s. See [REFERENCE](docs/REFERENCE.md) for the full breakdown and every gotcha (ID3 tags between sentence fetches, the reserved-slot race, silent-room STT behavior).

## Security notes

- **API keys are compiled into the firmware.** This is a hobby recipe, not a multi-tenant product — don't flash keys you aren't comfortable with into a device that leaves your bench, and don't commit `provider_config.h` (it's generated; `apply.sh` keeps it out of the repo).
- Each endpoint pins its root CA (`files/*.pem`); the ESP cert bundle alone doesn't carry them (the v0.1 story — see [REFERENCE](docs/REFERENCE.md#the-three-blockers) — now with a second root for Let's Encrypt hosts).
- Voice is recorded only while the knob is held. With a headless token placeholder the Muse cloud is never contacted.

## Roadmap

- More boards the SDK supports (Waveshare, M5Stack…), full-duplex speech-to-speech models (QuickSilver's qwen3.8-omni), local LLMs. *(Wake word is done — say "Hi ESP".)*

Full story, exact code paths and every gotcha found the hard way: **[docs/REFERENCE.md](docs/REFERENCE.md)**.

## Troubleshooting

Top three (full checklist in [REFERENCE](docs/REFERENCE.md#troubleshooting)):

- **No reply at all?** Check the console for `brain heard:` (transcription worked) and `TTS ok:` — a `BRAIN STT FAILED` on a quiet room is normal (whisper returns empty); in a real conversation it means the key/URL is wrong.
- **`device reports readiness to read but returned no data`** — two processes fighting over `/dev/ttyACM1` (monitor + probe). One at a time.
- **Garbled flash / boot loop** — you used plain `esptool` at high baud. The CH342 bridge drops whole packets; the recipe uses `paced_esptool` at 115200 for a reason.

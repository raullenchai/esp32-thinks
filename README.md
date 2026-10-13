<p align="center">
  <img width="340" alt="esp32-thinks" src="https://github.com/user-attachments/assets/ee7031ee-0ad3-4559-ad28-30c26c858a9c" />
</p>

# esp32-thinks

**The ESP32 gadget that thinks — and answers out loud.** Push-to-talk in, spoken replies out — a wall-mountable AI voice assistant.

Recipe #1: **Seeed SenseCAP Watcher W1-B** on Meta's open-source [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk).

- ESP32-S3 · muse-gadget-sdk · OpenAI TTS · MIT
- The device already has a speaker, a mic and a push-to-talk knob. It just doesn't use them for replies. This fixes that.

## Why

Muse gadget firmware is a thin client for a cloud voice agent: your voice goes in, the reply comes back as **captions on the screen — paced by deliberately generated silence**. The SDK's own comment says it plainly: *"Muse doesn't speak gadget replies"* — and documents the `start_tts` hook you're supposed to wire up yourself. Nobody did, so every Muse gadget on the market is silent (unless you count a chirp).

This recipe wires the hook to OpenAI TTS and fixes the two things that silently stop it from working out of the box. See [The three blockers](#the-three-blockers).

## What you get

- **Spoken replies** — reply text → OpenAI TTS (`tts-1`) → MP3 → decoded and resampled on device → speaker. Captions stay in sync with the audio.
- **Optional Chinese (CJK) captions** on the round display (the SDK ships the font; one line to enable).
- **Typed turns speak too** — the serial console path normally skips TTS entirely; patched.
- **Boot melody** — one second after power-on you know the speaker chain works.

## At a glance

| | |
|---|---|
| Device | Seeed SenseCAP Watcher W1-B (ESP32-S3, 1.45" 412×412 round LCD, ES8311 speaker codec, ES7243E mic, PTT knob) |
| Firmware | [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) @ `812c46f` (2026-10-09) + `patches/muse-tts.patch` |
| ESP-IDF | v6.0.1 (esp32s3 target) |
| Voice | OpenAI `tts-1`, any voice (default `alloy`), 24 kHz MP3 → 16 kHz on device |
| Brain | Your Muse gadget agent ([gadgets.muse.ai](https://gadgets.muse.ai)) — swap it any time; the TTS layer only sees reply text |
| Cost | Muse gadget token: free · OpenAI TTS: ~$15 per 1M chars (fractions of a cent per reply) |
| Build host | Linux or macOS with ESP-IDF v6.x |

## Quick start

```bash
# 0) One-time: ESP-IDF v6.x for esp32s3 (docs/REFERENCE.md §Prerequisites)

git clone https://github.com/facebookincubator/muse-gadget-sdk.git
git clone https://github.com/raullenchai/esp32-thinks.git
cd esp32-speaks

# 1) Back up the factory NVS once — your restore path if anything goes sideways
./scripts/backup-nvs.sh ../muse-gadget-sdk /dev/ttyACM1

# 2) Apply the patch + write your two keys into the tree
./apply.sh ../muse-gadget-sdk

# 3) Build + flash (CH342-safe pacing, ~2 min)
./build-and-flash.sh ../muse-gadget-sdk /dev/ttyACM1
```

Then: connect the Watcher to Wi-Fi (Chrome + the SDK's `tools/muse/ble_setup.html` over WebBLE, or the Muse app), bind it to your Muse account in the Muse app, press the knob, talk. **It answers out loud.**

| Command | Does |
|---|---|
| `./scripts/backup-nvs.sh <sdk> [port]` | Dump the factory NVS partition (0x9000, 0x32000) — do this once |
| `./apply.sh <sdk>` | Copy the pinned CA, apply `patches/muse-tts.patch`, prompt for your keys |
| `./build-and-flash.sh <sdk> [port]` | `idf.py build` + paced flash; never interrupt it |
| `python3 scripts/tts_probe.py <sdk> [port] ["question"]` | End-to-end test over the serial console, dumps TTS logs |

## Configuration

| Setting | Where | Default | Notes |
|---|---|---|---|
| Muse gadget token | `esp32/sdkconfig.token.local` (written by `apply.sh`) | — | From a gadget you create at gadgets.muse.ai |
| OpenAI API key | `esp32/components/muse/muse_chat_session.cpp` → `TTS_API_KEY` (written by `apply.sh`) | — | Compiled into the firmware; see Security in REFERENCE |
| TTS voice | same file → `TTS_VOICE` | `alloy` | `nova`, `shimmer`, `echo`, `onyx`, … all speak Chinese well |
| TTS model | same file → `TTS_MODEL` | `tts-1` | `gpt-4o-mini-tts` also works, promptable voices |
| CJK captions | `sdkconfig.token.local` → `CONFIG_MUSE_CJK_FONT=y` | off | Default renders Latin glyphs; uncomment the line for Chinese captions (+6.8 MB font, ships in the SDK) |

Changed a define? Re-run `./build-and-flash.sh` — it rebuilds and reflashes.

## The three blockers

1. **Silence by design.** `muse_chat_session.cpp` generates silence to pace captions ("silence in place of speech paces the captions… Muse doesn't speak gadget replies"). The fix: implement the documented `start_tts` hook — POST the reply text to OpenAI `/v1/audio/speech`, stream the MP3 into the SDK's own buffer, let its minimp3 decoder + automatic resampler handle the rest.
2. **Typed turns skip the TTS queue.** `message_done()` returns before setting `TTS_QUEUED` for console turns — captions only, by design. The patch makes the final text authoritative and queues TTS for both paths.
3. **`api.openai.com` has no root in the ESP cert bundle** (it chains to Google Trust Services **GTS Root R4**, which the bundle doesn't carry → `No matching trusted root certificate found`). The patch pins the self-signed GTS Root R4 (valid to 2036) via `EMBED_TXTFILES` + `cert_pem`.

Full story, exact code paths and every gotcha found the hard way: **[docs/REFERENCE.md](docs/REFERENCE.md)**.

## Troubleshooting

Top three (full checklist in [REFERENCE](docs/REFERENCE.md#troubleshooting)):

- **Still silent?** Check the console for `TTS ok: N audio bytes buffered` — if it says `TTS failed`, read the lines above it (cert error → you skipped `apply.sh`; 401 → bad key).
- **`device reports readiness to read but returned no data`** — two processes fighting over `/dev/ttyACM1` (monitor + probe). One at a time.
- **Garbled flash / boot loop** — you used plain `esptool` at high baud. The CH342 bridge drops whole packets; the recipe uses `paced_esptool` at 115200 for a reason.

## Swapping the brain

The TTS layer sits between the agent's reply text and the speaker — it doesn't know or care which agent wrote the text. Any Muse gadget agent works today (point your gadget at any backend the hatch supports). Next recipes on the todo: GLM/Claude/local-LLM backends, other ESP32-S3 boards the SDK supports (Waveshare, M5Stack…), wake word.

## Security notes

- Your OpenAI key and Muse token are **compiled into the firmware**. Fine on a shelf at home; don't gift the device with your keys inside. `scripts/backup-nvs.sh` + a factory restore wipe them.
- The pinned CA (`files/openai_root_ca.pem`) is a public Google Trust Services root — nothing secret in it.

## License & credits

Recipe and patches: **MIT**. Underneath it all: [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) (Apache-2.0, Meta), Seeed's SenseCAP Watcher hardware, OpenAI's TTS API, and the minimp3 decoder. The `start_tts` hook is documented in the SDK itself — this recipe is mostly doing what the comment says.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

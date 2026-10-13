# Reference

Everything this recipe learned the hard way. Tested with **muse-gadget-sdk @ `812c46f`** (2026-10-09) and **ESP-IDF v6.0.1** on an esp32s3 target. Newer revisions likely work — run `git rev-parse --short HEAD` in the SDK to compare.

## What the patch changes

Three files in `esp32/components/muse/`, all in the SDK's own extension points:

- **`muse_chat_session.cpp`**
  - `tts_fetch_openai()` + `tts_http_event()`: POSTs the reply text to `https://api.openai.com/v1/audio/speech` (`response_format: mp3`), streaming the response into the SDK's existing `tts_data()` buffer (512 KB in PSRAM) and calling `decode()` per chunk — the device speaks while the MP3 is still downloading. The fetch logs its duration (`TTS ok: N bytes in X ms`).
  - `start_tts()`: for a `TTS_QUEUED` message with text, sets up the documented TTS state (`mp3dec_init`, `silent = false`, …) and calls the fetch. On failure it falls back to the stock caption-paced silence, so a dead API key degrades to captions instead of a hung turn.
  - `message_done()`: the typed-turn branch (`s_turn.text`) returned before ever setting `TTS_QUEUED` — captions only by design. The patch makes the final text authoritative (copying it over partial accumulated text when they disagree) and queues TTS for both typed and voice turns.
  - `#define TTS_API_KEY / TTS_MODEL / TTS_VOICE` — your knobs.
- **`CMakeLists.txt`** — `EMBED_TXTFILES "openai_root_ca.pem"` (the pinned CA).
- **`muse_voice.c`** — a boot melody after `muse_audio_init()`: a synthesized chirp chain, so speaker-chain problems are obvious one second after power-on. Plus a reply-audio level log.

The decode path needs no changes: `decode()` reads the MP3 frame header, sees 24 kHz, and `resampler_init(&s_turn.down, info.hz, MIC_RATE)` handles the 24→16 kHz conversion. Captions follow the played frames automatically.

## Prerequisites

- **Build host**: Linux or macOS with ESP-IDF **v6.x** for esp32s3. The conventional layout is `~/esp/esp-idf-v6`; set `IDF_PATH` if yours differs. (During install, run `install.sh esp32s3`; if the Python installer stalls, `bash install.sh esp32s3`.)
- **Hardware**: Seeed SenseCAP Watcher W1-B + a USB-C data cable. It enumerates as a CH342 dual serial: `ttyACM0` is the Himax camera core, **`ttyACM1` is the ESP32-S3** (the one for flashing and the console). On macOS pick the matching `/dev/tty.usbmodem*`.
- **Muse gadget token**: create a gadget at [gadgets.muse.ai](https://gadgets.muse.ai) (free), copy the `mgst_…` token.
- **OpenAI API key**: needs `audio/speech` access. `tts-1` is ~$15 per 1M characters — a typical reply is 50–200 chars, so daily use costs fractions of a cent.

## Before the first flash: back up the factory NVS

The device ships with an NVS partition that holds factory identity and settings. One command, once:

```bash
./scripts/backup-nvs.sh ../muse-gadget-sdk /dev/ttyACM1
```

It reads `0x9000`, length `0x32000` (204800 bytes) via the paced tool and saves `nvsfactory-backup-YYYYMMDD.bin`. **Copy that file off the machine.** If a flash ever goes sideways, `write-flash 0x9000 <backup>` is the recovery path.

## Build & flash

`./build-and-flash.sh` runs the equivalent of:

```bash
cd muse-gadget-sdk/esp32
. ~/esp/esp-idf-v6/export.sh
idf.py -B build-muse-sensecap-watcher -DIDF_TARGET=esp32s3 \
    -DSDKCONFIG=build-muse-sensecap-watcher/sdkconfig \
    -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;devices/sdkconfig.muse;devices/sdkconfig.muse-sensecap-watcher;sdkconfig.token.local" build
cd build-muse-sensecap-watcher
python3 ../tools/muse/paced_esptool.py --chip esp32s3 -p /dev/ttyACM1 -b 115200 \
    --before default-reset --after hard-reset write-flash "@flash_args"
```

Two non-negotiables:

- **Use `paced_esptool`, not plain `esptool`.** The CH342 USB bridge drops whole packets at high baud; the paced tool writes at 115200 with inter-chunk pacing. Plain high-baud flashes come out silently corrupt.
- **Never interrupt a flash.** Half-written partitions are exactly what the NVS backup is for. The last line should be `Hard resetting via RTS pin...` and you'll hear the boot melody.

Changed `TTS_VOICE`/`TTS_MODEL`/the token? Just re-run `build-and-flash.sh` — the incremental build is fast. Changed anything in `SDKCONFIG_DEFAULTS` (e.g. the CJK font)? Delete `build-muse-sensecap-watcher/sdkconfig` first so it regenerates.

## Provisioning & pairing

1. Wi-Fi: serve `muse-gadget-sdk/esp32/tools/muse/ble_setup.html` over localhost (`python3 -m http.server 8000`), open it in Chrome, and pair over WebBLE to the device (`MuseGadget-XXXXXX`). It hands the credentials to the board.
2. Account: the Muse app (phone) binds the device to your Muse account — the gadget token in `sdkconfig.token.local` is what your firmware presents.
3. Verify: `python3 muse-gadget-sdk/esp32/tools/muse/chat.py --status` → expect `state: 'Connected'`, `link: Online`, and your SSID.

By default this is a **push-to-talk** device — press the knob, talk, release, intercom style. `apply.sh` can also enable the **"Hi ESP" voice wake word** (see below); button and wake word then both start a turn.

## How the spoken reply flows

```
PTT press → mic frames (16 kHz) → hatch upload (STT in the cloud)
  → agent reply arrives on the /chat/subscribe stream as message events
  → text accumulates per message; on message_done the message is TTS_QUEUED
  → start_tts() sets up mp3dec + pcm accounting, silent = false
  → tts_fetch_openai() POSTs the text, streams MP3 chunks into tts_data()
  → decode() minimp3-decodes, resamples 24k→16k, feeds the speaker stream buffer
  → captions follow the played frames; turn ends when drained
```

Failure modes are graceful: a non-200 or a dropped connection resets the state and falls back to caption-paced silence — the turn still ends, the reply still shows.

## Changing voice / model

Edit `TTS_VOICE` / `TTS_MODEL` in `muse_chat_session.cpp`, re-run `build-and-flash.sh` — or set the voice once at `apply.sh` time (it prompts). Voices that read Chinese well: `alloy`, `nova`, `shimmer`, `echo`, `onyx` (see OpenAI's voice list). `gpt-4o-mini-tts` also works and accepts style instructions — wire the prompt in yourself if you want a persona.

**Where the latency goes** (measured on a Watcher over 2.4 GHz Wi-Fi): Muse's cloud STT + LLM take ~5–8 s and are outside this recipe's control (swap the agent/backend for real gains); the TTS hop adds ~1–2 s to first sound with streaming enabled — TLS handshake to `api.openai.com` dominates it. Sentence-level TTS (speaking while the LLM is still writing) is a possible future cut, but replies are usually 1–3 sentences and the win is small.

## Swapping the brain

Nothing in the TTS path knows which agent produced the text — it fires on `TTS_QUEUED`. Point your Muse gadget at any backend the hatch supports and it still speaks. The natural next steps (not in this recipe yet): a self-hosted agent behind the SDK's home-network tunnel, local TTS on a box in the same LAN, wake word, other boards (the SDK supports Waveshare, M5Stack and more — the patch is in the board-agnostic `muse` component).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No matching trusted root certificate found` → `TTS failed` | You skipped `apply.sh` (no pinned CA) or applied to a different tree | Re-run `apply.sh`, rebuild |
| `TTS failed: 0 audio bytes buffered`, no other error | Bad key (401), no route to `api.openai.com`, or the reply text was empty | Check the key; `tts_probe.py` prints the console log |
| **No sound at all, but captions show** | Speaker off / volume 0 in device settings; or TTS failed silently (see above) | Settings → Speaker on, volume up; watch the console during a turn |
| `device reports readiness to read but returned no data` | Two processes on `/dev/ttyACM1` (monitor + probe/chat) | One serial client at a time |
| `turn failed: INTERRUPTED` | The knob was pressed mid-turn (it's the interrupt key) | Hands off the knob while testing |
| `wifi:bcn_timeout` → `LOST CONNECTION TO MUSE` | Router beacon loss, not the firmware | Auto-reconnects in seconds; retry |
| Garbled output / boot loop after flash | Flashed with plain esptool at high baud | Use `build-and-flash.sh` (paced, 115200); worst case restore NVS |
| Chinese renders as boxes (□□□) | `CONFIG_MUSE_CJK_FONT` not set — it's opt-in in this recipe (default: Latin glyphs) | Put it in `sdkconfig.token.local`, delete the build's `sdkconfig`, rebuild |
| `The board didn't take the message` on console | Board asleep or old firmware on the port | Re-plug; check `chat.py --status` |

The console is your friend for all of these: `python3 muse-gadget-sdk/esp32/tools/muse/monitor.py /dev/ttyACM1 30` streams the log. Lines that matter for TTS: `speaking message …`, `TTS ok: N audio bytes buffered`, `reply audio: 24000 Hz, 1 ch, … kbps`.

## Security

- **Your OpenAI key is compiled into the firmware** (and the Muse token into NVS). On a shelf at home that's fine — the device is not exposed to the internet beyond its own outbound connections. Don't gift or re-sell the device with your keys inside: `write-flash 0x9000 <factory-nvs-backup>` restores the factory partition, and a fresh `idf.py erase-flash` clears the app image.
- The pinned CA is a public Google Trust Services root (GTS Root R4, self-signed, valid to 2036). Nothing secret in it; it's pinned because the ESP x509 bundle doesn't carry it.
- The `tts_probe.py` traffic is device → `api.openai.com` over TLS with that pinned root, plus the SDK's own noise-encrypted channel to the Muse hatch.

## Hardware notes

- Wall mount is just a 5 V USB power source; everything else (Wi-Fi, mic, speaker) is wireless/ onboard. The USB-C data line is only needed for flashing and the console.
- The camera core (`ttyACM0`) is separate; this recipe never touches it.
- Speaker chain: ES8311 codec → amplifier (expander-gated at boot) → the little round speaker. The v0.1 boot melody is gone in v0.2.0 (it's a work device; the first spoken reply is the speaker test now).

---

# The brain (v0.2.0)

## Architecture

Three independent OpenAI-compatible endpoints, configured in `provider_config.h` (generated by `apply.sh`):

| Endpoint | Firmware entry | Notes |
|---|---|---|
| Speech | `TTS_URL` / `TTS_MODEL` / `TTS_VOICE` (+ `TTS_MODEL_CJK`) | Text → MP3. `TTS_MODEL_CJK` is auto-selected when a turn's text contains CJK ideographs (U+4E00–9FFF). |
| Transcription | `BRAIN_STT_URL` / `BRAIN_STT_MODEL` | Multipart WAV POST; shares the chat key. |
| Chat | `BRAIN_CHAT_URL` / `BRAIN_MODEL` (+ `BRAIN_CHAT_EXTRA`) | SSE streaming; empty URL falls back to the stock Muse cloud agent. |

Each endpoint pins its own root CA (`OPENAI_CA` = GTS Root R4 for api.openai.com, `ISRG_CA` = ISRG Root X1 for Let's Encrypt hosts). `provider_config.h` also carries `DEV_WIFI_SSID`/`DEV_WIFI_PASS` for headless provisioning: on boot, if the board has no saved Wi-Fi, it writes the credentials and a placeholder hatch token — no Muse app, no BLE pairing, no account.

## Turn pipeline

```
PTT release → record finalized (min 0.3 s, else "DIDN'T CATCH THAT")
  → wav_trim_silence(): the PTT note is mostly air at the edges; trim to speech ±200 ms
  → multipart POST to the transcription endpoint (keep-alive session A)
  → transcript opens an SSE chat stream (session A) and reserves the message slot up front
  → the stream parser splits at sentence boundaries: .!? \n and CJK 。！？…
  → every sentence POSTs to the speech endpoint (session B, kept open during the stream)
    → MP3 appended to the turn's audio buffer; responses 2+ have their ID3 tag stripped
    → decode() runs from the HTTP event handler: speaking starts while the LLM writes the next sentence
  → no audio by turn end (e.g. an empty or all-whitespace reply) → captions only
  → turn ends when all messages are done and settled 3 s (or the cap: 180 s voice / 15 min typed)
```

Two sessions, not one: the speech connection must stay open while the chat stream is still being read, so they cannot share. Both persist across turns; a failed request `cleanup()`s only its own client.

## Latency receipts

Measured on a Watcher over 2.4 GHz Wi-Fi, QuickSilver preset (deepseek-v4.1-flash with reasoning excluded, whisper-large-v3-turbo, chatterbox-turbo):

| Path | Cold | Warm |
|---|---|---|
| Transcription (release → transcript) | 5.5 s | **3.4 s** |
| Typed turn → first audio (chat + speech + decode) | ~10 s | **~5 s** |
| Full voice turn → first spoken word | ~8 s | **~6–7 s** |
| Text caption on screen | — | ~2–3 s after release |

Server-side floors, measured from a laptop (Chinese prompt, streaming): deepseek-v4.1-flash with `reasoning.exclude` 1.3 s to first sentence; chatterbox-turbo ~1.5 s TTFB; qwen3-tts ~2.9–3.9 s (why the CJK split exists); whisper-large-v3-turbo 1.2 s for a 3 s clip. Claude Opus-class models spend ~10 s before their first sentence — a flagship is the wrong shape for a voice loop.

## Gotchas found the hard way

- **Reserved slot race**: `tts_data → decode` fires from an HTTP event handler *while the chat stream is mid-flight*, and the decoder indexes `msgs[tts_msg]`. The slot is allocated before the stream opens, not after the reply is known.
- **ID3 between sentences**: each speech response starts its own MP3; an ID3 tag landing mid-decode desyncs minimp3. Response 2+ get the tag stripped by parsing the size header.
- **1-character replies**: the sentence gate used to require ≥2 buffered chars, so "4" never got speech and fell into the slower end-of-turn path. Gate is ≥1 now, plus a blank guard so `"\n\n"` never becomes a speech round trip.
- **Typed turns stall on long replies**: the voice path drains the audio buffer in its own loop; the console path didn't, so a long reply filled the stream buffer and the decoder waited forever. Both drain now.
- **DeepSeek thinks**: its stream starts with `reasoning_content` deltas that the parser must ignore — and, worse, wait for. `BRAIN_CHAT_EXTRA {"reasoning":{"exclude":true}}` turns the thinking phase off server-side.
- **Silence ≠ silence**: whisper on a quiet room returns `""` or `" ."`, which the brain reports as `BRAIN STT FAILED` — expected, not a bug.
- **Placeholder token**: with headless provisioning the gadget's token (`brain-local`) is rejected by the Muse cloud (HTTP 401 in the log). Harmless: the brain never contacts it, and the stock agent is only a fallback you opted out of.

## Wake word ("Hi ESP")

Implemented (v0.2.1): `apply.sh` asks *"Enable the 'Hi ESP' voice wake word?"* — say **"Hi ESP"** or hold the knob, both start a turn. The knob path is untouched; detection merely synthesizes a `MUSE_PTT_DOWN` into the same input queue, so recording, VAD end-of-speech and the reply flow are exactly the button's.

How it fits together:

- **esp-sr 2.6.0 + esp-dl kernels**: `idf_component.yml` adds esp-sr; `wn10_hiesp` ("Hi, ESP", 984 KB) is enabled in `sdkconfig.muse` and packed into `srmodels.bin` by `idf.py` (needs `MODEL_IN_FLASH`). `partitions_muse.csv` gains a `model` partition at 0x822000 — the Watcher's 32 MB flash has room; **flash `srmodels.bin` there once** (`build-and-flash.sh` does; it must be a separate esptool command — combined with `@flash_args` esptool reports a false overlap at 0x822000).
- **Direct WakeNet, no AFE**: the AFE audio-front-end's static buffers (~34 KB internal BSS) OOM the codec on this board — `muse_voice.c` calls WakeNet's `create/detect` directly on the 20 ms idle chunks (512-frame aggregation), skipping AFE entirely.
- **A missing kernel gotcha**: esp-sr's `compile_req` strips esp-dl to the kernels *its own* models use — the `wn10_hiesp` 1x1 W8A16 conv **without bias** (`0x0202`) isn't among them, and every `detect()` fails with `no Conv kernel for packed key 0x0202`. `dl-extra-req.yml` re-adds it via esp-dl's multi-component req union.
- **Self-test**: serial `k` plays the embedded wake phrase and records **in lockstep** (full duplex) — a blocking playback would miss its own wake word; `muse_audio` loopback (`l`) confirms both mic channels.
- End-of-turn for wake-initiated recording is the energy VAD (`WAKE_VAD_DB`, -45 dBFS, 1.4 s of quiet); a 4 s cooldown after each turn keeps the reply's tail from re-waking the device. Raise `WAKE_VAD_DB` toward -35 if it keeps recording after you stop.
- Custom phrase ("Hey Mica"): Espressif's TTS Pipeline V3 trains WakeNet models from TTS samples (esp-sr issue #88) — drop the trained model into the `model` partition. Prebuilt models ship for "Hi ESP", "你好小智", Alexa and others.

<p align="center">
  <img width="340" alt="esp32-thinks" src="https://github.com/user-attachments/assets/ee7031ee-0ad3-4559-ad28-30c26c858a9c" />
</p>

# esp32-thinks

**The ESP32 gadget that thinks — and answers out loud.** Push-to-talk in, spoken replies out — a wall-mountable AI voice assistant.

Recipe #1: **Seeed SenseCAP Watcher W1-B** on Meta's open-source [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk).

- ESP32-S3 · muse-gadget-sdk · QuickSilver Pro / OpenAI TTS · MIT
- The device already has a speaker, a mic and a push-to-talk knob. It just doesn't use them for replies. This fixes that.

## Why

Muse gadget firmware is a thin client for a cloud voice agent: your voice goes in, the reply comes back as **captions on the screen — paced by deliberately generated silence**. The SDK's own comment says it plainly: *"Muse doesn't speak gadget replies"* — and documents the `start_tts` hook you're supposed to wire up yourself. Nobody did, so every Muse gadget on the market is silent (unless you count a chirp).

This recipe wires the hook to QuickSilver Pro TTS by default (OpenAI is an option) and fixes the two things that silently stop it from working out of the box. See [The three blockers](#the-three-blockers).

## What you get

- **Spoken replies** — reply text → QuickSilver Pro (`chatterbox-turbo` for English, `qwen3-tts` for Chinese / mixed) or OpenAI → MP3 → decoded and resampled on device → speaker. Captions stay in sync with the audio.
- **Optional Chinese (CJK) captions** on the round display (the SDK ships the font; one line to enable).
- **Typed turns speak too** — the serial console path normally skips TTS entirely; patched.
- **Boot melody** — one second after power-on you know the speaker chain works.

## At a glance

| | |
|---|---|
| Device | Seeed SenseCAP Watcher W1-B (ESP32-S3, 1.45" 412×412 round LCD, ES8311 speaker codec, ES7243E mic, PTT knob) |
| Firmware | [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) @ `812c46f` (2026-10-09) + `patches/muse-tts.patch` |
| ESP-IDF | v6.0.1 (esp32s3 target) |
| Voice | QuickSilver Pro `chatterbox-turbo` by default; Chinese / mixed via `qwen3-tts`, OpenAI optional; 24 kHz MP3 → 16 kHz on device |
| Brain | Your Muse gadget agent ([gadgets.muse.ai](https://gadgets.muse.ai)) — swap it any time; the TTS layer only sees reply text |
| Cost | Muse gadget token: free · English TTS: QuickSilver Pro $1.50 vs OpenAI `tts-1` $15 per 1M characters — one tenth the price (10× cheaper); Chinese / mixed `qwen3-tts`: $25 |
| Build host | Linux or macOS with ESP-IDF v6.x |

## Choosing TTS

**English: $1.50 vs $15 per 1M characters.** QuickSilver Pro's `chatterbox-turbo` is English only and costs one tenth of OpenAI `tts-1` (10× cheaper). That's the default when you run `apply.sh`.

**Chinese / mixed: $25 vs $15 per 1M characters.** QuickSilver Pro's `qwen3-tts` costs more than OpenAI `tts-1`. Pick it for Chinese, English or mixed replies with one voice; stay on OpenAI if the lower Chinese price or choosing a voice matters to you. QuickSilver Pro also accepts `tts-1` as an alias of `qwen3-tts`, billed at $25 — it won't select the English-only model by accident. Input is limited to **4,000 characters per request** on QuickSilver Pro.

First byte for a sentence, **measured 2026-10-13 from a server, not on the device**: `chatterbox-turbo` about **0.8–2 s**, `qwen3-tts` about **1.3–3.4 s**. Device time also includes Wi-Fi, TLS and the Muse turn; these aren't knob-to-speaker timings. QuickSilver Pro streams MP3 by default (24 kHz mono, 64 kbps), the same container as `tts-1`; the on-device minimp3 + resampler path stays the same.

Get a QuickSilver Pro key at [quicksilverpro.io](https://quicksilverpro.io): sign up, then copy the key from the dashboard. Free trial credit needs no card and includes the speech models. Already have an OpenAI key? Choose `openai` at the provider prompt.

**The root CA must match the host.** QuickSilver Pro uses Let's Encrypt **ISRG Root X1**; OpenAI uses **GTS Root R4**. Keeping the OpenAI root while changing the URL gives `No matching trusted root certificate found` → `TTS failed`. `apply.sh` copies the right root to `tts_root_ca.pem` for you.

## Quick start

```bash
# 0) One-time: ESP-IDF v6.x for esp32s3 (docs/REFERENCE.md §Prerequisites)

git clone https://github.com/facebookincubator/muse-gadget-sdk.git
git clone https://github.com/raullenchai/esp32-thinks.git
cd esp32-thinks

# 1) Back up the factory NVS once — your restore path if anything goes sideways
./scripts/backup-nvs.sh ../muse-gadget-sdk /dev/ttyACM1

# 2) Choose TTS (default: quicksilver → en), apply the patch + write your two keys
./apply.sh ../muse-gadget-sdk

# Check the TTS key + TLS from your build host before flashing (uses API credit)
python3 scripts/tts_probe.py ../muse-gadget-sdk --preflight

# 3) Build + flash (CH342-safe pacing, ~2 min)
./build-and-flash.sh ../muse-gadget-sdk /dev/ttyACM1
```

Then: connect the Watcher to Wi-Fi (Chrome + the SDK's `tools/muse/ble_setup.html` over WebBLE, or the Muse app), bind it to your Muse account in the Muse app, press the knob, talk. **It answers out loud.**

| Command | Does |
|---|---|
| `./scripts/backup-nvs.sh <sdk> [port]` | Dump the factory NVS partition (0x9000, 0x32000) — do this once |
| `./apply.sh <sdk>` | Choose provider / model, copy the matching CA, apply `patches/muse-tts.patch`, prompt for your keys; safe to re-run |
| `python3 scripts/tts_probe.py <sdk> --preflight ["text"]` | Check the configured TTS key + connectivity + pinned CA from the build host before flashing; uses API credit |
| `./build-and-flash.sh <sdk> [port]` | `idf.py build` + paced flash; never interrupt it |
| `python3 scripts/tts_probe.py <sdk> [port] ["question"]` | End-to-end test over the serial console, dumps TTS logs |

## Configuration

| Setting | Where | Default | Notes |
|---|---|---|---|
| Muse gadget token | `esp32/sdkconfig.token.local` (written by `apply.sh`) | — | From a gadget you create at gadgets.muse.ai |
| TTS provider | `apply.sh` → `TTS_URL` + `tts_root_ca.pem` in `esp32/components/muse/` | `quicksilver` | `openai` remains an option; re-run `apply.sh` to switch URL, key and CA together |
| TTS API key | `esp32/components/muse/muse_chat_session.cpp` → `TTS_API_KEY` (written by `apply.sh`) | — | From the chosen provider; compiled into the firmware; see Security in REFERENCE |
| Reply language / model | same file → `TTS_MODEL` | `en` → `chatterbox-turbo` | QuickSilver: `zh` → `qwen3-tts` for Chinese / mixed; OpenAI prompts for model (default `tts-1`) |
| TTS voice | same file → `TTS_VOICE` | `alloy` | `chatterbox-turbo` accepts any value, including OpenAI names; `qwen3-tts` (also alias `tts-1` on QuickSilver) has one voice and ignores this field; OpenAI prompts for voice |
| CJK captions | `sdkconfig.token.local` → `CONFIG_MUSE_CJK_FONT=y` | off | Default renders Latin glyphs; uncomment the line for Chinese captions (+6.8 MB font, ships in the SDK) |

Changed a define? Re-run `./build-and-flash.sh` — it rebuilds and reflashes.

## The three blockers

1. **Silence by design.** `muse_chat_session.cpp` generates silence to pace captions ("silence in place of speech paces the captions… Muse doesn't speak gadget replies"). The fix: implement the documented `start_tts` hook — POST the reply text to the chosen provider's `/v1/audio/speech`, stream the MP3 into the SDK's own buffer, let its minimp3 decoder + automatic resampler handle the rest.
2. **Typed turns skip the TTS queue.** `message_done()` returns before setting `TTS_QUEUED` for console turns — captions only, by design. The patch makes the final text authoritative and queues TTS for both paths.
3. **TLS needs the right root.** `api.openai.com` chains to Google Trust Services **GTS Root R4**, which the ESP bundle doesn't carry; that root will NOT validate `api.quicksilverpro.io`. QuickSilver Pro chains to Let's Encrypt **ISRG Root X1** (expires 2035-06-04). The patch embeds `tts_root_ca.pem` via `EMBED_TXTFILES` + `cert_pem`; `apply.sh` copies the chosen provider's root into it.

Full story, exact code paths and every gotcha found the hard way: **[docs/REFERENCE.md](docs/REFERENCE.md)**.

## Troubleshooting

Top four (full checklist in [REFERENCE](docs/REFERENCE.md#troubleshooting)):

| Symptom | Cause | Fix |
|---|---|---|
| `No matching trusted root certificate found` → `TTS failed` | Missing CA or wrong provider's root (GTS Root R4 won't validate QuickSilver Pro) | Re-run `apply.sh` for the chosen provider, rebuild; QuickSilver needs ISRG Root X1 |
| Still silent / `TTS failed` | Check the lines above it; 401 means a bad key | Run `tts_probe.py <sdk> --preflight`, then watch for `TTS ok: N bytes in X ms` on the device |
| `device reports readiness to read but returned no data` | Monitor + probe fighting over `/dev/ttyACM1` | One serial client at a time |
| Garbled flash / boot loop | Plain esptool at high baud drops packets on the CH342 bridge | Use `build-and-flash.sh` (paced, 115200) |

## Swapping the brain

The TTS layer sits between the agent's reply text and the speaker — it doesn't know or care which agent wrote the text. Any Muse gadget agent works today (point your gadget at any backend the hatch supports). Next recipes on the todo: GLM/Claude/local-LLM backends, other ESP32-S3 boards the SDK supports (Waveshare, M5Stack…), wake word.

A possible follow-up is QuickSilver Pro STT (`POST /v1/audio/transcriptions`, `qwen3-asr`, `whisper-large-v3-turbo` or alias `whisper-1`, from $0.0003 per minute); this recipe still uses the Muse hatch for cloud STT.

## Security notes

- Your TTS key is **compiled into the firmware**, and the Muse token goes into NVS. Fine on a shelf at home; don't gift the device with your keys inside. Restore the factory NVS and erase the app image first (see Security in REFERENCE).
- The pinned CAs (`files/isrg-root-x1.pem`, `files/openai_root_ca.pem`) are public roots — nothing secret in them.

## License & credits

Recipe and patches: **MIT**. Underneath it all: [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk) (Apache-2.0, Meta), Seeed's SenseCAP Watcher hardware, QuickSilver Pro and OpenAI's TTS APIs, and the minimp3 decoder. The `start_tts` hook is documented in the SDK itself — this recipe is mostly doing what the comment says.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

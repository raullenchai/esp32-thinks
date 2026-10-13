# Changelog

## v0.2.1 — 2026-10-13 — wake word: "Hi, ESP"

The gadget now has both ears: **say "Hi, ESP" or press the knob** — both start a turn. Detection is esp-sr WakeNet10 `wn10_hiesp` running on-chip (direct WakeNet, no AFE); on detect it synthesizes a `MUSE_PTT_DOWN` into the same input queue, so recording, VAD end-of-turn and the reply flow are exactly the button's.

- **`model` flash partition** (`partitions_muse.csv`, 0x822000) holds the wake model (`srmodels.bin`); `build-and-flash.sh` flashes it only when `@flash_args` lacks it — appending it by hand makes esptool report a false overlap.
- **esp-dl kernel fix** — esp-sr's own `compile_req` strips the W8A16 **no-bias** 1×1 conv (`0x0202`) that `wn10_hiesp` needs, so every `detect()` failed with `no Conv kernel for packed key`; `dl-extra-req.yml` re-adds it via esp-dl's multi-component req union.
- **Why no AFE** — the audio front end's static buffers (~34 KB internal BSS) OOM the codec on this board; `muse_voice.c` feeds idle 20 ms chunks (512-frame aggregation) straight to `create/detect`.
- **Self-tests** — serial `k` plays the embedded wake phrase and records **in lockstep** (full duplex — a blocking playback would miss its own wake word); `l` runs the mic loopback probe (both channels alive; R is 15–20 dB less sensitive).
- **Post-turn cooldown** (4 s, armed after `record()` returns — the reply plays inside it) keeps the reply's tail from re-waking the device; `WAKE_VAD_DB` (-45 dBFS) tunes wake-turn end-of-speech.
- `apply.sh` asks to enable the wake word (default on) and writes `WAKE_WORD`/`WAKE_VAD_DB` into `provider_config.h`. AFE is skipped, so this works on the Watcher's tight internal-heap budget (~7 KB free at boot).
- Verified on-device: wake detect during the device's own TTS playback → record → STT → brain → spoken reply, end to end. Custom phrases ("Hey Mica") remain a TTS Pipeline V3 exercise (see REFERENCE).

## v0.2.0 — 2026-10-13 — bring your own brain

The gadget no longer needs the Muse cloud to hold a conversation. **STT + chat + TTS are three independent OpenAI-compatible endpoints** you configure in `provider_config.h` — same provider for all three, or mix and match. Presets: `openai`, `quicksilver`, `custom`.

- **Device-side brain** — voice notes are transcribed server-side, answered by the chat model you pick, and spoken via the speech endpoint. The Muse cloud agent still works as a fallback (its token is now optional).
- **Streaming sentence TTS** — the chat SSE stream is parsed at sentence boundaries (ASCII + CJK); each sentence is synthesized while the model writes the next one, into the audio buffer already playing. A reserved message slot keeps captions in sync mid-stream.
- **TLS keep-alive** — two persistent sessions (one for transcription+chat, one for speech, which must stay open while the chat stream is live). Warm turns skip the ~1.5 s handshake; a failed request drops only its own connection.
- **Language-aware voice** — `TTS_MODEL_CJK` picks a different speech model for Chinese turns (QuickSilver: chatterbox-turbo for English speed, qwen3-tts for Chinese quality).
- **Headless provisioning** — set `DEV_WIFI_SSID`/`DEV_WIFI_PASS` and the board self-provisions on boot (credentials + a placeholder token), no BLE phone flow required. The gadget works with **no Muse account at all**.
- **Faster STT** — recordings are trimmed to speech before upload (the PTT note is mostly air at the edges); warm transcription ≈ 3.4 s on device.
- **Fixes**: 1-character replies ("4") now get speech; whitespace-only sentences skip the speech round trip; `\r` is stripped from TTS input; a dropped connection no longer fails an in-flight brain turn; long replies on typed turns no longer stall the decoder (the console path now drains the audio buffer like voice turns do).
- `apply.sh` now generates `provider_config.h` (presets or fully custom) and asks for keys per endpoint; the Muse token and the boot melody are optional. `patches/muse-brain.patch` replaces `muse-tts.patch` (it includes the v0.1 TTS hook).
- Latency receipts (warm, QuickSilver preset, measured on device): transcription 3.4 s, first spoken word ≈ 5–7 s after release; the text caption shows at ~2–3 s.

## v0.1.1 — 2026-10-12

- **Stream the TTS audio while downloading** — `decode()` now runs from the HTTP event handler, so the device starts speaking as soon as the first MP3 frames land instead of after the full download (~1–2 s earlier first sound on Wi-Fi).
- `apply.sh` now asks for a TTS voice (default `alloy`); the fetch logs its duration (`TTS ok: N bytes in X ms`) for receipts.

## v0.1.0 — 2026-10-12

Initial recipe: **Seeed SenseCAP Watcher W1-B on muse-gadget-sdk @ `812c46f` (2026-10-09), ESP-IDF v6.0.1.**

- Spoken replies via OpenAI TTS (`tts-1`, MP3, streamed into the SDK's own minimp3 pipeline; its resampler handles 24 kHz → 16 kHz).
- Pinned Google Trust Services **GTS Root R4** for `api.openai.com` — the ESP cert bundle doesn't carry it.
- Typed turns (serial console) now queue TTS too; previously captions-only by design.
- CJK captions available via `CONFIG_MUSE_CJK_FONT=y` (opt-in; default renders Latin glyphs — the font adds ~6.8 MB).
- Boot melody: a synthesized chirp chain at startup as a one-second speaker test.
- Scripts: `apply.sh` (patch + keys), `build-and-flash.sh` (CH342-safe build & flash), `scripts/backup-nvs.sh`, `scripts/tts_probe.py`.

Known limits: push-to-talk only (no wake word), API key lives in firmware, free-tier Muse agents have weekly usage caps.

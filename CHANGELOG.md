# Changelog

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

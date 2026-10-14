# Changelog

## v0.2.5 — 2026-10-14 — recover quickly from peripheral stalls

Outstanding audio or LCD work now triggers the zero-allocation coroner after **20 s**, then reboots after the 3 s log-drain interval. Idle time and cloud response time do not count as peripheral stalls. This is a reboot recovery path; the underlying DMA/SPI fault remains unresolved.

- **Independent I/O deadlines** — monitor codec RX/TX, codec power changes, LCD flush completion and queued LCD commands. Cover boot/loopback audio reads as well as normal capture. Repeated driver errors retain the first failure's age until a successful operation or intentional audio power-down.
- **Keep evidence and the long backstop** — retain the existing task dump and 360 s voice-loop recovery. Fix the 300 s diagnostic dump resetting the stall clock, which could prevent that backstop from ever firing. Poll the coroner once per second and log health once per minute.
- **Avoid unsafe teardown** — IDF's SPI panel deletion waits indefinitely for outstanding transactions; I2S disable waits for the active read to release its semaphore. Resetting the panel alone cannot release these software waits. No force deletion of tasks or DMA-owned buffers.
- **Validation** — two spontaneous stalls rebooted in about **24.2 s and 24.0 s**. After the second restart, `>tasks` and the complete `k` voice path passed (2.8 s voice turn). Forced-battery sleep for 75 s caused no false reset. Watcher/AIPI builds and 248 host tests checked; final patch applies through `apply.sh`. The fault can recur soon after restart: [receipts and limitations](docs/STABILITY-v0.2.5.md).

## v0.2.4 — 2026-10-14 — faster voice turns, correct HTTP reuse

The Watcher now answers in **about 3.4 s after recording ends**, including the first turn after a fresh boot with connection preparation enabled. Typed turns finish in **2.2–2.6 s** (first after boot: **2.5 s**), down from the previous 5.1–5.6 s. [Measurements and conditions](docs/LATENCY-v0.2.4.md).

- **Correct keep-alive** — chat SSE is parsed in `perform()`'s data callback. IDF 6's manual `open()` path created a new TLS connection each turn. Short replies (up to 128 UTF-8 bytes, including short multi-sentence greetings) use the completed chat connection for one TTS request; longer replies continue sentence streaming on a separate client.
- **Prepare the first connection** — a HEAD request runs after Wi-Fi and board initialization, and before recording when needed. It establishes verified TLS without running a model; the transcription endpoint's 405 response keeps the connection usable. TLS 1.3 tickets are saved after headers arrive, scoped to the provider origin; an empty response or idle-close gets one retry before any reply data has started. A forced Wi-Fi reconnect resumed TLS in 480 ms during profiling.
- **Faster certificate checks** — the Let's Encrypt bundle adds the official [Root YE](https://letsencrypt.org/certificates/) alongside X1, shortening the current server chain; fixed-point EC tables accelerate signature verification. Profiling with wake disabled measured fresh handshakes at about 1.6–1.9 s; first-connection work is now prepared before the question. Server certificate and hostname verification remain enabled.
- **About 4× less STT upload** — `BRAIN_STT_WAV_ADPCM` uses the SDK's existing IMA encoder inside a standard WAV container, with no codec heap allocation. QuickSilver opts in; OpenAI/custom presets keep PCM by default. The firmware encoder's English and Chinese samples were accepted by the server; the Chinese transcript matched PCM exactly. HTTP buffers use PSRAM on equipped boards, and small requests disable Nagle's delay.
- **Finish completed brain replies immediately** — skip the generic 3 s quiet interval once HTTP and speech are complete; Muse cloud turns retain their follow-up interval. The QuickSilver preset uses `qwen3.7-flash`, with a concise voice prompt.
- **Meaningful `k` self-test** — preserve the microphone samples captured during the embedded wake phrase, then use the ordinary recording tail. Previously the self-test discarded its own phrase and uploaded subsequent room noise. Normal PTT and wake VAD keep their existing behavior.
- **Production cleanup** — remove `lat:` probes and mbedTLS debug; resting Wi-Fi uses MIN_MODEM and active turns restore the previous setting. Keep a balanced CPU maximum-frequency lock during turns. The zero-allocation coroner and 360 s recovery for existing DMA stalls remain enabled.
- **Validation** — Watcher (wake enabled) and AIPI (wake disabled) builds pass; 246 host tests complete with 2 environment-dependent skips, plus all 5 audio format/FFmpeg decoder checks on macOS. Final patch applies through `apply.sh` to a clean SDK at `812c46f`. On-device cold/warm typed, voice, boot and disconnect recovery checks pass.

## v0.2.3 — 2026-10-14 — watchdog + coroner: the wedge leaves evidence

The v0.2.2 known issue (device wedges after 1–6 h, buttons dead, `k`/`l` silent) now leaves evidence instead of silence. Two freezes were caught in the act; both showed the same signature: `muse_voice` blocked, `lvgl` spinning in `lv_refr_wait_for_flushing` — the display flush never completes, so the LVGL lock is never released and the voice task dies updating its caption.

- **Task watchdog** — `CONFIG_ESP_TASK_WDT_EN` on; `muse_voice` subscribes and reconfigures the timeout to 300 s at boot. A wedged voice task gets its backtrace logged (and re-logged every 5 min) instead of the device sitting quietly.
- **Coroner task** — if the voice task stalls ≥300 s, a low-priority coroner dumps the backtrace of **every** task to the console. It allocates nothing: static PSRAM buffers and a re-entrancy guard, because in a wedged system the heap lock may be held by the very path being autopsied — a malloc there kills the coroner too (v1 learned this the hard way; its second run produced no dump at all).
- **`>tasks` console command** — dump all task backtraces on demand from the serial console; answers even while everything else is frozen.
- Root cause of the flush hang is still open; the next freeze now leaves a full stack dump in the serial log (baseline when healthy: `voice_task → idle_capture → muse_audio_read → i2s_channel_read`).

## v0.2.2 — 2026-10-14 — Chinese-first STT + resilient transcription

First round of real-human testing surfaced three transcription bugs; all fixed on device and verified end to end (knob → record → STT → brain → spoken reply, Chinese in / Chinese out).

- **STT language pin** — Whisper was auto-detecting the language on short notes and hallucinating Korean on room noise; `BRAIN_STT_LANG` (`zh` by default) and a `BRAIN_STT_PROMPT` ("以下是普通话的句子。") are sent with every transcription request.
- **Instant STT retry** — a keep-alive socket the server just closed yields a silent 0-byte 200; `brain_stt` now retries once immediately instead of punting to the saved-note path (which waited 15 s before its first resend).
- **Faster note retries** — `RETRY_MIN_US` 15 s → 2 s (still exponential up to 120 s), so a failed turn comes back in seconds, not half a minute.
- **STT diagnostics** — the device logs every transcription response (size + body) and any HTTP failure with the status code; no more silent `BRAIN STT FAILED`.
- **`WAKE_WORD 0` builds clean** — the wake-test path is now `#if WAKE_WORD`-guarded, so disabling the wake word compiles (and frees the WakeNet internal-RAM budget).
- Known issue: after 1–6 h of runtime the audio/input tasks can wedge (buttons dead, `k`/`l` silent) until reboot; heartbeats and wake detection keep running. Under investigation.

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

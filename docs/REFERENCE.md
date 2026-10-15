# Reference

The full story of **esp32-thinks** — a multi-model Muse: a personal AI voice assistant on ESP32 with a brain you choose (three independent OpenAI-compatible endpoints) and an on-chip wake word. This document follows the project's timeline: the v0.1 TTS hook, the v0.2 brain, and the v0.2.1 wake word — with every gotcha found the hard way along the way. For the pitch and the quick start, see the [README](../README.md).

Everything here was learned on real hardware. Tested with **muse-gadget-sdk @ `812c46f`** (2026-10-09) and **ESP-IDF v6.0.1** on an esp32s3 target. Newer revisions likely work — run `git rev-parse --short HEAD` in the SDK to compare.

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

Each endpoint pins its own root CA (`OPENAI_CA` = GTS Root R4 for api.openai.com, `ISRG_CA` = Root YE + ISRG Root X1 for Let's Encrypt hosts). `provider_config.h` also carries `DEV_WIFI_SSID`/`DEV_WIFI_PASS` for headless provisioning: on boot, if the board has no saved Wi-Fi, it writes the credentials and a placeholder hatch token — no Muse app, no BLE pairing, no account.

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

Short replies can use one session: after the chat HTTP response is fully consumed, speech reuses its client when HTTPS authority and pinned roots match. Replies up to 128 UTF-8 bytes are batched for one speech request; longer replies use a separate speech client while chat continues streaming. `perform()` and its data callback retain the client state correctly; the manual `open()` path in IDF 6 started a new connection each turn. A stale socket gets one immediate retry before any reply data arrives. TLS 1.3 tickets are saved after reading response headers and scoped to the provider origin; changing hosts discards the old ticket. A HEAD request prepares the connection after Wi-Fi becomes ready (and before recording if no client exists); a 405 response is expected for a POST-only transcription endpoint and still establishes authenticated TLS.

## Interruption and quiet recordings

Cancellation used to change only the generation counter and enqueue a command. The same task was running blocking HTTP requests, so it could not handle the command until the fetch returned. The final implementation uses ESP-IDF's asynchronous HTTPS client, with the HTTP owner checking cancellation between I/O attempts, including TLS setup. Producers signal cancellation through the generation and queued command. The owner closes and frees old HTTP/TLS clients, resets decoder state and drains queued audio before processing the next turn. Successful ordinary turns retain their keepalive clients.

The custom SSL transport bounds each socket read/write wait to 50 ms (TCP connection attempts use up to 500 ms) and maps an idle poll to `EAGAIN`, so IDF does not mistake a gap between body chunks for a truncated response. Normal requests keep a 30-second no-progress timeout, extended by successful connection/header/data events so a healthy long response can continue. HEAD preparation and maintenance use a five-second total budget. Cancelled requests skip retries and stop feeding further chat/TTS data.

The microphone guard uses the idle microphone's adaptive background rather than a fixed absolute volume threshold. A run needs at least 80 ms continuously above background plus 6 dB to count toward speech. From v0.2.9, a complete utterance needs at least 400 ms of this qualified speech before upload; shorter clicks are discarded. The threshold stays relative to the microphone background so PTT can accept a quiet voice above a quiet local floor. Three seconds of continuous quiet ends capture after at least two seconds of captured audio. If fewer than 400 ms of qualified speech were detected, the recording is cancelled and discarded, captioned `DIDN'T CATCH THAT`, and is not passed to STT/chat/TTS. Brain-mode initial HEAD preparation may still occur; it contains no microphone audio and runs no model.

On ESP32-S3, the guard also requires the existing ESP-SR lightweight VAD to report voice. Its state uses about 0.8 KB during recording and is freed before STT; it is primed with available pre-roll. If allocation headroom is insufficient, it logs classifier unavailability and uses the energy guard. Other targets use the energy guard. Voice classification is imperfect, and nearby speech or playback can still qualify. Unit tests cover quiet backgrounds, higher steady background noise, low-volume speech and isolated clipped spikes. Socket-pair tests exercise a waiting nonblocking read and verify prompt cancellation. Other tests verify no replay after cancellation, a clean subsequent request, bounded HEAD preparation, and sustained progress on a response lasting longer than 30 seconds.

Historical v0.2.7 Watcher device checks on 2026-10-14, with the UART logger as the sole reader and the ordinary acoustic `k` path:

| Check | Observed result |
| --- | --- |
| Boot preparation | HEAD completed at uptime 8.151 s. |
| Idle maintenance | `brain: keepalive ok` at uptime 263.736 s, about 180 s after the final background preparation, without reconnecting or rebooting. A subsequent typed query completed in 2.9 s without a new TLS connection. |
| PTT without speech | Captured 3.00 s, discarded; no STT/chat/TTS. |
| Three playback interruptions followed by silence | Old turn cancelled in 18/9/16 ms; each new capture stopped after 3.00 s and was discarded without STT. |
| Normal `k` immediately after those discarded captures | `turn done` 3.1/3.2/4.0 s; `reply audio after` 2.83/2.93/3.78 s. All produced normal speech. |
| First normal `k` after boot and the initial silence check | `turn done` 4.9 s, including about 3.18 s from finalized recording to STT response. |
| Lower-volume acoustic replay | Volume 90: captured RMS -25.9 dBFS, about 4.4 dB below normal replay; accepted, `turn done` 3.3 s. Volume restored to 100. This is not a human whisper test. |
| Three typed controls | 2.8/2.1/2.2 s; no new TLS connection on any question path. |
| Post-test health | `>tasks` returned its dump. Idle heartbeat reports remained about 5 KB internal free / 2 KB largest block, with 1553 KB PSRAM free before and after the repeated turns; these rounded readings are not a long-duration leak test. |

**The strict next-turn ≤3 s acceptance criterion is not met.** The silent hallucination path is blocked and cancellation is prompt, but the three valid follow-up voice samples above include a 4.0 s turn. Their TTS-request-to-first-MP3 intervals were 626/604/1436 ms. The original 25 s symptom did not recur in these checks; that is not proof of its original cause. The existing peripheral/DMA stall issue and its v0.2.5 reboot fallback remain separate limitations.

Watcher (wake enabled) and AIPI (wake disabled) builds pass. The full host suite ran 260 tests with two environment skips; the final 19 HTTP checks also pass after adjusting the connection wait. The regenerated binary patch applies through `apply.sh --preset quicksilver` to a clean SDK at `812c46f` using a fake provider key. `muse-serial` was restored after flashing/testing.

The original `timing tts` mark records when the TTS request starts, not its first byte; it does not establish that TTS itself spent 25 seconds blocked. The cancellation change addresses outstanding HTTP ownership, while the quiet guard prevents the silent follow-up from reaching any model.

## Wake echo suppression (v0.2.9)

The old four-second wake cooldown started when recording returned, before `finish_note()` waited for and played the reply. It could expire before playback ended. The cooldown now starts **after the reply path returns** and lasts two seconds, including interrupted/error replies and saved-note replies.

Every codec speaker write marks playback active, with a 1.5-second tail after its completion. The wake detector is not run during this interval or the turn cooldown. Closing the gate clears its partial frame, recent-energy window and WakeNet state so old speaker samples cannot complete a later detection. These gates only affect wake detection; manual PTT still reaches recording. The deliberate acoustic `k` self-test bypasses the time gates, while keeping the energy check.

A WakeNet candidate is accepted only when the RMS of a 256 ms window within the most recent second of detector audio is at least **adaptive background +12 dB**. The reported -54 dBFS signal over a -61 dBFS floor fails that check. PTT retains its +6 dB recording guard and 400 ms minimum qualified speech, independently of the stronger wake threshold. This does not implement full acoustic echo cancellation: loud external speech containing the phrase can still meet the detector and energy criteria.

The provider template forbids greetings and saying the wake phrase. Greeting-only or wake-only input is directed to the short response `Please ask.`. A reply/transcript containing common ASCII variants of Hi ESP, High ESP or Hey ESP is not added to history; other history is capped at four messages (two exchanges). This bounds reinforcement of an echo transcript without claiming that every ASR hallucination can be identified.

A successful STT response with an empty `text` is now an explicit no-speech discard. It returns `DIDN'T CATCH THAT` without chat, TTS or saved-note retries. Transport failures and malformed responses still retain the existing note retry behavior. Host tests cover both awake and sleeping consumers so a discard cannot become a retry loop.

Final-device checks use the UART logger as the sole reader, volume 14 and mic gain 27. Three typed turns returned in 1.7, 1.7 and 2.7 s without a new turn-path TLS handshake. `hi` and `你好` both returned `Please ask.`; the question returned `瑞利散射。`. A silent PTT note was discarded without STT. The following 60-second awake observation had zero accepted wake events, with WakeNet still running and no reboot. The device was left awake at volume 14 with `muse-serial` active.

The single permitted acoustic `k` attempt was **incomplete**: WakeNet candidates were rejected by the original last-256-ms energy check, so it produced no voice turn or spoken reply. No second acoustic attempt was made. The energy check was then changed to search the most recent second for a qualifying 256 ms window, allowing a candidate reported after the phrase's loud portion; +12 dB remains required. Host tests cover this delayed report, +7 dB rejection and energy expiry. A successful acoustic voice turn and the following 60-second reply-echo check remain unverified on this final revision. Three repeated acoustic `k` turns were excluded under the user's one-use noise limit.

STT investigation from the preceding dogfood work did not establish a repeatable device upload slowdown. In three controlled pairs, direct/post-interruption STT took 1.440/1.396, 1.805/1.352 and 1.299/1.306 s. Encoding took 25–26 ms and the 23 KB multipart body was queued in 212–479 ms. A tighter immediate-retry sample returned empty text after a 277 ms enqueue plus a 2.951 s wait for response headers; the device's saved-note retries kept returning empty text, exposing the saved-note retry bug fixed above. Socket enqueue time does not prove when every byte reached the server. The self-test volume was also found at 14, about 15 dB below earlier volume-100 captures. The separate three-consecutive-turn ≤3.5 s latency target is not claimed as resolved by this release. All temporary STT timing and WAV-export probes were removed.

## Idle connection maintenance

The brain client sends an authenticated HEAD to its STT endpoint (or chat endpoint if no STT URL is configured) every 180 seconds when no turn is active and no command is queued. This does not run a transcription or model inference. The existing connection is actually probed; the old warmup fast path that only checked whether a client existed cannot mask a dead socket.

Probes run on the HTTP owner's task, with the existing CPU maximum-frequency lock held during the request, including a possible 40 MHz resting configuration. A 405 response is expected at the POST-only transcription endpoint. A failed request or closed socket clears preparation and destroys the stale client and transport. Preparation retries automatically after one second, with exponential backoff capped at 60 seconds. HEAD uses a 5-second I/O timeout; subsequent normal requests reset their timeout to 30 seconds. A probe already in progress can briefly delay a newly queued command, although active or already-queued turns prevent a probe from starting.

Both awake idle and resting idle are covered while Wi-Fi is available. The original battery policy turns Wi-Fi off after two minutes of low-power rest, which is shorter than the keepalive interval; connection maintenance does not force the radio back on. It resumes when Wi-Fi returns. Resting queue waits are finite and follow the deadline, with an offline check at most once per minute.

The connection-cut check used a temporary test build: immediately before the first keepalive, it called `shutdown()` on the existing client socket. This simulates an unusable connection without changing Wi-Fi or provider credentials. It is not a server-process restart. The test code was removed from the final source, patch, and firmware.

```text
I (7897)  brain: HTTPS connected (chat/STT)
I (8066)  brain: warmup ok
W (188229) TEST ONLY: cut idle HTTPS connection before keepalive
I (188263) brain: keepalive failed; rewarming
I (190899) brain: HTTPS connected (chat/STT)
I (191068) brain: warmup ok
I (191503) typed turn: 27 bytes
I (194272) turn done: 1 message(s) in 2.8s
I (371321) brain: keepalive ok
```

The follow-up typed turn and the subsequent keepalive had no new HTTPS-connection event. Automatic preparation completed about 2.8 s after the failed probe (including its one-second retry delay). The final Watcher and AIPI builds pass, with 16% and 47% app-slot space free. All 254 host tests completed, with two skips for the Jetson's missing PSA development library and FFmpeg IMA ADPCM decoder. The final patch applies cleanly through `apply.sh` against SDK `812c46f`.

Typed question: `天空为什么是蓝的？`. Each cold sample reset the device, waited for the logged boot warmup plus one second, then sent the question. Warm samples followed on the last boot, two seconds apart. These are device-cold samples with background connection preparation, not cold model-provider measurements.

| Sample | SDK turn duration | New HTTPS connections during the question |
|---|---:|---:|
| Cold 1 | 2.3 s | 0 |
| Cold 2 | 2.1 s | 0 |
| Cold 3 | 1.9 s | 0 |
| Warm 1 | 2.3 s | 0 |
| Warm 2 | 2.0 s | 0 |
| Warm 3 | 2.0 s | 0 |

The HTTPS event is emitted only for an actual connect in IDF's client; the six questions emitted none. Turn duration is the existing SDK `turn done` measurement, which ends when reply audio has been queued rather than measuring the physical end of playback. Model-provider variation still applies.

On the final production build, the last cold-test boot logged warmup at 8.019 s and successful probes at 188.341 s and 368.595 s. No additional HTTPS-connect event occurred between them. The last scheduled warm question finished at 24.861 s, leaving more than five minutes without questions before the second probe. Voice detections and health counters kept moving; internal free heap rose from roughly 6 KB to 10 KB rather than declining.

```text
I (7846)   brain: HTTPS connected (chat/STT)
I (8019)   brain: warmup ok
I (188341) brain: keepalive ok
I (368595) brain: keepalive ok
I (383559) typed turn: 27 bytes
I (386411) turn done: 1 message(s) in 2.9s
```

The extra post-probe question verified HEAD-to-POST reuse after the long idle window. It completed in 2.9 s with zero new HTTPS-connect events; that sample is retained alongside the six scheduled cold/warm measurements rather than omitted from the timing record. No new TLS was logged; this measurement alone does not isolate the source of the extra delay.

Production firmware SHA-256: `1f69d1506113f62f32ac9bf00339a74568f16e5a4a15ef33d9f93a206a08a6e8`. Patch SHA-256: `8edb582ec4fbf29deccfd5845ed8157dff4077b74d7e107443db461ff50b3e8f`.

The v0.2.5 peripheral watchdog remains enabled. This connection-maintenance check does not establish that the underlying DMA fault is resolved.

## Earlier latency receipts (v0.2.0)

The v0.2.4 measurements and conditions are recorded in the [changelog](../CHANGELOG.md).

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
- **Self-test (audible; avoid repeated bench playback)**: serial `k` plays the embedded wake phrase and records **in lockstep** (full duplex) — a blocking playback would miss its own wake word; `muse_audio` loopback (`l`) confirms both mic channels.
- End-of-turn for wake-initiated recording is the energy VAD (`WAKE_VAD_DB`, -45 dBFS, 1.4 s of quiet); a 2 s cooldown after the reply finishes, the speaker tail gate and an adaptive +12 dB wake threshold suppress reply echoes (see [echo suppression](#wake-echo-suppression-v029)). Raise `WAKE_VAD_DB` toward -35 if it keeps recording after you stop.
- Custom phrase ("Hey Mica"): Espressif's TTS Pipeline V3 trains WakeNet models from TTS samples (esp-sr issue #88) — drop the trained model into the `model` partition. Prebuilt models ship for "Hi ESP", "你好小智", Alexa and others.

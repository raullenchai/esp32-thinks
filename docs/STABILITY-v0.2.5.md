# Watcher peripheral stall recovery

The shipped path detects outstanding I/O after 20 seconds, dumps all task backtraces without allocating memory, allows three seconds for serial output, and restarts. With the one-second polling interval, the intended freeze-to-restart bound is about 23–24 seconds. The underlying event loss is still open; this release does not claim recovery without reboot.

The short deadline watches actual work: I2S RX/TX, codec power changes, LCD flush completion and queued LCD control calls. A driver that returns errors repeatedly keeps the first error's age until success. A powered-down codec, idle screen or long cloud response has no pending peripheral operation. The original 360-second voice-loop backstop remains, and the diagnostic dump at 300 seconds no longer resets its clock.

## Why teardown is deferred

The installed esp_codec_dev I2S driver already uses a 1000 ms read timeout. The affected system still stops making progress. IDF 6.0.1's `i2s_channel_disable()` waits without a deadline for the active read semaphore; SPI LCD deletion waits without a deadline for every queued transaction to complete. Issuing these calls from the coroner can strand the coroner too. Forcing LVGL flush-ready or freeing its queued DMA buffers before ownership is returned would be unsafe.

## Baseline reproduced

Before flashing this change, the previous firmware naturally froze around uptime **402 s**. Wake detections stopped, while link heartbeats continued. An on-demand `>tasks` dump at **515 s** showed:

- `muse_voice → idle_capture → muse_audio_read → esp_codec_dev_read → _i2s_data_read → i2s_channel_read → xQueueReceive`.
- `lcd_send → send_bands → esp_lcd_panel_draw_bitmap → panel_spd2010_draw_bitmap → panel_io_spi_tx_param`.
- LVGL waiting for flush completion; both draw workers idle.

The prior reported freeze window was 16–42 minutes; this particular baseline reproduced sooner. USB was attached, so this does not demonstrate the battery-only automatic light-sleep path.

## Checks

Watcher (wake enabled) and AIPI (wake disabled) builds pass, with 16% and 47% app-slot space free. `apply.sh` applies the final patch to a clean SDK at `812c46f`. The 248-test host suite completed with three skips; the pairing test skipped for an unset IDF_PATH was rerun with IDF_PATH and passed. The remaining two are the Jetson's missing PSA development library and FFmpeg IMA ADPCM decoder.

Initial hardware checks passed: clean boot, typed chat/TTS operation, the full `k` microphone/STT/chat/TTS path, and `>tasks`. The first typed turn completed in 3.6 s. The first `k` turn completed in 10.6 s, including a 4.8 s transcription wait and subsequent chat/TTS waits; this slower sample is retained rather than counted as a latency pass.

A 75 s forced-battery `>nap` test logged codecs off, display paused, Wi-Fi napping, APB minimum 40 MHz and light sleep enabled. Health lines at uptime 63 s and 123 s showed `resting=1 io=none age=0 ms`; there was no false reboot. Waking restored fixed 240 MHz. Subsequent typed and `k` turns completed in 2.9 s and 3.0 s respectively; the stale socket from Wi-Fi nap recovered automatically. These functional checks do not establish a sustained worst-case latency bound.

Two natural faults were captured with the final firmware; no injected stall was used:

| Cycle | I/O stall began (uptime) | Coroner detection | Last pre-reset log | Stall → reset |
|---|---:|---:|---:|---:|
| First | 460.279 s | 481.241 s (20.962 s) | 484.470 s | ≈24.2 s |
| Second | 20.467 s after the first automatic boot | 41.203 s (20.736 s) | 44.445 s | ≈24.0 s |

Both reset banners report `RTC_SW_CPU_RST`. The first automatic dump again showed voice blocked in `i2s_channel_read`, LVGL in `wait_for_flushing`, and LCD sender waiting for another band. Coroner preserved the zero-allocation backtraces before reboot.

After the first restart, a typed turn completed in 1.9 s, but the next `k` test was interrupted by the second spontaneous stall. This is a real limitation: the fault can recur soon after a reboot. After the second automatic restart, the complete typed and `k` checks passed (3.5 s typed, 2.8 s voice turn, 3.51 s through playback), and `>tasks` returned healthy task snapshots. Wake detections continued afterwards. Internal free heap was about 6 KB after these checks and about 10 KB at the first fault; minimum free heap was 283 bytes before the first reset and 279 bytes after the final check. There was no observed progressive heap loss across these samples, but free internal memory remains tight.

The goal validated here is **restart within 30 s and restored functionality**, not uninterrupted uptime or recovery without reboot. These observed windows are shorter than the previously reported 16–42 minutes. The forced-battery sleep test exercises the real software low-frequency/light-sleep path while the hardware remains USB-powered; it is not a long battery-only soak.

Firmware SHA-256: `ba478cee1b2b29c8a07700ac8d9ef49479db44de5f40f1dede551f7770e8cf51`. Distribution patch SHA-256: `6e2f4bfb9ba229b7a7c0d744c7a0284f39681646a1521c8b3b446684868aa816`.

Selected first-cycle evidence:

```text
E (481241) muse_voice: coroner: I2S RX stalled 20962 ms, voice idle 20 s — rebooting to recover
I (481244) muse_voice: coroner: walked 23 tasks, int=10063 min=283
I (484470) wifi:lmac stop hw txq
rst:0xc (RTC_SW_CPU_RST),boot:0x9 (SPI_FAST_FLASH_BOOT)
```

Selected post-second-restart evidence:

```text
I (101096) muse_voice: recorded 2.80s
I (101834) muse_chat_session: brain heard: Hi ESP. hi ESP.
I (103822) muse_chat_session: turn done: 1 message(s) in 2.8s
I (104667) muse_voice: muse reply: 1.03s of audio, 3.51s total
I (107003) muse_voice: coroner: walked 24 tasks, int=6039 min=279
```

Host checks exercise the compiled I/O tracker with a deterministic clock: successful reads, persistent errors, independent LCD stalls despite healthy audio, idle/sleep, power transitions, and a 32-bit microsecond rollover. The actual coroner function is compiled into another harness: a peripheral stall restarts at 23 s; normal minute-long sleep does not reboot; a general voice stall dumps at 300 s and restarts at 363 s.

# v0.2.4 latency receipts

Measured on 2026-10-14 on a Seeed SenseCAP Watcher (ESP32-S3), ESP-IDF 6.0.1, SDK `812c46f`, 2.4 GHz Wi-Fi, wake word and CJK captions enabled. QuickSilver: `qwen3.7-flash`, `whisper-large-v3-turbo`, chatterbox/qwen3 TTS; concise voice prompt. Recordings upload as 16-kHz mono IMA ADPCM WAV.

“First after boot” means a fresh device reset, then input at about 12 s. The firmware prepares verified TLS with HEAD after Wi-Fi is ready; this time is outside the question's response latency. With wake disabled during handshake profiling, bare fresh TLS took about 1.6–1.9 s; a forced reconnect resumed in 480 ms. Final cold/warm turn samples below have wake enabled.

| Path | First after boot | Repeat samples |
|---|---:|---:|
| Typed input → first PCM | 2.325 s | 2.024 / 2.239 / 2.445 s |
| Typed input → `turn done` | 2.5 s | 2.2 / 2.4 / 2.6 s |
| Voice release → first PCM | 3.429 s | 3.446 s |
| Voice SDK turn → `turn done` | 4.1 s | 3.7 s |

Voice uses serial `k`: the speaker plays the embedded phrase, the microphone captures it in full duplex, WakeNet detects it, and those actual microphone samples pass through STT → chat → TTS → PCM. Capture is 2.80 s, outside the release-to-response figures. The SDK voice turn begins just before the normal recording tail, so its `turn done` clock includes that tail. `turn done` means the reply has been decoded/queued; first PCM is the response-latency metric, not the duration of the spoken sentence.

Representative final console receipts:

```text
typed first: turn done: 1 message(s) in 2.5s
  timing (ms after release): sent +2455 tts +975 mp3 +2312 audio +2325
typed repeats: turn done in 2.2s / 2.4s / 2.6s
  first PCM +2024 / +2239 / +2445 ms
voice first: STT resp {"text":" Hi ESP. hi ESP."}
  timing (ms after release): tts +2496 mp3 +3416 audio +3429
voice repeat: STT resp {"text":" Hi ESP. hi ESP."}
  timing (ms after release): tts +2802 mp3 +3436 audio +3446
```

Provider compatibility was checked separately with synthetic English and Chinese speech. The firmware's encoder produced a 22,332-byte Chinese WAV versus 87,118 bytes of PCM; both returned `天空为什么是藍的?`. The independent FFmpeg decoder accepted the WAV headers, sample count and block boundaries, with bounded waveform loss. ADPCM is enabled only for the verified preset; other presets retain PCM compatibility.

The earlier `k` path discarded the played phrase and recorded room noise for 4–15 s; those timings are excluded from the final samples. Normal voice VAD thresholds and PTT capture behavior are unchanged. Existing DMA stalls still have watchdog/coroner recovery; they are a separate reliability issue.

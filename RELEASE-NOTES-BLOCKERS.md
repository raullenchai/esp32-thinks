# v0.2.10 release validation and known limits

2026-10-14. Release scope: synchronize the already verified language behavior and prepare the source repository for publication. No new release-stopping failure was found. The open issues and unverified journeys below remain follow-ups; the release does not claim every UX scenario passed.

## Verified on SenseCAP Watcher

The device was restarted to clear RAM conversation history. One UART logger remained the sole serial reader; tests wrote commands without opening another reader. Existing speaker settings were retained: volume 75, mic gain 27. The initial regression found a typed-request cancellation state bug; a small state fix was then built, flashed and rechecked separately. Persona, STT defaults, TTS routing and wake gates were preserved.

The table below records the initial language/echo regression, before the typed cancellation state/error fix.

| Journey | Result |
|---|---|
| Restart → boot → first typed question | English answer, 21 words / 142 characters, SDK turn 5.6 s. Chat/STT was prepared; a separate speech TLS connection opened for the longer answer. |
| Chinese typed question | Chinese answer, 42 characters, 10.8 s. |
| Korean typed question after EN/CN | Korean answer, 58 characters, 10.2 s. |
| Pure greeting `hi` | Exactly `Please ask.`, 2.4 s. |
| Silent `d` / `u`, held 0.5 s | Discarded in 0.70 s from press; no STT upload. |
| Held PTT with no speech | Automatically discarded in 3.08 s; no STT upload. This validates the quiet path, not genuine spoken PTT. |
| `z` → `w` → immediate typed question | Normal completion, 2.1 s. |
| One deliberate acoustic `k` | One accepted wake; 2.80 s recording; STT transcript `High ESP. PI ESP.`; reply `Please ask.` was physically played. First reply audio after 3.97 s; reply path completed in 5.17 s (including 1.25 s audio). |
| After that spoken reply | 60 s with zero additional accepted wakes, detector active, no reboot/stall. No second `k` was issued. |
| Heartbeat / status | Voice capture and wake counters continued, Wi-Fi up, no unexpected reboot loop. Device left awake with the UART service active. |

The previously verified short language samples were EN 3.9 s / CN 8.7 s / Korean with fresh history 3.2 s. Response length, model variation and connection state affect duration. The initial release-run EN/CN/KO questions produced longer answers; these measurements are not a controlled latency comparison. Character counts in this table are Unicode text counts, while some firmware log fields named `chars` count UTF-8 bytes.

Typed turns fetch/decode TTS and drain PCM without speaker playback. Their SDK `turn done` timings must not be described as physical first-word or playback-completion timings. The acoustic audio measurement above comes from the actual speaker path.

## Build and recipe checks

- SDK baseline: `812c46f`; ESP-IDF v6.0.1. Watcher build passes with wake enabled; AIPI build passes with wake disabled (compile coverage only, no AIPI hardware check).
- Full host suite: **271 tests, zero failures, two skips**. The skips are FFmpeg IMA ADPCM decoding and the imported Noise core's PSA development-library build. Real-crypto pairing passes with IDF loaded.
- Added production-source tests cover optional multipart language/prompt omission and English/Chinese/Hangul TTS routing, including fallback when no alternate model is configured. Another test confirms cancellation is visible while the typed HTTP response is still in progress.
- `apply.sh` applies the regenerated `git diff --binary` patch to a clean SDK clone. All changed files match the working SDK byte-for-byte. New language tests also pass from that applied checkout.
- The generated `BRAIN_SYSTEM` C literal matches the device build's provider header byte-for-byte. Language/prompt defaults and nonsecret model/wake settings match too. Persona literal SHA-256: `44ee107b73d48c684a743a1d95011e040cf0cdadc21add2616e0ca067b1ead71`. Credentials are intentionally excluded from comparison/output.
- Shell syntax, local documentation links and patch whitespace checks pass. No provider header, keys, provisioning credentials, NVS backups or compiled firmware are distributed in this repository.

## Typed cancellation fix found during regression

Initially, PTT and `>chat.cancel` during typed HTTP work did not preempt it promptly. The old request reached its response before cancellation was handled (about 5.5 s after the PTT press; 5.375 s after explicit cancel). The synchronous typed request had remained `P_IDLE`, so the HTTP cancellation predicate ignored its changed generation. The fix marks the turn active before entering chat/TTS I/O. The cancellation error branch also closes both clients and reports `CANCELLED`, rather than treating a user cancellation as `BRAIN UNREACHABLE`. It does not change model instructions or the speaker/wake path.

Final device controls passed after flashing the complete fix:

| Final firmware check | Observed result |
|---|---|
| First typed EN / CN / KO | 29 words / 7.1 s; 72 characters (66 Han) / 15.1 s; 76 characters / 10.3 s. Language followed input in all three. |
| Greeting / quiet tap / held silence | `Please ask.` in 1.7 s; tap discarded in 0.70 s; held quiet discarded in 3.06 s. No STT upload for either quiet note. |
| Sleep → wake → immediate typed | 1.9 s. |
| PTT during active typed HTTP | `CANCELLED` 29 ms after PTT down; no stale final reply. Quiet recording discarded; the next typed turn completed in 3.5 s. |
| Explicit `>chat.cancel` | `CANCELLED` in 42 ms, instead of the initial 5.375 s. |
| Typed after explicit cancellation | SDK turn 1.8 s; wall clock 3.34 s from submission, including preparation/queue time. Normal final/done, no error. |

The single acoustic test above was performed before this state/error fix; wake/audio gate code was unchanged and `k` was not repeated. After the final flash and control checks, another 60 s awake-idle observation had zero accepted wakes, an active detector and heartbeat, and no unexpected reboot. Status remained speaker on, volume 75, mic gain 27, sleep off; `muse-serial` was active.

## Open issues and coverage gaps

| Item | Evidence / limit | Follow-up or current use |
|---|---|---|
| Genuine spoken PTT and physical playback barge-in | No controlled human microphone-input check was performed in this automated run. The one acoustic replay was reserved for a complete wake/STT/reply plus the 60 s echo check. | A quiet `d/u` is not evidence for a successful spoken PTT turn. Real-person press/speak/release and interrupt/re-ask remain unverified in this release run. Earlier cancellation regressions and current host tests are retained. |
| Longer multilingual answers / soft length bound | Final Chinese/Korean typed turns took 15.1/10.3 s. The Chinese answer had 72 Unicode characters, including 66 Han, exceeding the approximate 60-character instruction. | The new length limit is a prompt instruction, not hard truncation or a timing SLA. The already verified persona was retained. Do not advertise the old 2–3 s short-answer figure for this persona. |
| Post-interruption STT latency | The earlier three-consecutive-voice-turn ≤3.5 s goal was not established. | Still under investigation; the release does not claim it fixed. |
| Rare peripheral/DMA stall | Underlying event-loss cause remains unresolved. | Existing ~20 s peripheral deadline plus diagnostic/restart and the 360 s voice backstop remain. This run is not a 16–42 minute freeze-cycle endurance qualification. |
| Echo suppression scope | One acoustic reply followed by 60 s passed. Speaker/time gates and +12 dB energy acceptance are not full AEC. | Sustained external speech or a loud phrase can still qualify. Longer room/device-volume testing remains useful. |
| Korean captions / other providers | Korean reply text and routing are tested; physical LCD glyph coverage and every provider/model are not. | Verify font coverage and endpoint/audio-format support for the chosen deployment. |

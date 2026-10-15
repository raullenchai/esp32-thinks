# Contributing

This repository distributes a patch and build recipe. Firmware changes are made in a separate `muse-gadget-sdk` checkout, then exported to `patches/muse-brain.patch`.

## Reproduce the build

1. Install ESP-IDF v6.x for ESP32-S3 and check out SDK commit `812c46f`.
2. Back up factory NVS before flashing hardware. Run `./apply.sh <sdk> --preset quicksilver` on a clean SDK checkout; other presets are described in the README.
3. Activate IDF, then run the host suite from `<sdk>/esp32`:

   ```bash
   python3 -m unittest discover -s tests -v
   ```

   Report skips as well as failures. Real-crypto tests need their development libraries, and waveform comparison needs an FFmpeg IMA ADPCM decoder.
4. Build Watcher without flashing, using the same configuration as `build-and-flash.sh`:

   ```bash
   idf.py -B build-muse-sensecap-watcher -DIDF_TARGET=esp32s3 \
     -DSDKCONFIG=build-muse-sensecap-watcher/sdkconfig \
     -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;devices/sdkconfig.muse;devices/sdkconfig.muse-sensecap-watcher;sdkconfig.token.local" build
   ```

   Release checks also build AIPI in a separate SDK checkout with `WAKE_WORD=0`, using `devices/sdkconfig.muse-aipi` and build directory `build-muse-aipi`. Separate checkouts avoid managed-component configuration conflicts. AIPI is build-tested; Watcher is the hardware-tested board.

## Export and review a change

From the SDK root, register any new source/test files with `git add -N <paths>` and export:

```bash
git diff --check
git diff --binary > /path/to/esp32-thinks/patches/muse-brain.patch
```

Do not register generated provider credentials, provisioning files or build artifacts. Apply the resulting recipe to another clean SDK checkout and compare the generated nonsecret configuration to the configuration you tested. Keep `apply.sh`, the changelog and reference documentation consistent.

For a pull request, describe the concrete behavior change, host/build results, actual device checks and remaining coverage gaps. Include response length and whether latency measures request completion, first audio or physical playback completion.

## Quiet hardware regression

Use `>chat=` for ordinary inference checks and `d` / `u` for PTT. Typed turns fetch/decode speech but do not play it. A silent PTT verifies the no-speech path, not real STT. Reserve `k` for one deliberate acoustic test, announce it before playback and never run a repeated wake-phrase loop. Test genuine spoken PTT and barge-in with a person when available.

Use one serial reader. Stop a background UART logger before tools that open the port for reading or reset, and restore it afterward. Leave the device awake at its original volume. Never attach credential-bearing firmware, factory NVS backups, or unredacted provisioning logs to an issue.

The [release notes](RELEASE-NOTES-BLOCKERS.md) distinguish verified behavior from known limits. License attribution is in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

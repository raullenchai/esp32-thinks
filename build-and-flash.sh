#!/usr/bin/env bash
# esp32-thinks: build the Watcher firmware and flash it with the CH342-safe paced esptool.
#
# Usage: ./build-and-flash.sh /path/to/muse-gadget-sdk [port]
#   port defaults to $PORT or /dev/ttyACM1
set -euo pipefail

SDK=${1:?usage: ./build-and-flash.sh /path/to/muse-gadget-sdk [/dev/ttyACM1]}
PORT=${2:-${PORT:-/dev/ttyACM1}}
IDF_PATH=${IDF_PATH:-$HOME/esp/esp-idf-v6}

test -f "$SDK/esp32/sdkconfig.token.local" || {
    echo "missing $SDK/esp32/sdkconfig.token.local — run ./apply.sh first"; exit 1; }

cd "$SDK/esp32"
. "$IDF_PATH/export.sh" >/dev/null

B=build-muse-sensecap-watcher
idf.py -B "$B" -DIDF_TARGET=esp32s3 \
    -DSDKCONFIG="$B/sdkconfig" \
    -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;devices/sdkconfig.muse;devices/sdkconfig.muse-sensecap-watcher;sdkconfig.token.local" \
    build

echo "== build ok, flashing $PORT (pacing: the CH342 bridge drops bytes at high baud — never interrupt this)"
cd "$B"
python3 ../tools/muse/paced_esptool.py --chip esp32s3 -p "$PORT" -b 115200 \
    --before default-reset --after hard-reset write-flash "@flash_args"
# The wake-word model rides in @flash_args (esp-sr adds 0x822000); older SDK
# revisions don't include it, so flash it separately when missing. Do NOT
# append it by hand: a duplicate 0x822000 makes esptool report a false overlap.
if [ -f srmodels/srmodels.bin ] && ! grep -q srmodels flash_args 2>/dev/null; then
    echo "== flashing wake-word model (0x822000)"
    python3 ../tools/muse/paced_esptool.py --chip esp32s3 -p "$PORT" -b 115200 \
        --before default-reset --after hard-reset write-flash 0x822000 srmodels/srmodels.bin
fi
echo "flashed. after Wi-Fi connects, press the knob and talk -- or say \"Hi ESP\"."

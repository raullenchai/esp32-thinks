#!/usr/bin/env bash
# esp32-thinks: one-time backup of the factory NVS partition, before the first flash.
# The Muse gadget token and Wi-Fi credentials live here; the restore path is
#   paced_esptool ... write-flash 0x9000 nvsfactory-backup-YYYYMMDD.bin
#
# Usage: ./scripts/backup-nvs.sh /path/to/muse-gadget-sdk [port]
set -euo pipefail

SDK=${1:?usage: ./scripts/backup-nvs.sh /path/to/muse-gadget-sdk [/dev/ttyACM1]}
PORT=${2:-${PORT:-/dev/ttyACM1}}
IDF_PATH=${IDF_PATH:-$HOME/esp/esp-idf-v6}
OUT="nvsfactory-backup-$(date +%Y%m%d).bin"

cd "$SDK/esp32"
. "$IDF_PATH/export.sh" >/dev/null
python3 tools/muse/paced_esptool.py --chip esp32s3 -p "$PORT" -b 115200 \
    --before default-reset --after hard-reset read-flash 0x9000 0x32000 "$OUT"

echo "== saved $OUT (204800 bytes)"
echo "   copy it off this machine. restore with:"
echo "   python3 tools/muse/paced_esptool.py --chip esp32s3 -p $PORT -b 115200 --before default-reset --after hard-reset write-flash 0x9000 $OUT"

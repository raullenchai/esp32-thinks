#!/usr/bin/env python3
"""esp32-thinks: end-to-end test. Sends a typed turn over the serial console and
dumps the TTS logs, so you can see whether the OpenAI fetch succeeded.

Usage: python3 tts_probe.py /path/to/muse-gadget-sdk [port] ["question"]

The board resets when the port opens (DTR), so give it ~12 s to boot and
reconnect to Wi-Fi. Don't press the knob while it runs — that interrupts the turn.
"""
import sys
import time

sys.path.insert(0, sys.argv[1].rstrip("/") + "/esp32/tools/muse")
from chat import Board  # noqa: E402  (muse-gadget-sdk's own console client)

sdk = sys.argv[1]
port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyACM1"
text = sys.argv[3] if len(sys.argv) > 3 else "Say something short."

board = Board(port)
print(f"port {port} opened; board resets on DTR — waiting for boot + wifi...")
time.sleep(12)
board.drain(1.0)

st = board.status()
print("STATUS:", "ok" if st else "no answer (wait for wifi and retry)")

try:
    r = board.chat(text)
    print("REPLY:", r.text)
except Exception as e:  # noqa: BLE001
    print("CHAT ERR:", e)

time.sleep(3)
print("---- console log (look for 'speaking message' / 'TTS ok' / 'TTS failed') ----")
for line in board.log:
    print(line)

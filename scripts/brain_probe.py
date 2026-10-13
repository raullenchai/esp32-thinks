#!/usr/bin/env python3
"""esp32-thinks: end-to-end brain test over the serial console.

Sends a typed turn and prints the device's reply plus the brain/TTS log lines,
so you can see the whole pipeline (transcription is voice-only; this exercises
chat + speech + keep-alive).

Usage: python3 brain_probe.py /dev/ttyACM1 ["question"]
"""
import sys, time, threading, collections

sys.path.insert(0, "/home/ubuntu/muse-gadget-sdk/esp32/tools/muse")  # adjust to your checkout
from chat import Board

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM1"
Q = sys.argv[2] if len(sys.argv) > 2 else "What is the capital of France? One short sentence."

board = Board(PORT)
board.log = collections.deque(maxlen=200000)
time.sleep(1.0)
board.drain(1.0)

result = {}
def do_chat():
    t0 = time.time()
    try:
        r = board.chat(Q)
        result['reply'] = r.text
        result['secs'] = time.time() - t0
    except Exception as e:
        result['err'] = repr(e)

t = threading.Thread(target=do_chat, daemon=True)
t.start()
t.join(90)
time.sleep(3)
print("REPLY: %s (%.1fs)" % (result.get('reply'), result.get('secs', -1)))
if 'err' in result:
    print("ERR:", result['err'])
print("---- console log ----")
for line in [l for l in board.log if "heartbeat" not in l]:
    if any(k in l for k in ("typed turn", "brain", "TTS", "reply audio", "turn done", "openai", "error", "fail")):
        print(line)

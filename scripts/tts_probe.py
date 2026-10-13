#!/usr/bin/env python3
"""esp32-thinks: test the configured TTS provider before flashing, or send a
typed turn over the serial console and dump the device's TTS logs.

Usage: python3 tts_probe.py /path/to/muse-gadget-sdk --preflight ["text"]
       python3 tts_probe.py /path/to/muse-gadget-sdk [port] ["question"]

Preflight POSTs from the build host using the firmware's URL, model, voice, key
and pinned CA. It uses API credit; it doesn't need a board or change the SDK.
The serial test resets the board when the port opens (DTR), so give it ~12 s to
boot and reconnect to Wi-Fi. Don't press the knob — that interrupts the turn.
"""
import argparse
import json
from pathlib import Path
import re
import ssl
import sys
import time
import urllib.error
import urllib.request

DEFAULT_TEXT = "Say something short."


def configuration(sdk):
    muse = Path(sdk) / "esp32/components/muse"
    source = (muse / "muse_chat_session.cpp").read_text()
    config = {}
    for name in ("TTS_URL", "TTS_MODEL", "TTS_VOICE", "TTS_API_KEY"):
        match = re.search(r'^#define ' + name + r' "([^"\\]*)"$', source, re.MULTILINE)
        if not match:
            raise ValueError(f"missing {name} — run ./apply.sh first")
        config[name] = match[1]
    return config, muse / "tts_root_ca.pem"


def preflight(config, ca, text):
    if not text:
        raise ValueError("give TTS some text to speak")
    if config["TTS_URL"] == "https://api.quicksilverpro.io/v1/audio/speech" and len(text) > 4000:
        raise ValueError("QuickSilver Pro accepts at most 4,000 characters per request")
    if not config["TTS_API_KEY"] or "REPLACE-WITH-YOURS" in config["TTS_API_KEY"]:
        raise ValueError("set your TTS API key with ./apply.sh first")
    # Trust only the embedded root, just like the firmware (not the host CA store).
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.load_verify_locations(cafile=str(ca))
    body = json.dumps({
        "model": config["TTS_MODEL"], "input": text,
        "voice": config["TTS_VOICE"], "response_format": "mp3",
    }).encode("utf-8")
    request = urllib.request.Request(config["TTS_URL"], data=body, headers={
        "Authorization": "Bearer " + config["TTS_API_KEY"],
        "Content-Type": "application/json",
        # Same User-Agent the firmware's esp_http_client sends. The default
        # Python-urllib agent is refused (HTTP 403) by Cloudflare-fronted APIs.
        "User-Agent": "ESP32 HTTP Client/1.0",
    }, method="POST")
    t0 = time.monotonic()
    with urllib.request.urlopen(request, context=context, timeout=15) as response:
        if response.status != 200:
            raise ValueError(f"TTS failed: HTTP {response.status}")
        first = response.read(1)
        first_ms = (time.monotonic() - t0) * 1000
        size = len(first)
        while chunk := response.read(8192):
            size += len(chunk)
    if not size:
        raise ValueError("TTS failed: 0 audio bytes received")
    print(f"TTS ok: {size} bytes in {(time.monotonic() - t0) * 1000:.0f} ms "
          f"(first byte {first_ms:.0f} ms, measured from this host)")


def serial_probe(sdk, port, text):
    sys.path.insert(0, str(Path(sdk) / "esp32/tools/muse"))
    from chat import Board  # muse-gadget-sdk's own console client

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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk")
    parser.add_argument("port", nargs="?")
    parser.add_argument("question", nargs="?")
    parser.add_argument("--preflight", nargs="?", const=DEFAULT_TEXT, metavar="text")
    args = parser.parse_args()
    if args.preflight is not None and (args.port or args.question):
        parser.error('use <sdk> --preflight ["text"] without a serial port')
    try:
        config, ca = configuration(args.sdk)
        print(f"TTS: {config['TTS_URL']} / {config['TTS_MODEL']} / "
              f"{config['TTS_VOICE']} (root: {ca})")
        if args.preflight is not None:
            preflight(config, ca, args.preflight)
        else:
            serial_probe(args.sdk, args.port or "/dev/ttyACM1", args.question or DEFAULT_TEXT)
    except urllib.error.HTTPError as e:
        print(f"TTS failed: HTTP {e.code} ({e.reason})", file=sys.stderr)
        return 1
    except (OSError, ValueError) as e:
        print(f"TTS probe failed: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

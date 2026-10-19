#!/usr/bin/env bash
# Nightly soak for a Muse gadget on USB: reboot, verify boot, run a typed-turn
# battery, scan the serial log for failure signatures, and write a dated report.
# Runs ON the host the gadget is plugged into (the Jetson). Exit 1 on any failure.
set -u

SDK=${SDK:-$HOME/muse-gadget-sdk/esp32}
ESPTOOL=${ESPTOOL:-$HOME/.espressif/python_env/idf6.0_py3.12_env/bin/esptool}
LOG=${LOG:-$HOME/muse-serial.log}
OUT=${OUT:-$HOME/soak}
MAX_TURN_S=${MAX_TURN_S:-30}
mkdir -p "$OUT"

DATE=$(date +%F)
REPORT="$OUT/soak-$DATE.md"
declare -a FAILURES=()
note() { echo "$1" >> "$REPORT.tmp"; }
fail() { FAILURES+=("$1"); note "FAIL: $1"; }

echo "# soak $DATE" > "$REPORT.tmp"
note ""

# byte offset where this soak's window starts (boot lines follow the reset)
POS0=$(stat -c %s "$LOG" 2>/dev/null || echo 0)

# hard reset via the ROM bootloader (works even if the app is wedged);
# the serial logger keeps running, so the fresh boot lands in the log.
"$ESPTOOL" --chip esp32s3 -p "$(ls /dev/ttyACM* | sort | head -1)" -b 115200 --after hard-reset chip_id > /dev/null 2>&1
sleep 25   # boot + wifi + brain warmup

scan_signatures() { # python: print failure lines found after $1 bytes, exit 1 if any
    python3 - "$LOG" "$1" <<'PYEOF'
import re, sys, os
log, pos0 = sys.argv[1], int(sys.argv[2])
if pos0 > os.path.getsize(log):
    pos0 = 0   # the 20 MB logger truncated while we were away
with open(log, 'rb') as f:
    f.seek(pos0)
    data = f.read().decode('utf-8', 'replace')
bad = False
pats = [('exp_read', r'exp_read'), ('panic', r'panic'), ('abort', r'abort\(\)'),
        ('guru', r'Guru Meditation'), ('tls', r'handshake returned'),
        ('coroner', r'coroner:.*rebooting')]
for name, pat in pats:
    hits = re.findall(f'^.*{pat}.*$', data, re.M)
    if name == 'exp_read' and len(hits) < 20:
        hits = []   # a couple of transient expander errors are normal at boot
    for h in hits[:3]:
        print(f'[{name}] {h.strip()[:160]}')
    if hits:
        bad = True
sys.exit(1 if bad else 0)
PYEOF
}

# console port = the ttyACM that answers >status (enumeration order shuffles)
find_port() {
    local p
    for p in $(ls /dev/ttyACM* 2>/dev/null | sort -r); do
        if python3 - "$p" <<'PYEOF'
import os, sys, time, fcntl, termios, struct
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
try:
    fcntl.ioctl(fd, termios.TIOCMSET, struct.pack('I', termios.TIOCM_DTR | termios.TIOCM_RTS))
except OSError:
    pass
time.sleep(0.5)
os.write(fd, b'>status\n')
PYEOF
        then
            sleep 3
            if tail -c 8192 "$LOG" | grep -q '@status'; then echo "$p"; return 0; fi
        fi
    done
    return 1
}

send_chat() { # $1 = text; echoes "OK <seconds>" or "TIMEOUT"
    local text=$1
    python3 - "$PORT" "$text" "$MAX_TURN_S" <<'PYEOF'
import os, sys, time, fcntl, termios, struct, re
port, text, cap = sys.argv[1], sys.argv[2], float(sys.argv[3])
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
try:
    fcntl.ioctl(fd, termios.TIOCMSET, struct.pack('I', termios.TIOCM_DTR | termios.TIOCM_RTS))
except OSError:
    pass
time.sleep(1.5)
LOG = os.environ.get('LOG', '/home/ubuntu/muse-serial.log')
p0 = os.path.getsize(LOG)
os.write(fd, f'>chat={text}\n'.encode())
t = time.time()
while time.time() - t < cap:
    time.sleep(0.5)
    with open(LOG, 'rb') as f:
        f.seek(p0); d = f.read().decode('utf-8', 'replace')
    m = re.search(r'turn done: .* in ([0-9.]+)s', d)
    if m:
        print(f'OK {m.group(1)}'); sys.exit(0)
    if 'BRAIN UNREACHABLE' in d or 'rst:' in d:
        print('FAIL turn aborted'); sys.exit(1)
print('TIMEOUT'); sys.exit(1)
PYEOF
}

note "## console"
PORT=$(find_port)
if [ -n "${PORT:-}" ]; then note "console: $PORT"; else fail "no console port answers >status"; note "console: NONE"; fi
note ""

note "## typed turns"
if [ -n "${PORT:-}" ]; then
    for t in "What is the capital of France?" "天空为什么是蓝色的？" "한국의 수도는 어디야?"; do
        r=$(send_chat "$t") || true
        note "- ${t}: $r"
        case "$r" in OK\ *) ;;
          *) fail "turn failed: $t ($r)" ;;
        esac
    done
fi
note ""

note "## log signatures (this soak's window)"
if scan_signatures "$POS0" >> "$REPORT.tmp"; then
    note "clean"
else
    fail "failure signatures in the serial log (see above)"
fi
note ""

if [ ${#FAILURES[@]} -eq 0 ]; then
    note "**SOAK PASS**"
    echo "SOAK PASS $DATE" > "$OUT/latest-status"
    status=0
else
    note "**SOAK FAIL**: ${FAILURES[*]}"
    echo "SOAK FAIL $DATE: ${FAILURES[*]}" > "$OUT/latest-status"
    status=1
fi
mv "$REPORT.tmp" "$REPORT"
tail -1 "$OUT/latest-status"
exit $status

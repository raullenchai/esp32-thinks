# Soak testing

The gadget's worst bugs have all been long-tail: a wedged I2C bus surfaced
after 21 hours of healthy uptime, an I2S stall after days. Neither shows up in
a five-minute test session. The soak runs the opposite way — the device just
stays plugged in and a nightly script pokes it.

## What the nightly soak does

`scripts/soak.sh` (runs on the Jetson, or any Linux box the gadget is plugged
into):

1. hard-resets the device via the ROM bootloader (works even if the app is
   wedged — this is how the brick from a killed mid-flash esptool was
   recovered) and records the serial-log byte offset
2. waits for boot + Wi-Fi + brain warmup
3. finds the console port (enumeration order shuffles between replugs)
4. runs three typed turns — English, 中文, 한국어 — and records turn latency
5. scans the soak's slice of the serial log for failure signatures:
   `exp_read` spam (wedged I2C bus), panics, aborts, TLS handshake failures,
   coroner reboots
6. writes `~/soak/soak-YYYY-MM-DD.md` and `~/soak/latest-status`; exits 1 on
   any failure

The report from the 21-hour run that found the expander wedge is what became
v0.2.11.

## Install (Jetson)

```bash
scp scripts/soak.sh jetson:~/soak.sh
ssh jetson 'chmod +x ~/soak.sh'
# systemd units are in docs/soak/ — copy and enable
```

`soak.service` + `soak.timer` (nightly 04:00 America/Los_Angeles, `Persistent=true`
so a powered-off Jetson catches up on boot):

```bash
sudo cp docs/soak/soak.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now soak.timer
```

## Reading the results

- `SOAK PASS` — device healthy, turn latency recorded, log clean
- `SOAK FAIL` — the report names the failing turns and prints up to three
  matching log lines per signature; feed the report back into a fix

Turn latency thresholds: `MAX_TURN_S` (default 30 s) guards against regressions
much more gently than the release targets — the soak cares about *broken*, not
*slightly slow*.

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Measure the load while streaming: measure-load.py <label>.

Runs for 30 seconds, or MEASURE_SECONDS. Used for docs/performance.md.

CPU of the whole system and of Hermes, Xorg, GNOME Shell and Screen Spawner;
Intel GPU busy share (from RC6 idle residency) and frequency; CPU temperature;
Wi-Fi transmit rate; the stream as Hermes reports it. Appends to measurements.log.
"""
import glob
import json
import os
import ssl
import sys
import time
import urllib.request

SECONDS = int(os.environ.get("MEASURE_SECONDS", 30))
LOG = os.environ.get("MEASURE_LOG", "measurements.log")   # in the current directory
TICK = os.sysconf("SC_CLK_TCK")
CORES = os.cpu_count()
WATCH = {"Hermes": ("sunshine",), "Xorg": ("Xorg",), "GNOME Shell": ("gnome-shell",),
         "Screen Spawner": ("screen-spawner",)}


def processes():
    found = {}
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            stat = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
        except OSError:
            continue
        for name, keys in WATCH.items():
            if any(k in cmd.split(" ")[0] or (k == "screen-spawner" and "app/screen-spawner" in cmd) for k in keys):
                found[name] = found.get(name, 0) + int(stat[11]) + int(stat[12])
    return found


def system_cpu():
    v = list(map(int, open("/proc/stat").readline().split()[1:]))
    return sum(v), v[3] + v[4]


def gpu():
    base = next((os.path.dirname(p) for p in glob.glob("/sys/class/drm/card*/gt/gt0/rc6_residency_ms")), "")
    try:
        return int(open(f"{base}/rc6_residency_ms").read()), int(open(f"{base}/rps_act_freq_mhz").read())
    except OSError:
        return None, None


def cpu_temp():
    for hw in glob.glob("/sys/class/hwmon/hwmon*"):
        if open(f"{hw}/name").read().strip() == "coretemp":
            return int(open(f"{hw}/temp1_input").read()) / 1000
    return None


def wifi_tx():
    for line in open("/proc/net/dev"):
        name, data = line.split(":", 1) if ":" in line else ("", "")
        if name.strip().startswith("wl"):
            return int(data.split()[8])
    return 0


def metrics():
    try:
        runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        token = open(f"{runtime}/hermes/local-api.token").read().strip()
        ctx = ssl.create_default_context()
        ctx.check_hostname, ctx.verify_mode = False, ssl.CERT_NONE
        req = urllib.request.Request("https://localhost:47990/api/metrics",
                                     headers={"Authorization": "Bearer " + token})
        with urllib.request.urlopen(req, context=ctx, timeout=5) as r:
            return json.load(r)
    except Exception:
        return {}


def main():
    label = " ".join(sys.argv[1:]) or "unnamed"
    p0, s0, g0, tx0, t0 = processes(), system_cpu(), gpu(), wifi_tx(), time.monotonic()
    temps, freqs, samples = [], [], []
    for _ in range(SECONDS):
        time.sleep(1)
        temps.append(cpu_temp())
        freqs.append(gpu()[1])
        samples.append(metrics().get("pipeline") or {})
    p1, s1, g1, tx1, t1 = processes(), system_cpu(), gpu(), wifi_tx(), time.monotonic()
    wall = t1 - t0
    total, idle = s1[0] - s0[0], s1[1] - s0[1]
    lines = [f"=== {label} — {time.strftime('%Y-%m-%d %H:%M:%S')}, {wall:.0f} s, {CORES} threads"]
    lines.append(f"System CPU busy: {100 * (1 - idle / total):.1f}% of all threads")
    for name in WATCH:
        if name in p1:
            used = (p1[name] - p0.get(name, p1[name])) / TICK
            lines.append(f"  {name}: {100 * used / wall:.1f}% of one thread")
    if g0[0] is not None:
        busy = 100 * (1 - (g1[0] - g0[0]) / (wall * 1000))
        f = [x for x in freqs if x]
        lines.append(f"Intel GPU busy: {max(0, busy):.0f}%, frequency avg {sum(f) / max(1, len(f)):.0f} MHz, "
                     f"max {max(f or [0])} MHz")
    t = [x for x in temps if x]
    if t:
        lines.append(f"CPU temperature: avg {sum(t) / len(t):.0f} °C, max {max(t):.0f} °C")
    lines.append(f"Wi-Fi transmit: {8 * (tx1 - tx0) / wall / 1e6:.1f} Mbit/s")
    s = [x for x in samples if x]
    if s:
        avg = lambda k: sum(x.get(k, 0) for x in s) / len(s)
        last = s[-1]
        lines.append(f"Stream: {last.get('width')}×{last.get('height')}, {avg('fps'):.0f} fps, "
                     f"encode {avg('encode_ms'):.1f} ms, capture→encode {avg('capture_to_encode_ms'):.1f} ms, "
                     f"bitrate {avg('bitrate_kbps') / 1000:.1f} Mbit/s, dropped {last.get('frames_dropped')} "
                     f"of {last.get('frames_encoded')}")
    else:
        lines.append("Stream: no device connected (or Hermes not running)")
    text = "\n".join(lines)
    print(text)
    with open(LOG, "a") as f:
        f.write(text + "\n\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Measures every gun's own fire layers (addons/fc_weapons/assets/sounds/<gun>/{attack,body,tail_outdoor,far}_N.ogg) and
fails (exit 1) when a gun has no fire sound, a layer is silent or clipped, an attack starts late, or two guns share a sample.
Prints the guns ranked by loudness plus warnings (a tail cut off abruptly, a narrow or dull spectrum). Needs numpy and ffmpeg.
Run: python3 tools/audit_fire_sounds.py [--json OUT] [--quiet]
"""
import hashlib
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SND = os.path.join(HERE, "..", "addons", "fc_weapons", "assets", "sounds")
RATE = 44100
# Every key of AwWeaponPack.SOUND_CLASSES: each must have its own fire layers.
GUNS = ["pistol", "revolver", "derringer", "machine_pistol", "smg", "carbine", "rifle", "bullpup", "burst_rifle", "battle_rifle",
        "marksman", "lmg", "sniper", "shotgun", "drum_shotgun", "minigun", "launcher", "quad_launcher", "grenade_launcher", "beamer", "charge_rifle"]
LAYERS = ["attack", "body", "tail_outdoor", "far"]
CLIP_MAX = 3  # samples at full scale before a layer counts as clipped


def load(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"], capture_output=True).stdout
    return np.frombuffer(out, dtype=np.float32)


def db(x):
    return 20 * np.log10(max(float(x), 1e-9))


def measure(x):
    if len(x) < 64:
        return {"len": 0.0, "peak": -99.0, "rms": -99.0, "clip": 0, "dc": 0.0, "head_ms": 0.0, "end_db": -99.0, "centroid": 0.0, "lowhigh": 0.0}
    peak = float(np.max(np.abs(x)))
    head = int(np.argmax(np.abs(x) > max(peak * 0.01, 1e-4)))
    tail = x[-int(0.02 * RATE):]
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    centroid = float((spec * freqs).sum() / max(spec.sum(), 1e-9))
    low = float((spec[freqs < 400] ** 2).sum())
    high = float((spec[freqs > 2500] ** 2).sum())
    return {"len": len(x) / RATE, "peak": db(peak), "rms": db(np.sqrt(np.mean(x ** 2))), "clip": int(np.sum(np.abs(x) >= 0.999)),
            "dc": float(abs(np.mean(x))), "head_ms": head / RATE * 1000, "end_db": db(np.sqrt(np.mean(tail ** 2))) - db(peak),
            "centroid": centroid, "lowhigh": 10 * np.log10(max(low, 1e-12) / max(high, 1e-12))}


def main():
    fails, warns, rows, hashes, atk = [], [], [], {}, {}
    for gun in GUNS:
        near = {}
        for layer in LAYERS:
            n = 0
            while os.path.exists(os.path.join(SND, gun, "%s_%d.ogg" % (layer, n))):
                x = load(os.path.join(SND, gun, "%s_%d.ogg" % (layer, n)))
                m = measure(x)
                near[(layer, n)] = x
                tag = "%s/%s_%d" % (gun, layer, n)
                h = hashlib.sha1(np.round(x[:RATE] * 2000).astype(np.int16).tobytes()).hexdigest()
                if hashes.setdefault(h, gun) != gun:
                    fails.append("%s is the same sample as %s" % (tag, hashes[h]))
                if m["peak"] < -40:
                    fails.append("%s is silent (peak %.1f dB)" % (tag, m["peak"]))
                if m["clip"] > CLIP_MAX:
                    fails.append("%s is clipped (%d samples at full scale)" % (tag, m["clip"]))
                if m["dc"] > 0.01:
                    fails.append("%s has DC offset %.3f" % (tag, m["dc"]))
                if layer == "attack" and m["head_ms"] > 40:
                    fails.append("%s starts late (%.0f ms of silence)" % (tag, m["head_ms"]))
                if layer in ("tail_outdoor", "far") and m["end_db"] > -30:
                    warns.append("%s ends abruptly (%.0f dB under its peak at the cut)" % (tag, m["end_db"]))
                if layer == "attack" and n == 0:
                    atk[gun] = x[: int(0.3 * RATE)]
                n += 1
            if n == 0:
                fails.append("%s has no %s layer" % (gun, layer))
        parts = [near.get((l, 0)) for l in ("attack", "body", "tail_outdoor")]
        if all(p is not None for p in parts):
            mix = np.zeros(max(len(p) for p in parts), dtype=np.float32)
            for p in parts:
                mix[: len(p)] += p
            m = measure(mix)
            if m["centroid"] < 350:
                warns.append("%s is dull (spectral centroid %.0f Hz, no crack)" % (gun, m["centroid"]))
            if m["lowhigh"] > 25:
                warns.append("%s has almost no highs (low/high %.0f dB)" % (gun, m["lowhigh"]))
            rows.append((gun, m))
    names = list(atk)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = atk[names[i]], atk[names[j]]
            n = min(len(a), len(b))
            if n > 100 and a[:n].std() > 0 and b[:n].std() > 0 and abs(float(np.corrcoef(a[:n], b[:n])[0, 1])) > 0.95:
                fails.append("%s and %s attacks are near-identical" % (names[i], names[j]))
    if "--quiet" not in sys.argv:
        print("%-18s %6s %8s %8s %5s %9s %8s %8s" % ("gun", "len s", "peak dB", "rms dB", "clip", "centroid", "low/high", "end dB"))
        for gun, m in sorted(rows, key=lambda r: r[1]["rms"]):
            print("%-18s %6.2f %8.1f %8.1f %5d %9.0f %8.1f %8.1f" % (gun, m["len"], m["peak"], m["rms"], m["clip"], m["centroid"], m["lowhigh"], m["end_db"]))
    if "--json" in sys.argv:
        json.dump({g: m for g, m in rows}, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
    for w in warns:
        print("warn:", w)
    for f in fails:
        print("FAIL:", f)
    print("audit_fire_sounds: %d guns, %d failures, %d warnings" % (len(GUNS), len(fails), len(warns)))
    return 1 if fails else 0


sys.exit(main())

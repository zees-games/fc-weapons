#!/usr/bin/env python3
"""Cuts the owner's raw recordings (assets-src/user-sounds/, not shipped) into per-gun sounds under
addons/fc_weapons/assets/sounds/<gun>/: the handling cues (cue_<name>_<n>.ogg, the AwReloadCues and cycle cue names),
the minigun's spin_up / spin_loop / spin_down, and the single-shot takes tools/make_fire_sounds.py builds each gun's
layered report from (SHOTS below; it imports this module and uses user_takes()).

Every cut: mono, 44.1 kHz, the recording's own clipping kept at plus or minus full scale (the sources are decoded
past 1.0 by their codecs), DC removed, started 3 ms before the first transient, tail faded, then peak-normalised
(handling cues to a common loudest-100-ms RMS, CUE_RMS_DB, peak-capped at CUE_PEAK_DB). Times are seconds in the source file,
read off its waveform and spectrogram; to re-cut a sound, edit its row. The minigun loop is crossfaded onto its own head.

Needs numpy and ffmpeg. Run: python3 tools/cut_user_sounds.py [--no-fire]   (then make_fire_sounds.py for the guns)
"""
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "assets-src", "user-sounds")
OUT = os.path.join(HERE, "..", "addons", "fc_weapons", "assets", "sounds")
RATE = 44100
CUE_RMS_DB = -24.0  # loudest 100 ms of every cue, so a click and a thump sound as loud as each other
CUE_PEAK_DB = -4.0  # but never past this, a vorbis overshoot included
LOOP_PEAK_DB = -3.0

# gun: (file, [(start, end), ...]) single shots, each ending before the next event; the first is the near take of
# make_fire_sounds.py, the second (or the first again) its mid-distance one.
SHOTS = {
    "rifle": ("ak47-sfx.mp3", [(5.25, 7.31), (7.94, 10.0)]),
    "battle_rifle": ("battlrifle_fire.ogg", [(0.0, 1.6)]),
    "burst_rifle": ("burst_fire.wav", [(0.03, 1.58), (1.93, 2.99)]),
    "drum_shotgun": ("drumshotgun_fire.wav", [(0.0, 1.29)]),
    "lmg": ("machinegun_fire.ogg", [(0.0, 0.3)]),
    "marksman": ("marksman_sfx.mp3", [(0.38, 1.70), (1.99, 3.8)]),
    "sniper": ("sniper_fire.flac", [(0.38, 5.6)]),
    "shotgun": ("shotgun_sounds.mp3", [(5.50, 6.75), (7.84, 9.1)]),
    "revolver": ("revolver_shots.wav", [(1.0 - 0.01, 1.93), (1.93, 2.95)]),
}

# (gun, cue, source, [(start, end), ...]): one file per window, cue_<cue>_<n>.ogg in order.
CUES = [
    # Mosin-Nagant: five bolt cycles; the second to fourth are single clean ones: lift, back, forward, down.
    ("sniper", "bolt_lift", "Mosin-Nagant_bolt.wav", [(5.76, 5.99), (7.63, 7.89), (0.38, 0.62), (11.62, 11.90), (13.55, 13.78)]),
    ("sniper", "bolt_back", "Mosin-Nagant_bolt.wav", [(3.60, 4.15), (6.00, 6.43), (7.87, 8.29), (0.75, 1.10), (12.20, 12.62), (13.80, 13.98)]),
    ("sniper", "bolt_fwd", "Mosin-Nagant_bolt.wav", [(4.24, 4.70), (6.43, 6.71), (8.32, 8.59)]),
    ("sniper", "bolt_down", "Mosin-Nagant_bolt.wav", [(4.79, 5.20), (6.73, 7.05), (8.60, 8.93), (1.14, 1.45), (12.70, 13.05), (14.00, 14.30)]),
    # shotgun_pumps: each pump is a back click then a forward click ~0.3-0.5 s later.
    ("shotgun", "pump_back", "shotgun_pumps.aiff", [(0.245, 0.55), (1.71, 2.16), (3.19, 3.43), (4.195, 4.44), (5.145, 5.42)]),
    ("shotgun", "pump_fwd", "shotgun_pumps.aiff", [(0.555, 0.90), (2.175, 2.62), (3.44, 3.78), (4.455, 4.80), (5.43, 5.78)]),
    # AK handling (ak47-sfx.mp3 between the two shots): the magazine out and in, then the charging handle. The split of
    # the clicks into cues is a guess from the onsets (ear review pending, nightly weapon-sounds-owner-1).
    ("rifle", "mag_out", "ak47-sfx.mp3", [(2.93, 3.20)]),
    ("rifle", "mag_seat", "ak47-sfx.mp3", [(3.27, 3.50)]),
    ("rifle", "charge_back", "ak47-sfx.mp3", [(4.34, 4.47)]),
    ("rifle", "charge_fwd", "ak47-sfx.mp3", [(4.47, 4.62)]),
    # shotgun_sounds.mp3: seven shells going in, one every 0.5335 s from 1.229.
    ("shotgun", "shell_load", "shotgun_sounds.mp3", [(1.229 + k * 0.5335 - 0.02, 1.229 + k * 0.5335 + 0.30) for k in range(7)]),
    # Revolver: the first recording is a cylinder open, a dump and five rounds going in; the second is long handling
    # noise, its clearest clicks are used for the close, twist and a second open and dump.
    ("revolver", "cyl_open", "revolver_reload.wav", [(0.66, 0.92)]),
    ("revolver", "cyl_open", "revolver_reload2.wav", [(4.92, 5.10)]),
    ("revolver", "cyl_dump", "revolver_reload.wav", [(1.55, 1.95)]),
    ("revolver", "cyl_dump", "revolver_reload2.wav", [(17.40, 17.65)]),
    ("revolver", "round_tick", "revolver_reload.wav", [(2.44, 2.60), (3.43, 3.59), (4.37, 4.55), (5.32, 5.50), (6.29, 6.47)]),
    ("revolver", "round_tick", "revolver_reload2.wav", [(8.47, 8.62), (8.77, 8.92), (9.88, 10.03), (12.85, 13.0), (15.38, 15.53), (16.33, 16.48)]),
    ("revolver", "cyl_close", "revolver_reload2.wav", [(14.28, 14.80), (25.77, 25.99)]),
    ("revolver", "cyl_twist", "revolver_reload2.wav", [(9.23, 9.40)]),
]

# minigun_fire.wav: 0-4 s steady fire; 8-13 s fire that ramps in within a quarter second and winds down after 12 s.
MINIGUN_FILE = "minigun_fire.wav"
MINIGUN_UP = (7.99, 8.60)
MINIGUN_LOOP = (0.40, 3.90)  # 3.5 s of steady fire, the last LOOP_XFADE crossfaded onto the first
LOOP_XFADE = 0.30
MINIGUN_DOWN = (11.95, 12.95)

_cache = {}


def load(name):
    """The file as mono float at RATE, clipped to full scale, DC removed."""
    if name not in _cache:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(SRC, name), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                             check=True, capture_output=True).stdout
        x = np.clip(np.frombuffer(raw, dtype=np.float32).astype(np.float64), -1.0, 1.0)
        _cache[name] = x - np.mean(x)
    return _cache[name]


def window(name, t0, t1):
    x = load(name)
    return x[int(t0 * RATE): int(t1 * RATE)].copy()


def onset(x, frac=0.12, pre_ms=3.0):
    """Index of the first sample above [param frac] of the peak, less [param pre_ms]."""
    i = int(np.argmax(np.abs(x) > frac * np.max(np.abs(x))))
    return max(i - int(pre_ms / 1000.0 * RATE), 0)


def fade_tail(x, ms):
    f = min(int(ms / 1000.0 * RATE), len(x) // 2)
    x[-f:] *= np.linspace(1.0, 0.0, f) ** 2
    return x


def scale_peak(x, db):
    return x * (10 ** (db / 20.0) / (np.max(np.abs(x)) + 1e-9))


def write_ogg(path, x):
    raw = (np.clip(x, -1.0, 1.0) * 32767).astype("<i2").tobytes()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", "-f", "ogg", path + ".tmp"], input=raw, check=True)
    os.replace(path + ".tmp", path)  # a rename, so a file another user owns in a shared folder is still replaced


def user_takes(gun):
    """The gun's single-shot takes as float arrays (clipped, DC removed, tail faded), or an empty list."""
    if gun not in SHOTS:
        return []
    name, wins = SHOTS[gun]
    return [fade_tail(window(name, a, b), 30.0) for a, b in wins]


def loud_db(x):
    """The loudest 100 ms of [param x] in dB RMS: a short click has no gated LUFS (ebur128 reads -70), so cues are matched on this."""
    h = int(0.1 * RATE)
    return max(20.0 * np.log10(np.sqrt(np.mean(x[i:i + h] ** 2)) + 1e-9) for i in range(0, max(1, len(x) - h // 2), h // 2))


def scale_loud(x, rms_db, peak_db):
    """Gain x so its loudest 100 ms sits at rms_db, unless that puts the peak over peak_db (then the peak wins)."""
    gain = 10 ** ((rms_db - loud_db(x)) / 20.0)
    return x * min(gain, 10 ** (peak_db / 20.0) / (np.max(np.abs(x)) + 1e-9))


def cue(x):
    x = x[onset(x):]
    return scale_loud(fade_tail(x, min(60.0, 0.3 * len(x) / RATE * 1000.0)), CUE_RMS_DB, CUE_PEAK_DB)


def make_cues():
    counts = {}
    for gun, name, src, wins in CUES:
        n = counts.get((gun, name), 0)
        for a, b in wins:
            write_ogg(os.path.join(OUT, gun, "cue_%s_%d.ogg" % (name, n)), cue(window(src, a, b)))
            n += 1
        counts[(gun, name)] = n
    return counts


def make_minigun():
    folder = os.path.join(OUT, "minigun")
    up = window(MINIGUN_FILE, *MINIGUN_UP)
    up[: int(0.004 * RATE)] *= np.linspace(0.0, 1.0, int(0.004 * RATE))
    write_ogg(os.path.join(folder, "spin_up.ogg"), scale_peak(fade_tail(up, 40.0), LOOP_PEAK_DB))
    # The loop: [n] samples that play on, then the crossfade region fading the same fire out under the head fading in,
    # so the last sample is followed by what the source would have played next.
    a, b = MINIGUN_LOOP
    x = window(MINIGUN_FILE, a, b)
    xf = int(LOOP_XFADE * RATE)
    n = len(x) - xf
    t = np.linspace(0.0, np.pi / 2.0, xf)
    loop = x[:n].copy()
    loop[:xf] = loop[:xf] * np.sin(t) + x[n:] * np.cos(t)
    write_ogg(os.path.join(folder, "spin_loop.ogg"), scale_peak(loop, LOOP_PEAK_DB))
    down = window(MINIGUN_FILE, *MINIGUN_DOWN)
    write_ogg(os.path.join(folder, "spin_down.ogg"), scale_peak(fade_tail(down, 80.0), LOOP_PEAK_DB))
    return len(loop) / RATE


if __name__ == "__main__":
    c = make_cues()
    print("cues:", ", ".join("%s/%s x%d" % (g, n, k) for (g, n), k in sorted(c.items())))
    print("minigun loop %.3f s" % make_minigun())

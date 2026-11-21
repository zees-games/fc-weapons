#!/usr/bin/env python3
"""Builds each gun's own layered fire sound (attack, body, open-air tail, far) from the CC0 Free Firearm Sound
Library recordings, with the layer splitting, tails and levels of gs-audio's tools/make_shot_layers.py, which this
runs rather than copies. Heavy guns get a generated low thump under the body. Two variants per gun: the take, and
the same take a few percent lower with its own tail seeds. Room tails stay the stock class's (AwShotLayers).

The launchers and energy guns have no firearm recording: the rocket launchers layer a pitched-down shotgun blast with a
generated thump and two CC0 OpenGameArt rocket recordings (fetched into tools/sound_sources/, which is not committed);
the grenade launcher's tube pop, the plasma bolt and the rail shot are generated here over library takes. Bodies and
far reports are then levelled to a per-gun loudness (LEVELS) under a soft limiter, so a gun's weight no longer hangs
on its take's crest factor.

Needs numpy, scipy, ffmpeg and 7z. Run: python3 tools/make_fire_sounds.py [gun ...]  (default: every gun below).
"""
import os
import subprocess
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GS_AUDIO = os.environ.get("GS_AUDIO", os.path.join(HERE, "..", "..", "gs-audio"))
if not os.path.isdir(os.path.join(GS_AUDIO, "tools")):
    GS_AUDIO = "/home/gamedev/godot/gs-audio"
LIB = os.path.join(GS_AUDIO, "source-candidates", "free-firearm-sound-library", "raw", "Prepared SFX Library")
OUT = os.path.join(HERE, "..", "addons", "fc_weapons", "assets", "sounds")

# Its helpers in their own namespace, so its OUT (gs-audio's stock folder) can never be where this writes; a checkout
# older than its main guard ends in a bare main() call, cut off here.
_src = open(os.path.join(GS_AUDIO, "tools", "make_shot_layers.py")).read()
if _src.rstrip().endswith("\nmain()"):
    _src = _src[: _src.rindex("\nmain()")]
L = {"__name__": "make_shot_layers", "__file__": os.path.join(GS_AUDIO, "tools", "make_shot_layers.py")}
exec(compile(_src, "make_shot_layers.py", "exec"), L)
RATE = L["RATE"]
sys.path.insert(0, os.path.join(GS_AUDIO, "tools"))
import audit_weapon_audio  # noqa: E402  (gs-audio's loudness meter, the one its audit reports in)
from scipy import signal  # noqa: E402

SRC = os.path.join(HERE, "sound_sources")
# name: (url, file inside the download); both CC0 on OpenGameArt (licence.json, CREDITS.md)
FETCH = {
    "missile": ("https://opengameart.org/sites/default/files/missile.wav", "missile.wav"),
    "launch": ("https://opengameart.org/sites/default/files/launch.7z", "launch/launch.wav"),
}

# gun: (library folder, near take, mid-distance take, thump Hz or 0, variant 1 pitch)
GUNS = {
    "sniper": ("Tikka", "W_29P", "W_24P", 48.0, 0.95),
    "marksman": ("Arisaka", "E_25P", "E_18P", 55.0, 0.96),
    "battle_rifle": ("1917", "B_24P", "B_16P", 55.0, 0.96),
    "rifle": ("AK-47", "C_28P", "C_31P", 0.0, 0.96),
    "bullpup": ("AR-15", "D_32P", "D_24P", 0.0, 0.97),
    "carbine": ("Savage 10 .300 Blackout", "T_27P", "T_17P", 0.0, 0.97),
    "burst_rifle": ("SKS", "U_14P", "U_19P", 0.0, 0.97),
    "lmg": ("Mosin Nagant", "M_21P", "M_26P", 60.0, 0.97),
    "shotgun": ("Nova", "O_21P", "O_17P", 52.0, 0.95),
    "drum_shotgun": ("Mossberg", "N_30P", "N_26P", 58.0, 0.97),
    "pistol": ("Walther PPQ", "X_39P", "X_31P", 0.0, 0.96),
    "machine_pistol": ("Bersa", "F_47P", "F_41P", 0.0, 0.97),
    "derringer": ("Smith & Wesson 642", "V_27P", "V_22P", 0.0, 0.96),
    "revolver": ("1911", "A_42P", "A_34P", 0.0, 0.95),
    "smg": ("Carl Gustav M45", "G_31P", "G_20P", 0.0, 0.97),
    "minigun": ("PPSh", "P_30P", "P_16P", 0.0, 0.98),
}
# The guns built from generated and rocket material over library takes: gun -> (builder, variant 1 pitch).
MADE = {
    "launcher": ("rocket", 0.95),
    "quad_launcher": ("quad_rocket", 0.96),
    "grenade_launcher": ("tube_pop", 0.94),
    "beamer": ("plasma", 0.94),
    "charge_rifle": ("rail", 0.95),
}
VARIANTS = 2
MID_LIFT_DB = 12.0  # on the guns with a generated thump, whose bodies were sub-bass only (mid 18 dB under the low band)
# Small guns whose takes have no low end (low band 15-30 dB under the mid): a higher thump, no mid lift, at
# (Hz, its energy in dB against the body's own 200 Hz - 3 kHz band), so it rounds the report out without booming.
SMALL_THUMP = {"derringer": (90.0, -6.0), "revolver": (68.0, -2.0), "smg": (82.0, -5.0), "burst_rifle": (72.0, -3.0),
               "minigun": (78.0, -4.0)}
# Active loudness (LUFS) of each gun's body and far report; None keeps the take's own level. The far reports sat
# 8-10 dB under the stock classes' and now step by size: sidearms, carbines and rifles, heavy guns, launchers.
LEVELS = {
    "derringer": (-21.0, -28.0), "pistol": (None, -27.0), "revolver": (-18.0, -26.0), "machine_pistol": (None, -27.0),
    "smg": (-19.0, -27.0), "carbine": (None, -26.0), "rifle": (None, -25.0), "bullpup": (None, -25.0),
    "burst_rifle": (-18.0, -25.0), "battle_rifle": (None, -24.0), "marksman": (None, -24.0), "lmg": (None, -24.0),
    "sniper": (None, -23.0), "shotgun": (None, -24.0), "drum_shotgun": (None, -24.0), "minigun": (-17.0, -24.0),
    "launcher": (-16.0, -22.0), "quad_launcher": (-16.0, -22.0), "grenade_launcher": (-19.0, -26.0),
    "beamer": (-17.0, -25.0), "charge_rifle": (-15.0, -22.0),
}
CEILING = 0.89  # -1 dBFS, the peak every layer was written at before
MADE_ATTACK_DB = -13.5  # the made guns' first 50 ms, at the firearm takes' attack loudness (-13 to -16 LUFS)


def thump(n, hz, seed):
    """A falling low sine, the chest punch a recording at a distance loses; generated here, so no licence."""
    t = np.arange(n) / RATE
    rng = np.random.default_rng(seed)
    f = hz * (1.0 + 0.6 * np.exp(-t / 0.02)) * rng.uniform(0.97, 1.03)
    y = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.11)
    return y * L["ramp"](n, 0, int(0.003 * RATE))


def mid_lift(body, db):
    """The recording's own 200 Hz - 3 kHz content of the body raised by [param db]: after the first 50 ms a close take
    keeps its sub rumble but loses the blast's mid, which is what leaves a heavy gun sounding hollow. No new material."""
    spec = np.fft.rfft(body)
    freq = np.fft.rfftfreq(len(body), 1.0 / RATE)
    band = ((freq >= 200.0) & (freq <= 3000.0)).astype(float)
    mid = np.fft.irfft(spec * band, len(body))
    return body + mid * (10 ** (db / 20.0) - 1.0)


def band_energy(x, lo, hi):
    spec = np.abs(np.fft.rfft(x)) ** 2
    freq = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return float(np.sum(spec[(freq >= lo) & (freq < hi)])) + 1e-12


def pitched(x, factor):
    """[param x] played [param factor] times as fast (below 1 is lower and longer)."""
    if factor == 1.0:
        return x
    src = np.arange(0, len(x) - 1, factor)
    return np.interp(src, np.arange(len(x)), x)


def lufs(y):
    return audit_weapon_audio.measure(y.astype(np.float32))["lufs_active"]


def levelled(y, target):
    """[param y] at [param target] active LUFS, its peaks held under CEILING by a tanh limiter rather than the whole
    layer turned down, so a spiky take still reaches its loudness. A few passes, as limiting costs a little level."""
    y = y / (np.max(np.abs(y)) + 1e-9) * CEILING
    if target is None:
        return y
    for _ in range(4):
        y = CEILING * np.tanh(y * 10 ** ((target - lufs(y)) / 20.0) / CEILING)
    return y


def save(path, y):
    """Writes [param y] at its own peak, as make_shot_layers' write() scales to the peak it is given."""
    L["write"](path, y, 20 * np.log10(np.max(np.abs(y - np.mean(y))) + 1e-9))


def source(name):
    """A CC0 recording from FETCH, downloaded and unpacked into SRC on first use."""
    url, inner = FETCH[name]
    folder = os.path.join(SRC, name)
    path = os.path.join(folder, inner)
    if not os.path.exists(path):
        os.makedirs(folder, exist_ok=True)
        archive = os.path.join(folder, url.rsplit("/", 1)[1])
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req) as r, open(archive, "wb") as f:
            f.write(r.read())
        if archive.endswith(".7z"):
            subprocess.run(["7z", "x", "-y", "-o" + folder, archive], check=True, capture_output=True)
    return L["load"](path)


def take(folder_name, name):
    return L["trim"](L["load"](os.path.join(LIB, folder_name, name + ".wav")))


def band(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (RATE / 2), hi / (RATE / 2)], "band")
    return signal.lfilter(b, a, x)


def lowpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (RATE / 2), "low")
    return signal.lfilter(b, a, x)


def decay(n, tau, attack=0.002):
    return np.exp(-np.arange(n) / RATE / tau) * L["ramp"](n, 0, max(int(attack * RATE), 1))


def fit(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


def motor_whir(n, seed):
    """The minigun's barrel motor: a steady band of noise round 500 Hz with a faint barrel buzz, flat across the body
    with soft ends, so the bodies of back-to-back shots overlap into one continuous spin. Generated, no licence."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / RATE
    noise = band(rng.standard_normal(n), 300.0, 900.0)
    tone = sum(np.sin(2 * np.pi * f * t * rng.uniform(0.99, 1.01)) / k for k, f in enumerate((300.0, 600.0, 900.0), 1))
    y = norm(noise) * (1.0 + 0.3 * np.sin(2 * np.pi * 50.0 * t)) + 0.25 * norm(tone)
    return norm(y) * L["ramp"](n, 0, int(0.06 * RATE)) * (1.0 - L["ramp"](n, n - int(0.12 * RATE), n))


def rocket(factor, n_var):
    """A shoulder rocket: the back-blast (a pump gun's take a fifth lower, so bigger), a deep thump, and the motor's
    roar lighting a few ms later and fading over a second as the rocket leaves. Returns the near shot and far source."""
    n = int(1.6 * RATE)
    blast = fit(pitched(norm(take("Nova", "O_21P")), 0.8 * factor), n)
    roar = lowpass(fit(source("launch")[int(2.2 * RATE):], n), 5000.0) * decay(n, 0.45, 0.03)
    roar = np.roll(roar, int(0.015 * RATE))
    x = blast + 0.5 * thump(n, 42.0 * factor, 300 + n_var) + 0.45 * norm(roar)
    far = fit(pitched(norm(take("Nova", "O_17P")), 0.8 * factor), n) + 0.5 * norm(lowpass(roar, 900.0))
    return norm(x), norm(far)


def quad_rocket(factor, n_var):
    """The quad launcher: a heavier pump gun's blast, lower still, and the whoosh of a missile clearing the tubes."""
    n = int(1.6 * RATE)
    blast = fit(pitched(norm(take("Mossberg", "N_30P")), 0.82 * factor), n)
    whoosh = fit(source("missile")[int(0.35 * RATE):], n) * decay(n, 0.6, 0.02)
    roar = lowpass(fit(source("launch")[int(3.6 * RATE):], n), 5000.0) * decay(n, 0.35, 0.03)
    x = blast + 0.45 * thump(n, 46.0 * factor, 310 + n_var) + 0.4 * norm(whoosh) + 0.3 * norm(roar)
    far = fit(pitched(norm(take("Mossberg", "N_26P")), 0.82 * factor), n) + 0.4 * norm(lowpass(whoosh + roar, 900.0))
    return norm(x), norm(far)


def tube_pop(factor, n_var):
    """A 40 mm grenade launcher's hollow "thoomp": a low falling bloop from the tube, a short dull puff of gas, and a
    pump gun's report filtered to its low body for the mechanism. No supersonic crack: the grenade is slow."""
    n = int(1.6 * RATE)
    rng = np.random.default_rng(320 + n_var)
    t = np.arange(n) / RATE
    f = (95.0 + 90.0 * np.exp(-t / 0.025)) * factor
    bloop = np.sin(2 * np.pi * np.cumsum(f) / RATE) * decay(n, 0.09, 0.003)
    puff = band(rng.standard_normal(n), 200.0, 1400.0) * decay(n, 0.04, 0.001)
    gun = lowpass(fit(pitched(norm(take("Model 12", "K_22P")), 0.9 * factor), n), 1600.0, 3)
    x = 0.8 * norm(bloop) + 0.7 * norm(puff) + 0.6 * norm(gun)
    far = norm(bloop) + 0.5 * norm(lowpass(fit(pitched(norm(take("Model 12", "K_17P")), 0.9 * factor), n), 500.0, 3))
    return norm(x), norm(far)


def plasma(factor, n_var):
    """A plasma bolt: a bright falling chirp overdriven so it buzzes, a crackle of high noise, a low hum and punch."""
    n = int(1.6 * RATE)
    rng = np.random.default_rng(330 + n_var)
    t = np.arange(n) / RATE
    f = (520.0 + 2300.0 * np.exp(-t / 0.035)) * factor * (1.0 + 0.03 * np.sin(2 * np.pi * 38.0 * t))
    chirp = np.tanh(3.0 * np.sin(2 * np.pi * np.cumsum(f) / RATE)) * decay(n, 0.05, 0.001)
    crackle = band(rng.standard_normal(n) * (rng.random(n) < 0.08), 2500.0, 8000.0) * decay(n, 0.05, 0.0005)
    hum = np.sin(2 * np.pi * 110.0 * factor * t) * decay(n, 0.06, 0.004)
    x = norm(chirp) + 0.5 * norm(crackle) + 0.45 * hum + 0.3 * thump(n, 70.0 * factor, 330 + n_var)
    return norm(x), norm(x)


def rail(factor, n_var):
    """A rail shot: a sniper rifle's crack for the weight, an electric snap, a ringing metallic shimmer as the rails
    discharge, a deep thump and a falling whoosh of air behind the slug."""
    n = int(1.6 * RATE)
    rng = np.random.default_rng(340 + n_var)
    t = np.arange(n) / RATE
    crack = fit(pitched(norm(take("Tikka", "W_29P")), factor), n)
    snap = band(rng.standard_normal(n), 3000.0, 12000.0) * decay(n, 0.006, 0.0003)
    ring = sum(np.sin(2 * np.pi * h * factor * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
               for h, d in ((1180.0, 0.2), (2930.0, 0.15), (4710.0, 0.1), (6250.0, 0.07)))
    ring = norm(ring) * L["ramp"](n, 0, int(0.002 * RATE))
    sweep = 200.0 + 3000.0 * np.exp(-t / 0.25)
    noise = rng.standard_normal(n)
    whoosh = np.zeros(n)
    for k in range(0, n, 2048):
        whoosh[k:k + 2048] = band(noise[k:k + 2048], max(sweep[k] * 0.5, 80.0), sweep[k] * 1.5)
    whoosh *= decay(n, 0.3, 0.02)
    x = 0.8 * crack + 0.6 * norm(snap) + 0.25 * ring + 0.5 * thump(n, 50.0 * factor, 340 + n_var) + 0.35 * norm(whoosh)
    far = fit(pitched(norm(take("Tikka", "W_24P")), factor), n) + 0.12 * ring
    return norm(x), norm(far)


def build(gun):
    folder = os.path.join(OUT, gun)
    os.makedirs(folder, exist_ok=True)
    body_db, far_db = LEVELS.get(gun, (None, None))
    hz = 0.0
    if gun in MADE:
        maker, low = MADE[gun]
    else:
        folder_name, near, mid, hz, low = GUNS[gun]
        base = take(folder_name, near)
        far_src = take(folder_name, mid)
    for n in range(VARIANTS):
        factor = 1.0 if n == 0 else low
        if gun in MADE:
            x, f = globals()[maker](factor, n)
        else:
            x = norm(pitched(base, factor))
            f = norm(pitched(far_src, factor))
        attack, body, late = L["split"](x)
        if hz > 0.0:
            body = mid_lift(body, MID_LIFT_DB) + 0.3 * thump(len(body), hz * factor, 90 + n)
        elif gun in SMALL_THUMP:
            t_hz, t_db = SMALL_THUMP[gun]
            boom = thump(len(body), t_hz * factor, 90 + n)
            body = body + boom * np.sqrt(band_energy(body, 200.0, 3000.0) / band_energy(boom, 20.0, 200.0) * 10 ** (t_db / 10.0))
        if gun == "minigun":
            body = body + 0.12 * motor_whir(len(body), 600 + n)
        save(os.path.join(folder, "attack_%d.ogg" % n), levelled(attack, MADE_ATTACK_DB if gun in MADE else None))
        save(os.path.join(folder, "body_%d.ogg" % n), levelled(body, body_db))
        L["write"](os.path.join(folder, "tail_outdoor_%d.ogg" % n), L["outdoor_for"](x, late, 700 + n), L["OUTDOOR_DB"])
        save(os.path.join(folder, "far_%d.ogg" % n), levelled(L["far_for"](f, 40 + n), far_db))
    print(gun, VARIANTS, "variants")


for g in sys.argv[1:] or list(GUNS) + list(MADE):
    build(g)

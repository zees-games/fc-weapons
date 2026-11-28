"""Models this pack's own-work grenade launcher (CC0, modelled here from scratch) as a source GLB for the shared texture bake.
Run: blender -b -P tools/build_launchers.py -- <out dir> [<name>...]   (no names: all)
grenade_launcher: a six-shot revolving 40 mm launcher. Origin at the grip, muzzle toward -Z, bore 0.10 m above the grip like the model
it replaces (so the view hold, the muzzle and the reload anchors keep their numbers):
  frame        receiver block over the grip, a top strap over the cylinder to the barrel trunnion, a bottom strap and front bearing
  cylinder     fluted six-chamber drum on a centre spindle; each chamber mouth is open (dark bore, brass case head) on the rear face,
               with a cam groove band around the drum
  barrel       rifled tube with a muzzle ring inside a four-rail handguard (picatinny on the top, sides and bottom), vertical foregrip
  controls     pistol grip with finger grooves and a backstrap, trigger in a guard, safety lever, cylinder release, sling loops
  stock        a telescoping tube stock with a cheek riser and a rubber butt pad
  sights       flip-up irons at both rail ends; the red dot is the view runtime's (aw_sight_fit.gd), seated on the top rail by the aim
Colours are picked for the bake's classes (tex_gen.py classify reads the sRGB albedo): steel grey reads as metal, near-black as
polymer, olive as coat. Output: <out>/<name>.glb. Textures: addons/gs_weapon/tools/texbake/tex_pipeline.sh."""
import bpy, sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import blender_mesh_kit as kit  # noqa: E402
from blender_mesh_kit import Mesh, lathe, chamfered_tube, chamfered_ring, box, screw, build  # noqa: E402

kit.MATS.update({
    'steel': ((0.30, 0.30, 0.31), 0.75, 0.4), 'park': ((0.10, 0.10, 0.10), 0.5, 0.55), 'grip': ((0.018, 0.018, 0.02), 0.0, 0.75),
    'od': ((0.12, 0.14, 0.07), 0.1, 0.6), 'core': ((0.012, 0.012, 0.013), 0.0, 0.9), 'rubber': ((0.01, 0.01, 0.01), 0.0, 0.95),
})
SEG = 32
BORE_Y = 0.10          # bore height above the grip origin (the replaced model's muzzle_offset.y)
MUZZLE_Z = -0.522      # the replaced model's muzzle distance
AXIS_Y = 0.032         # cylinder axis
PITCH = BORE_Y - AXIS_Y  # chamber circle radius: the top chamber lines up with the bore
DRUM_R = 0.112
DRUM_Z0, DRUM_Z1 = -0.130, -0.300   # rear and front faces of the cylinder
RAIL_Y = 0.178         # top rail base


def bx(lo, hi, mat, bevel=None):
    """A bevelled box between two corners (Godot space)."""
    s = [hi[i] - lo[i] for i in range(3)]
    c = [(hi[i] + lo[i]) / 2 for i in range(3)]
    return box(s[0], s[1], s[2], mat, bevel).xf(None, c)


def tube_z(r, z0, z1, mat, at=(0, 0), segs=SEG, c=None, teeth=0, depth=0.0):
    """A solid chamfered tube along Z from z0 (rear, larger) to z1 (front)."""
    return chamfered_tube(r, r, z0 - z1, mat, c, segs, teeth, depth).xf(None, (at[0], at[1], (z0 + z1) / 2))


def ring_z(r_out, r_in, z0, z1, mat, at=(0, 0), segs=SEG):
    return chamfered_ring(r_out, z0 - z1, r_in, mat, None, segs).xf(None, (at[0], at[1], (z0 + z1) / 2))


def rail(z0, z1, at, normal, mat='park', width=0.021):
    """A picatinny rail: a base with cross slots (teeth), along Z, facing `normal` ('up', 'left', 'right', 'down')."""
    ms = []
    n = max(2, int(round((z0 - z1) / 0.01)))
    step = (z0 - z1) / n
    for face in ([bx((-width / 2, 0.0, z1), (width / 2, 0.004, z0), mat)] +
                 [bx((-width / 2 - 0.002, 0.004, z0 - (k + 0.15) * step), (width / 2 + 0.002, 0.0085, z0 - (k + 0.85) * step), mat, 0.0006)
                  for k in range(n)]):
        rotn = {'up': None, 'down': [('z', 180)], 'left': [('z', 90)], 'right': [('z', -90)]}[normal]
        ms.append(face.xf(rotn, at))
    return ms


def drum():
    ms = []
    # fluted body: six shallow flutes between the chambers, a cam-groove band, chamfered faces
    ms.append(tube_z(DRUM_R, DRUM_Z0, DRUM_Z1, 'steel', (0, AXIS_Y), 48, 0.006, teeth=6, depth=0.06).xf([('z', 0)]))
    ms.append(ring_z(DRUM_R + 0.002, DRUM_R - 0.004, -0.196, -0.214, 'park', (0, AXIS_Y), 48))
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        cx, cy = PITCH * math.cos(a), AXIS_Y + PITCH * math.sin(a)
        # chamber mouth on the rear face: dark bore inside a raised lip; a brass case head in all but the top (fired) one
        ms.append(ring_z(0.026, 0.021, DRUM_Z0 + 0.003, DRUM_Z0 - 0.004, 'steel', (cx, cy), 24))
        ms.append(tube_z(0.021, DRUM_Z0 - 0.002, DRUM_Z0 - 0.030, 'core', (cx, cy), 24))
        if k:
            ms.append(tube_z(0.0205, DRUM_Z0 - 0.003, DRUM_Z0 - 0.007, 'brass', (cx, cy), 24, 0.0008))
            ms.append(tube_z(0.004, DRUM_Z0 - 0.0025, DRUM_Z0 - 0.004, 'nickel', (cx, cy), 12))
        # chamber mouth on the front face
        ms.append(ring_z(0.025, 0.021, DRUM_Z1 + 0.004, DRUM_Z1 - 0.002, 'steel', (cx, cy), 24))
        ms.append(tube_z(0.021, DRUM_Z1 + 0.030, DRUM_Z1 - 0.001, 'core', (cx, cy), 24))
    # spindle through the centre, ratchet star on the rear face
    ms.append(tube_z(0.013, DRUM_Z0 + 0.012, DRUM_Z1 - 0.024, 'nickel', (0, AXIS_Y), 20))
    ms.append(tube_z(0.022, DRUM_Z0 + 0.004, DRUM_Z0 - 0.002, 'steel', (0, AXIS_Y), 12, teeth=6, depth=0.25))
    return ms


def barrel():
    ms = []
    # trunnion block the top strap and the bottom strap meet; the barrel and handguard hang off it
    ms.append(bx((-0.045, AXIS_Y - 0.035, DRUM_Z1 - 0.004), (0.045, RAIL_Y, DRUM_Z1 - 0.040), 'park', 0.003))
    ms.append(tube_z(0.031, DRUM_Z1 - 0.030, MUZZLE_Z + 0.012, 'steel', (0, BORE_Y), 32))
    ms.append(ring_z(0.035, 0.0215, MUZZLE_Z + 0.014, MUZZLE_Z, 'park', (0, BORE_Y), 32))
    ms.append(tube_z(0.0215, MUZZLE_Z + 0.06, MUZZLE_Z + 0.002, 'core', (0, BORE_Y), 24, teeth=8, depth=0.05))
    # handguard: an open-sided box of four plates around the barrel, rails on all four faces, vent slots between
    z0, z1 = DRUM_Z1 - 0.040, MUZZLE_Z + 0.048
    hw, y0, y1 = 0.040, BORE_Y - 0.042, BORE_Y + 0.042
    ms.append(bx((-hw, y1 - 0.006, z0), (hw, y1, z1), 'park', 0.002))
    ms.append(bx((-hw, y0, z0), (hw, y0 + 0.006, z1), 'park', 0.002))
    for sx in (-1, 1):
        ms.append(bx((sx * hw - 0.003, y0, z0), (sx * hw + 0.003, y1, z1), 'park', 0.0015).xf(None))
        for k in range(4):
            zc = z0 - 0.03 - k * 0.04
            ms.append(bx((sx * (hw + 0.0005) - 0.0035, BORE_Y - 0.013, zc - 0.012), (sx * (hw + 0.0005) + 0.0035, BORE_Y + 0.013, zc), 'core', 0.0015))
        ms += rail(z0 - 0.02, z1 + 0.02, (sx * (hw + 0.003), BORE_Y, 0), 'right' if sx > 0 else 'left', width=0.019)
        ms.append(screw((sx * (hw + 0.003), y1 - 0.010, z0 - 0.010), (sx, 0, 0), 0.0035))
        ms.append(screw((sx * (hw + 0.003), y0 + 0.010, z1 + 0.010), (sx, 0, 0), 0.0035))
    ms += rail(z0 - 0.004, z1 + 0.004, (0, y1, 0), 'up')
    ms += rail(z0 - 0.03, z1 + 0.02, (0, y0, 0), 'down')
    # vertical foregrip under the handguard
    fz = -0.405
    ms.append(bx((-0.013, y0 - 0.020, fz - 0.016), (0.013, y0 - 0.008, fz + 0.016), 'park', 0.002))
    g = lathe([(0, 0.0), (0.0175, 0.0), (0.0185, -0.012), (0.0165, -0.040), (0.018, -0.070), (0.0195, -0.090), (0.019, -0.098), (0, -0.100)],
              'grip', 24, axis='y', teeth=10, depth=0.05)
    ms.append(g.xf([('x', 8)], (0, y0 - 0.010, fz)))
    # front sight: a flip-up post on the handguard rail
    ms.append(bx((-0.010, y1 + 0.0085, z1 + 0.030), (0.010, y1 + 0.018, z1 + 0.008), 'park', 0.0015))
    ms.append(bx((-0.009, y1 + 0.018, z1 + 0.021), (-0.006, y1 + 0.040, z1 + 0.015), 'park', 0.0008))
    ms.append(bx((0.006, y1 + 0.018, z1 + 0.021), (0.009, y1 + 0.040, z1 + 0.015), 'park', 0.0008))
    ms.append(bx((-0.0018, y1 + 0.018, z1 + 0.020), (0.0018, y1 + 0.036, z1 + 0.016), 'steel', 0.0006))
    return ms


def frame():
    ms = []
    # receiver over the grip: the hammer housing the cylinder's rear face bears on
    ms.append(bx((-0.036, -0.030, DRUM_Z0 + 0.004), (0.036, RAIL_Y, 0.030), 'park', 0.004))
    ms.append(bx((-0.030, AXIS_Y - 0.022, DRUM_Z0 + 0.002), (0.030, AXIS_Y + 0.022, DRUM_Z0 + 0.010), 'steel', 0.002))  # recoil shield
    # top strap over the cylinder, rail on top from the receiver to the trunnion
    ms.append(bx((-0.028, BORE_Y + 0.040, DRUM_Z0 + 0.010), (0.028, RAIL_Y, DRUM_Z1 - 0.010), 'park', 0.003))
    ms += rail(0.024, DRUM_Z1 - 0.036, (0, RAIL_Y, 0), 'up')
    # bottom strap under the cylinder with the release latch
    yb = AXIS_Y - DRUM_R - 0.004
    ms.append(bx((-0.018, yb - 0.016, DRUM_Z0 + 0.010), (0.018, yb, DRUM_Z1 - 0.010), 'park', 0.003))
    ms.append(bx((-0.024, yb - 0.022, DRUM_Z1 + 0.006), (0.024, AXIS_Y - 0.020, DRUM_Z1 - 0.036), 'park', 0.003))  # front bearing
    ms.append(bx((0.018, yb - 0.012, DRUM_Z0 - 0.012), (0.026, yb - 0.002, DRUM_Z0 - 0.050), 'steel', 0.0015))      # release latch
    for x in (-0.036, 0.036):
        ms.append(screw((x, 0.120, -0.040), (1 if x > 0 else -1, 0, 0), 0.0045))
        ms.append(screw((x, 0.020, -0.090), (1 if x > 0 else -1, 0, 0), 0.0045))
    # safety lever on the left side of the receiver
    ms.append(tube_z(0.009, 0.0, -0.004, 'steel', (0, 0), 16).xf([('y', -90)], (-0.040, 0.050, -0.030)))
    ms.append(bx((-0.044, 0.044, -0.031), (-0.041, 0.056, 0.004), 'steel', 0.001))
    # rear sight: a flip-up aperture at the rear of the rail
    ms.append(bx((-0.012, RAIL_Y + 0.0085, 0.020), (0.012, RAIL_Y + 0.018, 0.000), 'park', 0.0015))
    ap = chamfered_ring(0.009, 0.004, 0.0035, 'park', None, 20).xf(None, (0, RAIL_Y + 0.031, 0.008))
    ms.append(ap)
    ms.append(bx((-0.004, RAIL_Y + 0.018, 0.010), (0.004, RAIL_Y + 0.023, 0.006), 'park', 0.0008))
    return ms


def grip_and_trigger():
    ms = []
    # pistol grip: stacked lathe sections raked back 18 degrees, finger grooves on the front, flat backstrap
    prof = [(0, 0.0), (0.019, 0.0), (0.021, -0.010), (0.019, -0.026), (0.022, -0.040), (0.019, -0.056), (0.022, -0.072),
            (0.021, -0.096), (0.023, -0.112), (0.020, -0.120), (0, -0.122)]
    g = lathe(prof, 'grip', 24, axis='y', teeth=16, depth=0.03)
    g.v = [(x * 0.82, y, z * 1.25 if z > 0 else z) for x, y, z in g.v]   # flatter sides, a deeper backstrap
    ms.append(g.xf([('x', -18)], (0, -0.022, 0.006)))
    # trigger guard (a flat loop) and the trigger blade
    ms.append(bx((-0.006, -0.068, 0.006), (0.006, -0.062, -0.078), 'park', 0.0015))
    ms.append(bx((-0.006, -0.068, -0.078), (0.006, -0.030, -0.072), 'park', 0.0015))
    tr = lathe([(0, 0.0), (0.004, 0.0), (0.004, -0.030), (0, -0.032)], 'steel', 8, axis='y')
    tr.v = [(x, y, z * 0.5) for x, y, z in tr.v]
    ms.append(tr.xf([('x', -20)], (0, -0.028, -0.036)))
    # sling loops: one behind the grip, one on the trunnion
    loop = chamfered_ring(0.010, 0.004, 0.0065, 'steel', None, 16)
    ms.append(Mesh('steel').add(loop.v, loop.f).xf([('y', 90)], (-0.040, 0.000, 0.022)))
    ms.append(Mesh('steel').add(list(loop.v), list(loop.f)).xf([('y', 90)], (-0.048, BORE_Y + 0.020, DRUM_Z1 - 0.022)))
    return ms


def stock():
    ms = []
    # receiver extension tube and a telescoping stock: body over the tube, cheek riser, rubber pad
    ms.append(tube_z(0.016, 0.200, 0.020, 'park', (0, 0.115), 24))
    ms.append(bx((-0.026, 0.060, 0.235), (0.026, 0.140, 0.120), 'od', 0.006))
    ms.append(bx((-0.020, 0.140, 0.225), (0.020, 0.158, 0.135), 'od', 0.006))  # cheek riser
    ms.append(bx((-0.022, -0.040, 0.250), (0.022, 0.060, 0.215), 'od', 0.006))  # lower toe
    ms.append(bx((-0.028, -0.048, 0.265), (0.028, 0.160, 0.244), 'rubber', 0.005))  # butt pad
    for k in range(5):
        y = -0.030 + k * 0.040
        ms.append(bx((-0.029, y - 0.004, 0.2665), (0.029, y + 0.004, 0.262), 'rubber', 0.0015))
    ms.append(bx((-0.010, 0.050, 0.150), (0.010, 0.062, 0.200), 'steel', 0.002))  # adjustment lever
    return ms


def grenade_launcher():
    return [('frame', m) for m in frame()] + [('cylinder', m) for m in drum()] + [('barrel', m) for m in barrel()] + \
        [('grip', m) for m in grip_and_trigger()] + [('stock', m) for m in stock()]


MODELS = {'grenade_launcher': grenade_launcher}


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    out_dir, only = args[0], args[1:]
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in MODELS.items():
        if only and name not in only:
            continue
        build(name, fn(), out_dir)


main()

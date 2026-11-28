"""Models this pack's own-work grenade launcher, quad rocket launcher and rocket launcher (CC0, modelled here from scratch) as source GLBs for the shared texture bake.
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
quad_rocket_launcher: four tubes in a 2x2 cluster on the replaced model's bore line (y 0.04), muzzles at z -0.448, rear at +0.422:
  tubes        olive shells with steel muzzle lips, a loaded rocket nose and fuse a few cm into each, flared rear venturis with the motor
               nozzle and firing contact (the rear faces the shooter)
  frame        three clamp bands, top and side spines, a hooded rear aperture and a front post on the sight line (y 0.185), tube
               latches on the rear band, sling loops
  controls     trigger housing, raked pistol grip, guard, trigger, arming lever, folding foregrip, shoulder rest, firing module with a
               selector dial and an indicator lamp on the right
Colours are picked for the bake's classes (tex_gen.py classify reads the sRGB albedo): steel grey reads as metal, near-black as
polymer, olive as coat. Output: <out>/<name>.glb. Textures: addons/gs_weapon/tools/texbake/tex_pipeline.sh.
rocket_launcher: one tube on the replaced model's bore line (y -0.0154), muzzle at z -0.756, rear at +0.427, sight line y 0.110:
  tube         olive shell with a steel muzzle collar over a dark liner 0.42 m deep (no loaded warhead in sight, so a shot leaves
               none behind), seam ring, flared venturi with breech ring, motor face and nozzle, three clamp bands with screws
  frame        top spine, hooded rear aperture tower, front post with ears, shoulder rest with a rubber pad, sling loops
  controls     trigger housing, raked pistol grip, guard and trigger, cocking lever, folding foregrip"""
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


# quad_rocket_launcher: four tubes in a 2x2 cluster around the replaced model's bore line (y 0.04), muzzles at z -0.448, rear at +0.422
Q_Y, Q_P, Q_R = 0.040, 0.050, 0.044     # cluster centre height, tube offset from it, tube radius
Q_FRONT, Q_REAR = -0.448, 0.422
Q_TUBES = [(sx * Q_P, Q_Y + sy * Q_P) for sy in (1, -1) for sx in (-1, 1)]
Q_HALF = Q_P + Q_R                       # cluster half extent: the bands wrap it
Q_SIGHT_Y = 0.185                        # sight line: the rear aperture's centre and the front post's tip


def quad_tube(at):
    """One launch tube: an olive shell with a steel muzzle lip, a dark liner, a loaded rocket's nose and fuse a few cm in; a flared
    venturi at the rear with the motor nozzle and its firing contact (the rear faces the shooter)."""
    ms = []
    ms.append(ring_z(Q_R, Q_R - 0.004, Q_REAR - 0.030, Q_FRONT + 0.012, 'od', at, 40))
    ms.append(ring_z(Q_R + 0.003, Q_R - 0.005, Q_FRONT + 0.016, Q_FRONT, 'steel', at, 40))           # muzzle lip
    ms.append(ring_z(Q_R - 0.0042, Q_R - 0.007, Q_FRONT + 0.120, Q_FRONT + 0.004, 'core', at, 32))  # dark liner
    nose = lathe([(0.034, 0.0), (0.033, -0.020), (0.028, -0.040), (0.018, -0.056), (0.009, -0.064), (0.0, -0.066)], 'olive', 28)
    ms.append(nose.xf(None, (at[0], at[1], Q_FRONT + 0.115)))
    ms.append(tube_z(0.0075, Q_FRONT + 0.052, Q_FRONT + 0.036, 'brass', at, 16, 0.0012))            # fuse
    ms.append(tube_z(Q_R - 0.006, Q_FRONT + 0.125, Q_FRONT + 0.114, 'core', at, 32))                 # behind the warhead
    # rear: a flared venturi ring, the motor's dark face with a steel nozzle and a brass contact ring
    ven = lathe([(Q_R + 0.001, 0.0), (Q_R + 0.006, 0.020), (Q_R + 0.007, 0.030), (Q_R + 0.003, 0.031), (Q_R - 0.002, 0.012),
                 (Q_R - 0.004, 0.0)], 'park', 40, closed=True)
    ms.append(ven.xf(None, (at[0], at[1], Q_REAR - 0.031)))
    ms.append(tube_z(Q_R - 0.004, Q_REAR - 0.012, Q_REAR - 0.020, 'core', at, 32))
    ms.append(ring_z(0.017, 0.009, Q_REAR - 0.006, Q_REAR - 0.013, 'steel', at, 24))
    ms.append(ring_z(0.026, 0.023, Q_REAR - 0.010, Q_REAR - 0.013, 'brass', at, 28))
    return ms


def quad_band(z0, z1, mat='park'):
    """A clamp band around the cluster: four bevelled plates and a bolt at each corner."""
    h, t = Q_HALF, 0.006
    ms = [bx((-h - t, Q_Y + h, z1), (h + t, Q_Y + h + t, z0), mat, 0.002), bx((-h - t, Q_Y - h - t, z1), (h + t, Q_Y - h, z0), mat, 0.002),
          bx((-h - t, Q_Y - h, z1), (-h, Q_Y + h, z0), mat, 0.002), bx((h, Q_Y - h, z1), (h + t, Q_Y + h, z0), mat, 0.002)]
    zc = (z0 + z1) / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            ms.append(screw((sx * (h + t), Q_Y + sy * (h - 0.012), zc), (sx, 0, 0), 0.004))
    return ms


def quad_frame():
    ms = []
    for z0, z1 in ((Q_REAR - 0.040, Q_REAR - 0.075), (0.040, 0.000), (Q_FRONT + 0.065, Q_FRONT + 0.030)):
        ms += quad_band(z0, z1)
    # top spine in the valley between the upper tubes, carrying the sights; side spines between the left and right pairs
    top = Q_Y + Q_P + Q_R * 0.62
    ms.append(bx((-0.011, top - 0.012, Q_REAR - 0.040), (0.011, top + 0.004, Q_FRONT + 0.030), 'park', 0.002))
    for sx in (-1, 1):
        ms.append(bx((sx * Q_HALF - 0.010, Q_Y - 0.008, Q_REAR - 0.075), (sx * Q_HALF + 0.001, Q_Y + 0.008, Q_FRONT + 0.065), 'park', 0.0015))
    # rear sight: a hooded aperture on a tower over the rear band
    rz = Q_REAR - 0.058
    ms.append(bx((-0.016, top + 0.004, rz + 0.016), (0.016, Q_SIGHT_Y - 0.020, rz - 0.016), 'park', 0.002))
    ms.append(ring_z(0.017, 0.0045, rz + 0.006, rz - 0.006, 'park', (0, Q_SIGHT_Y), 24))
    for sx in (-1, 1):
        ms.append(bx((sx * 0.017 - 0.003, Q_SIGHT_Y - 0.020, rz + 0.010), (sx * 0.017 + 0.003, Q_SIGHT_Y + 0.014, rz - 0.010), 'park', 0.001))
    # front sight: a post between two guard ears over the front band
    fz = Q_FRONT + 0.048
    ms.append(bx((-0.014, top + 0.004, fz + 0.012), (0.014, top + 0.020, fz - 0.012), 'park', 0.002))
    ms.append(bx((-0.0022, top + 0.020, fz + 0.003), (0.0022, Q_SIGHT_Y, fz - 0.003), 'steel', 0.0006))
    for sx in (-1, 1):
        ms.append(bx((sx * 0.012 - 0.0025, top + 0.020, fz + 0.008), (sx * 0.012 + 0.0025, Q_SIGHT_Y + 0.004, fz - 0.008), 'park', 0.0008))
    # tube latches on the rear band (the reload's readable part), sling loops on the left
    for x, y in Q_TUBES:
        sx = 1 if x > 0 else -1
        ms.append(bx((x + sx * 0.010, y + (0.010 if y > Q_Y else -0.016), Q_REAR - 0.028), (x + sx * 0.030, y + (0.016 if y > Q_Y else -0.010),
                  Q_REAR - 0.042), 'steel', 0.001))
    loop = chamfered_ring(0.011, 0.005, 0.007, 'steel', None, 16)
    for z in (Q_REAR - 0.058, Q_FRONT + 0.048):
        ms.append(Mesh('steel').add(list(loop.v), list(loop.f)).xf([('y', 90)], (-Q_HALF - 0.012, Q_Y + 0.030, z)))
    return ms


def quad_controls():
    ms = []
    yb = Q_Y - Q_HALF - 0.006
    # trigger housing under the middle band, raked pistol grip, guard and trigger
    ms.append(bx((-0.022, yb - 0.030, 0.050), (0.022, yb, -0.070), 'park', 0.003))
    prof = [(0, 0.0), (0.019, 0.0), (0.021, -0.010), (0.019, -0.026), (0.022, -0.040), (0.019, -0.056), (0.022, -0.072),
            (0.021, -0.096), (0.023, -0.112), (0.020, -0.120), (0, -0.122)]
    g = lathe(prof, 'grip', 24, axis='y', teeth=16, depth=0.03)
    g.v = [(x * 0.82, y, z * 1.25 if z > 0 else z) for x, y, z in g.v]
    ms.append(g.xf([('x', -15)], (0, yb - 0.024, 0.026)))
    ms.append(bx((-0.006, yb - 0.078, 0.020), (0.006, yb - 0.072, -0.068), 'park', 0.0015))
    ms.append(bx((-0.006, yb - 0.078, -0.068), (0.006, yb - 0.028, -0.062), 'park', 0.0015))
    tr = lathe([(0, 0.0), (0.004, 0.0), (0.004, -0.030), (0, -0.032)], 'steel', 8, axis='y')
    tr.v = [(x, y, z * 0.5) for x, y, z in tr.v]
    ms.append(tr.xf([('x', -20)], (0, yb - 0.026, -0.030)))
    ms.append(bx((0.022, yb - 0.022, -0.020), (0.028, yb - 0.008, -0.046), 'steel', 0.001))   # arming lever
    # folding foregrip under the front half
    fz = -0.250
    ms.append(bx((-0.014, yb - 0.014, fz - 0.020), (0.014, yb, fz + 0.020), 'park', 0.002))
    ms.append(tube_z(0.006, 0.017, -0.017, 'steel', (0, 0), 12).xf([('y', 90)], (0, yb - 0.008, fz)))   # hinge pin across
    fg = lathe([(0, 0.0), (0.0175, 0.0), (0.0185, -0.012), (0.0165, -0.040), (0.018, -0.070), (0.0195, -0.090), (0.019, -0.098), (0, -0.100)],
               'grip', 24, axis='y', teeth=10, depth=0.05)
    ms.append(fg.xf([('x', 10)], (0, yb - 0.010, fz)))
    # shoulder rest under the rear: an olive block with a rubber pad
    ms.append(bx((-0.032, yb - 0.060, Q_REAR - 0.080), (0.032, yb, 0.170), 'od', 0.006))
    ms.append(bx((-0.034, yb - 0.072, Q_REAR - 0.085), (0.034, yb - 0.058, 0.165), 'rubber', 0.004))
    # firing module on the right of the rear half: selector dial, indicator lamp, contact cover
    mx = Q_HALF + 0.006
    ms.append(bx((mx, Q_Y - 0.045, 0.250), (mx + 0.032, Q_Y + 0.040, 0.080), 'park', 0.004))
    dial = lathe([(0, 0.010), (0.016, 0.010), (0.018, 0.004), (0.018, 0.0), (0, 0.0)], 'steel', 24, teeth=12, depth=0.08)
    ms.append(dial.xf([('y', 90)], (mx + 0.032, Q_Y + 0.005, 0.180)))
    ms.append(bx((mx + 0.040, Q_Y + 0.003, 0.192), (mx + 0.044, Q_Y + 0.007, 0.168), 'park', 0.0008))   # dial pointer
    ms.append(bx((mx + 0.032, Q_Y - 0.036, 0.235), (mx + 0.036, Q_Y - 0.012, 0.100), 'rubber', 0.001))
    for z in (0.240, 0.090):
        for y in (Q_Y - 0.036, Q_Y + 0.031):
            ms.append(screw((mx + 0.032, y, z), (1, 0, 0), 0.0035))
    return ms


def quad_rocket_launcher():
    tubes = [m for at in Q_TUBES for m in quad_tube(at)]
    # the indicator lamp is its own part: texbake splits glow materials off a mixed part and loses the rest of it
    lamp = tube_z(0.005, 0.0, -0.004, 'reticle', (0, 0), 12).xf([('y', 90)], (Q_HALF + 0.038, Q_Y + 0.026, 0.120))
    return [('tubes', m) for m in tubes] + [('frame', m) for m in quad_frame()] + [('controls', m) for m in quad_controls()] + [('lamp', lamp)]


# ------------------------------------------------------------------------------ single-tube rocket launcher
R_Y, R_R = -0.0154, 0.052               # tube axis height (the replaced model's bore) and shell radius
R_FRONT, R_REAR = -0.756, 0.427         # muzzle and venturi ends of the replaced model
R_LINE = 0.110                          # sight line: the rear aperture's centre and the front post's tip
R_SIGHT_REAR, R_SIGHT_FRONT = -0.030, -0.460


def rocket_tube():
    """The tube: an olive shell, a steel muzzle collar over a dark liner that runs deep (the round loads from the breech and sits
    far back, out of sight, so nothing is left at the muzzle after the shot), a flared rear venturi with the breech ring."""
    at = (0, R_Y)
    ms = [ring_z(R_R, R_R - 0.004, R_REAR - 0.060, R_FRONT + 0.050, 'od', at, 48)]
    ms.append(ring_z(R_R + 0.008, R_R - 0.006, R_FRONT + 0.075, R_FRONT + 0.004, 'park', at, 48))      # muzzle collar
    ms.append(ring_z(R_R + 0.005, R_R - 0.007, R_FRONT + 0.006, R_FRONT, 'steel', at, 48))             # muzzle lip
    ms.append(ring_z(R_R - 0.004, R_R - 0.008, R_FRONT + 0.420, R_FRONT + 0.002, 'core', at, 40))      # liner
    ms.append(tube_z(R_R - 0.006, R_FRONT + 0.430, R_FRONT + 0.416, 'core', at, 40))                   # the dark end of the bore
    ms.append(ring_z(R_R + 0.004, R_R - 0.004, R_FRONT + 0.160, R_FRONT + 0.140, 'park', at, 48))      # a seam ring
    ven = lathe([(R_R - 0.002, 0.0), (R_R + 0.004, 0.022), (R_R + 0.014, 0.050), (R_R + 0.016, 0.060), (R_R + 0.010, 0.061),
                 (R_R - 0.004, 0.030), (R_R - 0.006, 0.0)], 'park', 48, closed=True)
    ms.append(ven.xf(None, (0, R_Y, R_REAR - 0.061)))
    ms.append(ring_z(R_R + 0.006, R_R - 0.004, R_REAR - 0.058, R_REAR - 0.074, 'steel', at, 48))       # breech ring
    ms.append(tube_z(R_R - 0.006, R_REAR - 0.040, R_REAR - 0.052, 'core', at, 40))                     # the motor face, deep in
    ms.append(ring_z(0.018, 0.010, R_REAR - 0.036, R_REAR - 0.042, 'steel', at, 24))                   # its nozzle
    for z0, z1 in ((R_REAR - 0.120, R_REAR - 0.150), (0.060, 0.030), (R_FRONT + 0.300, R_FRONT + 0.270)):  # clamp bands
        ms.append(ring_z(R_R + 0.006, R_R - 0.002, z0, z1, 'park', at, 48))
        ms.append(screw((R_R + 0.006, R_Y, (z0 + z1) / 2), (1, 0, 0), 0.0035))
    return ms


def rocket_frame():
    """Sights on a top spine, a shoulder rest and pad under the rear, sling loops."""
    ms = []
    top = R_Y + R_R
    ms.append(bx((-0.010, top - 0.006, R_SIGHT_REAR + 0.050), (0.010, top + 0.008, R_SIGHT_FRONT - 0.030), 'park', 0.002))
    # rear sight: a hooded aperture on a two-leg tower
    rz = R_SIGHT_REAR
    for sx in (-1, 1):
        ms.append(bx((sx * 0.012 - 0.003, top + 0.008, rz + 0.010), (sx * 0.012 + 0.003, R_LINE - 0.012, rz - 0.010), 'park', 0.001))
    ms.append(bx((-0.018, R_LINE - 0.020, rz + 0.008), (0.018, R_LINE - 0.012, rz - 0.008), 'park', 0.0015))
    ms.append(ring_z(0.016, 0.0045, rz + 0.006, rz - 0.006, 'park', (0, R_LINE), 24))
    for sx in (-1, 1):
        ms.append(bx((sx * 0.016 - 0.003, R_LINE - 0.020, rz + 0.009), (sx * 0.016 + 0.003, R_LINE + 0.016, rz - 0.009), 'park', 0.001))
    # front sight: a post between two guard ears on a tower
    fz = R_SIGHT_FRONT
    ms.append(bx((-0.012, top + 0.008, fz + 0.012), (0.012, R_LINE - 0.024, fz - 0.012), 'park', 0.002))
    ms.append(bx((-0.0022, R_LINE - 0.026, fz + 0.003), (0.0022, R_LINE, fz - 0.003), 'steel', 0.0006))
    for sx in (-1, 1):
        ms.append(bx((sx * 0.011 - 0.0025, R_LINE - 0.026, fz + 0.008), (sx * 0.011 + 0.0025, R_LINE + 0.004, fz - 0.008), 'park', 0.0008))
    # shoulder rest under the rear half: an olive block on two saddles, a rubber pad on its face
    yb = R_Y - R_R
    ms.append(bx((-0.026, yb - 0.040, R_REAR - 0.160), (0.026, yb + 0.004, 0.120), 'od', 0.006))
    ms.append(bx((-0.028, yb - 0.050, R_REAR - 0.165), (0.028, yb - 0.038, 0.115), 'rubber', 0.004))
    loop = chamfered_ring(0.011, 0.005, 0.007, 'steel', None, 16)
    for z in (R_REAR - 0.135, R_FRONT + 0.285):
        ms.append(Mesh('steel').add(list(loop.v), list(loop.f)).xf([('y', 90)], (-R_R - 0.012, R_Y + 0.012, z)))
    return ms


def rocket_controls():
    """Trigger housing under the grip origin, a raked pistol grip, guard and trigger, a cocking lever, a folding foregrip."""
    ms = []
    yb = R_Y - R_R
    ms.append(bx((-0.022, yb - 0.028, 0.040), (0.022, yb + 0.004, -0.075), 'park', 0.003))
    prof = [(0, 0.0), (0.019, 0.0), (0.021, -0.010), (0.019, -0.026), (0.022, -0.040), (0.019, -0.056), (0.022, -0.072),
            (0.021, -0.090), (0.023, -0.100), (0.020, -0.106), (0, -0.108)]
    g = lathe(prof, 'grip', 24, axis='y', teeth=16, depth=0.03)
    g.v = [(x * 0.82, y, z * 1.25 if z > 0 else z) for x, y, z in g.v]
    ms.append(g.xf([('x', -15)], (0, yb - 0.022, 0.018)))
    ms.append(bx((-0.006, yb - 0.074, 0.012), (0.006, yb - 0.068, -0.070), 'park', 0.0015))
    ms.append(bx((-0.006, yb - 0.074, -0.070), (0.006, yb - 0.026, -0.064), 'park', 0.0015))
    tr = lathe([(0, 0.0), (0.004, 0.0), (0.004, -0.028), (0, -0.030)], 'steel', 8, axis='y')
    tr.v = [(x, y, z * 0.5) for x, y, z in tr.v]
    ms.append(tr.xf([('x', -20)], (0, yb - 0.024, -0.034)))
    ms.append(bx((0.022, yb - 0.020, -0.010), (0.028, yb - 0.006, -0.050), 'steel', 0.001))   # cocking lever
    fz = -0.300
    ms.append(bx((-0.014, yb - 0.014, fz - 0.020), (0.014, yb + 0.004, fz + 0.020), 'park', 0.002))
    ms.append(tube_z(0.006, 0.017, -0.017, 'steel', (0, 0), 12).xf([('y', 90)], (0, yb - 0.008, fz)))
    fg = lathe([(0, 0.0), (0.0175, 0.0), (0.0185, -0.012), (0.0165, -0.040), (0.018, -0.070), (0.0195, -0.090), (0.019, -0.098), (0, -0.100)],
               'grip', 24, axis='y', teeth=10, depth=0.05)
    ms.append(fg.xf([('x', 10)], (0, yb - 0.010, fz)))
    return ms


def rocket_launcher():
    return ([('tube', m) for m in rocket_tube()] + [('frame', m) for m in rocket_frame()] + [('controls', m) for m in rocket_controls()])


MODELS = {'grenade_launcher': grenade_launcher, 'quad_rocket_launcher': quad_rocket_launcher, 'rocket_launcher': rocket_launcher}


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    out_dir, only = args[0], args[1:]
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in MODELS.items():
        if only and name not in only:
            continue
        build(name, fn(), out_dir)


main()

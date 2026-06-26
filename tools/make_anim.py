#!/usr/bin/env python3
"""Add canter + gallop + idle animations to the Mineclonia horse mesh,
writing models/edoras_horse.b3d.

The stock mobs_mc_horse.b3d has ONE 40-frame walk in which only the four
upper-leg bones swing; knees/neck/head/tail are static (the "stiff" look).
We measure each leg's real swing (axis + amplitude, relative to its rest
pose, straight from the walk keys -- no axis guessing) and resynthesize it
as a clean sinusoid we can re-phase per leg. That lets us build real gaits:

  CANTER  (3-beat, right lead): LH , then diagonal RH+LF , then leading RF ,
          then suspension. Slower, rolling.
  GALLOP  (4-beat transverse, right lead): LH, RH, LF, RF land in quick
          succession (syncopated) with a suspension gap. Faster.
  IDLE    legs planted, gentle neck sway.

Both gaits get a soft ONCE-per-stride body bob and neck nod (the head, a
child of the neck, inherits the nod) -- a galloping horse's head rises and
falls slowly, once per stride, not a fast jitter.

Timeline (b3d keyframes are 1-based; Luanti frame = keyframe - 1):
  walk    keys   1- 41   (unchanged)        Luanti   0- 40
  canter  keys  50- 74   (new)              Luanti  49- 73
  gallop  keys  80-100   (new)              Luanti  79- 99
  idle    keys 110-170   (new)              Luanti 109-169
  trot    keys 180-208   (new, 2-beat)      Luanti 179-207

Edit the tunables, re-run, then restart Luanti.
"""
import math, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import b3d  # noqa: E402

SRC = os.path.expanduser(
    "~/.var/app/org.luanti.luanti/.minetest/games/mineclonia/mods/"
    "ENTITIES/mobs_mc/models/mobs_mc_horse.b3d")
DST = os.path.join(os.path.dirname(HERE), "models", "edoras_horse.b3d")

# ---- tunables --------------------------------------------------------------
WALK_LAST   = 41
CANTER_BEG, CANTER_LEN = 50, 24
GALLOP_BEG, GALLOP_LEN = 80, 20
IDLE_BEG,   IDLE_LEN   = 110, 60
TROT_BEG,   TROT_LEN   = 180, 28   # 2-beat diagonal gait (between walk & canter)
GRAZE_BEG,  GRAZE_LEN  = 210, 40   # head-down self-feeding loop (Luanti 209-249)

CANTER_AMP = 1.5      # leg-swing exaggeration vs the measured walk amplitude
GALLOP_AMP = 2.0
TROT_AMP   = 1.2      # springy, less reaching than canter
BODY_BOB_CANTER = 0.03   # body bob swings the head, kept minimal
BODY_BOB_GALLOP = 0.05
BODY_BOB_TROT   = 0.09   # trot bobs TWICE per stride (bob_freq below)
NECK_NOD_CANTER = math.radians(1.5)   # head nod amplitude (downward dip)
NECK_NOD_GALLOP = math.radians(1.5)
NECK_NOD_TROT   = math.radians(1.4)   # head stays fairly level at a trot
# Nods per stride. MUST be an integer, or the looped clip pops at the seam: the closing
# keyframe is u=0, and only whole cycles return cleanly to zero there.
NECK_FREQ_CANTER = 1      # one clean up/down nod per stride (real canter)
NECK_FREQ_GALLOP = 2      # 2-cycle head bob per stride
NECK_FREQ_TROT   = 2      # 2-beat gait -> head bobs twice per stride
# Neutral neck carriage. The stock rig holds the head too steep/upright; this constant
# downward pitch lowers the rest pose for ALL clips. Negative = head down/forward.
NECK_REST_PITCH = math.radians(-15.0)
# Constant forward pitch of the neck during gallop (a real horse extends its neck low
# and forward at speed), ADDED on top of NECK_REST_PITCH. Flip the sign if it leans up.
NECK_PITCH_GALLOP = math.radians(-13.0)
IDLE_SWAY       = math.radians(4.0)
# Walk head bob: a real horse nods ONCE per stride, slowly. We overwrite the stock neck
# walk keys with a DOWNWARD-biased nod -- the head dips toward the ground and returns to
# rest, never rising above neutral (freq MUST be integer, like the gaits, or it pops).
WALK_NECK_NOD  = math.radians(7.0)    # depth of the downward dip (bigger = deeper)
WALK_NECK_FREQ = 1                     # one slow nod per stride

# Graze (self-feeding) pose: lower the whole head/neck so the mouth is ~ground level,
# then chew. GRAZE_NECK_PITCH swings the neck DOWN about its own local X (negative =
# down). GRAZE_HEAD_PITCH straightens the rest "L" so the head continues the neck's line;
# it is PRE-multiplied onto the head rest rotation (rotates about the NECK-frame X), so
# the head bone's flipped local frame is irrelevant and negative = nose down, like the
# neck. Flip GRAZE_HEAD_PITCH's sign if the head bends the wrong way.
GRAZE_NECK_PITCH = math.radians(-72.0)
GRAZE_HEAD_PITCH = math.radians(-46.0)
GRAZE_MUNCH_AMP  = math.radians(3.0)   # gentle chewing nod on the head
GRAZE_MUNCH_FREQ = 3                   # chews per loop (integer -> no seam pop)

# ---- buck (rodeo) ----------------------------------------------------------
# This clip animates only the LEGS and the neck/head toss. The gross rear/leap/kick
# pitch is done at RUNTIME on the whole OBJECT (init.lua BUCK_OBJ_*), which pivots about
# the feet and throws the rider; pitching this body bone instead would rock about its
# mid-barrel origin (the "rocking horse" look). Two half-waves of sin(2*pi*u):
#   GATHER (rear, peak u=0.25): forelegs raise up & forward, neck tosses up.
#   PLUNGE (buck, peak u=0.75): forelegs reach forward to land, hind legs kick out high
#     behind, neck/head drop. This is the dominant beat, fired while airborne.
# b3d keyframes 260-290 -> Luanti 259-289. Signs may need flipping in-game.
BUCK_BEG, BUCK_LEN = 260, 30
# Spine flex on top of the object pitch. Gather is 0 (a grounded nose-up body bone is
# the centre see-saw we avoid); only the plunge keeps a small nose-down round of the
# back, firing airborne (u=0.75) where centre rotation looks correct. Y-lift is unused:
# the object pitches about the feet and the horse is airborne through the plunge.
BUCK_GATHER_PITCH = math.radians(0.0)
BUCK_PLUNGE_PITCH = math.radians(6.0)
BUCK_REAR_RISE    = 0.0
BUCK_PLUNGE_RISE  = 0.0
# Forelegs: swing up & forward in the gather (-=forward on the -X leg axis); reach
# forward (less, straighter) to land on during the plunge.
BUCK_FRONT_LIFT   = math.radians(50.0)
BUCK_FRONT_KNEE   = math.radians(42.0) # foreleg knee curls while raised (gather only)
BUCK_FRONT_FET    = math.radians(32.0)
BUCK_FRONT_REACH  = math.radians(20.0) # forelegs reach forward to plant on landing
# Hind legs: planted in the gather; thrown out behind HIGH in the plunge (+=back). The
# rest leg hangs straight DOWN, so the angle is measured from there: 90deg = straight
# out horizontal, >90 = up-and-out. Stacked on the ~50deg nose-down object pitch (rear
# already up), this reads as the legs thrown high up and out at the apex.
BUCK_BACK_KICK    = math.radians(80.0)
BUCK_BACK_FET     = math.radians(52.0)
# Head/neck TOSS: the head pumps up through the rear/gather (peak u=0.25) and drops back
# down through the plunge/kick (peak u=0.75), keyed off the same sin(2pi*u) the legs use
# so head and hooves pulse together. BASE = mid carriage the toss swings about (negative
# = head down/forward); TOSS = swing amplitude (positive = lifts up on the rear). Tune
# in-game: if the head dips when it should rear, flip the TOSS sign.
BUCK_NECK_BASE = math.radians(-30.0)
BUCK_NECK_TOSS = math.radians(28.0)
BUCK_HEAD_BASE = math.radians(-20.0)
BUCK_HEAD_TOSS = math.radians(26.0)   # head follows, a touch less than the neck
# As the neck rears UP (rear = the positive half of the buck wave), tuck the head
# FORWARD from the neck (nose pitches down/forward off the neck line) instead of the
# head just riding straight up with it. Scaled by the rear amount, 0 through the plunge.
BUCK_HEAD_FWD  = math.radians(28.0)   # forward head pitch at the top of the rear (deg)

LEGS = ["leg.front.left1", "leg.front.right1",
        "leg.back.left1",  "leg.back.right1"]

# ---- leg joint dynamics ----------------------------------------------------
# Three-segment leg (1 = hip/shoulder, 2 = knee/hock, 3 = fetlock/hoof).
# Segment 1 swings (measured sinusoid); 2/3 fold during the swing/recovery half
# of the stride; the fetlock ALSO keeps the hoof flat on the ground in stance.
# Phase offset placing the knee/fetlock fold in the SWING half (leg lifting and
# reaching forward, in the air) so the leg is straight through STANCE. The
# measured hip swing's +direction is BACKWARD, so this is +0.25 (half a stride
# past the naive -0.25); a real horse folds the knee forward-and-up in swing,
# NOT while the hoof is planted. Shift by +/-0.5 to move the fold to the other
# half if a leg folds while stepping.
KNEE_PHASE  = 0.25
FETLOCK_LAG = 0.08      # fetlock trails the knee slightly
# Knee fold direction per leg group. ANATOMY: the front knee (carpus) folds the
# OPPOSITE way to the hind hock, so the signs differ -- do NOT unify them
# (flip a sign only if that group folds the wrong way in-game).
KNEE_SIGN = {"front": 1.0, "back": -1.0}
# Fetlock fold direction. Unlike the knee, the hoof folds BACK the same way on
# all four legs during swing (the box is offset forward to fake the planted
# stance, so no ground-leveling rotation is applied). Flip if it folds forward.
FETLOCK_SIGN = 1.0
# Per-group fetlock fold amplitude multiplier -- the back hooves kick back harder.
FETLOCK_GROUP_MULT = {"front": 1.0, "back": 1.6}
# Stride phase at which each group's fetlock fold PEAKS, measured as an offset
# past the leg's footfall (the fold itself is the positive half of a sine, so its
# crest sits 0.25 of a stride after this offset). FRONT hooves fold during the
# forward swing (in the air): offset KNEE_PHASE+FETLOCK_LAG -> crest at u-phase
# ~0.58, mid-swing. The HIND hooves instead flick back at the END of stance, when the
# leg is at its furthest-BACK push-off extreme (~80deg back, NOT straight). The hip is
# furthest back at u-phase 0.25 (peak of the backward swing), so the back offset is 0.0.
# Shift a group's value by +/-0.25 to slide its fold earlier/later in the stride.
FETLOCK_PEAK_PHASE = {"front": KNEE_PHASE + FETLOCK_LAG, "back": 0.0}
# Per-gait peak knee flex (segment 2): trot is the crisp "high knee", gallop
# tucks tightest, walk is gentle.
KNEE_BEND_WALK   = math.radians(26)
KNEE_BEND_TROT   = math.radians(52)
KNEE_BEND_CANTER = math.radians(45)
KNEE_BEND_GALLOP = math.radians(55)
# Per-gait fetlock free-flex (segment 3) during swing. Aggressive: with the back
# multiplier (1.6) the hind hooves fold ~up to 80deg back at speed.
FETLOCK_BEND_WALK   = math.radians(32)
FETLOCK_BEND_TROT   = math.radians(45)
FETLOCK_BEND_CANTER = math.radians(48)
FETLOCK_BEND_GALLOP = math.radians(50)
# Fetlock ground-tracking: during STANCE the hoof should stay parallel to the
# ground, so the fetlock counter-rotates to cancel the hip+knee pitch
# (fetlock = -(hip + knee), per the kinematic spec). GAIN scales how fully
# (1.0 = exact level, lower = stylised); MAX clamps it so a big hip sweep can't
# crank the hoof past a sane angle. Set GAIN = 0 to disable and fall back to a
# plain fold.
FETLOCK_LEVEL_GAIN = 0.6
FETLOCK_LEVEL_MAX  = math.radians(45)
# Fetlock "snap": a short forward extension in late swing to break the impact
# just before the hoof lands. SNAP_PHASE places the pulse.
FETLOCK_SNAP = {"walk": math.radians(6), "trot": math.radians(10),
                "canter": math.radians(10), "gallop": math.radians(12)}
SNAP_PHASE   = 0.40
# Body "rocking-horse" pitch (about X) added on top of the vertical bob: canter
# and gallop rock, walk/trot stay level. PITCH_PHASE aligns the dip with the
# footfalls (tune sign/phase in-game).
BODY_PITCH_CANTER = math.radians(1)     # the rock swings the head a lot, keep small
BODY_PITCH_GALLOP = math.radians(1.5)
PITCH_PHASE       = 0.0

# footfall phase per leg (fraction of stride). Right-lead.
#   FL=leg.front.left1 RF=leg.front.right1 BL=leg.back.left1 BR=leg.back.right1
CANTER_PHASE = {  # 3-beat: LH , then RH+LF diagonal , then RF
    "leg.back.left1": 0.00, "leg.back.right1": 0.33,
    "leg.front.left1": 0.33, "leg.front.right1": 0.66}
GALLOP_PHASE = {  # 4-beat: LH, RH, LF, RF then suspension
    "leg.back.left1": 0.00, "leg.back.right1": 0.15,
    "leg.front.left1": 0.50, "leg.front.right1": 0.65}
TROT_PHASE = {  # 2-beat: diagonal pairs together (LH+RF, then RH+LF)
    "leg.front.left1": 0.00, "leg.back.right1": 0.00,
    "leg.front.right1": 0.50, "leg.back.left1": 0.50}
# True 4-beat LATERAL walk (right-lead): RH -> RF -> LH -> LF, evenly spaced.
# (The stock walk was diagonal -- it read as a too-fast shuffle.)
WALK_PHASE = {
    "leg.back.right1":  0.00, "leg.front.right1": 0.25,
    "leg.back.left1":   0.50, "leg.front.left1":  0.75}
WALK_AMP      = 0.85    # walk reaches less than the trot
WALK_BODY_BOB = 0.04    # subtle, twice per stride

# Per-gait synthesis config consumed by clip_keys (see main).
WALK_CFG = dict(phase=WALK_PHASE, amp=WALK_AMP, knee=KNEE_BEND_WALK,
                fetlock=FETLOCK_BEND_WALK, snap=FETLOCK_SNAP["walk"],
                bob=WALK_BODY_BOB, bob_freq=2, pitch=0.0, pitch_freq=1,
                nod=WALK_NECK_NOD, neck_freq=WALK_NECK_FREQ, neck_pitch=0.0,
                neck_mode="dip")
TROT_CFG = dict(phase=TROT_PHASE, amp=TROT_AMP, knee=KNEE_BEND_TROT,
                fetlock=FETLOCK_BEND_TROT, snap=FETLOCK_SNAP["trot"],
                bob=BODY_BOB_TROT, bob_freq=2, pitch=0.0, pitch_freq=1,
                nod=NECK_NOD_TROT, neck_freq=NECK_FREQ_TROT, neck_pitch=0.0,
                neck_mode="sym")
CANTER_CFG = dict(phase=CANTER_PHASE, amp=CANTER_AMP, knee=KNEE_BEND_CANTER,
                  fetlock=FETLOCK_BEND_CANTER, snap=FETLOCK_SNAP["canter"],
                  bob=BODY_BOB_CANTER, bob_freq=1, pitch=BODY_PITCH_CANTER,
                  pitch_freq=1, nod=NECK_NOD_CANTER, neck_freq=NECK_FREQ_CANTER,
                  neck_pitch=0.0, neck_mode="dip")
GALLOP_CFG = dict(phase=GALLOP_PHASE, amp=GALLOP_AMP, knee=KNEE_BEND_GALLOP,
                  fetlock=FETLOCK_BEND_GALLOP, snap=FETLOCK_SNAP["gallop"],
                  bob=BODY_BOB_GALLOP, bob_freq=1, pitch=BODY_PITCH_GALLOP,
                  pitch_freq=1, nod=NECK_NOD_GALLOP, neck_freq=NECK_FREQ_GALLOP,
                  neck_pitch=NECK_PITCH_GALLOP, neck_mode="dip")
# ---------------------------------------------------------------------------

KEY_SZ = 4 + 12 + 12 + 16


def parse_keys(p):
    flags = struct.unpack("<i", p[:4])[0]
    n = (len(p) - 4) // KEY_SZ
    out = []
    for k in range(n):
        o = 4 + k * KEY_SZ
        out.append([struct.unpack("<i", p[o:o + 4])[0],
                    list(struct.unpack("<3f", p[o + 4:o + 16])),
                    list(struct.unpack("<3f", p[o + 16:o + 28])),
                    list(struct.unpack("<4f", p[o + 28:o + 44]))])
    return flags, out


def build_keys(flags, keys):
    out = struct.pack("<i", flags)
    for f, pos, scl, rot in keys:
        out += struct.pack("<i", f) + struct.pack("<3f", *pos) \
            + struct.pack("<3f", *scl) + struct.pack("<4f", *rot)
    return out


# ---- quaternion helpers (w,x,y,z) -----------------------------------------
def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return [c / n for c in q]


def qmul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return [aw*bw - ax*bx - ay*by - az*bz,
            aw*bx + ax*bw + ay*bz - az*by,
            aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw]


def qconj(q):
    return [q[0], -q[1], -q[2], -q[3]]


def qx(angle):
    return [math.cos(angle / 2), math.sin(angle / 2), 0.0, 0.0]


def axisangle(axis, angle):
    s = math.sin(angle / 2)
    return [math.cos(angle / 2), axis[0]*s, axis[1]*s, axis[2]*s]


def to_axisangle(q):
    q = qnorm(q)
    w = max(-1.0, min(1.0, q[0]))
    ang = 2 * math.acos(w)
    s = math.sqrt(max(0.0, 1 - w*w))
    if s < 1e-6:
        return (1.0, 0.0, 0.0), 0.0
    return (q[1]/s, q[2]/s, q[3]/s), ang


def main():
    ver, top = b3d.parse(SRC)

    rest = {}                 # name -> (pos, scl, rot) at frame 1
    walk_curve = {}           # leg name -> {frame: rot}

    def scan(node):
        name = b3d.node_name(node)
        for c in node.children:
            if isinstance(c, b3d.Chunk) and c.tag == b"KEYS":
                _, keys = parse_keys(c.payload)
                if name not in rest:
                    f1 = next(k for k in keys if k[0] == 1)
                    rest[name] = (f1[1], f1[2], f1[3])
                if name in LEGS and name not in walk_curve:
                    walk_curve[name] = {k[0]: k[3] for k in keys}
            elif isinstance(c, b3d.Node):
                scan(c)
    for o in top:
        if isinstance(o, b3d.Node):
            scan(o)

    # Lower the neck's neutral carriage. The stock rig holds the head too
    # upright; pitching the rest pose down here re-bases EVERY clip (walk, trot,
    # canter, gallop, idle/stand all build off rest["neck"]) so the head is
    # carried lower throughout, and the per-gait neck pitches/nods stay relative
    # to this new baseline.
    if "neck" in rest and NECK_REST_PITCH != 0.0:
        npos, nscl, nrot = rest["neck"]
        rest["neck"] = (npos, nscl, qmul(nrot, qx(NECK_REST_PITCH)))

    # Measure each leg's swing: dominant local axis, neutral pose, amplitude.
    leg = {}
    walk_phase = {}            # leg name -> stride phase of its walk swing
    for name in LEGS:
        r = rest[name][2]
        rinv = qconj(qnorm(r))
        series = []
        for f in range(1, WALK_LAST + 1):
            ax, ang = to_axisangle(qmul(rinv, walk_curve[name][f]))
            series.append((ax, ang))
        ref = max(series, key=lambda t: t[1])[0]
        # Normalise every leg to a common axis convention (point -X). Bones are
        # mirrored, so some measure +X; without this their swing direction (and
        # thus footfall phase) would be inverted relative to the others.
        if ref[0] > 0:
            ref = (-ref[0], -ref[1], -ref[2])
        signed = [ang * (1 if (ax[0]*ref[0] + ax[1]*ref[1] + ax[2]*ref[2]) >= 0
                         else -1) for ax, ang in series]
        lo, hi = min(signed), max(signed)
        center, amp = (hi + lo) / 2, (hi - lo) / 2
        # Phase of the walk swing's fundamental, so the knee/fetlock flex can be
        # locked to each leg's real footfall in the stock walk (DFT at 1 cycle
        # per stride; frame 41 duplicates frame 1, so analyse frames 1..40).
        N = WALK_LAST - 1
        Cc = sum((signed[k] - center) * math.cos(2 * math.pi * k / N)
                 for k in range(N))
        Cs = sum((signed[k] - center) * math.sin(2 * math.pi * k / N)
                 for k in range(N))
        walk_phase[name] = (math.atan2(-Cc, Cs) / (2 * math.pi)) % 1.0
        neutral = qmul(r, axisangle(ref, center))
        leg[name] = (ref, neutral, amp, center)

    def leg_rot(name, u, amp_scale, phase):
        ref, neutral, amp, center = leg[name]
        a = amp * amp_scale * math.sin(2 * math.pi * (u - phase[name]))
        return qmul(neutral, axisangle(ref, a))

    def leg_segment(name):
        p = name.split(".")
        if len(p) == 3 and p[0] == "leg" and p[1] in ("front", "back") \
                and p[2][-1] in "123":
            return p[1], int(p[2][-1])
        return None

    # All four legs' swing axes are normalised to -X, so axisangle(ref, theta)
    # == qx(-theta): a leg's pitch about world +X (relative to rest) is just the
    # negated rotation amount. These scalar helpers feed the fetlock leveller.
    def hip_dev(base, u, amp_scale, phase):
        # Total hip pitch (about ref) away from rest = mean offset + swing.
        _, _, amp, center = leg[base]
        a = amp * amp_scale * math.sin(2 * math.pi * (u - phase[base]))
        return center + a

    def knee_flex(base, group, u, phase, knee_bend):
        ph = phase[base]
        return knee_bend * max(0.0, math.sin(2 * math.pi * (u - ph - KNEE_PHASE)))

    def knee_rot(base, group, u, phase, knee_bend, rot0):
        return qmul(rot0, qx(KNEE_SIGN[group]
                             * knee_flex(base, group, u, phase, knee_bend)))

    def fetlock_rot(base, group, u, phase, amp_scale, knee_bend, fetlock_bend,
                    snap_amp, rot0):
        # The hoof folds BACK over the positive half of a sine and is neutral the rest
        # of the stride -- the forward box offset (hooves.py) imitates the hoof resting on
        # the ground, so there is no stance ground-leveling. Folds the same way on all
        # legs via FETLOCK_SIGN (not the per-group knee sign). The crest sits at
        # FETLOCK_PEAK_PHASE per group: front folds in mid-swing, the hind hooves flick
        # back at the furthest-back push-off.
        ph = phase[base]
        s_fet = max(0.0, math.sin(2 * math.pi * (u - ph - FETLOCK_PEAK_PHASE[group])))
        amp = FETLOCK_SIGN * fetlock_bend * FETLOCK_GROUP_MULT[group]
        return qmul(rot0, qx(amp * s_fet))

    def clip_keys(name, beg, length, cfg):
        pos0, scl0, rot0 = rest[name]
        keys = []
        for j in range(length + 1):           # +1 closes the loop
            u = (j % length) / length
            pos, rot = list(pos0), rot0
            seg = leg_segment(name)
            if seg:
                group, idx = seg
                base = name[:-1] + "1"
                if idx == 1:
                    rot = leg_rot(name, u, cfg["amp"], cfg["phase"])
                elif idx == 2:
                    rot = knee_rot(base, group, u, cfg["phase"], cfg["knee"], rot0)
                else:
                    rot = fetlock_rot(base, group, u, cfg["phase"], cfg["amp"],
                                      cfg["knee"], cfg["fetlock"], cfg["snap"], rot0)
            elif name == "body":
                pos[1] = pos0[1] + cfg["bob"] * math.sin(2 * math.pi * cfg["bob_freq"] * u)
                if cfg["pitch"] != 0.0:
                    rot = qmul(rot0, qx(cfg["pitch"]
                        * math.sin(2 * math.pi * cfg["pitch_freq"] * u + PITCH_PHASE)))
            elif name == "neck":
                if cfg["neck_mode"] == "dip":
                    osc = -cfg["nod"] * (1 - math.cos(2 * math.pi * cfg["neck_freq"] * u)) / 2
                else:
                    osc = cfg["nod"] * math.sin(2 * math.pi * cfg["neck_freq"] * u)
                rot = qmul(rot0, qx(cfg["neck_pitch"] + osc))
            keys.append([beg + j, pos, scl0, rot])
        return keys

    def idle_keys(name):
        pos0, scl0, rot0 = rest[name]
        keys = []
        for j in range(IDLE_LEN + 1):
            u = j / IDLE_LEN
            rot = rot0
            if name == "neck":
                rot = qmul(rot0, qx(IDLE_SWAY * math.sin(2 * math.pi * u)))
            keys.append([IDLE_BEG + j, list(pos0), scl0, rot])
        return keys

    def graze_keys(name):
        # Standing self-feeding loop: legs/body/tail planted at rest; the neck
        # swings down and the head straightens in-line with it (mouth at ground),
        # plus a gentle chewing nod on the head.
        pos0, scl0, rot0 = rest[name]
        keys = []
        for j in range(GRAZE_LEN + 1):
            u = (j % GRAZE_LEN) / GRAZE_LEN
            rot = rot0
            if name == "neck":
                rot = qmul(rot0, qx(GRAZE_NECK_PITCH))        # own X (like the nods)
            elif name == "head":
                munch = GRAZE_MUNCH_AMP * math.sin(2 * math.pi * GRAZE_MUNCH_FREQ * u)
                rot = qmul(qx(GRAZE_HEAD_PITCH + munch), rot0)  # PRE-mult: neck-frame X
            keys.append([GRAZE_BEG + j, list(pos0), scl0, rot])
        return keys

    def buck_keys(name):
        # Rodeo: REAR (lean back, forelegs up/forward, head up) then PLUNGE (land on
        # the forelegs, hindquarters up, hind legs thrown back, head down). rear and
        # buck are the two half-waves of sin, so the poses sum without overlapping.
        pos0, scl0, rot0 = rest[name]
        seg = leg_segment(name)
        keys = []
        for j in range(BUCK_LEN + 1):
            u = (j % BUCK_LEN) / BUCK_LEN
            s = math.sin(2 * math.pi * u)
            rear = max(0.0, s)                  # first half: rear up (peak u=0.25)
            buck = max(0.0, -s)                 # second half: plunge (peak u=0.75)
            pos, rot = list(pos0), rot0
            if seg:
                group, idx = seg
                ref = leg[name[:-1] + "1"][0]
                if group == "front":
                    if idx == 1:                # up/forward in rear, reach to land in plunge
                        a = -(BUCK_FRONT_LIFT * rear + BUCK_FRONT_REACH * buck)
                        rot = qmul(rot0, axisangle(ref, a))
                    elif idx == 2:              # knee curls only while tucked up (rear)
                        rot = qmul(rot0, qx(KNEE_SIGN["front"] * BUCK_FRONT_KNEE * rear))
                    else:
                        rot = qmul(rot0, qx(FETLOCK_SIGN * BUCK_FRONT_FET * rear))
                else:                           # hind: planted in rear, thrown back in plunge
                    if idx == 1:
                        rot = qmul(rot0, axisangle(ref, BUCK_BACK_KICK * buck))
                    elif idx == 3:
                        rot = qmul(rot0, qx(FETLOCK_SIGN * BUCK_BACK_FET * buck))
            elif name == "body":
                # Lift in the gather, then lift hard through the plunge so the
                # nose-down pitch swings the rear up while the forefeet stay planted.
                pos[1] = pos0[1] + BUCK_REAR_RISE * rear + BUCK_PLUNGE_RISE * buck
                rot = qmul(rot0, qx(BUCK_GATHER_PITCH * rear - BUCK_PLUNGE_PITCH * buck))
            elif name == "neck":            # toss UP in the rear, DOWN in the plunge
                rot = qmul(rot0, qx(BUCK_NECK_BASE + BUCK_NECK_TOSS * s))
            elif name == "head":            # follows the neck, + tucks forward as it rears up
                rot = qmul(qx(BUCK_HEAD_BASE + BUCK_HEAD_TOSS * s
                              - BUCK_HEAD_FWD * rear), rot0)
            keys.append([BUCK_BEG + j, pos, scl0, rot])
        return keys

    def appended(name):
        return (clip_keys(name, CANTER_BEG, CANTER_LEN, CANTER_CFG)
                + clip_keys(name, GALLOP_BEG, GALLOP_LEN, GALLOP_CFG)
                + idle_keys(name)
                + clip_keys(name, TROT_BEG, TROT_LEN, TROT_CFG)
                + graze_keys(name)
                + buck_keys(name))

    new_last = BUCK_BEG + BUCK_LEN
    counts = {"keys": 0, "anim": 0}

    def edit(node):
        name = b3d.node_name(node)
        for c in node.children:
            if isinstance(c, b3d.Chunk) and c.tag == b"KEYS":
                flags, keys = parse_keys(c.payload)
                # Walk is now fully synthesised as a true 4-beat lateral gait
                # (frames 1..WALK_LAST), replacing the stock diagonal walk.
                walk = clip_keys(name, 1, WALK_LAST - 1, WALK_CFG)
                keys = walk + appended(name)
                c.payload = build_keys(flags, keys)
                counts["keys"] += 1
            elif isinstance(c, b3d.Chunk) and c.tag == b"ANIM":
                fl = struct.unpack("<i", c.payload[:4])[0]
                fps = struct.unpack("<f", c.payload[8:12])[0]
                c.payload = struct.pack("<iif", fl, new_last - 1, fps)
                counts["anim"] += 1
            elif isinstance(c, b3d.Node):
                edit(c)
    for o in top:
        if isinstance(o, b3d.Node):
            edit(o)

    size = b3d.write(DST, ver, top)
    print(f"wrote {DST}: {size} bytes; {counts['keys']} KEYS, {counts['anim']} ANIM")
    # Reshape the hoof geometry (mesh edit; the stock mesh was copied verbatim).
    import hooves
    nh, nm = hooves.apply(DST)
    print(f"  hooves: reshaped {nh} verts (W={hooves.HOOF_WIDTH} "
          f"H={hooves.HOOF_HEIGHT} D={hooves.HOOF_DEPTH} fwd={hooves.HOOF_FORWARD})")
    for n in LEGS:
        ref, _, amp, _ = leg[n]
        print(f"  {n}: swing amp={math.degrees(amp):.1f} deg "
              f"axis=({ref[0]:.2f},{ref[1]:.2f},{ref[2]:.2f}) "
              f"walk_phase={walk_phase[n]:.3f}")
    print(f"Luanti ranges: walk 0-40  trot {TROT_BEG-1}-{TROT_BEG+TROT_LEN-1}"
          f"  canter {CANTER_BEG-1}-{CANTER_BEG+CANTER_LEN-1}"
          f"  gallop {GALLOP_BEG-1}-{GALLOP_BEG+GALLOP_LEN-1}"
          f"  idle {IDLE_BEG-1}-{IDLE_BEG+IDLE_LEN-1}"
          f"  graze {GRAZE_BEG-1}-{GRAZE_BEG+GRAZE_LEN-1}"
          f"  buck {BUCK_BEG-1}-{BUCK_BEG+BUCK_LEN-1}")


if __name__ == "__main__":
    main()

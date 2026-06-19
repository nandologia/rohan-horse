#!/usr/bin/env python3
"""Reshape the hoof (fetlock = the leg.*.3 segment) in edoras_horse.b3d.

make_anim.py copies the stock mesh verbatim, so this runs AFTER it (make_anim.py
calls apply() at the end) to edit the hoof geometry across every body mesh
(coat / chest / saddle layers):

  * WIDTH  -- scale the hoof's X width to match the upper leg (the stock fetlock
              is wider than the leg above it).
  * OFFSET -- shift the whole fetlock box forward (+Z, toward the head) so it
              sits slightly in front of the leg above it. Stays a rectangular
              prism (every vert moves equally), so there's a small forward step
              at the knee/fetlock seam by design.

Vertices are edited in place (same byte size, so file offsets stay valid). Only
verts dominantly weighted to a leg.*.3 bone AND low to the ground (Y <= HOOF_YMAX)
are touched, so the chest/saddle overlay boxes are never disturbed.

The hoof box is resized to exact dimensions (W x H x D) and then offset forward.
Width is anchored about the box centre, depth about its centre, height about its
BOTTOM (so the hoof stays planted on the ground as it grows/shrinks taller).

Tunables (the stock fetlock is ~0.80 W x 0.60 H x 0.80 D):
  HOOF_WIDTH    target X (left-right) size.
  HOOF_HEIGHT   target Y (up-down) size, grown from the bottom.
  HOOF_DEPTH    target Z (front-back) size.
  HOOF_FORWARD  +Z offset applied after resizing (toward the head). Flip the
                sign if the hoof shifts backward in-game.
"""
import struct, os

HOOF_WIDTH   = 0.70
HOOF_HEIGHT  = 0.70
HOOF_DEPTH   = 0.60
HOOF_FORWARD = 0.10
HOOF_NODES   = ("leg.front.left3", "leg.front.right3",
                "leg.back.left3",  "leg.back.right3")
HOOF_YMAX    = 1.0   # verts above this aren't the hoof (guards overlay meshes)

DST = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "models", "edoras_horse.b3d")


def apply(path=DST, width=HOOF_WIDTH, height=HOOF_HEIGHT, depth=HOOF_DEPTH,
          forward=HOOF_FORWARD):
    buf = bytearray(open(path, "rb").read())

    def ci(o): return struct.unpack_from("<i", buf, o)[0]
    def cf(o): return struct.unpack_from("<f", buf, o)[0]

    total = ci(4)
    meshes = []                       # {vbase, stride, nv, bones:{name:[(vid,w)]}}
    cur = [None]

    def walk(o, end, name):
        while o + 8 <= end:
            tag = bytes(buf[o:o + 4]); ln = ci(o + 4); body = o + 8; nend = body + ln
            if tag == b"NODE":
                e = buf.index(b"\x00", body)
                walk(e + 1 + 40, nend, buf[body:e].decode("latin1"))
            elif tag == b"MESH":
                cur[0] = {"bones": {}}; meshes.append(cur[0])
                walk(body + 4, nend, name)            # skip brush id, find VRTS
            elif tag == b"VRTS":
                flags = ci(body); ts = ci(body + 4); tz = ci(body + 8)
                stride = 3 + (3 if flags & 1 else 0) + (4 if flags & 2 else 0) + ts * tz
                cur[0]["vbase"] = body + 12; cur[0]["stride"] = stride
                cur[0]["nv"] = (ln - 12) // (stride * 4)
            elif tag == b"BONE":
                cur[0]["bones"].setdefault(name, [(ci(body + k * 8), cf(body + k * 8 + 4))
                                                  for k in range(ln // 8)])
            o = nend
    walk(12, 8 + total, "")

    edited = 0
    for m in meshes:
        if "vbase" not in m:
            continue
        vbase, stride, nv = m["vbase"], m["stride"], m["nv"]
        def vx(i): return vbase + i * stride * 4
        for name in HOOF_NODES:
            ids = sorted(set(vid for vid, w in m["bones"].get(name, [])
                             if w > 0.5 and vid < nv))
            if not ids:
                continue
            ys = [cf(vx(i) + 4) for i in ids]
            if max(ys) > HOOF_YMAX:                   # not the hoof box; skip
                continue
            xs = [cf(vx(i)) for i in ids]
            zs = [cf(vx(i) + 8) for i in ids]
            cx = (min(xs) + max(xs)) / 2.0           # width  -> about centre
            ylo = min(ys)                            # height -> about the bottom
            cz = (min(zs) + max(zs)) / 2.0           # depth  -> about centre
            def sc(span, target): return (target / span) if span > 1e-4 else 1.0
            sx = sc(max(xs) - min(xs), width)
            sy = sc(max(ys) - min(ys), height)
            sz = sc(max(zs) - min(zs), depth)
            for i in ids:
                o = vx(i)
                x, y, z = cf(o), cf(o + 4), cf(o + 8)
                struct.pack_into("<f", buf, o,     cx + (x - cx) * sx)
                struct.pack_into("<f", buf, o + 4, ylo + (y - ylo) * sy)
                struct.pack_into("<f", buf, o + 8, cz + (z - cz) * sz + forward)
                edited += 1
    open(path, "wb").write(buf)
    return edited, len([m for m in meshes if "vbase" in m])


if __name__ == "__main__":
    n, nm = apply()
    print(f"hooves: reshaped {n} verts across {nm} meshes "
          f"(W={HOOF_WIDTH} H={HOOF_HEIGHT} D={HOOF_DEPTH} fwd={HOOF_FORWARD})")

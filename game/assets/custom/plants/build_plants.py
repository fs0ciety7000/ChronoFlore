"""ChronoFlore plant species generator (Blender bpy, headless, deterministic).

Builds the hand-made, rigged and animated emotion-plants and writes one GLB per species:
<id>/<id>.glb next to this script. Each model is a single skinned mesh with named
materials (base colour + a 0.2 emission lift, like the heroine), origin on the ground,
facing -Y in Blender (+Z in Godot), with the actions Idle, Move, Sleep, Caught
(+ Attack for hostiles). Idle, Move and Sleep loop (set by the .glb.import next to
each GLB, written on first run). Eyes close by scaling the eye.* bones to ~0 and the
shut.* (closed-eye arcs) bones to 1.

Usage: <bpy python> build_plants.py [species_id ...]   (default: every species)
"""
import math
import os
import sys

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 60
LIGHT_LIFT = 0.2
HIDDEN = 0.01  # bone scale that hides a part (closed eyes)


# ---------------------------------------------------------------- colours / materials
def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    h = h.lstrip("#")
    return [srgb_to_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]


MATS = {}


def mat(name, hexc, rough=0.8, emit=LIGHT_LIFT):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col = hexcol(hexc)
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = (*col, 1.0)
    bsdf.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*col, 1.0)
    MATS[name] = m
    return m


# ---------------------------------------------------------------- geometry helpers
def frame(n, up=Vector((0, 0, 1))):
    """Tangent frame on a surface: x (to +X / character's left), y (up), n (out)."""
    n = n.normalized()
    x = up.cross(n)
    if x.length < 1e-6:
        x = Vector((1, 0, 0))
    x.normalize()
    y = n.cross(x).normalized()
    return x, y, n


def basis(x, y, z):
    return Matrix((x, y, z)).transposed()


def ellipsoid(c, r, u=16, v=10, m=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    for vt in bm.verts:
        p = Vector((vt.co.x * r[0], vt.co.y * r[1], vt.co.z * r[2]))
        if m is not None:
            p = m @ p
        vt.co = p + Vector(c)
    return bm


def surf(c, r, yaw, el):
    """Point and normal on an ellipsoid; yaw 0 = front (-Y), + towards +X; el = elevation."""
    d = Vector((math.sin(yaw) * math.cos(el), -math.cos(yaw) * math.cos(el), math.sin(el)))
    p = Vector((c[0] + d.x * r[0], c[1] + d.y * r[1], c[2] + d.z * r[2]))
    n = Vector((d.x / r[0], d.y / r[1], d.z / r[2])).normalized()
    return p, n


def tube(points, radii, sides=6):
    """Closed tube along a polyline (parallel-transported frames); radius 0 ends in a point."""
    bm = bmesh.new()
    pts = [Vector(p) for p in points]
    n = len(pts)
    tangents = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    up = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    nrm = tangents[0].cross(up).normalized()
    rings = []
    for i, p in enumerate(pts):
        t = tangents[i]
        nrm = (nrm - t * nrm.dot(t)).normalized()
        b = t.cross(nrm)
        if radii[i] < 1e-6:
            rings.append([bm.verts.new(p)])
            continue
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (nrm * math.cos(a) + b * math.sin(a)) * radii[i]))
        rings.append(ring)
    for k in range(n - 1):
        a, b = rings[k], rings[k + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(sides):
                bm.faces.new((a[0], b[i], b[(i + 1) % sides]))
        elif len(b) == 1:
            for i in range(sides):
                bm.faces.new((a[i], a[(i + 1) % sides], b[0]))
        else:
            for i in range(sides):
                j = (i + 1) % sides
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if len(rings[0]) > 1:
        bm.faces.new(rings[0])
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def lathe(profile, seg=20, rfun=None, m=None, origin=Vector((0, 0, 0))):
    """Surface of revolution around Z; profile = [(r, z)] top to bottom, r == 0 makes a pole.
    rfun(angle, row) scales the radius (lobes); m rotates around origin."""
    bm = bmesh.new()
    rings = []
    for row, (r, z) in enumerate(profile):
        if r < 1e-6:
            rings.append([bm.verts.new(Vector((0, 0, z)))])
            continue
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            rr = r * (rfun(a, row) if rfun else 1.0)
            ring.append(bm.verts.new(Vector((math.sin(a) * rr, -math.cos(a) * rr, z))))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        if len(a) == 1:
            for i in range(seg):
                bm.faces.new((a[0], b[i], b[(i + 1) % seg]))
        elif len(b) == 1:
            for i in range(seg):
                bm.faces.new((a[i], a[(i + 1) % seg], b[0]))
        else:
            for i in range(seg):
                j = (i + 1) % seg
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if m is not None:
        for vt in bm.verts:
            vt.co = m @ (vt.co - origin) + origin
    return bm


def leaf(base, direction, normal, length, width, thick, curl=0.0, u=8, v=6):
    """Closed leaf/petal: ellipsoid along `direction` from `base`, flat along `normal`,
    tip bent by `curl` towards `normal`."""
    y = Vector(direction).normalized()
    z = Vector(normal)
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    m = basis(x, y, z)
    for vt in bm.verts:
        # sphere pole axis is Z: map it to the leaf length (local y)
        ly = (vt.co.z + 1.0) * 0.5 * length
        lx = vt.co.x * width * 0.5
        lz = vt.co.y * thick * 0.5 + curl * (ly / length) ** 2
        vt.co = m @ Vector((lx, ly, lz)) + Vector(base)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def arc_points(center, x, y, n, half_w, depth, count=7, bulge=0.0, sag_r=0.2):
    """Curve in the tangent plane: depth > 0 bends down (smile), < 0 bends up (frown).
    Pulled back onto a surface of radius ~sag_r."""
    out = []
    for k in range(count):
        u = -1.0 + 2.0 * k / (count - 1)
        off = u * half_w
        p = center + x * off - y * depth * (1.0 - u * u) + n * (bulge - off * off / (2 * sag_r))
        out.append(p)
    return out


def catmull(pts, samples):
    pts = [Vector(p) for p in pts]
    p = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    segs = len(pts) - 1
    for k in range(samples):
        u = k / (samples - 1) * segs
        i = min(int(u), segs - 1)
        t = u - i
        p0, p1, p2, p3 = p[i], p[i + 1], p[i + 2], p[i + 3]
        t2, t3 = t * t, t * t * t
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return out


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- object assembly
PARTS = []
TRIS = {}


def add_part(name, bm, mat_name, weight_fn, smooth=True):
    me = bpy.data.meshes.new(name)
    for f in bm.faces:
        f.smooth = smooth
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MATS[mat_name])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    groups = {}
    for vtx in me.vertices:
        for bone, w in weight_fn(Vector(vtx.co)):
            if w <= 1e-4:
                continue
            if bone not in groups:
                groups[bone] = ob.vertex_groups.new(name=bone)
            groups[bone].add([vtx.index], w, "REPLACE")
    PARTS.append(ob)
    TRIS[name] = TRIS.get(name, 0) + len(me.polygons)
    return ob


def rigid(bone):
    return lambda p: [(bone, 1.0)]


def along_z(bone_a, bone_b, z0, z1):
    def fn(p):
        t = smoothstep(z0, z1, p.z)
        return [(bone_a, 1.0 - t), (bone_b, t)]
    return fn


BONES = []  # (name, head, tail, parent, roll_vec)
FWD = Vector((0, -1, 0))


def bone(name, head, tail, parent=None, roll=FWD):
    BONES.append((name, Vector(head), Vector(tail), parent, Vector(roll)))


def face_eye(side, c, r, yaw, el, w, h, parent, iris="EyeDark", sclera=None, pupil_shift=(0.0, 0.0),
             lid=None):
    """Big kawaii eye on an ellipsoid (c, r): eye.<S> bone (open eye) + shut.<S> bone (closed arc)."""
    S = "L" if side > 0 else "R"
    p, n = surf(c, r, side * yaw, el)
    x, y, n = frame(n)
    m = basis(x, y, n)
    center = p + n * 0.002
    eye_b = "eye." + S
    shut_b = "shut." + S
    bone(eye_b, center, center + y * 0.04, parent, roll=n)
    bone(shut_b, center, center + y * 0.04, parent, roll=n)
    front = center
    if sclera is not None:
        add_part("Sclera." + S, ellipsoid(center, (w, h, 0.016), 12, 7, m), sclera, rigid(eye_b))
        pw, ph = w * 0.55, h * 0.62
        front = center + x * (pupil_shift[0] * side * w) + y * (pupil_shift[1] * h) + n * 0.01
        add_part("Iris." + S, ellipsoid(front, (pw, ph, 0.012), 10, 6, m), iris, rigid(eye_b))
        hl_w, hl_h = pw, ph
        depth = 0.012
    else:
        add_part("Iris." + S, ellipsoid(center, (w, h, 0.018), 10, 6, m), iris, rigid(eye_b))
        hl_w, hl_h = w, h
        depth = 0.018
    # highlights: same screen side on both eyes (one light)
    big = front + x * (-0.32 * hl_w) + y * (0.36 * hl_h) + n * (depth * 0.8)
    add_part("EyeHi." + S, ellipsoid(big, (0.3 * hl_w, 0.3 * hl_w, 0.006), 8, 5, m), "EyeWhite", rigid(eye_b))
    small = front + x * (0.34 * hl_w) + y * (-0.38 * hl_h) + n * (depth * 0.75)
    add_part("EyeHi2." + S, ellipsoid(small, (0.14 * hl_w, 0.14 * hl_w, 0.005), 6, 4, m), "EyeWhite",
             rigid(eye_b))
    if lid is not None:
        lid_mat, cover = lid
        lc = center + y * (h * (1.0 - cover) + 0.006) + n * 0.003
        add_part("Lid." + S, ellipsoid(lc, (w * 1.22, h * 0.62, 0.024), 10, 5, m), lid_mat, rigid(eye_b))
    # closed eye: soft downward arc, hidden (bone scale ~0) unless asleep
    pts = arc_points(center, x, y, n, w * 0.95, h * 0.32, count=7, bulge=0.006, sag_r=min(r[0], r[2]))
    add_part("Shut." + S, tube(pts, [0.0] + [0.0075] * 5 + [0.0], sides=5), iris, rigid(shut_b))
    return center, x, y, n


def face_decal(name, c, r, yaw, el, radii, mat_name, parent_bone):
    p, n = surf(c, r, yaw, el)
    x, y, n = frame(n)
    add_part(name, ellipsoid(p + n * 0.001, radii, 8, 5, basis(x, y, n)), mat_name, rigid(parent_bone))


def mouth(c, r, el, half_w, depth, parent_bone, mat_name="Mouth", thick=0.0075, yaw=0.0):
    p, n = surf(c, r, yaw, el)
    x, y, n = frame(n)
    pts = arc_points(p, x, y, n, half_w, depth, count=7, bulge=0.004, sag_r=min(r[0], r[2]))
    add_part("Mouth", tube(pts, [0.0] + [thick] * 5 + [0.0], sides=5), mat_name, rigid(parent_bone))
    return p, x, y, n


# ---------------------------------------------------------------- species: Rêvette
def build_revette():
    """Joie légère: round butter-yellow flower face in a peach petal ring, on a leafy stem."""
    mat("RevetteFace", "#fff0b8", rough=0.75)
    mat("RevettePetalA", "#ffcfb3", rough=0.75)
    mat("RevettePetalB", "#ffe2c6", rough=0.75)
    mat("RevetteStem", "#addcb6", rough=0.85)
    mat("RevetteLeaf", "#c3ebc7", rough=0.85)
    mat("EyeDark", "#3d3346", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#8a3f52", rough=0.6)
    mat("Blush", "#ffadc0", rough=0.8)

    hc = Vector((0, 0, 0.53))
    hr = Vector((0.18, 0.15, 0.165))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("stem", (0, 0, 0.03), (0, 0, 0.36), "root")
    bone("head", (0, 0, 0.36), (0, 0, 0.75), "stem")
    bone("crown", (0, 0.03, hc.z), (0, 0.03, hc.z + 0.12), "head")
    bone("leaf.L", (0.035, 0, 0.19), (0.2, -0.02, 0.3), "stem")
    bone("leaf.R", (-0.035, 0, 0.19), (-0.2, -0.02, 0.3), "stem")

    add_part("Head", ellipsoid(hc, hr, 18, 10), "RevetteFace", rigid("head"))
    for k in range(10):
        a = math.radians(k * 36 + 18)
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        base = Vector((0, 0.05, hc.z)) + d * 0.1
        direction = (d + Vector((0, 0.3, 0))).normalized()
        add_part("Petal%d" % k, leaf(base, direction, Vector((0, -1, 0)), 0.17, 0.13, 0.035, curl=-0.035),
                 "RevettePetalA" if k % 2 == 0 else "RevettePetalB", rigid("crown"))
    stem_prof = [(0.0, 0.42), (0.036, 0.4), (0.038, 0.3), (0.044, 0.17), (0.056, 0.07), (0.05, 0.03), (0.0, 0.02)]
    add_part("Stem", lathe(stem_prof, 8), "RevetteStem", along_z("stem", "head", 0.3, 0.42))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Leaf." + S, leaf((s * 0.03, 0, 0.19), (s * 0.85, -0.1, 0.5), (0, -0.3, 1), 0.2, 0.1, 0.025,
                                   curl=0.035), "RevetteLeaf", rigid("leaf." + S))
        add_part("Foot." + S, ellipsoid((s * 0.062, -0.02, 0.032), (0.05, 0.065, 0.034), 8, 5), "RevetteStem",
                 rigid("root"))
        face_eye(s, hc, hr, 0.37, 0.02, 0.04, 0.052, "head")
        face_decal("Blush." + S, hc, hr, s * 0.66, -0.16, (0.034, 0.019, 0.006), "Blush", "head")
    # open happy smile
    p, x, y, n = mouth(hc, hr, -0.2, 0.03, 0.016, "head")
    add_part("Tongue", ellipsoid(p - y * 0.01 + n * 0.002, (0.016, 0.009, 0.005), 8, 5, basis(x, y, n)),
             "Mouth", rigid("head"))
    return {"root": "root", "lower": "stem", "upper": "head",
            "arms": [("leaf.L", 1), ("leaf.R", -1)], "extra": revette_extra}


def revette_extra(action, t):
    if action == "Idle":
        return {"crown": {"rot": (0, 0, 6 * math.sin(2 * math.pi * t))}}
    if action == "Move":  # pinwheel: 2 petals per loop (colours alternate every 36 deg)
        return {"crown": {"rot": (0, 0, -72 * t)}}
    if action == "Sleep":
        return {"crown": {"rot": (0, 0, 4), "scale": (0.96, 0.96, 0.96)}}
    return {}


# ---------------------------------------------------------------- species: Nostalgerbe
NOSTAL_BLADES = [  # yaw (deg, 0 = back, + towards +X), height scale, droop, material, tip bone
    (-115, 0.9, 1.0, "NostalBladeA", "tip.R"),
    (-75, 1.0, 0.9, "NostalBladeB", "tip.R"),
    (-38, 1.12, 0.8, "NostalBladeC", "tip.R"),
    (0, 1.2, 0.7, "NostalBladeA", "tip.B"),
    (38, 1.12, 0.8, "NostalBladeB", "tip.L"),
    (75, 1.0, 0.9, "NostalBladeC", "tip.L"),
    (115, 0.9, 1.0, "NostalBladeA", "tip.L"),
]


def build_nostalgerbe():
    """Nostalgie: lavender-blue bulb with wistful half-lidded eyes under a fountain of feather-grass."""
    mat("NostalBody", "#cdd5f7", rough=0.75)
    mat("NostalLid", "#bcc5f0", rough=0.75)
    mat("NostalBladeA", "#b0bbef", rough=0.8)
    mat("NostalBladeB", "#c5baf0", rough=0.8)
    mat("NostalBladeC", "#d3c8f5", rough=0.8)
    mat("NostalPlume", "#e4dcfa", rough=0.9)
    mat("EyeDark", "#3a3350", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#6d4466", rough=0.6)
    mat("Blush", "#e9b9d6", rough=0.8)

    bc = Vector((0, 0, 0.215))
    br = Vector((0.205, 0.185, 0.2))
    top = Vector((0, 0.02, 0.38))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.02), (0, 0, 0.38), "root")
    bone("plume", (0, 0.02, 0.38), (0, 0.02, 0.58), "body")
    bone("tip.L", (0.14, 0.06, 0.62), (0.3, 0.08, 0.66), "plume")
    bone("tip.R", (-0.14, 0.06, 0.62), (-0.3, 0.08, 0.66), "plume")
    bone("tip.B", (0, 0.16, 0.66), (0, 0.32, 0.68), "plume")

    add_part("Body", ellipsoid(bc, br, 18, 10), "NostalBody", rigid("body"))
    add_part("Collar", ellipsoid(top + Vector((0, 0, -0.01)), (0.07, 0.065, 0.035), 10, 5), "NostalBladeA",
             rigid("body"))
    for k, (yaw, hs, droop, mname, tip) in enumerate(NOSTAL_BLADES):
        a = math.radians(yaw)
        out = Vector((math.sin(a), math.cos(a), 0.0))
        up = Vector((0, 0, 1))
        b0 = top + out * 0.03
        ctrl = [b0, b0 + up * 0.16 * hs + out * 0.04, b0 + up * 0.32 * hs + out * 0.13,
                b0 + up * 0.4 * hs + out * 0.26, b0 + up * (0.4 * hs - 0.1 * droop) + out * (0.36 + 0.03 * droop)]
        pts = catmull(ctrl, 8)
        radii = [0.036 - 0.02 * (i / 7) for i in range(8)]
        radii[-1] = 0.0

        def blade_w(p, tip=tip):
            t = smoothstep(0.42, 0.7, p.z)
            return [("plume", 1.0 - t), (tip, t)]
        add_part("Blade%d" % k, tube(pts, radii, sides=5), mname, blade_w)
        # feathery plume along the drooping end
        end_dir = (pts[-1] - pts[-3]).normalized()
        side = end_dir.cross(Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        add_part("Plume%d" % k, leaf(pts[-3] - end_dir * 0.03, end_dir, side.cross(end_dir), 0.2, 0.105, 0.075),
                 "NostalPlume", rigid(tip))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Foot." + S, ellipsoid((s * 0.075, -0.03, 0.03), (0.05, 0.06, 0.032), 8, 5), "NostalBladeA",
                 rigid("root"))
        face_eye(s, bc, br, 0.38, 0.08, 0.04, 0.05, "body", lid=("NostalLid", 0.42))
        face_decal("Blush." + S, bc, br, s * 0.66, -0.07, (0.032, 0.017, 0.006), "Blush", "body")
    mouth(bc, br, -0.16, 0.02, 0.009, "body")
    return {"root": "root", "lower": "body", "upper": "plume", "arms": [], "extra": nostal_extra}


def nostal_extra(action, t):
    s = math.sin(2 * math.pi * t)
    c = math.cos(2 * math.pi * t)
    if action == "Idle":
        return {"tip.L": {"rot": (4 * c, 0, 8 * s)}, "tip.R": {"rot": (4 * c, 0, -8 * s)},
                "tip.B": {"rot": (6 * s, 0, 4 * c)}}
    if action == "Move":
        w = math.sin(4 * math.pi * t)
        return {"tip.L": {"rot": (-18, 0, 10 * w)}, "tip.R": {"rot": (-18, 0, -10 * w)},
                "tip.B": {"rot": (-22 + 8 * w, 0, 0)}}
    if action == "Sleep":
        return {"tip.L": {"rot": (0, 0, -18)}, "tip.R": {"rot": (0, 0, 18)}, "tip.B": {"rot": (14, 0, 0)}}
    return {}


# ---------------------------------------------------------------- species: Timidelle
def build_timidelle():
    """Timidité: cream bulb peeking from under a big pink rosebud cap, leaf hands up to its blush."""
    mat("TimiBody", "#fff1ee", rough=0.75)
    mat("TimiCap", "#ffbfd0", rough=0.7)
    mat("TimiPetal", "#ffa7bf", rough=0.7)
    mat("TimiLeaf", "#c3ebc7", rough=0.85)
    mat("TimiFoot", "#f6dcd6", rough=0.8)
    mat("EyeDark", "#3d3346", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#8a3f52", rough=0.6)
    mat("Blush", "#ff98b2", rough=0.8)

    bc = Vector((0, 0, 0.19))
    br = Vector((0.195, 0.18, 0.185))
    pivot = Vector((0, 0, 0.3))
    tilt = Matrix.Rotation(math.radians(6), 3, "X")  # front of the bud leaning down a little (shy)
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.02), (0, 0, 0.3), "root")
    bone("cap", (0, 0, 0.3), (0, 0, 0.72), "body")
    bone("leaf.L", (0.15, -0.06, 0.13), (0.19, -0.1, 0.25), "body")
    bone("leaf.R", (-0.15, -0.06, 0.13), (-0.19, -0.1, 0.25), "body")

    add_part("Body", ellipsoid(bc, br, 18, 10), "TimiBody", rigid("body"))
    # rosebud: a pointed teardrop of furled petals...
    cap_prof = [(0.0, 0.72), (0.045, 0.7), (0.1, 0.645), (0.152, 0.565), (0.184, 0.48), (0.19, 0.41),
                (0.172, 0.355), (0.13, 0.322), (0.0, 0.318)]

    def lobes(a, row):
        return 1.0 + (0.05 if 0 < row < len(cap_prof) - 1 else 0.0) * math.cos(3 * a + row * 0.5)
    add_part("Cap", lathe(cap_prof, 18, rfun=lobes, m=tilt, origin=pivot), "TimiCap", rigid("cap"))
    # ...hugged by three outer petals, opening a little at their tips
    for k in range(3):
        a = math.radians(k * 120 + 60)
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        base = Vector((0, 0, 0.31)) + out * 0.14
        direction = (out * 0.22 + Vector((0, 0, 1))).normalized()
        bm = leaf(base, direction, out, 0.25, 0.25, 0.04, curl=0.05, u=10, v=6)
        for vt in bm.verts:
            vt.co = tilt @ (vt.co - pivot) + pivot
        add_part("BudPetal%d" % k, bm, "TimiPetal", rigid("cap"))
    sprout = tilt @ (Vector((0, 0, 0.7)) - pivot) + pivot
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Sprout." + S, leaf(sprout, (s * 0.8, 0.1, 0.6), (0, 0, 1), 0.11, 0.06, 0.02, curl=0.02),
                 "TimiLeaf", rigid("cap"))
        # leaf hands raised shyly towards the cheeks
        add_part("Hand." + S, leaf((s * 0.15, -0.06, 0.13), (s * 0.2, -0.45, 0.85), (0, -1, 0.2), 0.13, 0.075,
                                   0.022, curl=-0.02), "TimiLeaf", rigid("leaf." + S))
        add_part("Foot." + S, ellipsoid((s * 0.07, -0.03, 0.03), (0.05, 0.06, 0.032), 8, 5), "TimiFoot",
                 rigid("root"))
        face_eye(s, bc, br, 0.34, 0.16, 0.038, 0.05, "body")
        face_decal("Blush." + S, bc, br, s * 0.6, 0.02, (0.042, 0.024, 0.006), "Blush", "body")
    # tiny wobbly 'o' mouth
    p, n = surf(bc, br, 0.0, 0.03)
    x, y, n = frame(n)
    add_part("Mouth", ellipsoid(p + n * 0.002, (0.011, 0.009, 0.005), 8, 5, basis(x, y, n)), "Mouth",
             rigid("body"))
    return {"root": "root", "lower": "body", "upper": "cap",
            "arms": [("leaf.L", 1), ("leaf.R", -1)], "arm_rest": 0.0, "arm_swing": 0.4, "extra": timi_extra}


def timi_extra(action, t):
    if action == "Idle":  # peeks out from the cap now and then
        peek = smoothstep(0.35, 0.5, t) * (1 - smoothstep(0.6, 0.75, t))
        return {"cap": {"rot": (-7 * peek, 0, 0)}}
    if action == "Move":  # cap pulled down while fleeing
        return {"cap": {"rot": (8, 0, 3 * math.sin(2 * math.pi * t))}}
    return {}


# ---------------------------------------------------------------- species: Ronce-Angoisse
def fib_dirs(count):
    out = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        z = 1 - (i + 0.5) / count * 2
        r = math.sqrt(1 - z * z)
        a = golden * i
        out.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
    return out


def build_ronce_angoisse():
    """Angoisse (hostile): dusty violet bramble ball, frowning brows, tiny fangs; menacing but cute."""
    mat("RonceBody", "#a493b4", rough=0.85)
    mat("RonceVine", "#86759a", rough=0.85)
    mat("RonceThorn", "#6f6480", rough=0.7)
    mat("RonceRoot", "#8f8299", rough=0.9)
    mat("RonceLeaf", "#a9b79c", rough=0.85)
    mat("RonceSclera", "#f6e7a6", rough=0.35)
    mat("EyeDark", "#2f2738", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Brow", "#4f4260", rough=0.7)
    mat("Mouth", "#3f2c48", rough=0.6)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Blush", "#c99bbb", rough=0.8)

    bc = Vector((0, 0, 0.41))
    br = Vector((0.285, 0.265, 0.27))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("base", (0, 0, 0.02), (0, 0, 0.2), "root")
    bone("body", (0, 0, 0.2), (0, 0, 0.72), "base")
    bone("arm.L", (0.27, 0, 0.34), (0.45, -0.04, 0.4), "body")
    bone("arm.R", (-0.27, 0, 0.34), (-0.45, -0.04, 0.4), "body")

    add_part("Body", ellipsoid(bc, br, 18, 11), "RonceBody", rigid("body"))
    add_part("Base", ellipsoid((0, 0, 0.085), (0.2, 0.185, 0.075), 14, 6), "RonceRoot",
             along_z("base", "body", 0.1, 0.2))
    for k in range(4):
        a = math.radians(45 + 90 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [d * 0.17 + Vector((0, 0, 0.07)), d * 0.26 + Vector((0, 0, 0.035)), d * 0.33 + Vector((0, 0, 0.012))]
        add_part("Root%d" % k, tube(pts, [0.03, 0.022, 0.0], sides=5), "RonceRoot", rigid("root"))
    # bramble vines around the back half (the face stays clear)
    for k, (el0, amp, ph) in enumerate(((-0.28, 0.12, 0.0), (0.32, 0.1, 1.7))):
        pts = []
        for i in range(12):
            u = i / 11
            yaw = math.radians(70 + 220 * u)
            el = el0 + amp * math.sin(2 * math.pi * u * 1.5 + ph)
            p, n = surf(bc, br, yaw, el)
            pts.append(p + n * 0.012)
        add_part("Vine%d" % k, tube(pts, [0.0] + [0.024] * 10 + [0.0], sides=5), "RonceVine", rigid("body"))
    # thorns, avoiding the face and the underside
    count = 0
    for d in fib_dirs(30):
        if d.z < -0.35 or (d.y < -0.45 and d.z < 0.75):
            continue
        p = Vector((bc.x + d.x * br.x, bc.y + d.y * br.y, bc.z + d.z * br.z))
        n = Vector((d.x / br.x, d.y / br.y, d.z / br.z)).normalized()
        length = 0.11 + 0.04 * ((count * 7) % 3) / 2
        tip = p + (n + Vector((0, 0, 0.25))).normalized() * length
        add_part("Thorn%d" % count, tube([p - n * 0.01, tip], [0.038, 0.0], sides=5), "RonceThorn", rigid("body"))
        count += 1
    # wilted sprout on top
    topp = bc + Vector((0, 0.02, br.z - 0.01))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Sprout." + S, leaf(topp, (s * 0.7, 0.15, 0.6), (0, 0, 1), 0.13, 0.07, 0.02, curl=-0.03),
                 "RonceLeaf", rigid("body"))
    for s, S in ((1, "L"), (-1, "R")):
        # curly vine arms with two thorns
        p0, n0 = surf(bc, br, s * 1.45, -0.12)
        side = Vector((s, 0, 0))
        ctrl = [p0 - n0 * 0.01, p0 + side * 0.09 + Vector((0, -0.02, 0.0)), p0 + side * 0.17 + Vector((0, -0.05, 0.06)),
                p0 + side * 0.19 + Vector((0, -0.07, 0.13)), p0 + side * 0.14 + Vector((0, -0.07, 0.17))]
        pts = catmull(ctrl, 9)
        add_part("Arm." + S, tube(pts, [0.03 - 0.022 * i / 8 for i in range(8)] + [0.0], sides=5), "RonceVine",
                 rigid("arm." + S))
        for j, i in enumerate((3, 6)):
            tang = (pts[i + 1] - pts[i - 1]).normalized()
            out = tang.cross(Vector((0, 1, 0))).normalized() * (-1 if j else 1) * s
            add_part("ArmThorn%d.%s" % (j, S), tube([pts[i], pts[i] + out * 0.055], [0.016, 0.0], sides=4),
                     "RonceThorn", rigid("arm." + S))
        center, x, y, n = face_eye(s, bc, br, 0.29, 0.12, 0.05, 0.056, "body", sclera="RonceSclera",
                                   pupil_shift=(-0.18, -0.12))
        # frowning brow: inner end low, outer end high
        pi, ni = surf(bc, br, s * 0.1, 0.3)
        po, no = surf(bc, br, s * 0.44, 0.36)
        pm, nm = surf(bc, br, s * 0.27, 0.355)
        add_part("Brow." + S, tube([pi + ni * 0.012, pm + nm * 0.016, po + no * 0.012], [0.011, 0.017, 0.009],
                                   sides=5), "Brow", rigid("body"))
        face_decal("Blush." + S, bc, br, s * 0.6, -0.06, (0.034, 0.018, 0.006), "Blush", "body")
    # pouty frown + two tiny fangs
    p, x, y, n = mouth(bc, br, -0.13, 0.042, -0.014, "body", thick=0.009)
    for s in (1, -1):
        fb = p + x * (s * 0.02) + n * 0.006 - y * 0.004
        add_part("Fang.%d" % s, tube([fb, fb - y * 0.026 + n * 0.002], [0.011, 0.0], sides=5), "Teeth",
                 rigid("body"))
    return {"root": "root", "lower": "base", "upper": "body",
            "arms": [("arm.L", 1), ("arm.R", -1)], "sleep_arm": 4.0, "attack": True, "extra": None}


# ---------------------------------------------------------------- species: Câlinette
def build_calinette():
    """Tendresse: cream face peeking out of a soft mint moss hood, leaf arms open for a hug,
    a pink heart sprout on top."""
    mat("CaliFace", "#fbf4e0", rough=0.85)
    mat("CaliMoss", "#bfe8c6", rough=0.95)
    mat("CaliTuft", "#d9f3d3", rough=0.95)
    mat("CaliLeaf", "#9fd8ae", rough=0.85)
    mat("CaliHeart", "#ffb1c5", rough=0.7)
    mat("EyeDark", "#3a3346", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#8a3f52", rough=0.6)
    mat("Blush", "#ff9fb9", rough=0.8)

    bc = Vector((0, 0, 0.215))
    br = Vector((0.2, 0.185, 0.195))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.02), (0, 0, 0.4), "root")
    bone("sprout", (0, 0.02, 0.43), (0, 0.02, 0.56), "body")
    bone("arm.L", (0.19, -0.04, 0.17), (0.3, -0.12, 0.22), "body")
    bone("arm.R", (-0.19, -0.04, 0.17), (-0.3, -0.12, 0.22), "body")

    add_part("Body", ellipsoid(bc, br, 18, 10), "CaliFace", rigid("body"))
    # moss hood: a lumpy shell over the back and top, open in front around the face
    hood = ellipsoid(bc + Vector((0, 0.018, 0.012)), (br.x * 1.1, br.y * 1.1, br.z * 1.1), 22, 12)
    hc = bc + Vector((0, 0.018, 0.012))
    for vt in hood.verts:
        d = (vt.co - hc).normalized()
        a = math.atan2(d.x, d.y)
        bump = 1.0 + 0.05 * math.sin(7 * a) * math.cos(5 * math.asin(max(-1.0, min(1.0, d.z))))
        vt.co = hc + (vt.co - hc) * bump
    face_hole = [f for f in hood.faces
                 if (f.calc_center_median() - hc).normalized().y < -0.5
                 and (f.calc_center_median() - hc).normalized().z < 0.62]
    bottom = [f for f in hood.faces if (f.calc_center_median() - hc).normalized().z < -0.72]
    bmesh.ops.delete(hood, geom=list(set(face_hole + bottom)), context="FACES")
    add_part("Hood", hood, "CaliMoss", rigid("body"))
    # a few fluffy tufts on the crown
    for k, d in enumerate(fib_dirs(22)):
        if d.z < 0.25 or d.y < -0.3:
            continue
        p = Vector((hc.x + d.x * br.x * 1.1, hc.y + d.y * br.y * 1.1, hc.z + d.z * br.z * 1.1))
        x, y, n = frame(Vector((d.x / br.x, d.y / br.y, d.z / br.z)))
        add_part("Tuft%d" % k, ellipsoid(p, (0.05, 0.05, 0.03), 7, 4, basis(x, y, n)),
                 "CaliTuft" if k % 2 else "CaliMoss", rigid("body"))
    # heart sprout: a short stem and two round pink leaves leaning together
    top = Vector((0, 0.02, hc.z + br.z * 1.1 - 0.01))
    add_part("SproutStem", tube([top, top + Vector((0, 0, 0.06))], [0.012, 0.009], sides=5), "CaliLeaf",
             rigid("sprout"))
    for s, S in ((1, "L"), (-1, "R")):
        base = top + Vector((0, 0, 0.055))
        add_part("Heart." + S, leaf(base, (s * 0.75, 0.0, 0.66), (0, -1, 0), 0.1, 0.085, 0.022, curl=0.0),
                 "CaliHeart", rigid("sprout"))
        # leaf arms reaching forward for a hug
        add_part("Arm." + S, leaf((s * 0.185, -0.04, 0.17), (s * 0.7, -0.6, 0.3), (0, 0, 1), 0.13, 0.08, 0.022,
                                  curl=0.025), "CaliLeaf", rigid("arm." + S))
        add_part("Foot." + S, ellipsoid((s * 0.07, -0.03, 0.03), (0.05, 0.06, 0.032), 8, 5), "CaliMoss",
                 rigid("root"))
        face_eye(s, bc, br, 0.33, 0.06, 0.044, 0.056, "body")
        face_decal("Blush." + S, bc, br, s * 0.6, -0.09, (0.04, 0.022, 0.006), "Blush", "body")
    # soft ':3' smile
    for s in (1, -1):
        mouth(bc, br, -0.12, 0.016, 0.01, "body", yaw=s * 0.075)
    return {"root": "root", "lower": "body", "upper": "sprout",
            "arms": [("arm.L", 1), ("arm.R", -1)], "arm_rest": 0.5, "extra": cali_extra}


def cali_extra(action, t):
    s = math.sin(2 * math.pi * t)
    if action == "Idle":  # the heart sprout sways like a wagging tail
        return {"sprout": {"rot": (0, 0, 10 * s)}}
    if action == "Move":
        return {"sprout": {"rot": (-10, 0, 14 * math.sin(4 * math.pi * t))}}
    if action == "Sleep":
        return {"sprout": {"rot": (16, 0, 10)}}
    return {}


# ---------------------------------------------------------------- species: Souffloine
def build_souffloine():
    """Insouciance: dandelion clock, a pale-yellow flower face in a cream-white puff of seeds,
    on a thin stem with leafy arms and feet."""
    mat("SouffPuff", "#f7f2e4", rough=0.95)
    mat("SouffSeed", "#ffffff", rough=0.9)
    mat("SouffSpoke", "#e6dfca", rough=0.9)
    mat("SouffFace", "#fff0a6", rough=0.8)
    mat("SouffStem", "#b9e0a9", rough=0.85)
    mat("SouffLeaf", "#a5d79a", rough=0.85)
    mat("EyeDark", "#3d3346", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#8a4a45", rough=0.6)
    mat("Blush", "#ffb5a3", rough=0.8)

    hc = Vector((0, 0, 0.5))
    core = 0.155
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("stem", (0, 0, 0.03), (0, 0, 0.32), "root")
    bone("head", (0, 0, 0.32), (0, 0, 0.78), "stem")
    bone("seeds", (0, 0.02, hc.z), (0, 0.02, hc.z + 0.15), "head")
    bone("arm.L", (0.02, 0, 0.2), (0.17, -0.02, 0.28), "stem")
    bone("arm.R", (-0.02, 0, 0.2), (-0.17, -0.02, 0.28), "stem")

    add_part("Puff", ellipsoid(hc + Vector((0, 0.02, 0)), (core, core, core), 12, 7), "SouffPuff",
             rigid("head"))
    for k, d in enumerate(fib_dirs(36)):
        if d.y < -0.66 or d.z < -0.8:
            continue  # the face, and where the stem goes in
        p0 = hc + Vector((0, 0.02, 0)) + d * (core - 0.01)
        p1 = hc + Vector((0, 0.02, 0)) + d * 0.25
        add_part("Spoke%d" % k, tube([p0, p1], [0.006, 0.004], sides=3), "SouffSpoke", rigid("seeds"))
        x, y, n = frame(d)
        add_part("Seed%d" % k, ellipsoid(p1 + d * 0.01, (0.042, 0.042, 0.02), 6, 3, basis(x, y, n)),
                 "SouffSeed", rigid("seeds"))
    # flower face on the front of the puff
    fc = hc + Vector((0, -0.11, -0.005))
    fr = Vector((0.13, 0.06, 0.12))
    add_part("Face", ellipsoid(fc, fr, 14, 7), "SouffFace", rigid("head"))
    stem_prof = [(0.0, 0.38), (0.026, 0.37), (0.026, 0.25), (0.03, 0.12), (0.04, 0.05), (0.034, 0.025), (0.0, 0.02)]
    add_part("Stem", lathe(stem_prof, 7), "SouffStem", along_z("stem", "head", 0.28, 0.38))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Arm." + S, leaf((s * 0.02, 0, 0.2), (s * 0.85, -0.1, 0.45), (0, -0.3, 1), 0.17, 0.07, 0.02,
                                  curl=0.03), "SouffLeaf", rigid("arm." + S))
        add_part("Foot." + S, leaf((s * 0.02, -0.01, 0.02), (s * 0.9, -0.35, 0.05), (0, 0, 1), 0.15, 0.075,
                                   0.022, curl=0.02), "SouffLeaf", rigid("root"))
        face_eye(s, fc, fr, 0.36, 0.1, 0.034, 0.044, "head")
        face_decal("Blush." + S, fc, fr, s * 0.62, -0.18, (0.03, 0.017, 0.006), "Blush", "head")
    # big carefree grin
    p, x, y, n = mouth(fc, fr, -0.24, 0.032, 0.02, "head")
    add_part("Tongue", ellipsoid(p - y * 0.012 + n * 0.002, (0.014, 0.008, 0.005), 8, 4, basis(x, y, n)),
             "Mouth", rigid("head"))
    return {"root": "root", "lower": "stem", "upper": "head",
            "arms": [("arm.L", 1), ("arm.R", -1)], "arm_swing": 1.4, "extra": souff_extra}


def souff_extra(action, t):
    s = math.sin(2 * math.pi * t)
    if action == "Idle":  # the puff turns lazily in the breeze
        return {"seeds": {"rot": (0, 0, 8 * s)}}
    if action == "Move":  # arms flap like wings, the puff spins
        return {"seeds": {"rot": (0, 0, -90 * t)}}
    if action == "Sleep":
        return {"seeds": {"scale": (0.97, 0.97, 0.97)}}
    return {}


# ---------------------------------------------------------------- species: Mélancolys
def build_melancolys():
    """Mélancolie: pale-blue lily, a sleepy-sad face under droopy petals that hang like hair,
    long leaves for sleeves; still cute (soft smile, blush)."""
    mat("MelaBody", "#e3f1fb", rough=0.75)
    mat("MelaPetalA", "#a9d2f2", rough=0.75)
    mat("MelaPetalB", "#c4e1f8", rough=0.75)
    mat("MelaInner", "#9fc6ea", rough=0.75)
    mat("MelaStamen", "#f4e3a0", rough=0.7)
    mat("MelaLeaf", "#b0d9c9", rough=0.85)
    mat("MelaLid", "#d2e6f6", rough=0.75)
    mat("EyeDark", "#363f58", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Brow", "#8aa4c8", rough=0.7)
    mat("Tear", "#cdeeff", rough=0.2, emit=0.4)
    mat("Mouth", "#5d5274", rough=0.6)
    mat("Blush", "#f2c3d5", rough=0.8)

    bc = Vector((0, 0, 0.2))
    br = Vector((0.185, 0.17, 0.185))
    top = Vector((0, 0.01, 0.36))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.02), (0, 0, 0.36), "root")
    bone("bloom", (0, 0.01, 0.36), (0, 0.01, 0.6), "body")
    bone("arm.L", (0.17, -0.01, 0.24), (0.2, -0.03, 0.06), "body")
    bone("arm.R", (-0.17, -0.01, 0.24), (-0.2, -0.03, 0.06), "body")

    add_part("Body", ellipsoid(bc, br, 18, 10), "MelaBody", rigid("body"))
    # lily cup and six droopy petals (none in front: the face stays clear)
    cup_prof = [(0.0, 0.47), (0.05, 0.465), (0.075, 0.43), (0.07, 0.39), (0.04, 0.355), (0.0, 0.35)]
    add_part("Cup", lathe(cup_prof, 12), "MelaInner", rigid("bloom"))
    for k, deg in enumerate((62, 108, 154, 206, 252, 298)):  # hanging around the sides and back like hair
        a = math.radians(deg)
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        base = top + out * 0.055 + Vector((0, 0, 0.1))
        direction = (out * 0.62 + Vector((0, 0, -0.78))).normalized()
        add_part("Petal%d" % k, leaf(base, direction, Vector((0, 0, 1)), 0.27, 0.135, 0.03, curl=0.06, u=8, v=6),
                 "MelaPetalA" if k % 2 == 0 else "MelaPetalB", rigid("bloom"))
    for k in range(3):
        a = math.radians(120 * k + 180)
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        b0 = top + Vector((0, 0, 0.1))
        pts = catmull([b0, b0 + Vector((0, 0, 0.07)) + out * 0.02, b0 + Vector((0, 0, 0.12)) + out * 0.06], 5)
        add_part("Stamen%d" % k, tube(pts, [0.008, 0.007, 0.006, 0.005, 0.0], sides=4), "MelaLeaf",
                 rigid("bloom"))
        add_part("Anther%d" % k, ellipsoid(pts[-1], (0.018, 0.018, 0.012), 7, 4), "MelaStamen", rigid("bloom"))
    for s, S in ((1, "L"), (-1, "R")):
        # long leaves hanging like sleeves
        add_part("Sleeve." + S, leaf((s * 0.165, -0.01, 0.26), (s * 0.35, -0.12, -1.0), (s * 1, -0.3, 0), 0.22,
                                     0.085, 0.022, curl=-0.03), "MelaLeaf", rigid("arm." + S))
        add_part("Foot." + S, ellipsoid((s * 0.07, -0.03, 0.03), (0.05, 0.06, 0.032), 8, 5), "MelaLeaf",
                 rigid("root"))
        center, x, y, n = face_eye(s, bc, br, 0.35, 0.1, 0.04, 0.05, "body", lid=("MelaLid", 0.4))
        # worried brows: inner end raised
        pi, ni = surf(bc, br, s * 0.15, 0.4)
        po, no = surf(bc, br, s * 0.48, 0.33)
        add_part("Brow." + S, tube([pi + ni * 0.008, po + no * 0.008], [0.007, 0.005], sides=5), "Brow",
                 rigid("body"))
        face_decal("Blush." + S, bc, br, s * 0.62, -0.06, (0.034, 0.018, 0.006), "Blush", "body")
    # one tear pearl under the right eye, and a small brave smile
    face_decal("Tear", bc, br, -0.4, -0.08, (0.012, 0.017, 0.008), "Tear", "body")
    mouth(bc, br, -0.14, 0.018, 0.006, "body")
    return {"root": "root", "lower": "body", "upper": "bloom",
            "arms": [("arm.L", 1), ("arm.R", -1)], "arm_rest": 0.0, "arm_swing": 0.5, "extra": mela_extra}


def mela_extra(action, t):
    s = math.sin(2 * math.pi * t)
    if action == "Idle":  # heavy sigh: the bloom nods
        sigh = smoothstep(0.2, 0.45, t) * (1 - smoothstep(0.55, 0.85, t))
        return {"bloom": {"rot": (8 * sigh, 0, 3 * s)}}
    if action == "Move":
        return {"bloom": {"rot": (6, 0, 6 * math.sin(4 * math.pi * t))}}
    if action == "Sleep":
        return {"bloom": {"rot": (14, 0, 6)}}
    return {}


# ---------------------------------------------------------------- species: Lumiole
FIREFLIES = [(0.28, 0.42, 0.0), (0.24, 0.3, 1.6), (0.3, 0.52, 3.3), (0.22, 0.2, 4.7)]  # radius, height, phase


def build_lumiole():
    """Espoir: a glowing warm-white bulb with a peach heart, a tiny leaf cap and a dangling root;
    a few fireflies orbit it. Floats (the plant lifts the model 0.8 m)."""
    mat("GlowBulb", "#ffe4c6", rough=0.45, emit=0.4)
    mat("GlowPeach", "#ffb08a", rough=0.5, emit=0.45)
    mat("GlowFirefly", "#ffe170", rough=0.3, emit=1.2)
    mat("LumiLeaf", "#a9dcb4", rough=0.85)
    mat("LumiRoot", "#f2c3a5", rough=0.8)
    mat("EyeDark", "#4a3a3e", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#a0525a", rough=0.6)
    mat("Blush", "#ffa8a8", rough=0.8)

    bc = Vector((0, 0, 0.3))
    br = Vector((0.175, 0.165, 0.17))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.1), (0, 0, 0.48), "root")
    bone("cap", (0, 0.01, 0.46), (0, 0.01, 0.6), "body")
    bone("tail", (0, 0, 0.14), (0, 0, 0.0), "body")
    for i, (r, h, ph) in enumerate(FIREFLIES):
        bone("fly.%d" % i, (0, 0, 0.3), (0, 0, 0.42), "root")

    add_part("Bulb", ellipsoid(bc, br, 18, 10), "GlowBulb", rigid("body"))
    # glowing peach cup under the bulb, like the base of a light bulb
    cup = [(0.0, 0.2), (0.1, 0.19), (0.09, 0.155), (0.072, 0.125), (0.045, 0.105), (0.0, 0.1)]
    add_part("BulbCup", lathe(cup, 14), "GlowPeach", rigid("body"))
    tail = catmull([Vector((0, 0, 0.11)), Vector((0.03, 0.01, 0.075)), Vector((-0.02, 0.02, 0.04)),
                    Vector((0.02, 0.03, 0.01))], 7)
    add_part("Tail", tube(tail, [0.022, 0.02, 0.017, 0.014, 0.011, 0.007, 0.0], sides=5), "LumiRoot",
             along_z("tail", "body", 0.08, 0.16))
    capb = bc + Vector((0, 0.01, br.z - 0.012))
    add_part("CapNub", ellipsoid(capb, (0.03, 0.03, 0.022), 8, 4), "LumiLeaf", rigid("cap"))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("CapLeaf." + S, leaf(capb, (s * 0.8, 0.15, 0.55), (0, 0, 1), 0.12, 0.065, 0.02, curl=0.025),
                 "LumiLeaf", rigid("cap"))
        face_eye(s, bc, br, 0.34, 0.08, 0.04, 0.052, "body")
        face_decal("Blush." + S, bc, br, s * 0.62, -0.12, (0.036, 0.02, 0.006), "Blush", "body")
    # hopeful open smile
    p, x, y, n = mouth(bc, br, -0.17, 0.026, 0.014, "body")
    for i, (r, h, ph) in enumerate(FIREFLIES):
        c = Vector((math.cos(ph) * r, math.sin(ph) * r, h))
        add_part("Firefly%d" % i, ellipsoid(c, (0.02, 0.02, 0.02), 8, 5), "GlowFirefly", rigid("fly.%d" % i))
    return {"root": "root", "lower": "body", "upper": "cap", "arms": [], "extra": lumi_extra}


def lumi_extra(action, t):
    pose = {}
    speed = {"Idle": 1.0, "Move": 2.0, "Sleep": 0.25}.get(action, 0.0)
    for i, (r, h, ph) in enumerate(FIREFLIES):
        turns = (1 if i % 2 == 0 else -1) * speed * (2 if action == "Move" else 1)
        bob = 0.02 * math.sin(2 * math.pi * (t * 2 + i * 0.25))
        pose["fly.%d" % i] = {"rot": (0, 360 * turns * t, 0), "loc": (0, bob, 0)}
    s = math.sin(2 * math.pi * t)
    if action == "Idle":  # floats up and down
        pose["root"] = {"loc": (0, 0.035 * s, 0)}
        pose["tail"] = {"rot": (8 * s, 0, 6 * math.cos(2 * math.pi * t))}
        pose["cap"] = {"rot": (0, 0, 6 * s)}
    elif action == "Move":
        pose["tail"] = {"rot": (-30, 0, 12 * math.sin(4 * math.pi * t))}
        pose["cap"] = {"rot": (-12, 0, 0)}
    elif action == "Sleep":
        pose["tail"] = {"rot": (0, 0, 10)}
        pose["cap"] = {"rot": (10, 0, 8)}
    return pose


# ---------------------------------------------------------------- hostile helpers
def brow(name, c, r, s, inner, outer, parent, mat_name="Brow", thick=(0.011, 0.017, 0.009), lift=0.012):
    """Thick brow from inner (yaw, el) to outer (yaw, el), mirrored by side s. Frown: inner el lower."""
    pi, ni = surf(c, r, s * inner[0], inner[1])
    po, no = surf(c, r, s * outer[0], outer[1])
    pm, nm = surf(c, r, s * (inner[0] + outer[0]) / 2, (inner[1] + outer[1]) / 2 + 0.01)
    add_part(name, tube([pi + ni * lift, pm + nm * (lift + 0.004), po + no * lift], list(thick), sides=5),
             mat_name, rigid(parent))


def fang(name, base, direction, length, radius, parent, mat_name="Teeth"):
    d = Vector(direction).normalized()
    add_part(name, tube([Vector(base) - d * 0.004, Vector(base) + d * length], [radius, 0.0], sides=5),
             mat_name, rigid(parent))


# ---------------------------------------------------------------- species: Croque-Colère
def build_croque_colere():
    """Colère (hostile): a coral flytrap head with a big grumpy mouth and tiny fangs, frowning eyes
    on top, spiky leaf collar, on a short stem with leaf arms. Snaps its jaw when it charges."""
    mat("CroqueJaw", "#f58b8e", rough=0.7)
    mat("CroqueJawLow", "#ec7a86", rough=0.7)
    mat("CroqueSpot", "#ffcfc4", rough=0.75)
    mat("CroqueMouth", "#a9465f", rough=0.6)
    mat("CroqueTongue", "#ff9db2", rough=0.6)
    mat("CroqueStem", "#9fd193", rough=0.85)
    mat("CroqueLeaf", "#b9e09d", rough=0.85)
    mat("CroqueSclera", "#fff3d4", rough=0.35)
    mat("EyeDark", "#3b2632", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Brow", "#87324a", rough=0.7)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Blush", "#ff9cae", rough=0.8)

    uc = Vector((0, 0, 0.56))
    ur = Vector((0.27, 0.25, 0.15))
    lc = Vector((0, -0.005, 0.345))
    lr = Vector((0.245, 0.23, 0.085))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("stem", (0, 0, 0.02), (0, 0, 0.3), "root")
    bone("head", (0, 0, 0.3), (0, 0, 0.75), "stem")
    bone("jaw", (0, 0.16, 0.36), (0, -0.12, 0.36), "head", roll=Vector((0, 0, 1)))
    bone("arm.L", (0.1, -0.02, 0.17), (0.28, -0.08, 0.24), "stem")
    bone("arm.R", (-0.1, -0.02, 0.17), (-0.28, -0.08, 0.24), "stem")

    add_part("UpperJaw", ellipsoid(uc, ur, 16, 9), "CroqueJaw", rigid("head"))
    add_part("LowerJaw", ellipsoid(lc, lr, 14, 7), "CroqueJawLow", rigid("jaw"))
    # the dark mouth fills the gap between the jaws (recessed a little)
    add_part("MouthIn", ellipsoid((0, 0.02, 0.43), (0.225, 0.2, 0.06), 14, 6), "CroqueMouth",
             along_z("jaw", "head", 0.4, 0.46))
    add_part("Tongue", ellipsoid((0, -0.06, 0.4), (0.09, 0.08, 0.025), 10, 5), "CroqueTongue", rigid("jaw"))
    # upper fangs along the front rim, lower fangs pointing up
    for k, yaw in enumerate((-0.62, -0.22, 0.22, 0.62)):
        p, n = surf(uc, ur, yaw, -0.78)
        fang("Fang%d" % k, p + Vector((0, 0, 0.012)), (n.x * 0.25, n.y * 0.25, -1), 0.05, 0.018, "head")
    for k, yaw in enumerate((-0.42, 0.42)):
        p, n = surf(lc, lr, yaw, 0.62)
        fang("LowFang%d" % k, p - Vector((0, 0, 0.008)), (n.x * 0.2, n.y * 0.2, 1), 0.035, 0.015, "jaw")
    # light spots on the crown
    for k, (yaw, el, rr) in enumerate(((2.3, 0.75, 0.045), (-2.5, 0.6, 0.04), (1.6, 0.3, 0.036))):
        face_decal("Spot%d" % k, uc, ur, yaw, el, (rr, rr * 0.9, 0.008), "CroqueSpot", "head")
    # spiky leaf collar behind the head
    for k in range(5):
        a = math.radians(110 + 35 * k)
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        base = Vector((0, 0, 0.42)) + out * 0.16
        add_part("Collar%d" % k, leaf(base, (out * 0.8 + Vector((0, 0, 0.45))).normalized(), Vector((0, 0, 1)),
                                      0.22, 0.09, 0.025, curl=0.03, u=6, v=5), "CroqueLeaf", rigid("head"))
    stem_prof = [(0.0, 0.34), (0.06, 0.33), (0.07, 0.24), (0.075, 0.12), (0.09, 0.05), (0.08, 0.02), (0.0, 0.015)]
    add_part("Stem", lathe(stem_prof, 10), "CroqueStem", along_z("stem", "head", 0.26, 0.34))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Arm." + S, leaf((s * 0.07, -0.01, 0.17), (s * 0.85, -0.3, 0.42), (0, -0.2, 1), 0.2, 0.1, 0.024,
                                  curl=0.04), "CroqueLeaf", rigid("arm." + S))
        add_part("Foot." + S, ellipsoid((s * 0.08, -0.03, 0.032), (0.055, 0.07, 0.034), 8, 5), "CroqueStem",
                 rigid("root"))
        face_eye(s, uc, ur, 0.36, 0.42, 0.05, 0.056, "head", sclera="CroqueSclera", pupil_shift=(-0.16, -0.18))
        brow("Brow." + S, uc, ur, s, (0.12, 0.72), (0.56, 0.86), "head")
        face_decal("Blush." + S, uc, ur, s * 0.72, 0.02, (0.04, 0.02, 0.006), "Blush", "head")
    return {"root": "root", "lower": "stem", "upper": "head",
            "arms": [("arm.L", 1), ("arm.R", -1)], "sleep_arm": -18.0, "attack": True,
            "extra": croque_extra, "attack_extra": croque_attack}


def croque_extra(action, t):
    s = math.sin(2 * math.pi * t)
    if action == "Idle":  # grumpy chomping
        chomp = max(0.0, math.sin(4 * math.pi * t)) ** 2
        return {"jaw": {"rot": (-10 * chomp, 0, 0)}}
    if action == "Move":
        return {"jaw": {"rot": (-14 * max(0.0, math.sin(4 * math.pi * t)), 0, 0)}}
    if action == "Sleep":
        return {"jaw": {"rot": (-6 - 2 * s, 0, 0)}}
    return {}


def croque_attack(phase):
    return {"windup": {"jaw": {"rot": (-32, 0, 0)}, "head": {"rot": (-14, 0, 0)}},
            "lunge": {"jaw": {"rot": (2, 0, 0)}},
            "settle": {"jaw": {"rot": (-8, 0, 0)}}}.get(phase, {})


# ---------------------------------------------------------------- species: Lierre-Jalousie
IVY_LEAVES = [  # yaw (deg, 0 = front), elevation (rad), size, material
    (100, 0.15, 0.15, "LierreLeafA"), (140, 0.4, 0.16, "LierreLeafB"), (180, 0.2, 0.17, "LierreLeafA"),
    (220, 0.4, 0.16, "LierreLeafC"), (260, 0.15, 0.15, "LierreLeafB"), (160, -0.2, 0.15, "LierreLeafC"),
    (200, -0.2, 0.15, "LierreLeafB"), (120, -0.15, 0.14, "LierreLeafC"), (240, -0.15, 0.14, "LierreLeafA"),
    (180, 0.75, 0.15, "LierreLeafB"),
]


def build_lierre_jalousie():
    """Jalousie (hostile): a sour lime bulb wrapped in ivy leaves, side-eyeing from under heavy
    lids with a pout and one tiny fang; curly tendril arms and a corkscrew sprout."""
    mat("LierreBody", "#dbeb8e", rough=0.8)
    mat("LierreLid", "#c8df74", rough=0.8)
    mat("LierreLeafA", "#9fcb57", rough=0.85)
    mat("LierreLeafB", "#86ba4a", rough=0.85)
    mat("LierreLeafC", "#b6d964", rough=0.85)
    mat("LierreVine", "#79a843", rough=0.85)
    mat("LierreSclera", "#f6f8d8", rough=0.35)
    mat("EyeDark", "#33361f", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Brow", "#4f6a26", rough=0.7)
    mat("Mouth", "#5d4a2a", rough=0.6)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Blush", "#e7c86c", rough=0.8)

    bc = Vector((0, 0, 0.27))
    br = Vector((0.215, 0.195, 0.235))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.03), (0, 0, 0.5), "root")
    bone("sprout", (0, 0.03, 0.5), (0, 0.03, 0.66), "body")
    bone("arm.L", (0.2, -0.02, 0.22), (0.36, -0.08, 0.3), "body")
    bone("arm.R", (-0.2, -0.02, 0.22), (-0.36, -0.08, 0.3), "body")

    add_part("Body", ellipsoid(bc, br, 16, 9), "LierreBody", rigid("body"))
    for k, (yaw, el, size, mname) in enumerate(IVY_LEAVES):
        p, n = surf(bc, br, math.radians(yaw), el)
        x, y, n = frame(n)
        direction = (y * 0.8 + n * 0.45).normalized()
        add_part("Ivy%d" % k, leaf(p - n * 0.01, direction, n, size, size * 0.85, 0.025, curl=0.03, u=6, v=5),
                 mname, rigid("body"))
    # corkscrew sprout
    top = bc + Vector((0, 0.03, br.z - 0.015))
    spiral = [top + Vector((0.035 * math.sin(i * 1.1), 0.035 * (1 - math.cos(i * 1.1)), 0.022 * i))
              for i in range(9)]
    add_part("Sprout", tube(spiral, [0.016] * 8 + [0.0], sides=5), "LierreVine", rigid("sprout"))
    add_part("SproutLeaf", leaf(spiral[-2], (0.3, -0.2, 0.9), (0, -1, 0.2), 0.1, 0.08, 0.02, curl=0.02, u=6, v=4),
             "LierreLeafC", rigid("sprout"))
    for s, S in ((1, "L"), (-1, "R")):
        # curly tendril arms
        p0, n0 = surf(bc, br, s * 1.5, -0.1)
        side = Vector((s, 0, 0))
        ctrl = [p0 - n0 * 0.01, p0 + side * 0.08 + Vector((0, -0.03, 0.02)), p0 + side * 0.15 + Vector((0, -0.05, 0.08)),
                p0 + side * 0.13 + Vector((0, -0.08, 0.15)), p0 + side * 0.07 + Vector((0, -0.07, 0.15)),
                p0 + side * 0.07 + Vector((0, -0.05, 0.1))]
        pts = catmull(ctrl, 10)
        add_part("Arm." + S, tube(pts, [0.024 - 0.016 * i / 9 for i in range(9)] + [0.0], sides=5), "LierreVine",
                 rigid("arm." + S))
        add_part("ArmLeaf." + S, leaf(pts[3], (s * 0.6, -0.2, 0.6), (0, -1, 0.3), 0.09, 0.07, 0.018, curl=0.02),
                 "LierreLeafA", rigid("arm." + S))
        add_part("Foot." + S, ellipsoid((s * 0.08, -0.03, 0.03), (0.055, 0.065, 0.032), 8, 5), "LierreLeafB",
                 rigid("root"))
        # side-eye: both pupils glance to the same side, under heavy envious lids
        face_eye(s, bc, br, 0.33, 0.14, 0.046, 0.054, "body", sclera="LierreSclera",
                 pupil_shift=(0.34 * s, -0.12), lid=("LierreLid", 0.4))
        brow("Brow." + S, bc, br, s, (0.1, 0.36), (0.48, 0.44) if s > 0 else (0.48, 0.5), "body")
        face_decal("Blush." + S, bc, br, s * 0.62, -0.06, (0.034, 0.018, 0.006), "Blush", "body")
    p, x, y, n = mouth(bc, br, -0.14, 0.03, -0.012, "body", thick=0.009, yaw=0.05)
    fang("Fang", p + x * 0.012 + n * 0.006 - y * 0.004, -y + n * 0.1, 0.022, 0.01, "body")
    return {"root": "root", "lower": "body", "upper": "sprout",
            "arms": [("arm.L", 1), ("arm.R", -1)], "arm_rest": 0.3, "attack": True,
            "extra": lierre_extra, "attack_extra": lierre_attack}


def lierre_extra(action, t):
    s = math.sin(2 * math.pi * t)
    if action == "Idle":
        return {"sprout": {"rot": (0, 25 * s, 6 * s)}}
    if action == "Move":
        return {"sprout": {"rot": (-12, 40 * math.sin(4 * math.pi * t), 0)}}
    if action == "Sleep":
        return {"sprout": {"rot": (18, 0, 8)}}
    return {}


def lierre_attack(phase):
    return {"windup": {"sprout": {"rot": (-20, 60, 0)}, "arm.L": {"rot": (0, 0, 80)}, "arm.R": {"rot": (0, 0, -80)}},
            "lunge": {"sprout": {"rot": (14, -30, 0)}, "arm.L": {"rot": (0, 0, -30)}, "arm.R": {"rot": (0, 0, 30)}},
            }.get(phase, {})


# ---------------------------------------------------------------- species: Ortie-Regret
ORTIE_LEAVES = [  # height, yaw (deg), length, material
    (0.2, 100, 0.2, "OrtieLeafA"), (0.2, -100, 0.2, "OrtieLeafA"),
    (0.32, 160, 0.18, "OrtieLeafB"), (0.32, -160, 0.18, "OrtieLeafB"),
    (0.43, 60, 0.17, "OrtieLeafA"), (0.43, -60, 0.17, "OrtieLeafA"),
]


def build_ortie_regret():
    """Regret (hostile): a rooted grey-teal nettle, droopy serrated leaves hanging along its stem,
    a sulky bulb head with heavy lids, frowning brows and a tiny fang; spits thorns."""
    mat("OrtieHead", "#b6d3cf", rough=0.8)
    mat("OrtieLid", "#9fc2bd", rough=0.8)
    mat("OrtieStem", "#7fa7a2", rough=0.85)
    mat("OrtieLeafA", "#8db5b0", rough=0.85)
    mat("OrtieLeafB", "#a2c5c0", rough=0.85)
    mat("OrtieHair", "#e8f4f1", rough=0.6)
    mat("OrtieRoot", "#a69aa6", rough=0.9)
    mat("OrtieSclera", "#eef6f2", rough=0.35)
    mat("EyeDark", "#28343a", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Brow", "#3f5a5c", rough=0.7)
    mat("Mouth", "#3e4650", rough=0.6)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Blush", "#c9b6cf", rough=0.8)

    hc = Vector((0, 0, 0.68))
    hr = Vector((0.185, 0.17, 0.175))
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("stem", (0, 0, 0.02), (0, 0, 0.52), "root")
    bone("head", (0, 0, 0.52), (0, 0, 0.85), "stem")
    bone("arm.L", (0.03, 0, 0.42), (0.2, -0.05, 0.36), "stem")
    bone("arm.R", (-0.03, 0, 0.42), (-0.2, -0.05, 0.36), "stem")
    bone("ear.L", (0.1, 0.02, 0.76), (0.22, 0.02, 0.7), "head")
    bone("ear.R", (-0.1, 0.02, 0.76), (-0.22, 0.02, 0.7), "head")

    add_part("Head", ellipsoid(hc, hr, 18, 10), "OrtieHead", rigid("head"))
    stem_prof = [(0.0, 0.56), (0.035, 0.55), (0.04, 0.4), (0.045, 0.25), (0.055, 0.1), (0.075, 0.03), (0.0, 0.02)]
    add_part("Stem", lathe(stem_prof, 8), "OrtieStem", along_z("stem", "head", 0.5, 0.56))
    hair = 0
    for k, (h, yaw, length, mname) in enumerate(ORTIE_LEAVES):
        a = math.radians(yaw)
        out = Vector((math.sin(a), -math.cos(a), 0.0))
        base = Vector((0, 0, h)) + out * 0.035
        direction = (out + Vector((0, 0, -0.32))).normalized()  # droopy
        bone_name = "arm.L" if k == 4 else "arm.R" if k == 5 else "stem"
        bm = leaf(base, direction, Vector((0, 0, 1)), length, length * 0.68, 0.024, curl=-0.06, u=10, v=5)
        # serrated edge: zigzag the rim
        y = direction
        for vt in bm.verts:
            rel = vt.co - base
            along = rel.dot(y)
            side = rel - y * along
            if side.length > 0.02:
                vt.co = vt.co + side.normalized() * 0.008 * math.sin(along * 90)
        add_part("Leaf%d" % k, bm, mname, rigid(bone_name))
        for j in (0.35, 0.65):  # little stinging hairs
            hp = base + direction * length * j + Vector((0, 0, 0.012))
            fang("Hair%d" % hair, hp, (0, 0, 1), 0.025, 0.006, bone_name, "OrtieHair")
            hair += 1
    for s, S in ((1, "L"), (-1, "R")):
        # droopy ear leaves on the head
        p, n = surf(hc, hr, s * 1.35, 0.55)
        add_part("Ear." + S, leaf(p - n * 0.01, (s * 0.7, 0.1, -0.45), (0, 0, 1), 0.17, 0.1, 0.022, curl=-0.04),
                 "OrtieLeafB", rigid("ear." + S))
        face_eye(s, hc, hr, 0.33, 0.06, 0.04, 0.046, "head", sclera="OrtieSclera", pupil_shift=(-0.1, -0.2),
                 lid=("OrtieLid", 0.38))
        brow("Brow." + S, hc, hr, s, (0.1, 0.3), (0.5, 0.42), "head", thick=(0.009, 0.014, 0.008))
        face_decal("Blush." + S, hc, hr, s * 0.6, -0.16, (0.03, 0.016, 0.006), "Blush", "head")
    p, x, y, n = mouth(hc, hr, -0.24, 0.026, -0.012, "head", thick=0.008)
    fang("Fang", p - x * 0.01 + n * 0.006 - y * 0.003, -y + n * 0.1, 0.02, 0.009, "head")
    # rooted: splayed roots instead of feet
    for k in range(5):
        a = math.radians(36 + 72 * k)
        d = Vector((math.sin(a), -math.cos(a), 0))
        pts = [d * 0.04 + Vector((0, 0, 0.06)), d * 0.1 + Vector((0, 0, 0.028)), d * 0.16 + Vector((0, 0, 0.012)),
               d * 0.2 + Vector((0, 0, 0.006))]
        add_part("Root%d" % k, tube(pts, [0.034, 0.026, 0.016, 0.0], sides=5), "OrtieRoot", rigid("root"))
    return {"root": "root", "lower": "stem", "upper": "head",
            "arms": [("arm.L", 1), ("arm.R", -1)], "arm_rest": -1.0, "arm_swing": 0.5, "sleep_arm": -10.0,
            "attack": True, "extra": ortie_extra, "attack_extra": ortie_attack, "rooted": True}


def ortie_extra(action, t):
    s = math.sin(2 * math.pi * t)
    if action == "Idle":
        return {"ear.L": {"rot": (0, 0, -6 + 4 * s)}, "ear.R": {"rot": (0, 0, 6 - 4 * s)}}
    if action == "Sleep":
        return {"ear.L": {"rot": (0, 0, -16)}, "ear.R": {"rot": (0, 0, 16)}}
    return {}


def ortie_attack(phase):
    return {"windup": {"head": {"rot": (-24, 0, 0)}, "stem": {"rot": (-8, 0, 0)},
                       "ear.L": {"rot": (0, 0, 20)}, "ear.R": {"rot": (0, 0, -20)}},
            "lunge": {"head": {"rot": (22, 0, 0)}, "stem": {"rot": (8, 0, 0)}},
            "settle": {"head": {"rot": (6, 0, 0)}}}.get(phase, {})


# ---------------------------------------------------------------- species: Champi-Panique
CHAMPI_SPOTS = [(0.0, 0.9, 0.05), (0.9, 0.55, 0.045), (-0.9, 0.55, 0.045), (2.2, 0.6, 0.05), (-2.2, 0.6, 0.05),
                (3.14, 0.45, 0.05)]  # yaw, elevation, radius


def build_champi_panique():
    """Panique (hostile): a lilac mushroom whose cream body is all face: huge nervous eyes with tiny
    pupils, worried-cross brows, a wobbly zigzag mouth with two little fangs, a sweat drop.
    Its cap is pushed back so the face shows from above. Puffs up before bursting into spores."""
    mat("ChampiCap", "#c7a3e0", rough=0.7)
    mat("ChampiSpot", "#f3e6fb", rough=0.75)
    mat("ChampiGill", "#e8d6f0", rough=0.85)
    mat("ChampiBody", "#f5ecf6", rough=0.8)
    mat("ChampiFoot", "#dccbe6", rough=0.8)
    mat("ChampiSweat", "#bfe4f6", rough=0.3, emit=0.3)
    mat("EyeDark", "#3a2846", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("ChampiSclera", "#ffffff", rough=0.35)
    mat("Brow", "#6b4683", rough=0.7)
    mat("Mouth", "#6b3a5c", rough=0.6)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Blush", "#f0a6d0", rough=0.8)

    bc = Vector((0, 0, 0.2))
    br = Vector((0.19, 0.175, 0.19))
    pivot = Vector((0, 0.02, 0.37))
    tilt = Matrix.Rotation(math.radians(-24), 3, "X")  # cap pushed back, like a hat off the eyes
    bone("root", (0, 0, 0), (0, 0, 0.06))
    bone("body", (0, 0, 0.02), (0, 0, 0.37), "root")
    bone("cap", (0, 0.02, 0.37), (0, 0.02, 0.7), "body")
    bone("arm.L", (0.17, -0.02, 0.15), (0.26, -0.06, 0.12), "body")
    bone("arm.R", (-0.17, -0.02, 0.15), (-0.26, -0.06, 0.12), "body")

    def tilted(bm):
        for vt in bm.verts:
            vt.co = tilt @ (vt.co - pivot) + pivot
        return bm

    add_part("Body", ellipsoid(bc, br, 18, 10), "ChampiBody", rigid("body"))
    cap_prof = [(0.0, 0.64), (0.07, 0.63), (0.14, 0.605), (0.2, 0.565), (0.245, 0.505), (0.265, 0.45),
                (0.26, 0.415), (0.235, 0.4), (0.0, 0.395)]

    def wavy(a, row):
        return 1.0 + (0.035 * math.sin(6 * a) if row >= 4 else 0.0)
    add_part("Cap", tilted(lathe(cap_prof, 22, rfun=wavy)), "ChampiCap", rigid("cap"))
    gill = [(0.0, 0.405), (0.235, 0.402), (0.17, 0.385), (0.0, 0.375)]
    add_part("Gills", tilted(lathe(gill, 16)), "ChampiGill", rigid("cap"))
    cc = Vector((0, 0, 0.4))
    crr = Vector((0.262, 0.262, 0.235))
    for k, (yaw, el, rr) in enumerate(CHAMPI_SPOTS):
        p, n = surf(cc, crr, yaw, el)
        x, y, n = frame(n)
        add_part("Spot%d" % k, tilted(ellipsoid(p + n * 0.001, (rr, rr * 0.92, 0.01), 8, 5, basis(x, y, n))),
                 "ChampiSpot", rigid("cap"))
    # sweat drop on the side of the cap
    p, n = surf(cc, crr, 0.8, 0.1)
    add_part("Sweat", tilted(tube([p + n * 0.01 + Vector((0, 0, 0.03)), p + n * 0.02, p + n * 0.025 - Vector((0, 0, 0.03))],
                                  [0.0, 0.016, 0.0], sides=6)), "ChampiSweat", rigid("cap"))
    for s, S in ((1, "L"), (-1, "R")):
        add_part("Arm." + S, ellipsoid((s * 0.215, -0.04, 0.13), (0.05, 0.04, 0.035), 8, 5), "ChampiFoot",
                 rigid("arm." + S))
        add_part("Foot." + S, ellipsoid((s * 0.08, -0.03, 0.028), (0.05, 0.06, 0.03), 8, 5), "ChampiFoot",
                 rigid("root"))
        # huge nervous eyes, tiny pupils looking in different directions
        face_eye(s, bc, br, 0.34, 0.2, 0.06, 0.068, "body", sclera="ChampiSclera",
                 pupil_shift=(0.22 if s > 0 else -0.08, 0.18 if s > 0 else -0.05))
        # worried brows (inner end high) slanted into a cross little frown
        brow("Brow." + S, bc, br, s, (0.12, 0.58), (0.52, 0.5), "body", thick=(0.01, 0.014, 0.008))
        face_decal("Blush." + S, bc, br, s * 0.66, -0.06, (0.034, 0.019, 0.006), "Blush", "body")
    # wobbly zigzag mouth
    p, n = surf(bc, br, 0.0, -0.16)
    x, y, n = frame(n)
    pts = [p + x * (0.036 * (i / 3.0 - 1.0)) + y * (0.007 if i % 2 else -0.007) + n * 0.004 for i in range(7)]
    add_part("Mouth", tube(pts, [0.0] + [0.0075] * 5 + [0.0], sides=5), "Mouth", rigid("body"))
    for s in (1, -1):
        fang("Fang.%d" % s, p + x * (s * 0.016) + n * 0.006 - y * 0.008, -y + n * 0.1, 0.018, 0.008, "body")
    return {"root": "root", "lower": "body", "upper": "cap",
            "arms": [("arm.L", 1), ("arm.R", -1)], "arm_rest": 0.5, "attack": True,
            "extra": champi_extra, "attack_extra": champi_attack}


def champi_extra(action, t):
    if action == "Idle":  # nervous trembling of the cap
        return {"cap": {"rot": (0, 0, 3 * math.sin(2 * math.pi * t * 12))}}
    if action == "Move":
        return {"cap": {"rot": (-6, 0, 5 * math.sin(2 * math.pi * t * 2))}}
    if action == "Sleep":
        return {"cap": {"rot": (6, 0, 6), "scale": (0.95, 0.92, 0.95)}}
    return {}


def champi_attack(phase):
    return {"windup": {"cap": {"rot": (-10, 0, 0), "scale": (1.18, 1.14, 1.18)},
                       "body": {"rot": (0, 0, 0), "scale": (1.24, 1.1, 1.24)}},
            "lunge": {"cap": {"scale": (0.92, 0.8, 0.92)}, "body": {"scale": (0.95, 0.9, 0.95)}},
            "settle": {"cap": {"scale": (1.04, 1.02, 1.04)}}}.get(phase, {})


# ---------------------------------------------------------------- rig + animation
def build_armature(name):
    arm_data = bpy.data.armatures.new(name + "Rig")
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    for bname, head, tail, parent, roll in BONES:
        b = eb.new(bname)
        b.head = head
        b.tail = tail
        b.align_roll(roll)
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def key_pose(arm, frame, pose):
    """pose: {bone: {"rot": degrees XYZ (local), "loc": local, "scale": local}}"""
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        spec = pose.get(pb.name, {})
        pb.rotation_euler = tuple(math.radians(v) for v in spec.get("rot", (0, 0, 0)))
        pb.location = spec.get("loc", (0, 0, 0))
        pb.scale = spec.get("scale", (1, 1, 1))
        pb.keyframe_insert("rotation_euler", frame=frame)
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("scale", frame=frame)


def make_action(arm, name, frames, pose_fn, step=2):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    keys = sorted(set(list(range(0, frames + 1, step)) + [frames]))
    for f in keys:
        key_pose(arm, f, pose_fn(f))
    try:
        curves = act.fcurves
    except AttributeError:
        curves = [fc for layer in act.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, act)
    strip.name = name
    arm.animation_data.action = None


def merge(*poses):
    out = {}
    for p in poses:
        for b, spec in p.items():
            out.setdefault(b, {}).update(spec)
    return out


def lerp_pose(a, b, t):
    out = {}
    for bname in set(a) | set(b):
        sa, sb = a.get(bname, {}), b.get(bname, {})
        out[bname] = {}
        for key, default in (("rot", (0, 0, 0)), ("loc", (0, 0, 0)), ("scale", (1, 1, 1))):
            va, vb = sa.get(key, default), sb.get(key, default)
            out[bname][key] = tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out


def keyed(keys):
    """keys: [(frame, pose)] -> pose_fn(frame), eased between keys."""
    def fn(f):
        for (f0, p0), (f1, p1) in zip(keys, keys[1:]):
            if f <= f1:
                return lerp_pose(p0, p1, smoothstep(f0, f1, f))
        return keys[-1][1]
    return fn


def eyes(rig, open_scale=1.0, shut=False, squint=1.0):
    pose = {}
    for S in ("L", "R"):
        if shut:
            pose["eye." + S] = {"scale": (HIDDEN, HIDDEN, HIDDEN)}
            pose["shut." + S] = {"scale": (1, 1, 1)}
        else:
            pose["eye." + S] = {"scale": (open_scale, open_scale * squint, open_scale)}
            pose["shut." + S] = {"scale": (HIDDEN, HIDDEN, HIDDEN)}
    return pose


def arms(rig, angle_fn):
    return {b: {"rot": (0, 0, s * angle_fn(s))} for b, s in rig["arms"]}


def extra(rig, action, t):
    return rig["extra"](action, t) if rig.get("extra") else {}


def build_actions(arm, rig):
    root, lower, upper = rig["root"], rig["lower"], rig["upper"]
    arm_rest = rig.get("arm_rest", 1.0)
    arm_swing = rig.get("arm_swing", 1.0)

    def idle_at(t, f):
        s, c, s2 = math.sin(2 * math.pi * t), math.cos(2 * math.pi * t), math.sin(4 * math.pi * t)
        blink = max(0.0, 1.0 - abs(f - 87) / 3.0)
        return merge(
            {lower: {"rot": (1.5 * s, 0, 2.5 * c), "scale": (1 + 0.025 * s2, 1 - 0.03 * s2, 1 + 0.025 * s2)},
             upper: {"rot": (-2 * s, 3 * c, -3 * c)}},
            arms(rig, lambda sd: arm_rest * 6 + arm_swing * 7 * s2),
            eyes(rig, squint=1.0 - 0.92 * blink),
            extra(rig, "Idle", t))

    n = 120
    make_action(arm, "Idle", n, lambda f: idle_at(f / n, f), step=3)

    def move(f):
        t = f / 30
        a = 2 * math.pi * t
        h = abs(math.sin(a))
        land = 1.0 - h
        sx = 1 + 0.07 * land - 0.03 * h
        return merge(
            {root: {"loc": (0, 0.08 * h, 0)},
             lower: {"rot": (9, 0, 5 * math.sin(a)), "scale": (sx, 1 - 0.1 * land + 0.06 * h, sx)},
             upper: {"rot": (-3 + 5 * math.cos(2 * a), 0, -4 * math.sin(a))}},
            arms(rig, lambda sd: arm_rest * 20 + arm_swing * 25 * math.sin(2 * a)),
            eyes(rig, open_scale=1.05),
            extra(rig, "Move", t))
    make_action(arm, "Move", 30, move, step=1)

    def sleep(f):
        t = f / 180
        s = math.sin(2 * math.pi * t)
        return merge(
            {lower: {"rot": (3, 0, 6), "scale": (1.08 + 0.025 * s, 0.86 - 0.03 * s, 1.08 + 0.025 * s)},
             upper: {"rot": (4 + 2 * s, 0, 12)}},
            arms(rig, lambda sd: rig.get("sleep_arm", -12.0)),
            eyes(rig, shut=True),
            extra(rig, "Sleep", t))
    make_action(arm, "Sleep", 180, sleep, step=6)

    rest = idle_at(0.0, 0)
    surprise = merge(
        {lower: {"scale": (0.82, 1.28, 0.82)}, upper: {"rot": (-12, 0, 0)}},
        arms(rig, lambda sd: 70.0), eyes(rig, open_scale=1.35))
    spin = merge(
        {root: {"rot": (0, 140, 0)}, lower: {"scale": (1.15, 0.8, 1.15)}},
        arms(rig, lambda sd: 40.0), eyes(rig, shut=True))
    end = merge(
        {root: {"rot": (0, 260, 0)}, lower: {"scale": (0.9, 0.9, 0.9)}},
        arms(rig, lambda sd: 10.0), eyes(rig, shut=True))
    make_action(arm, "Caught", 18, keyed([(0, rest), (5, surprise), (11, spin), (18, end)]), step=1)

    if rig.get("attack"):
        ax = rig.get("attack_extra") or (lambda phase: {})
        # rooted hostiles (Ortie) never leave their spot: no lunge forward
        reach = 0.0 if rig.get("rooted") else 1.0
        windup = merge(
            {lower: {"rot": (-10, 0, 0), "scale": (1.12, 0.82, 1.12)}, upper: {"rot": (-12, 0, 0)}},
            arms(rig, lambda sd: 55.0), eyes(rig, squint=0.7), ax("windup"))
        lunge = merge(
            {root: {"loc": (0, 0.04 * reach, 0.2 * reach)}, lower: {"rot": (14, 0, 0), "scale": (0.92, 1.1, 0.92)},
             upper: {"rot": (16, 0, 0)}},
            arms(rig, lambda sd: -15.0), eyes(rig, open_scale=1.1), ax("lunge"))
        settle = merge(
            {root: {"loc": (0, 0, 0.12 * reach)}, lower: {"rot": (6, 0, 0)}, upper: {"rot": (6, 0, 0)}},
            arms(rig, lambda sd: 10.0), eyes(rig, squint=0.85), ax("settle"))
        make_action(arm, "Attack", 36, keyed([(0, rest), (14, windup), (20, lunge), (28, settle), (36, rest)]),
                    step=1)


# ---------------------------------------------------------------- main
SPECIES = {
    "revette": ("Revette", build_revette),
    "nostalgerbe": ("Nostalgerbe", build_nostalgerbe),
    "timidelle": ("Timidelle", build_timidelle),
    "ronce_angoisse": ("RonceAngoisse", build_ronce_angoisse),
    "calinette": ("Calinette", build_calinette),
    "souffloine": ("Souffloine", build_souffloine),
    "melancolys": ("Melancolys", build_melancolys),
    "lumiole": ("Lumiole", build_lumiole),
    "croque_colere": ("CroqueColere", build_croque_colere),
    "lierre_jalousie": ("LierreJalousie", build_lierre_jalousie),
    "ortie_regret": ("OrtieRegret", build_ortie_regret),
    "champi_panique": ("ChampiPanique", build_champi_panique),
}

IMPORT_TEMPLATE = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/custom/plants/{id}/{id}.glb"

[params]

nodes/root_type=""
nodes/root_name=""
meshes/generate_lods=false
animation/import=true
animation/fps=60
animation/trimming=false
animation/remove_immutable_tracks=false
_subresources={{
"animations": {{
"Idle": {{
"settings/loop_mode": 1
}},
"Move": {{
"settings/loop_mode": 1
}},
"Sleep": {{
"settings/loop_mode": 1
}}
}}
}}
"""


def build(species_id):
    name, builder = SPECIES[species_id]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    PARTS.clear()
    TRIS.clear()
    BONES.clear()
    bpy.context.scene.render.fps = FPS
    rig = builder()
    bpy.ops.object.select_all(action="DESELECT")
    for ob in PARTS:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name + "Mesh"
    body.data.name = name + "Mesh"
    tris = len(body.data.polygons)
    arm = build_armature(name)
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    build_actions(arm, rig)
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    out_dir = os.path.join(HERE, species_id)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, species_id + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_skins=True,
        export_yup=True,
        export_apply=False,
        export_force_sampling=True,
        export_materials="EXPORT",
    )
    imp = out + ".import"
    if not os.path.exists(imp):
        with open(imp, "w") as fh:
            fh.write(IMPORT_TEMPLATE.format(id=species_id))
    print("SPECIES", species_id, "TRIANGLES", tris, "MATERIALS", [m.name for m in body.data.materials])
    print("  PER PART", sorted(TRIS.items(), key=lambda kv: -kv[1])[:8])
    print("  ACTIONS", [a.name for a in bpy.data.actions])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ids = [a for a in argv if a in SPECIES] or list(SPECIES)
    for species_id in ids:
        build(species_id)


main()

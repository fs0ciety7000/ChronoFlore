"""ChronoFlore second hero generator (Blender bpy, headless, deterministic).

Builds the chibi flat-cap hero (~1.17 m, origin at the feet, facing -Y in Blender
which becomes +Z in Godot), rigs it on the SAME skeleton as the heroine (same bone
names, so gameplay code drives both) and writes hero2.glb with the actions
Idle, Walk, Swing and Hurt, plus a "Grin" shape key on the mouth.

Usage: <bpy python> build_hero2.py [output.glb]
(default output: hero2.glb next to this script, i.e. game/assets/custom/hero2/).
The .glb.import next to it makes Idle and Walk loop and samples animations at 60 fps.
"""
import math
import os
import random
import sys
import tempfile

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "hero2.glb")
FPS = 60

# ---------------------------------------------------------------- dimensions (metres, Blender Z up)
HEAD_C = Vector((0.0, 0.0, 0.87))
HEAD_R = Vector((0.262, 0.235, 0.24))  # semi-axes x (width), y (depth), z (height)
EYE_Z = 0.852
EYE_X = 0.09
BROW_Z = 0.925
MOUTH_Z = 0.745
SHOULDER = Vector((0.158, 0.0, 0.548))
ELBOW = Vector((0.214, 0.0, 0.437))
WRIST = Vector((0.234, -0.005, 0.342))
HAND = Vector((0.242, -0.008, 0.298))
HIP_Z = 0.315
LEG_X = 0.07
KNEE_Z = 0.18
ANKLE_Z = 0.065
JACKET_V_Z = 0.49  # bottom of the open V of the jacket


# ---------------------------------------------------------------- colours / materials
def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexrgb(h, lighten=0.0):
    h = h.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [c + (1.0 - c) * lighten for c in rgb]


def hexcol(h, lighten=0.0):
    return [srgb_to_lin(c) for c in hexrgb(h, lighten)]


MATS = {}


def mat(name, hexc, alpha=1.0, rough=0.8, lighten=0.0, emit=0.0, image=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col = hexcol(hexc, lighten)
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    if image is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Linear"
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*col, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except AttributeError:
            m.blend_method = "BLEND"
    m.diffuse_color = (*col, alpha)
    MATS[name] = m
    return m


def make_tweed_image():
    """Small deterministic heathered-tweed texture (grey-blue with cream / navy / brown flecks)."""
    W = H = 64
    rnd = random.Random(1907)
    palette = [  # (weight, hex)
        (45, "#7d8090"), (12, "#5f6373"), (14, "#959aa8"), (5, "#bdb6a8"),
        (6, "#4b4f60"), (7, "#816a5a"),
    ]
    total = sum(w for w, _ in palette)

    def pick():
        r = rnd.uniform(0, total)
        for w, h in palette:
            r -= w
            if r <= 0:
                return h
        return palette[0][1]

    px = [None] * (W * H)
    for y in range(H):
        x = 0
        while x < W:
            run = rnd.choice((1, 2, 2, 3))  # short horizontal yarn runs
            c = hexrgb(pick())
            for k in range(run):
                if x + k < W:
                    px[y * W + x + k] = c
            x += run
    img = bpy.data.images.new("TweedTex", W, H, alpha=False)
    flat = []
    for c in px:
        flat += [c[0], c[1], c[2], 1.0]
    img.pixels = flat
    path = os.path.join(tempfile.gettempdir(), "chronoflore_hero2_tweed.png")  # packed into the GLB
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.pack()
    return img


def build_materials():
    mat("Skin", "#e6b796", rough=0.7)
    mat("SkinShade", "#c9906f", rough=0.7)
    mat("HairShort", "#5b463b", rough=0.9)
    mat("Brow", "#2a1d16", rough=0.7)
    mat("Beard", "#3a2a20", rough=0.85)
    mat("EyeIris", "#6b4226", rough=0.3)
    mat("EyeDark", "#1e130e", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#5a1e22", rough=0.6)
    mat("Lip", "#a8544c", rough=0.6)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Blush", "#e58b80", rough=0.8)
    mat("CapTweed", "#7d8090", rough=0.95, image=make_tweed_image())
    mat("Jacket", "#4a4a36", rough=0.45, lighten=0.10)
    mat("JacketDark", "#2f2f20", rough=0.5, lighten=0.05)
    mat("CordA", "#5a3a2a", rough=0.9, lighten=0.04)
    mat("CordB", "#462c1f", rough=0.9, lighten=0.04)
    mat("Brass", "#b8913f", rough=0.45)
    mat("Tee", "#2b2b33", rough=0.9, lighten=0.04)
    mat("Trousers", "#2f3650", rough=0.9, lighten=0.10)
    mat("Boots", "#6e4630", rough=0.6)
    mat("BootSole", "#3a2a20", rough=0.9)


# ---------------------------------------------------------------- bmesh helpers
def ellipsoid_bm(center, radii, u=24, v=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    for vert in bm.verts:
        vert.co = Vector((vert.co.x * radii.x, vert.co.y * radii.y, vert.co.z * radii.z)) + center
    return bm


def lathe_bm(profile, seg=20, yscale=1.0, center=Vector((0, 0, 0)), cap_bottom=False):
    """profile: list of (radius, z) from top to bottom."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring.append(bm.verts.new(center + Vector((math.sin(a) * r, -math.cos(a) * r * yscale, z))))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(seg):
            j = (i + 1) % seg
            if a[i].co != a[j].co:
                bm.faces.new((a[i], b[i], b[j], a[j]))  # outward-facing winding
    if cap_bottom:
        bm.faces.new(list(reversed(rings[-1])))
    return bm


def tube_bm(points, radii, sides=6, cap0=True, cap1=True, twist=0.0):
    """Tube along a polyline with parallel-transported frames."""
    bm = bmesh.new()
    n = len(points)
    tangents = []
    for i in range(n):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    up = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    nrm = tangents[0].cross(up).normalized()
    rings = []
    for i in range(n):
        t = tangents[i]
        nrm = (nrm - t * nrm.dot(t)).normalized()
        bin_ = t.cross(nrm)
        ring = []
        for s in range(sides):
            a = 2 * math.pi * s / sides + twist * i
            off = nrm * math.cos(a) + bin_ * math.sin(a)
            ring.append(bm.verts.new(points[i] + off * radii[i]))
        rings.append(ring)
    for i in range(n - 1):
        for s in range(sides):
            j = (s + 1) % sides
            bm.faces.new((rings[i][s], rings[i][j], rings[i + 1][j], rings[i + 1][s]))
    if cap0:
        c = bm.verts.new(points[0] - tangents[0] * radii[0] * 0.4)
        for s in range(sides):
            bm.faces.new((rings[0][(s + 1) % sides], rings[0][s], c))
    if cap1:
        c = bm.verts.new(points[-1] + tangents[-1] * radii[-1] * 0.6)
        for s in range(sides):
            bm.faces.new((rings[-1][s], rings[-1][(s + 1) % sides], c))
    return bm


def catmull(pts, samples):
    """Catmull-Rom through pts, returns `samples` points evenly spaced by parameter."""
    p = [pts[0] * 2 - pts[1]] + list(pts) + [pts[-1] * 2 - pts[-2]]
    out = []
    segs = len(pts) - 1
    for k in range(samples):
        u = k / (samples - 1) * segs
        i = min(int(u), segs - 1)
        t = u - i
        p0, p1, p2, p3 = p[i], p[i + 1], p[i + 2], p[i + 3]
        t2, t3 = t * t, t * t * t
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return out


def bisect_all(bm, co, no):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)


def bvh_of(bm):
    return BVHTree.FromBMesh(bm)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def table_lerp(table, a):
    """Smooth piecewise interpolation in a [(key, value)] table (keys ascending)."""
    if a <= table[0][0]:
        return table[0][1]
    for (a0, e0), (a1, e1) in zip(table, table[1:]):
        if a <= a1:
            return e0 + (e1 - e0) * smoothstep(a0, a1, a)
    return table[-1][1]


# ---------------------------------------------------------------- object assembly
PARTS = []
TRI_COUNT = {}


def add_part(name, bm, mats, weight_fn, face_mat_fn=None, smooth=True, shape_keys=None):
    """mats: list of material names. face_mat_fn(face) -> index into mats.
    shape_keys: {name: [Vector per bm vert, in bm.verts order]}"""
    me = bpy.data.meshes.new(name)
    if face_mat_fn is not None:
        for f in bm.faces:
            f.material_index = face_mat_fn(f)
    for f in bm.faces:
        f.smooth = smooth
    # triangulate here so the export is byte-for-byte reproducible (adds no vertices)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(MATS[m])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if shape_keys:
        ob.shape_key_add(name="Basis", from_mix=False)
        for kname, cos in shape_keys.items():
            sk = ob.shape_key_add(name=kname, from_mix=False)
            for i, co in enumerate(cos):
                sk.data[i].co = co
    groups = {}
    for v in me.vertices:
        for bone, w in weight_fn(Vector(v.co)):
            if w <= 1e-4:
                continue
            if bone not in groups:
                groups[bone] = ob.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, "REPLACE")
    PARTS.append(ob)
    TRI_COUNT[name] = TRI_COUNT.get(name, 0) + sum(len(p.vertices) - 2 for p in me.polygons)
    return ob


def rigid(bone):
    return lambda p: [(bone, 1.0)]


def blend(bone_a, bone_b, t):
    return [(bone_a, 1.0 - t), (bone_b, t)]


def fix_normals_outward(bm, center):
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - center) < 0:
            f.normal_flip()


# ---------------------------------------------------------------- cap parametrisation
CAP_C = HEAD_C + Vector((0.0, 0.005, 0.01))
CAP_R = Vector((HEAD_R.x + 0.022, HEAD_R.y + 0.024, HEAD_R.z + 0.022))


def cap_dir(p):
    rel = p - CAP_C
    d = Vector((rel.x / CAP_R.x, rel.y / CAP_R.y, rel.z / CAP_R.z)).normalized()
    return math.atan2(d.x, -d.y), math.asin(max(-1.0, min(1.0, d.z)))


def cap_point(phi, el, scale=1.0):
    d = Vector((math.sin(phi) * math.cos(el), -math.cos(phi) * math.cos(el), math.sin(el)))
    return CAP_C + Vector((d.x * CAP_R.x, d.y * CAP_R.y, d.z * CAP_R.z)) * scale


def rim_el(phi):
    """Elevation (radians, cap space) of the cap's lower edge: at the brow in front, low at the nape."""
    return math.radians(table_lerp([(0, 24), (40, 19), (80, 9), (120, 1), (180, -4)], abs(math.degrees(phi))))


# ---------------------------------------------------------------- head and face
def head_point_fn(p):
    """Round chubby head: full cheeks, wide soft lower face, gently rounded chin."""
    rel = p - HEAD_C
    nrm = Vector((rel.x / HEAD_R.x ** 2, rel.y / HEAD_R.y ** 2, rel.z / HEAD_R.z ** 2)).normalized()
    push = 0.0
    for s in (-1, 1):
        cc = HEAD_C + Vector((s * 0.14, -0.13, -0.09))
        d = (p - cc).length
        push += 0.034 * math.exp(-(d / 0.1) ** 2)
    k_wide = smoothstep(0.0, -0.12, rel.z) * (1.0 - smoothstep(-0.14, -0.24, rel.z))
    k_chin = smoothstep(-0.13, -0.24, rel.z)
    p = Vector((p.x * (1 + 0.05 * k_wide - 0.10 * k_chin), p.y, p.z))
    return p + nrm * push


HEAD_BVH = None


def head_surface(d, offset=0.0, origin=None):
    """Point on the head surface along direction d from origin (default head centre)."""
    o = HEAD_C if origin is None else origin
    d = d.normalized()
    hit = HEAD_BVH.ray_cast(o + d * 0.7, -d)
    if hit[0] is None:
        return o + d * 0.24
    return hit[0] + hit[1] * offset


def build_head():
    global HEAD_BVH
    bm = ellipsoid_bm(HEAD_C, HEAD_R, u=24, v=16)
    for v in bm.verts:
        v.co = head_point_fn(v.co)
    head_bvh_bm = bm.copy()
    HEAD_BVH = bvh_of(head_bvh_bm)
    # drop the skull faces hidden under the cap (saves triangles, never visible)
    hidden = [f for f in bm.faces
              if all(cap_dir(v.co)[1] > rim_el(cap_dir(v.co)[0]) + math.radians(7) for v in f.verts)]
    bmesh.ops.delete(bm, geom=hidden, context="FACES")
    add_part("Head", bm, ["Skin"], rigid("head"))
    # round button nose
    hit = HEAD_BVH.ray_cast(Vector((0, -1, 0.8)), Vector((0, 1, 0)))
    n = ellipsoid_bm(hit[0] + Vector((0, 0.003, 0)), Vector((0.027, 0.02, 0.021)), u=10, v=6)
    add_part("Nose", n, ["Skin"], rigid("head"))
    # ears
    for s in (-1, 1):
        hit = HEAD_BVH.ray_cast(Vector((s * 1.0, 0.02, 0.835)), Vector((-s, 0, 0)))
        c = hit[0] + Vector((s * 0.006, 0.0, 0.0))
        e = ellipsoid_bm(Vector((0, 0, 0)), Vector((0.016, 0.034, 0.048)), u=10, v=6)
        rot = Matrix.Rotation(s * math.radians(-18), 3, "Z") @ Matrix.Rotation(math.radians(-8), 3, "X")
        for v in e.verts:
            v.co = rot @ v.co + c
        add_part("Ear", e, ["Skin"], rigid("head"))
        # inner-ear shade
        ie = ellipsoid_bm(Vector((0, 0, 0)), Vector((0.006, 0.019, 0.03)), u=8, v=5)
        for v in ie.verts:
            v.co = rot @ (v.co + Vector((s * 0.0125, -0.004, 0.0))) + c
        add_part("EarIn", ie, ["SkinShade"], rigid("head"))


def project_on(bvh, x, z, offset):
    hit = bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
    if hit[0] is None:
        return Vector((x, 0.0, z))
    return hit[0] + hit[1] * offset


def flip_to_front(bm):
    bm.normal_update()
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()


def decal_bm(bvh, outline, offset, rings=3):
    """Filled star-shaped 2D polygon (x, z) projected onto a surface along +Y."""
    bm = bmesh.new()
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    loops = []
    for r in range(rings, 0, -1):
        t = r / rings
        loops.append([bm.verts.new(project_on(bvh, cx + (x - cx) * t, cz + (z - cz) * t, offset)) for x, z in outline])
    center = bm.verts.new(project_on(bvh, cx, cz, offset))
    n = len(outline)
    for k in range(len(loops) - 1):
        a, b = loops[k], loops[k + 1]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], b[i], b[j], a[j]))
    inner = loops[-1]
    for i in range(n):
        bm.faces.new((inner[i], center, inner[(i + 1) % n]))
    flip_to_front(bm)
    return bm


def strip_bm(bvh, tops, bots, offset_fn, rows=2):
    """Band between two (x, z) curves projected along +Y. offset_fn(row_t, col_t) -> offset.
    Same topology for any curves of the same length (used for shape keys)."""
    bm = bmesh.new()
    n = len(tops)
    grid = []
    for r in range(rows + 1):
        t = r / rows
        row = []
        for i in range(n):
            x = tops[i][0] + (bots[i][0] - tops[i][0]) * t
            z = tops[i][1] + (bots[i][1] - tops[i][1]) * t
            row.append(bm.verts.new(project_on(bvh, x, z, offset_fn(t, i / (n - 1)))))
        grid.append(row)
    for r in range(rows):
        for i in range(n - 1):
            bm.faces.new((grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i]))
    flip_to_front(bm)
    return bm


def ellipse(cx, cz, rx, rz, n=14, rot=0.0):
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, z = math.cos(a) * rx, math.sin(a) * rz
        out.append((cx + x * math.cos(rot) - z * math.sin(rot), cz + x * math.sin(rot) + z * math.cos(rot)))
    return out


def mouth_curves(g):
    """Closed smile (g=0) -> open grin (g=1). Returns (tops, bots) with 13 points each."""
    w = 0.040 + 0.014 * g
    lift = 0.0085 + 0.004 * g
    depth = 0.0042 + 0.026 * g
    tops, bots = [], []
    for i in range(13):
        u = -1 + 2 * i / 12
        x = u * w
        zt = MOUTH_Z + lift * u * u + 0.0025 * g * (1 - u * u)
        tops.append((x, zt))
        bots.append((x, zt - depth * (1 - u * u) ** 0.8 - 0.0006))
    return tops, bots


def teeth_curves(g):
    tops, bots = mouth_curves(g)
    t2, b2 = [], []
    for (x, zt), (_, zb) in zip(tops, bots):
        x *= 0.88
        t2.append((x, zt - 0.0015 * g))
        b2.append((x, zt - (0.0015 + 0.009 * (1 - (x / 0.06) ** 2)) * g))
    return t2, b2


def build_face():
    bvh = HEAD_BVH
    for s in (-1, 1):
        ex = s * EYE_X
        # warm brown eyes: iris, pupil, two highlights, soft upper lid line
        add_part("Eye", decal_bm(bvh, ellipse(ex, EYE_Z, 0.028, 0.034, 14), 0.002), ["EyeIris"], rigid("head"))
        add_part("Pupil", decal_bm(bvh, ellipse(ex, EYE_Z - 0.002, 0.017, 0.021, 12), 0.003, rings=2),
                 ["EyeDark"], rigid("head"))
        add_part("EyeHi", decal_bm(bvh, ellipse(ex + s * 0.009, EYE_Z + 0.012, 0.0095, 0.0105, 8), 0.0045, rings=1),
                 ["EyeWhite"], rigid("head"))
        add_part("EyeHi2", decal_bm(bvh, ellipse(ex - s * 0.01, EYE_Z - 0.016, 0.0045, 0.005, 6), 0.0045, rings=1),
                 ["EyeWhite"], rigid("head"))
        tops, bots = [], []
        for i in range(11):
            t = i / 10
            a = math.pi * (0.06 + 0.88 * t)
            x = ex - s * math.cos(a) * 0.0315
            z = EYE_Z + math.sin(a) * 0.0365
            tops.append((x, z + 0.0045 + 0.0015 * math.sin(math.pi * t) + (0.003 if (s * (x - ex) > 0.02) else 0.0)))
            bots.append((x, z - 0.0015))
        add_part("Lid", strip_bm(bvh, tops, bots, lambda r, c: 0.0035, rows=1), ["EyeDark"], rigid("head"))
        # thick dark brows, gently arched, heavier at the inner end
        tops, bots = [], []
        for i in range(11):
            t = i / 10  # 0 inner -> 1 outer
            x = ex + s * (-0.038 + 0.08 * t)
            mid = BROW_Z + 0.004 + 0.012 * math.sin(math.pi * (0.15 + 0.75 * t)) - 0.004 * t
            half = 0.0105 * (1 - t) + 0.0055 * t
            tops.append((x, mid + half))
            bots.append((x, mid - half))
        add_part("Brow", strip_bm(bvh, tops, bots, lambda r, c: 0.0025 + 0.002 * math.sin(math.pi * r), rows=2),
                 ["Brow"], rigid("head"))
        # rosy cheeks
        add_part("Blush", decal_bm(bvh, ellipse(s * 0.152, 0.778, 0.034, 0.019, 12), 0.0015, rings=2),
                 ["Blush"], rigid("head"))
    # closed, slightly mischievous smile with a "Grin" shape key (open toothy grin)
    t0, b0 = mouth_curves(0.0)
    t1, b1 = mouth_curves(1.0)
    off = lambda r, c: 0.002  # noqa: E731
    grin = strip_bm(bvh, t1, b1, off, rows=2)
    grin_co = [v.co.copy() for v in grin.verts]
    grin.free()
    add_part("Mouth", strip_bm(bvh, t0, b0, off, rows=2), ["Mouth"], rigid("head"), shape_keys={"Grin": grin_co})
    t0, b0 = teeth_curves(0.0)
    t1, b1 = teeth_curves(1.0)
    off_t = lambda r, c: 0.0032  # noqa: E731
    gt = strip_bm(bvh, t1, b1, off_t, rows=1)
    gt_co = [v.co.copy() for v in gt.verts]
    gt.free()
    add_part("Teeth", strip_bm(bvh, t0, b0, off_t, rows=1), ["Teeth"], rigid("head"), shape_keys={"Grin": gt_co})
    # soft lower lip hint
    lip_t, lip_b = [], []
    for i in range(9):
        u = -1 + 2 * i / 8
        x = u * 0.022
        z = MOUTH_Z - 0.009 - 0.002 * (1 - u * u)
        lip_t.append((x, z))
        lip_b.append((x, z - 0.006 * (1 - u * u) ** 0.7 - 0.0005))
    lip_lo = strip_bm(bvh, lip_t, lip_b, lambda r, c: 0.0012, rows=1)
    add_part("Lip", lip_lo, ["Lip"], rigid("head"))
    # thin moustache with slightly upturned ends
    ctrl = [(0.0, 0.0225), (0.022, 0.021), (0.044, 0.0145), (0.06, 0.0115), (0.073, 0.0175)]
    half = [0.0052, 0.0054, 0.0045, 0.0031, 0.0012]
    ctl = [Vector((x, z, h)) for (x, z), h in zip(ctrl, half)]
    right = catmull(ctl, 9)
    pts = [Vector((-p.x, p.y, p.z)) for p in reversed(right[1:])] + right
    tops = [(p.x, MOUTH_Z + p.y + p.z) for p in pts]
    bots = [(p.x, MOUTH_Z + p.y - p.z) for p in pts]
    add_part("Moustache", strip_bm(bvh, tops, bots,
                                   lambda r, c: 0.002 + 0.0045 * math.sin(math.pi * r) * (1 - abs(2 * c - 1) ** 3), rows=2),
             ["Beard"], rigid("head"))


def build_beard():
    """Short chin beard / goatee: a shell over the chin and along the lower jaw, no sideburns."""
    cols, rows = 24, 7
    phi_max = 86.0
    hi_tab = [(0, -42), (14, -43), (30, -50), (55, -55), (75, -52), (86, -49)]
    lo_tab = [(0, -88), (40, -80), (70, -66), (86, -56)]
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        v = r / rows  # 0 = under the chin, 1 = top edge
        row = []
        for c in range(cols + 1):
            ph = -phi_max + 2 * phi_max * c / cols
            a = abs(ph)
            el = table_lerp(lo_tab, a) + (table_lerp(hi_tab, a) - table_lerp(lo_tab, a)) * v
            phr, elr = math.radians(ph), math.radians(el)
            d = Vector((math.sin(phr) * math.cos(elr), -math.cos(phr) * math.cos(elr), math.sin(elr)))
            side = 1 - (a / phi_max) ** 2
            thick = 0.0018 + 0.0115 * (math.sin(math.pi * min(1.0, 0.2 + 0.8 * v)) ** 0.55) * side ** 0.6
            row.append(bm.verts.new(head_surface(d, thick)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    fix_normals_outward(bm, HEAD_C)
    add_part("Beard", bm, ["Beard"], rigid("head"))


def build_short_hair():
    """Very short dark hair visible below the cap at the sides and nape (no sideburns)."""
    cols, rows = 26, 3
    low_tab = [(60, None), (74, 6), (100, 4), (120, -8), (150, -20), (180, -23)]
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        v = r / rows
        row = []
        for c in range(cols + 1):
            ph = 60 + (300 - 60) * c / cols  # around the back
            a = ph if ph <= 180 else 360 - ph
            top = math.degrees(rim_el(math.radians(a))) + 6
            tab = [(60, top)] + low_tab[1:]
            lo = min(table_lerp(tab, a), top)
            el = lo + (top - lo) * v
            q = cap_point(math.radians(ph), math.radians(el))
            row.append(bm.verts.new(head_surface(q - HEAD_C, 0.0035)))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
    fix_normals_outward(bm, HEAD_C)
    add_part("HairShort", bm, ["HairShort"], rigid("head"))


# ---------------------------------------------------------------- flat cap
def build_cap():
    cols, rows = 32, 13
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    grid = []
    for r in range(rows):
        row = []
        t = r / (rows - 1)
        for c in range(cols):
            phi = -math.pi + 2 * math.pi * c / cols
            e0 = rim_el(phi)
            el = e0 + (math.radians(88) - e0) * (1 - (1 - t) ** 1.25)
            base = cap_point(phi, el, 0.955 if r == 0 else 1.0)
            if r > 0:
                rel = base - CAP_C
                n = Vector((rel.x / CAP_R.x ** 2, rel.y / CAP_R.y ** 2, rel.z / CAP_R.z ** 2)).normalized()
                front = smoothstep(0.06, -0.2, base.y)  # position-based: no pinching at the pole
                puff = 0.052 * smoothstep(0.06, 0.32, t) * (1 - 0.45 * smoothstep(0.45, 1.0, t))
                puff *= 1.0 + 0.25 * front
                base = base + n * puff
                # the crown is pulled forward over the brim and slopes down to the front
                base.y -= 0.07 * front * smoothstep(0.08, 0.5, t)
                base.y += 0.012 * smoothstep(0.6, 1.0, t)
                # wedge profile: the crown top slopes down towards the brim (soft clamp under a tilted plane)
                top_z = 1.13 + 0.26 * base.y
                w = 0.04
                if base.z > top_z - w:
                    base.z = top_z - w + w * math.tanh((base.z - (top_z - w)) / w)
            row.append(bm.verts.new(base))
        grid.append(row)
    top_v = sum((v.co for v in grid[-1]), Vector()) / cols
    top_v.z = max(v.co.z for v in grid[-1]) + 0.004
    top = bm.verts.new(top_v)
    for r in range(rows - 1):
        for c in range(cols):
            d = (c + 1) % cols
            bm.faces.new((grid[r][c], grid[r][d], grid[r + 1][d], grid[r + 1][c]))
    for c in range(cols):
        bm.faces.new((grid[-1][c], grid[-1][(c + 1) % cols], top))
    fix_normals_outward(bm, CAP_C)
    box_uv(bm, uv)
    add_part("Cap", bm, ["CapTweed"], rigid("head"))
    build_brim()


def build_brim():
    """Short stiff visor at the front, tucked under the crown overhang, angled down."""
    cols, rows = 16, 4
    phi_max = math.radians(74)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    top, bot = [], []
    for r in range(rows + 1):
        s = r / rows
        rt, rb = [], []
        for c in range(cols + 1):
            phi = -phi_max + 2 * phi_max * c / cols
            root = cap_point(phi, rim_el(phi) + math.radians(2.5), 0.99)
            h = Vector((math.sin(phi), -math.cos(phi), 0.0))
            L = 0.012 + 0.062 * max(0.0, math.cos(phi * 1.18)) ** 0.75
            dist = L * s
            p = root + h * dist + Vector((0, 0, -0.16 * dist - 0.1 * dist * s))
            th = 0.011 - 0.004 * s
            rt.append(bm.verts.new(p + Vector((0, 0, th * 0.5))))
            rb.append(bm.verts.new(p - Vector((0, 0, th * 0.5))))
        top.append(rt)
        bot.append(rb)
    F = []
    for r in range(rows):
        for c in range(cols):
            F.append(bm.faces.new((top[r][c], top[r][c + 1], top[r + 1][c + 1], top[r + 1][c])))
            F.append(bm.faces.new((bot[r][c], bot[r + 1][c], bot[r + 1][c + 1], bot[r][c + 1])))
    for c in range(cols):
        F.append(bm.faces.new((top[rows][c], top[rows][c + 1], bot[rows][c + 1], bot[rows][c])))
        F.append(bm.faces.new((top[0][c + 1], top[0][c], bot[0][c], bot[0][c + 1])))
    for r in range(rows):
        F.append(bm.faces.new((top[r + 1][0], top[r][0], bot[r][0], bot[r + 1][0])))
        F.append(bm.faces.new((top[r][cols], top[r + 1][cols], bot[r + 1][cols], bot[r][cols])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    box_uv(bm, uv)
    add_part("Brim", bm, ["CapTweed"], rigid("head"))


# ---------------------------------------------------------------- body
def build_body():
    # neck
    add_part("Neck", lathe_bm([(0.06, 0.68), (0.058, 0.61), (0.062, 0.565)], seg=12, yscale=0.9),
             ["Skin"], lambda p: blend("neck", "head", smoothstep(0.63, 0.67, p.z)))
    # waxed jacket (stocky, straight hip-length hem), half-open V over a dark tee
    prof = [(0.06, 0.625), (0.112, 0.612), (0.152, 0.586), (0.17, 0.54), (0.174, 0.46),
            (0.179, 0.38), (0.183, 0.30), (0.183, 0.258), (0.176, 0.246), (0.125, 0.242)]
    bm = lathe_bm(prof, seg=24, yscale=0.82)
    vz, k = JACKET_V_Z, 0.62
    for s in (-1, 1):
        no = Vector((1.0, 0.0, -s * k)).normalized()
        bisect_all(bm, Vector((0.0, 0.0, vz)), no)

    def face_mat(f):
        c = f.calc_center_median()
        if c.y < -0.02 and c.z > vz and abs(c.x) < (c.z - vz) * k:
            return 1  # tee
        return 0

    def jacket_w(p):
        t = smoothstep(0.41, 0.51, p.z)
        w = blend("spine", "chest", t)
        if p.z < 0.34:
            u = smoothstep(0.34, 0.29, p.z)
            w = [(b, x * (1 - u)) for b, x in w] + [("hips", u)]
        return w

    jacket_copy = bm.copy()
    add_part("Jacket", bm, ["Jacket", "Tee"], jacket_w, face_mat)
    jbvh = bvh_of(jacket_copy)
    jacket_copy.free()
    build_jacket_details(jbvh, jacket_w)
    build_collar()

    # trousers: hip block + legs
    add_part("Hips", lathe_bm([(0.13, 0.33), (0.145, 0.29), (0.135, 0.245), (0.095, 0.22)], seg=16, yscale=0.8,
                              cap_bottom=True), ["Trousers"], rigid("hips"))
    for s in (-1, 1):
        x = s * LEG_X
        side = "L" if s > 0 else "R"
        pts = [Vector((x, 0, z)) for z in (0.29, 0.25, 0.21, 0.18, 0.145, 0.11, 0.08)]
        radii = [0.056, 0.054, 0.051, 0.049, 0.048, 0.048, 0.048]

        def leg_w(p, side=side):
            t = smoothstep(KNEE_Z + 0.02, KNEE_Z - 0.02, p.z)
            return blend("upper_leg." + side, "lower_leg." + side, t)

        add_part("Leg", tube_bm(pts, radii, sides=10, cap0=False, cap1=False), ["Trousers"], leg_w)
        # boot: short shaft + rounded toe + dark sole
        shaft = lathe_bm([(0.052, 0.118), (0.059, 0.11), (0.058, 0.06), (0.057, 0.03)], seg=12, yscale=1.0,
                         center=Vector((x * 1.04, 0.002, 0)))
        add_part("BootShaft", shaft, ["Boots"], rigid("foot." + side))
        sh = ellipsoid_bm(Vector((x * 1.05, -0.026, 0.037)), Vector((0.056, 0.084, 0.045)), u=12, v=7)
        for v in sh.verts:
            if v.co.z < 0.012:
                v.co.z = 0.012 + (v.co.z - 0.012) * 0.15
        add_part("Boot", sh, ["Boots"], rigid("foot." + side))
        sole = ellipsoid_bm(Vector((x * 1.05, -0.026, 0.009)), Vector((0.058, 0.086, 0.01)), u=12, v=3)
        add_part("Sole", sole, ["BootSole"], rigid("foot." + side))

    # arms: long waxed sleeves with a cuff, mitten hands
    for s in (-1, 1):
        side = "L" if s > 0 else "R"
        sh_p = Vector((s * SHOULDER.x, SHOULDER.y, SHOULDER.z))
        el_p = Vector((s * ELBOW.x, ELBOW.y, ELBOW.z))
        wr_p = Vector((s * WRIST.x, WRIST.y, WRIST.z))
        hd_p = Vector((s * HAND.x, HAND.y, HAND.z))
        sl_pts = [sh_p + Vector((-s * 0.03, 0, 0.012)), sh_p.lerp(el_p, 0.25), sh_p.lerp(el_p, 0.65), el_p,
                  el_p.lerp(wr_p, 0.4), el_p.lerp(wr_p, 0.8), wr_p + (wr_p - el_p).normalized() * 0.008]
        sl_r = [0.056, 0.062, 0.058, 0.055, 0.052, 0.05, 0.049]

        def arm_w(p, side=side, ez=ELBOW.z):
            return blend("upper_arm." + side, "lower_arm." + side, smoothstep(ez + 0.015, ez - 0.025, p.z))

        add_part("Sleeve", tube_bm(sl_pts, sl_r, sides=10, cap0=True, cap1=False), ["Jacket"], arm_w)
        cdir = (wr_p - el_p).normalized()
        cuff = tube_bm([wr_p - cdir * 0.012, wr_p + cdir * 0.01], [0.054, 0.054], sides=10, cap0=False, cap1=True)
        add_part("Cuff", cuff, ["JacketDark"], rigid("lower_arm." + side))
        hb = ellipsoid_bm(hd_p, Vector((0.035, 0.039, 0.045)), u=10, v=6)
        add_part("Hand", hb, ["Skin"], rigid("hand." + side))
        th = ellipsoid_bm(hd_p + Vector((-s * 0.005, -0.032, 0.012)), Vector((0.014, 0.017, 0.023)), u=6, v=4)
        add_part("Thumb", th, ["Skin"], rigid("hand." + side))


def box_uv(bm, uv, k=6.5):
    """Box-projected UVs (per face, by dominant normal axis): no pole pinching; seams vanish in the tweed noise."""
    bm.normal_update()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            co = lp.vert.co
            if ax == 2:
                lp[uv].uv = (co.x * k, co.y * k)
            elif ax == 0:
                lp[uv].uv = (co.y * k, co.z * k)
            else:
                lp[uv].uv = (co.x * k, co.z * k)


def rect(x0, x1, z0, z1, n=4):
    pts = []
    for i in range(n):
        pts.append((x0 + (x1 - x0) * i / n, z1))
    for i in range(n):
        pts.append((x1, z1 + (z0 - z1) * i / n))
    for i in range(n):
        pts.append((x1 + (x0 - x1) * i / n, z0))
    for i in range(n):
        pts.append((x0, z0 + (z1 - z0) * i / n))
    return pts


def snap(bvh, x, z, w_fn, r=0.0085):
    c = project_on(bvh, x, z, 0.0)
    hit = bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
    n = hit[1] if hit[1] is not None else Vector((0, -1, 0))
    disc = tube_bm([c + n * 0.002, c + n * 0.0075], [r, r * 0.85], sides=10, cap0=False, cap1=True)
    add_part("Snap", disc, ["Brass"], w_fn)


def build_jacket_details(bvh, w_fn):
    vz, k = JACKET_V_Z, 0.62
    # storm flap beside the zip, with brass snaps
    add_part("Flap", decal_bm(bvh, rect(0.004, 0.05, 0.25, vz - 0.004, 4), 0.0045, rings=2), ["JacketDark"], w_fn)
    for z in (0.43, 0.33):
        snap(bvh, 0.03, z, w_fn)
    # brass zip: open V edges, then closed below the V
    for s in (-1, 1):
        pts = [project_on(bvh, s * (z - vz) * k + s * 0.004, z, 0.004)
               for z in [0.605 - (0.605 - vz) * i / 6 for i in range(7)]]
        add_part("Zip", tube_bm(pts, [0.0052] * len(pts), sides=4), ["Brass"], w_fn)
    pts = [project_on(bvh, 0.0, z, 0.0045) for z in [vz - (vz - 0.25) * i / 6 for i in range(7)]]
    add_part("Zip", tube_bm(pts, [0.0062] * len(pts), sides=4), ["Brass"], w_fn)
    # zip pull with ring
    c = project_on(bvh, 0.0, vz - 0.022, 0.012)
    add_part("ZipPull", tube_bm([c + Vector((0, 0, 0.016)), c - Vector((0, 0, 0.004))], [0.0055, 0.0055], sides=4),
             ["Brass"], w_fn)
    ring = []
    for i in range(13):
        a = 2 * math.pi * i / 12
        ring.append(c + Vector((math.sin(a) * 0.011, -0.002, -0.014 + math.cos(a) * 0.011)))
    add_part("ZipRing", tube_bm(ring, [0.0028] * len(ring), sides=4, cap0=False, cap1=False), ["Brass"], w_fn)
    # big bellows pockets with flaps and a snap each
    for s in (-1, 1):
        x0, x1 = (0.06, 0.15) if s > 0 else (-0.15, -0.06)
        add_part("Pocket", decal_bm(bvh, rect(x0, x1, 0.262, 0.345, 4), 0.004, rings=2), ["JacketDark"], w_fn)
        add_part("PocketFlap", decal_bm(bvh, rect(x0 - 0.004, x1 + 0.004, 0.33, 0.362, 4), 0.0085, rings=2),
                 ["Jacket"], w_fn)
        snap(bvh, (x0 + x1) / 2, 0.344, w_fn, r=0.0075)


def build_collar():
    """Brown corduroy stand collar, open at the front, a little taller at the back."""
    a0, a1 = math.radians(28), math.radians(332)
    cols = 26
    bm = bmesh.new()
    loops = []
    for c in range(cols + 1):
        a = a0 + (a1 - a0) * c / cols
        back = (1 - math.cos(a)) / 2  # 0 front .. 1 back
        frontness = 1 - smoothstep(0.0, 0.35, back)
        h_top = 0.664 + 0.022 * back
        r_in = 0.074 + 0.012 * frontness
        r_out = r_in + 0.03 + 0.02 * frontness  # lapel ends flare outward
        prof = [(r_in, 0.585), (r_in + 0.004, h_top), (r_out, h_top - 0.012 - 0.01 * frontness), (r_out + 0.008, 0.592)]
        d = Vector((math.sin(a), -math.cos(a) * 0.86, 0.0))
        loops.append([bm.verts.new(Vector((0, 0, z)) + d * r) for r, z in prof])
    faces = []
    for c in range(cols):
        for i in range(4):
            j = (i + 1) % 4
            f = bm.faces.new((loops[c][i], loops[c][j], loops[c + 1][j], loops[c + 1][i]))
            f.material_index = c % 2  # corduroy ribs
            faces.append(f)
    for L in (loops[0], loops[-1]):
        f = bm.faces.new(L)
        f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    add_part("Collar", bm, ["CordA", "CordB"], lambda p: blend("chest", "neck", smoothstep(0.62, 0.68, p.z) * 0.5))


# ---------------------------------------------------------------- armature (same bone names as the heroine)
def build_armature():
    arm_data = bpy.data.armatures.new("Hero2Rig")
    arm = bpy.data.objects.new("Hero2", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    fwd = Vector((0, -1, 0))

    def bone(name, head, tail, parent=None, roll_vec=fwd):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.align_roll(roll_vec)
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        return b

    bone("root", (0, 0, 0), (0, 0, 0.1))
    bone("hips", (0, 0, HIP_Z), (0, 0, 0.40), "root")
    bone("spine", (0, 0, 0.40), (0, 0, 0.49), "hips")
    bone("chest", (0, 0, 0.49), (0, 0, 0.59), "spine")
    bone("neck", (0, 0, 0.59), (0, 0, 0.655), "chest")
    bone("head", (0, 0, 0.655), (0, 0, 1.08), "neck")
    for s, side in ((1, "L"), (-1, "R")):
        sh = Vector((s * SHOULDER.x, SHOULDER.y, SHOULDER.z))
        el = Vector((s * ELBOW.x, ELBOW.y, ELBOW.z))
        wr = Vector((s * WRIST.x, WRIST.y, WRIST.z))
        hd = Vector((s * HAND.x, HAND.y, HAND.z - 0.04))
        bone("upper_arm." + side, sh, el, "chest")
        bone("lower_arm." + side, el, wr, "upper_arm." + side)
        bone("hand." + side, wr, hd, "lower_arm." + side)
        x = s * LEG_X
        bone("upper_leg." + side, (x, 0, HIP_Z - 0.02), (x, 0, KNEE_Z), "hips")
        bone("lower_leg." + side, (x, 0, KNEE_Z), (x, 0, ANKLE_Z), "upper_leg." + side)
        bone("foot." + side, (x, 0, ANKLE_Z), (x, -0.08, 0.02), "lower_leg." + side, roll_vec=Vector((0, 0, 1)))
        # kept for skeleton parity with the heroine (no geometry bound: he has no braids)
        bone("braid." + side, (s * 0.27, -0.03, HEAD_C.z - 0.08), (s * 0.27, -0.03, 0.45), "head")
    bone("braid.B", (0, 0.23, HEAD_C.z - 0.08), (0, 0.23, 0.45), "head", roll_vec=Vector((0, 1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ---------------------------------------------------------------- animation
def key_pose(arm, frame, pose):
    """pose: {bone: {"rot": (x, y, z) degrees local euler, "loc": (x, y, z)}}"""
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        spec = pose.get(pb.name, {})
        r = spec.get("rot", (0, 0, 0))
        l = spec.get("loc", (0, 0, 0))
        pb.rotation_euler = tuple(math.radians(v) for v in r)
        pb.location = l
        pb.keyframe_insert("rotation_euler", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def make_action(arm, name, keys):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, pose in keys:
        key_pose(arm, frame, pose)
    try:
        curves = act.fcurves
    except AttributeError:
        curves = [fc for layer in act.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.easing = "AUTO"
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(keys[0][0]), act)
    strip.name = name
    arm.animation_data.action = None
    return act


# Right-arm shoulder carry (Idle, Walk, start/end of Swing): upper arm hanging a little forward,
# forearm folded up so the wrist sits by the right collarbone (~(-0.185, -0.09, 0.52)) and the
# hand grips the net handle that rests over the shoulder. Solved numerically, then rounded.
def CARRY_UPPER_R(bob):
    return (19 + bob, 0, 8)


def CARRY_LOWER_R(bob):
    return (128 + bob, 0, 0)


def build_actions(arm):
    # Idle: 2 s breathing / bob loop (a touch heavier and calmer than the heroine)
    def idle(t):
        s = math.sin(2 * math.pi * t)
        c = math.cos(2 * math.pi * t)
        return {
            "hips": {"loc": (0, 0.005 * s, 0)},
            "spine": {"rot": (1.5 * s, 0, 0)},
            "chest": {"rot": (-1.8 * s, 0, 0)},
            "head": {"rot": (-2.0 * s, 0, 2.5 * c)},
            "upper_arm.L": {"rot": (2 * s, 0, -6 - 2 * s)},
            # right arm: shoulder carry, the hand grips the net handle by the collarbone
            "upper_arm.R": {"rot": CARRY_UPPER_R(1.5 * s)},
            "lower_arm.L": {"rot": (8, 0, 0)},
            "lower_arm.R": {"rot": CARRY_LOWER_R(0.0)},
        }
    n = 120
    make_action(arm, "Idle", [(f, idle(f / n)) for f in range(0, n + 1, 15)])

    # Walk: bouncy chibi walk, 0.6 s loop
    def walk(t):
        a = 2 * math.pi * t
        s, c = math.sin(a), math.cos(a)
        bounce = abs(math.sin(a))
        lift_l = max(0.0, -s)
        lift_r = max(0.0, s)
        return {
            "hips": {"loc": (0, 0.022 * bounce - 0.01, 0), "rot": (0, 8 * s, 4 * c)},
            "spine": {"rot": (4, -4 * s, 0)},
            "chest": {"rot": (0, -6 * s, 0)},
            "head": {"rot": (-4 + 3 * bounce, 4 * s, -3 * c)},
            "upper_leg.L": {"rot": (-28 * s + 5, 0, 0)},
            "upper_leg.R": {"rot": (28 * s + 5, 0, 0)},
            "lower_leg.L": {"rot": (-45 * lift_l, 0, 0)},
            "lower_leg.R": {"rot": (-45 * lift_r, 0, 0)},
            "foot.L": {"rot": (20 * lift_l - 10 * max(0, s), 0, 0)},
            "foot.R": {"rot": (20 * lift_r - 10 * max(0, -s), 0, 0)},
            "upper_arm.L": {"rot": (30 * s, 0, -10)},
            "upper_arm.R": {"rot": CARRY_UPPER_R(3.0 * s)},
            "lower_arm.L": {"rot": (18 + 10 * max(0, s), 0, 0)},
            "lower_arm.R": {"rot": CARRY_LOWER_R(4.0 * bounce)},
        }
    n = 36
    make_action(arm, "Walk", [(f, walk(f / n)) for f in range(0, n + 1, 3)])

    # Swing: right-arm net swing, 0.45 s one-shot (27 frames @ 60 fps).
    # Readable from the iso camera: head stays up, torso only twists a little, and the
    # arm sweeps the net at shoulder height from his right-back (wind-up) to front-right
    # (strike) to front-left (follow-through). The hoop stays ~0.7 m up and out of the
    # head's silhouette, plane kept near horizontal (the Net prop in hand_tools.tscn
    # is rolled to match), so it reads as a ring whether he faces the camera or not.
    # upper_arm X raises the arm forward, then Y yaws it (+ = to his right).
    # Same keys as the heroine (solved numerically for those hoop targets, then rounded).
    rest = idle(0.0)
    wind = {
        "hips": {"loc": (0, -0.008, 0), "rot": (0, -6, 0)},
        "spine": {"rot": (0, -4, 0)},
        "chest": {"rot": (-2, -8, 0)},
        "head": {"rot": (-6, 14, 0)},
        "upper_arm.R": {"rot": (111, 51, -1)},
        "lower_arm.R": {"rot": (0, 0, 0)},
        "hand.R": {"rot": (-26, 46, 13)},
        "upper_arm.L": {"rot": (15, 0, -20)},
        "lower_arm.L": {"rot": (30, 0, 0)},
        "upper_leg.L": {"rot": (8, 0, 0)},
        "upper_leg.R": {"rot": (-6, 0, 0)},
    }
    strike = {
        "hips": {"loc": (0, -0.015, 0), "rot": (0, 4, 0)},
        "spine": {"rot": (2, 3, 0)},
        "chest": {"rot": (0, 6, 0)},
        "head": {"rot": (-6, -8, 0)},
        "upper_arm.R": {"rot": (125, -2, 27)},
        "lower_arm.R": {"rot": (0, 0, 0)},
        "hand.R": {"rot": (-29, 30, 20)},
        "upper_arm.L": {"rot": (-15, 0, -25)},
        "lower_arm.L": {"rot": (30, 0, 0)},
        "upper_leg.L": {"rot": (14, 0, 0)},
        "lower_leg.L": {"rot": (-8, 0, 0)},
        "upper_leg.R": {"rot": (-10, 0, 0)},
    }
    follow = {
        "hips": {"loc": (0, -0.01, 0), "rot": (0, 8, 0)},
        "spine": {"rot": (2, 5, 0)},
        "chest": {"rot": (0, 10, 0)},
        "head": {"rot": (-4, -14, 0)},
        "upper_arm.R": {"rot": (91, -62, 47)},
        "lower_arm.R": {"rot": (0, 0, 0)},
        "hand.R": {"rot": (-25, 21, 30)},
        "upper_arm.L": {"rot": (-10, 0, -15)},
        "lower_arm.L": {"rot": (20, 0, 0)},
        "upper_leg.L": {"rot": (10, 0, 0)},
        "upper_leg.R": {"rot": (-6, 0, 0)},
    }
    make_action(arm, "Swing", [(0, rest), (7, wind), (13, strike), (19, follow), (27, rest)])

    # Hurt: short flinch, 0.35 s
    flinch = {
        "hips": {"loc": (0, -0.02, 0.02)},
        "spine": {"rot": (-10, 0, 0)},
        "chest": {"rot": (-8, 0, 0)},
        "head": {"rot": (-12, 0, 6)},
        "upper_arm.L": {"rot": (-20, 0, -30)},
        "upper_arm.R": {"rot": (-20, 0, 30)},
        "lower_arm.L": {"rot": (60, 0, 0)},
        "lower_arm.R": {"rot": (60, 0, 0)},
    }
    make_action(arm, "Hurt", [(0, rest), (5, flinch), (12, flinch), (21, rest)])


# ---------------------------------------------------------------- main
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    build_materials()
    build_head()
    build_face()
    build_beard()
    build_short_hair()
    build_cap()
    build_body()

    # join all parts into one skinned mesh (Mouth carries the shape keys: make it the active object)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in PARTS:
        ob.select_set(True)
    active = next(ob for ob in PARTS if ob.data.shape_keys is not None)
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Hero2Mesh"
    body.data.name = "Hero2Mesh"
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("TRIANGLES", tris)
    print("PER PART", sorted(TRI_COUNT.items(), key=lambda kv: -kv[1]))
    print("SHAPE KEYS", [k.name for k in body.data.shape_keys.key_blocks] if body.data.shape_keys else None)
    print("MATERIALS", [m.name for m in body.data.materials])

    arm = build_armature()
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    build_actions(arm)
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)

    print("BONES", [b.name for b in arm.data.bones])
    print("ACTIONS", [a.name for a in bpy.data.actions])
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_skins=True,
        export_morph=True,
        export_yup=True,
        export_apply=False,
        export_force_sampling=True,
        export_materials="EXPORT",
    )
    print("WROTE", OUT)


main()

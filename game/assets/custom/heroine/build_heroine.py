"""ChronoFlore heroine generator (Blender bpy, headless, deterministic).

Builds the chibi dreamer-botanist (~1.1 m, origin at the feet, facing -Y in Blender
which becomes +Z in Godot), rigs it and writes heroine.glb with the actions
Idle, Walk, Swing and Hurt.

Usage: <bpy python> build_heroine.py [output.glb]
(default output: heroine.glb next to this script, i.e. game/assets/custom/heroine/).
The .glb.import next to it makes Idle and Walk loop and samples animations at 60 fps.
"""
import math
import os
import sys

import bpy  # noqa: I001  (bpy must be imported before bmesh/mathutils)
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "heroine.glb")
FPS = 60

# ---------------------------------------------------------------- dimensions (metres, Blender Z up)
HEAD_C = Vector((0.0, 0.0, 0.835))
HEAD_R = Vector((0.25, 0.225, 0.235))  # semi-axes x (width), y (depth), z (height)
EYE_Z = 0.81
EYE_X = 0.088
MOUTH_Z = 0.712
SHOULDER = Vector((0.135, 0.0, 0.53))
ELBOW = Vector((0.185, 0.0, 0.42))
WRIST = Vector((0.205, -0.005, 0.33))
HAND = Vector((0.212, -0.008, 0.29))
HIP_Z = 0.31
LEG_X = 0.062
KNEE_Z = 0.175
ANKLE_Z = 0.065


# ---------------------------------------------------------------- colours / materials
def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, lighten=0.0):
    h = h.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    rgb = [c + (1.0 - c) * lighten for c in rgb]
    return [srgb_to_lin(c) for c in rgb]


MATS = {}
# Self-lit share of every albedo (glTF emissive) so she stays readable under the game's weak
# night sun and ambient light without flattening the shading.
LIGHT_LIFT = 0.2


def mat(name, hexc, alpha=1.0, rough=0.8, lighten=0.0, emit=0.0):
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
    emit = max(emit, LIGHT_LIFT)
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


def build_materials():
    mat("Skin", "#74462f", rough=0.7)
    mat("SkinDark", "#3a2218", rough=0.7)
    mat("Hair", "#1c1614", rough=0.55)
    mat("HairShine", "#3a2e2a", rough=0.5)
    mat("EyeDark", "#1a1210", rough=0.3)
    mat("EyeWhite", "#ffffff", rough=0.3, emit=0.4)
    mat("Mouth", "#5a1e22", rough=0.6)
    mat("Teeth", "#fffaf2", rough=0.4)
    mat("Tongue", "#e07a86", rough=0.6)
    mat("Blush", "#c85a5a", rough=0.8)
    mat("GlassFrame", "#eab0bf", alpha=0.88, rough=0.25)
    mat("GlassLens", "#b07a7a", alpha=0.55, rough=0.15)
    mat("Gold", "#d6a84a", rough=0.35)
    mat("StripeGreen", "#2f5a46", lighten=0.18)
    mat("StripeNavy", "#2e2a55", lighten=0.18)
    mat("StripeRed", "#c8392f", lighten=0.12)
    mat("StripeOrange", "#e07a2a", lighten=0.10)
    mat("StripeTeal", "#2f6b6b", lighten=0.18)
    mat("Trousers", "#efe3cf", rough=0.9)
    mat("Shoes", "#6e4430", rough=0.7)
    mat("ShoeSole", "#f6efe0", rough=0.9)
    mat("Nails", "#d3e07a", rough=0.5)


STRIPES = ["StripeGreen", "StripeNavy", "StripeRed", "StripeOrange", "StripeTeal"]
STRIPE_W = 0.05
BRAID_SPACING = 0.04  # ring spacing along a braid (main triangle-budget knob)
STRIPE_N = Vector((-0.5, 0.0, 0.866)).normalized()  # stripes rise to the character's left


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
                bm.faces.new((a[i], a[j], b[j], b[i]))
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


def resample(pts, spacing):
    """Resample a dense polyline at constant arc-length spacing."""
    L = [0.0]
    for i in range(1, len(pts)):
        L.append(L[-1] + (pts[i] - pts[i - 1]).length)
    total = L[-1]
    n = max(2, int(round(total / spacing)) + 1)
    out = []
    j = 0
    for k in range(n):
        d = total * k / (n - 1)
        while j < len(L) - 2 and L[j + 1] < d:
            j += 1
        seg = L[j + 1] - L[j]
        t = 0.0 if seg == 0 else (d - L[j]) / seg
        out.append(pts[j].lerp(pts[j + 1], t))
    return out, total


def bisect_all(bm, co, no):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)


def stripe_index(p):
    return int(math.floor(p.dot(STRIPE_N) / STRIPE_W)) % len(STRIPES)


def cut_stripes(bm):
    ds = [v.co.dot(STRIPE_N) for v in bm.verts]
    k0 = int(math.floor(min(ds) / STRIPE_W))
    k1 = int(math.ceil(max(ds) / STRIPE_W))
    for k in range(k0, k1 + 1):
        bisect_all(bm, STRIPE_N * (k * STRIPE_W), STRIPE_N)


def bvh_of(bm):
    return BVHTree.FromBMesh(bm)


# ---------------------------------------------------------------- object assembly
PARTS = []
TRI_COUNT = {}


def add_part(name, bm, mats, weight_fn, face_mat_fn=None, smooth=True):
    """mats: list of material names. face_mat_fn(face) -> index into mats."""
    me = bpy.data.meshes.new(name)
    if face_mat_fn is not None:
        for f in bm.faces:
            f.material_index = face_mat_fn(f)
    for f in bm.faces:
        f.smooth = smooth
    # triangulate here so the export is byte-for-byte reproducible
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="FIXED", ngon_method="EAR_CLIP")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(MATS[m])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
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


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def blend(bone_a, bone_b, t):
    return [(bone_a, 1.0 - t), (bone_b, t)]


# ---------------------------------------------------------------- head and face
def head_point_fn(p):
    """Shape the head: chubby cheeks, slightly narrower chin."""
    rel = p - HEAD_C
    nrm = Vector((rel.x / HEAD_R.x ** 2, rel.y / HEAD_R.y ** 2, rel.z / HEAD_R.z ** 2)).normalized()
    push = 0.0
    for s in (-1, 1):
        cc = HEAD_C + Vector((s * 0.13, -0.15, -0.085))
        d = (p - cc).length
        push += 0.03 * math.exp(-(d / 0.085) ** 2)
    # flatten the face front a little and narrow the chin
    if rel.z < -0.1:
        k = smoothstep(-0.1, -0.235, rel.z)
        p = Vector((p.x * (1 - 0.12 * k), p.y, p.z))
    return p + nrm * push


def build_head():
    bm = ellipsoid_bm(HEAD_C, HEAD_R, u=24, v=16)
    for v in bm.verts:
        v.co = head_point_fn(v.co)
    head_bvh_bm = bm.copy()
    # drop the skull faces hidden under the hair cap (saves triangles, never visible)
    hidden = [f for f in bm.faces
              if all(cap_dir(v.co)[1] > hairline_el(cap_dir(v.co)[0]) + math.radians(8) for v in f.verts)]
    bmesh.ops.delete(bm, geom=hidden, context="FACES")
    add_part("Head", bm, ["Skin"], rigid("head"))
    # nose: tiny bump
    bvh = bvh_of(head_bvh_bm)
    hit = bvh.ray_cast(Vector((0, -1, 0.765)), Vector((0, 1, 0)))
    n = ellipsoid_bm(hit[0] + Vector((0, 0.004, 0)), Vector((0.022, 0.016, 0.016)), u=8, v=5)
    add_part("Nose", n, ["Skin"], rigid("head"))
    return bvh


def project_on(bvh, x, z, offset):
    hit = bvh.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
    if hit[0] is None:
        return Vector((x, 0.0, z))
    return hit[0] + hit[1] * offset


def decal_bm(bvh, outline, offset, rings=3):
    """Filled 2D polygon (x, z) projected onto a surface along +Y, with interior rings for curvature."""
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
    # make faces point outward (-Y-ish)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    return bm


def ellipse(cx, cz, rx, rz, n=14, rot=0.0):
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, z = math.cos(a) * rx, math.sin(a) * rz
        out.append((cx + x * math.cos(rot) - z * math.sin(rot), cz + x * math.sin(rot) + z * math.cos(rot)))
    return out


def build_face(bvh):
    # eyes: big glossy ovals with highlights
    for s in (-1, 1):
        ex = s * EYE_X
        add_part("Eye", decal_bm(bvh, ellipse(ex, EYE_Z, 0.024, 0.032, 14), 0.002), ["EyeDark"], rigid("head"))
        add_part("EyeHi", decal_bm(bvh, ellipse(ex + s * 0.008, EYE_Z + 0.012, 0.009, 0.01, 8), 0.004, rings=1),
                 ["EyeWhite"], rigid("head"))
        add_part("EyeHi2", decal_bm(bvh, ellipse(ex - s * 0.009, EYE_Z - 0.014, 0.004, 0.0045, 6), 0.004, rings=1),
                 ["EyeWhite"], rigid("head"))
        # happy eyebrows above the frames
        brow = []
        for i in range(9):
            t = i / 8
            x = ex + s * (-0.03 + 0.06 * t)
            brow.append((x, 0.912 + 0.012 * math.sin(math.pi * t)))
        for i in range(8, -1, -1):
            t = i / 8
            x = ex + s * (-0.03 + 0.06 * t)
            brow.append((x, 0.902 + 0.010 * math.sin(math.pi * t)))
        add_part("Brow", decal_bm(bvh, brow, 0.002, rings=1), ["Hair"], rigid("head"))
        # blush
        add_part("Blush", decal_bm(bvh, ellipse(s * 0.145, 0.735, 0.03, 0.017, 12), 0.0015, rings=2),
                 ["Blush"], rigid("head"))
    # big open toothy smile (D shape): top edge gently curved, bottom deep arc
    w = 0.07
    top = [(-w + 2 * w * i / 12, MOUTH_Z + 0.02 - 0.008 * math.sin(math.pi * i / 12) ** 2 + 0.004 * (abs(i - 6) / 6) ** 2)
           for i in range(13)]
    # ordered loop: top edge left->right, then the bottom arc right->left
    loop = list(top) + [(w * math.cos(math.pi * i / 12), MOUTH_Z + 0.02 - 0.07 * math.sin(math.pi * i / 12) ** 0.9)
                        for i in range(1, 12)]
    add_part("Mouth", decal_bm(bvh, loop, 0.002, rings=3), ["Mouth"], rigid("head"))
    # teeth band under the top lip
    tw = w * 0.86
    t_top = [(-tw + 2 * tw * i / 10, MOUTH_Z + 0.0175 - 0.008 * math.sin(math.pi * i / 10) ** 2) for i in range(11)]
    t_bot = [(tw - 2 * tw * i / 10, MOUTH_Z + 0.0005 - 0.008 * math.sin(math.pi * i / 10) ** 2 - 0.004 * math.sin(math.pi * i / 10))
             for i in range(11)]
    add_part("Teeth", decal_bm(bvh, t_top + t_bot, 0.0035, rings=1), ["Teeth"], rigid("head"))
    # tongue at the bottom
    add_part("Tongue", decal_bm(bvh, ellipse(0.0, MOUTH_Z - 0.034, 0.034, 0.014, 12), 0.003, rings=1),
             ["Tongue"], rigid("head"))


def rounded_hex(cx, cz, r, corner=0.25, rot=0.0, sx=1.0):
    """Flat-topped hexagon with rounded corners, as a list of (x, z)."""
    pts = []
    for k in range(6):
        a = math.radians(60 * k) + rot
        prev_a = math.radians(60 * (k - 1)) + rot
        next_a = math.radians(60 * (k + 1)) + rot
        c = Vector((math.cos(a), math.sin(a)))
        p = Vector((math.cos(prev_a), math.sin(prev_a)))
        nx = Vector((math.cos(next_a), math.sin(next_a)))
        a0 = c.lerp(p, corner * 0.5)
        a1 = c.lerp(nx, corner * 0.5)
        for t in (0.0, 0.5, 1.0):
            q = (a0.lerp(c, t)).lerp(c.lerp(a1, t), t)  # quadratic bezier
            pts.append((cx + q.x * r * sx, cz + q.y * r))
    return pts


def ring_solid_bm(outer, inner, y_front, y_back, xform):
    bm = bmesh.new()
    n = len(outer)
    lo_f = [bm.verts.new(xform(Vector((x, y_front, z)))) for x, z in outer]
    li_f = [bm.verts.new(xform(Vector((x, y_front, z)))) for x, z in inner]
    lo_b = [bm.verts.new(xform(Vector((x, y_back, z)))) for x, z in outer]
    li_b = [bm.verts.new(xform(Vector((x, y_back, z)))) for x, z in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo_f[i], lo_f[j], li_f[j], li_f[i]))
        bm.faces.new((lo_b[j], lo_b[i], li_b[i], li_b[j]))
        bm.faces.new((lo_f[j], lo_f[i], lo_b[i], lo_b[j]))
        bm.faces.new((li_f[i], li_f[j], li_b[j], li_b[i]))
    bm.normal_update()
    return bm


def build_glasses(bvh):
    R = 0.07
    face_y = project_on(bvh, EYE_X, EYE_Z, 0.0).y
    y0 = face_y - 0.03
    for s in (-1, 1):
        cx = s * (EYE_X + 0.004)

        def xform(p, s=s, cx=cx):
            # wrap each lens around the face (rotate about Z through the lens centre)
            ang = s * math.radians(-12)
            q = Vector((p.x - cx, p.y - y0, p.z))
            q = Matrix.Rotation(ang, 3, "Z") @ q
            return Vector((q.x + cx, q.y + y0, q.z))

        outer = rounded_hex(cx, EYE_Z + 0.003, R, corner=0.35, sx=1.1)
        inner = rounded_hex(cx, EYE_Z + 0.003, R * 0.80, corner=0.35, sx=1.1)
        add_part("GlassFrame", ring_solid_bm(outer, inner, y0 - 0.006, y0 + 0.006, xform), ["GlassFrame"], rigid("head"))
        # lens
        bm = bmesh.new()
        vs = [bm.verts.new(xform(Vector((x, y0, z)))) for x, z in inner]
        c = bm.verts.new(xform(Vector((cx, y0, EYE_Z + 0.003))))
        for i in range(len(vs)):
            bm.faces.new((vs[i], c, vs[(i + 1) % len(vs)]))
        bm.normal_update()
        for f in bm.faces:
            if f.normal.y > 0:
                f.normal_flip()
        add_part("GlassLens", bm, ["GlassLens"], rigid("head"), smooth=False)
        # temple arm back to the ear
        x_out = s * (EYE_X + R * 1.1 * 0.95)
        p0 = xform(Vector((x_out + s * 0.004, y0, EYE_Z + 0.03)))
        # hug the side of the head: march around it at a constant offset from the surface
        a0 = math.atan2(abs(p0.x), -p0.y)
        pts = [p0]
        for k in range(1, 7):
            t = k / 6
            ang = a0 + (math.radians(100) - a0) * t
            z = p0.z + (EYE_Z - 0.005 - p0.z) * t
            d = Vector((s * math.sin(ang), -math.cos(ang), 0.0))
            hit = bvh.ray_cast(Vector((0, 0, z)) + d * 0.6, -d)
            q = hit[0] + d * 0.011 if hit[0] is not None else Vector((0, 0, z)) + d * 0.26
            pts.append(q)
        pts = catmull(pts, 9)
        add_part("GlassTemple", tube_bm(pts, [0.0065] * len(pts), sides=5), ["GlassFrame"], rigid("head"))
    # bridge
    bx = EYE_X + 0.004 - R * 1.1 * 0.95
    pts = [Vector((-bx, y0 - 0.001, EYE_Z + 0.02)), Vector((0, y0 - 0.006, EYE_Z + 0.03)), Vector((bx, y0 - 0.001, EYE_Z + 0.02))]
    add_part("GlassBridge", tube_bm(catmull(pts, 6), [0.007] * 6, sides=5), ["GlassFrame"], rigid("head"))


# ---------------------------------------------------------------- hair
CAP_C = HEAD_C + Vector((0.0, 0.012, 0.012))
CAP_R = Vector((HEAD_R.x + 0.017, HEAD_R.y + 0.02, HEAD_R.z + 0.02))


def cap_dir(p):
    rel = p - CAP_C
    d = Vector((rel.x / CAP_R.x, rel.y / CAP_R.y, rel.z / CAP_R.z)).normalized()
    return math.atan2(d.x, -d.y), math.asin(max(-1.0, min(1.0, d.z)))


def cap_point(phi, el, scale=1.0):
    d = Vector((math.sin(phi) * math.cos(el), -math.cos(phi) * math.cos(el), math.sin(el)))
    return CAP_C + Vector((d.x * CAP_R.x, d.y * CAP_R.y, d.z * CAP_R.z)) * scale


def hairline_el(phi):
    """Hairline elevation (radians) on the cap: rounded forehead, temples, low nape."""
    a = abs(math.degrees(phi))
    table = [(0, 36), (30, 29), (50, 16), (65, -8), (80, -28), (110, -40), (180, -52)]
    for (a0, e0), (a1, e1) in zip(table, table[1:]):
        if a <= a1:
            e = e0 + (e1 - e0) * smoothstep(a0, a1, a)
            break
    return math.radians(e)


def build_hair():
    # cap built on a grid that follows the hairline exactly (clean edge, no slivers)
    cols, rows = 24, 8
    bm = bmesh.new()
    grid = []
    for r in range(rows):
        row = []
        for c in range(cols):
            phi = -math.pi + 2 * math.pi * c / cols
            e0 = hairline_el(phi)
            t = r / rows
            el = e0 + (math.radians(90) - e0) * (1 - (1 - t) ** 1.3)
            row.append(bm.verts.new(cap_point(phi, el, 0.975 if r == 0 else 1.0)))
        grid.append(row)
    top = bm.verts.new(cap_point(0.0, math.radians(90)))
    for r in range(rows - 1):
        for c in range(cols):
            d = (c + 1) % cols
            bm.faces.new((grid[r][c], grid[r][d], grid[r + 1][d], grid[r + 1][c]))
    for c in range(cols):
        bm.faces.new((grid[-1][c], grid[-1][(c + 1) % cols], top))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.dot(f.calc_center_median() - CAP_C) < 0:
            f.normal_flip()
    add_part("HairCap", bm, ["Hair"], rigid("head"))

    # centre part: thin line of scalp from the forehead hairline over the top
    part_pts = [cap_point(0.0, math.radians(31 + 52 * i / 6), 1.004) for i in range(7)]
    add_part("HairPart", tube_bm(part_pts, [0.0018] * 7, sides=4), ["SkinDark"], rigid("head"))

    braids = []
    # (azimuth deg from front, root elevation deg, end point offsets, side bone)
    # front framing braids
    specs = [
        (46, 55, Vector((0.18, -0.135, 0.40)), "braid.L"),
        (-46, 55, Vector((-0.18, -0.135, 0.40)), "braid.R"),
        (62, 45, Vector((0.25, -0.06, 0.43)), "braid.L"),
        (-62, 45, Vector((-0.25, -0.06, 0.43)), "braid.R"),
        (78, 52, Vector((0.275, 0.0, 0.42)), "braid.L"),
        (-78, 52, Vector((-0.275, 0.0, 0.42)), "braid.R"),
        (96, 58, Vector((0.27, 0.07, 0.40)), "braid.L"),
        (-96, 58, Vector((-0.27, 0.07, 0.40)), "braid.R"),
        (115, 62, Vector((0.235, 0.14, 0.37)), "braid.B"),
        (-115, 62, Vector((-0.235, 0.14, 0.37)), "braid.B"),
        (135, 64, Vector((0.17, 0.2, 0.35)), "braid.B"),
        (-135, 64, Vector((-0.17, 0.2, 0.35)), "braid.B"),
        (157, 66, Vector((0.085, 0.235, 0.34)), "braid.B"),
        (-157, 66, Vector((-0.085, 0.235, 0.34)), "braid.B"),
        (176, 66, Vector((0.012, 0.245, 0.33)), "braid.B"),
        (-176, 66, Vector((-0.012, 0.245, 0.33)), "braid.B"),
    ]
    for az, el0, end, bone in specs:
        a = math.radians(az)
        side = 1.0 if az > 0 else -1.0
        # root on the centre part (front braids at the front of the part, back ones further back),
        # then a great-circle arc over the scalp down to just below the head's equator
        g = math.radians(42 + (abs(az) - 46) / (176 - 46) * 100)
        d_root = Vector((side * 0.07, -math.cos(g), math.sin(g))).normalized()
        e_end = math.radians(-8)
        d_end = Vector((math.sin(a) * math.cos(e_end), -math.cos(a) * math.cos(e_end), math.sin(e_end)))
        omega = math.acos(max(-1.0, min(1.0, d_root.dot(d_end))))
        pts = []
        for k in range(7):
            t = k / 6
            d = (d_root * math.sin((1 - t) * omega) + d_end * math.sin(t * omega)) / math.sin(omega)
            pts.append(CAP_C + Vector((d.x * CAP_R.x, d.y * CAP_R.y, d.z * CAP_R.z)) * 1.045)
        last = pts[-1]
        mid = Vector((last.x * 0.5 + end.x * 0.5, last.y * 0.5 + end.y * 0.5, last.z * 0.45 + end.z * 0.55))
        mid += Vector((math.copysign(0.012, end.x) if abs(end.x) > 0.05 else 0.0, 0.0, 0.0))
        ctrl = pts + [mid, end]
        dense = catmull(ctrl, 80)
        res, total = resample(dense, BRAID_SPACING)
        n = len(res)
        radii = []
        for i in range(n):
            t = i / (n - 1)
            base = 0.019 * (1.0 - 0.3 * t)
            if i == 0:
                base *= 0.55
            bump = 1.2 if i % 2 == 0 else 0.78
            radii.append(base * bump)
        radii[-1] *= 0.8

        def wfn(p, bone=bone):
            t = smoothstep(HEAD_C.z - 0.05, HEAD_C.z - 0.22, p.z)
            return blend("head", bone, t)

        add_part("Braid", tube_bm(res, radii, sides=5, cap0=True, twist=0.0), ["Hair"], wfn)
        braids.append(res)
        # gold cuff near the tip
        tip = res[-2]
        dirv = (res[-1] - res[-3]).normalized()
        cuff = tube_bm([tip - dirv * 0.009, tip + dirv * 0.009], [radii[-2] * 1.1] * 2, sides=5, cap0=False, cap1=False)
        add_part("BraidCuff", cuff, ["Gold"], lambda p, bone=bone: [(bone, 1.0)])
    return braids


# ---------------------------------------------------------------- body
def build_body():
    # neck
    add_part("Neck", lathe_bm([(0.05, 0.66), (0.048, 0.60), (0.052, 0.555)], seg=12, yscale=0.9),
             ["Skin"], lambda p: blend("neck", "head", smoothstep(0.62, 0.66, p.z)))
    # shirt (loose tunic with flared hem)
    prof = [(0.05, 0.605), (0.095, 0.59), (0.13, 0.565), (0.147, 0.52), (0.147, 0.45),
            (0.157, 0.37), (0.172, 0.29), (0.163, 0.272), (0.12, 0.268)]
    bm = lathe_bm(prof, seg=20, yscale=0.8)
    cut_stripes(bm)
    # V collar
    vz = 0.50
    # planes |x| = (z - vz) * k  ->  x - k z + k vz = 0
    k = 0.55
    for s in (-1, 1):
        no = Vector((1.0, 0.0, -s * k)).normalized()
        bisect_all(bm, Vector((0.0, 0.0, vz)), no)

    def face_mat(f):
        c = f.calc_center_median()
        if c.y < -0.02 and c.z > vz and abs(c.x) < (c.z - vz) * k:
            return len(STRIPES)  # skin
        return stripe_index(c)

    def shirt_w(p):
        t = smoothstep(0.40, 0.50, p.z)
        w = blend("spine", "chest", t)
        if p.z < 0.33:
            u = smoothstep(0.33, 0.28, p.z)
            w = [(b, x * (1 - u)) for b, x in w] + [("hips", u)]
        return w

    shirt_bm_copy = bm.copy()
    add_part("Shirt", bm, STRIPES + ["Skin"], shirt_w, face_mat)

    # trousers: hip block + legs
    add_part("Hips", lathe_bm([(0.12, 0.34), (0.135, 0.30), (0.125, 0.25), (0.09, 0.225)], seg=16, yscale=0.8, cap_bottom=True),
             ["Trousers"], rigid("hips"))
    for s in (-1, 1):
        x = s * LEG_X
        side = "L" if s > 0 else "R"
        pts = [Vector((x, 0, z)) for z in (0.29, 0.25, 0.21, 0.175, 0.14, 0.10, 0.07)]
        radii = [0.052, 0.05, 0.047, 0.045, 0.044, 0.046, 0.05]

        def leg_w(p, side=side):
            t = smoothstep(KNEE_Z + 0.02, KNEE_Z - 0.02, p.z)
            return blend("upper_leg." + side, "lower_leg." + side, t)

        add_part("Leg", tube_bm(pts, radii, sides=10, cap0=False, cap1=False), ["Trousers"], leg_w)
        # shoe: rounded, slightly long towards the front, flat sole
        sh = ellipsoid_bm(Vector((x * 1.05, -0.022, 0.035)), Vector((0.052, 0.078, 0.042)), u=12, v=7)
        for v in sh.verts:
            if v.co.z < 0.004:
                v.co.z = 0.004 + (v.co.z - 0.004) * 0.15
        add_part("Shoe", sh, ["Shoes"], rigid("foot." + side))
        sole = ellipsoid_bm(Vector((x * 1.05, -0.022, 0.006)), Vector((0.054, 0.08, 0.008)), u=12, v=3)
        add_part("Sole", sole, ["ShoeSole"], rigid("foot." + side))

    # arms
    for s in (-1, 1):
        side = "L" if s > 0 else "R"
        sh_p = Vector((s * SHOULDER.x, SHOULDER.y, SHOULDER.z))
        el_p = Vector((s * ELBOW.x, ELBOW.y, ELBOW.z))
        wr_p = Vector((s * WRIST.x, WRIST.y, WRIST.z))
        hd_p = Vector((s * HAND.x, HAND.y, HAND.z))
        # sleeve: puffy at the shoulder, flared at the elbow
        sl_pts = [sh_p + (sh_p - el_p).normalized() * 0.01 + Vector((-s * 0.02, 0, 0)), sh_p.lerp(el_p, 0.2), sh_p.lerp(el_p, 0.55),
                  sh_p.lerp(el_p, 0.85), el_p + (el_p - sh_p).normalized() * 0.012]
        sl_r = [0.05, 0.056, 0.054, 0.058, 0.06]
        bm = tube_bm(sl_pts, sl_r, sides=10, cap0=True, cap1=False)
        # inner rim so the open sleeve end is not see-through
        cut_stripes(bm)
        add_part("Sleeve", bm, STRIPES, rigid("upper_arm." + side), lambda f: stripe_index(f.calc_center_median()))
        cap = tube_bm([el_p + (el_p - sh_p).normalized() * 0.008, el_p + (el_p - sh_p).normalized() * 0.0081],
                      [0.056, 0.056], sides=10, cap0=True, cap1=True)
        add_part("SleeveIn", cap, ["StripeNavy"], rigid("upper_arm." + side))
        # forearm
        fa = [el_p.lerp(sh_p, 0.15), el_p, el_p.lerp(wr_p, 0.5), wr_p]
        add_part("Forearm", tube_bm(fa, [0.034, 0.034, 0.031, 0.028], sides=8, cap0=False, cap1=False), ["Skin"],
                 lambda p, side=side, ez=ELBOW.z: blend("upper_arm." + side, "lower_arm." + side, smoothstep(ez + 0.01, ez - 0.02, p.z)))
        # mitten hand + thumb
        hb = ellipsoid_bm(hd_p, Vector((0.032, 0.036, 0.042)), u=10, v=6)
        add_part("Hand", hb, ["Skin"], rigid("hand." + side))
        th = ellipsoid_bm(hd_p + Vector((-s * 0.004, -0.03, 0.012)), Vector((0.013, 0.016, 0.022)), u=6, v=4)
        add_part("Thumb", th, ["Skin"], rigid("hand." + side))
    return shirt_bm_copy


def build_necklace(shirt_bm):
    neck_bm = lathe_bm([(0.05, 0.66), (0.048, 0.60), (0.052, 0.555)], seg=12, yscale=0.9)
    bm = shirt_bm.copy()
    neck_bm.to_mesh(tmp := bpy.data.meshes.new("tmp"))
    bm.from_mesh(tmp)
    bpy.data.meshes.remove(tmp)
    bvh = bvh_of(bm)
    pts = []
    n = 24
    for i in range(n):
        th = 2 * math.pi * i / n
        f = ((1 + math.cos(th)) / 2) ** 3
        z = 0.588 - 0.082 * f
        d = Vector((math.sin(th), -math.cos(th), 0))
        o = Vector((0, 0, z)) + d * 0.5
        hit = bvh.ray_cast(o, -d)
        p = hit[0] if hit[0] is not None else Vector((0, 0, z)) + d * 0.1
        pts.append(p + d * 0.007)
    pts.append(pts[0])
    pts.insert(0, pts[-2])
    chain = tube_bm(pts[1:], [0.0045] * (len(pts) - 1), sides=4, cap0=False, cap1=False)
    add_part("Chain", chain, ["Gold"], rigid("chest"))
    # sun medallion
    front = pts[1]
    c = front + Vector((0, -0.006, -0.03))
    disc = tube_bm([c + Vector((0, 0.004, 0)), c + Vector((0, -0.004, 0))], [0.024, 0.024], sides=14)
    add_part("Medallion", disc, ["Gold"], rigid("chest"), smooth=False)
    rays = bmesh.new()
    for k in range(10):
        a = 2 * math.pi * k / 10
        dv = Vector((math.cos(a), 0, math.sin(a)))
        tv = Vector((-math.sin(a), 0, math.cos(a)))
        base = c + dv * 0.022 + Vector((0, -0.001, 0))
        v0 = rays.verts.new(base + tv * 0.008)
        v1 = rays.verts.new(base - tv * 0.008)
        v2 = rays.verts.new(c + dv * 0.04 + Vector((0, -0.001, 0)))
        v3 = rays.verts.new(base + Vector((0, 0.004, 0)))
        rays.faces.new((v0, v1, v2))
        rays.faces.new((v1, v0, v3))
        rays.faces.new((v0, v2, v3))
        rays.faces.new((v2, v1, v3))
    rays.normal_update()
    add_part("SunRays", rays, ["Gold"], rigid("chest"), smooth=False)
    # loop linking chain and medallion
    ring = tube_bm([front + Vector((0, 0, 0.002)), c + Vector((0, 0, 0.022))], [0.004, 0.004], sides=4)
    add_part("Bail", ring, ["Gold"], rigid("chest"))


# ---------------------------------------------------------------- armature
BONES = {}


def build_armature():
    arm_data = bpy.data.armatures.new("HeroineRig")
    arm = bpy.data.objects.new("Heroine", arm_data)
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
    bone("spine", (0, 0, 0.40), (0, 0, 0.48), "hips")
    bone("chest", (0, 0, 0.48), (0, 0, 0.58), "spine")
    bone("neck", (0, 0, 0.58), (0, 0, 0.64), "chest")
    bone("head", (0, 0, 0.64), (0, 0, 1.02), "neck")
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
        bone("braid." + side, (s * 0.25, -0.03, HEAD_C.z - 0.08), (s * 0.25, -0.03, 0.42), "head")
    bone("braid.B", (0, 0.22, HEAD_C.z - 0.08), (0, 0.22, 0.42), "head", roll_vec=Vector((0, 1, 0)))
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
    # smooth easing everywhere
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


def build_actions(arm):
    # Idle: 2 s breathing / bob loop
    def idle(t):
        s = math.sin(2 * math.pi * t)
        c = math.cos(2 * math.pi * t)
        return {
            "hips": {"loc": (0, 0.006 * s, 0)},
            "spine": {"rot": (1.5 * s, 0, 0)},
            "chest": {"rot": (-1.5 * s, 0, 0)},
            "head": {"rot": (-2.0 * s, 0, 3.0 * c)},
            "upper_arm.L": {"rot": (2 * s, 0, -4 - 2 * s)},
            "upper_arm.R": {"rot": (2 * s, 0, 4 + 2 * s)},
            "lower_arm.L": {"rot": (6, 0, 0)},
            "lower_arm.R": {"rot": (6, 0, 0)},
            "braid.L": {"rot": (2 * c, 0, 0)},
            "braid.R": {"rot": (2 * c, 0, 0)},
            "braid.B": {"rot": (-2 * c, 0, 0)},
        }
    n = 120
    make_action(arm, "Idle", [(f, idle(f / n)) for f in range(0, n + 1, 15)])

    # Walk: bouncy chibi walk, 0.6 s loop
    def walk(t):
        a = 2 * math.pi * t
        s, c = math.sin(a), math.cos(a)
        bounce = abs(math.sin(a))
        lift_l = max(0.0, -s)  # left foot lifts while swinging forward
        lift_r = max(0.0, s)
        return {
            "hips": {"loc": (0, 0.025 * bounce - 0.01, 0), "rot": (0, 8 * s, 3 * c)},
            "spine": {"rot": (4, -4 * s, 0)},
            "chest": {"rot": (0, -6 * s, 0)},
            "head": {"rot": (-4 + 3 * bounce, 4 * s, -3 * c)},
            "upper_leg.L": {"rot": (-28 * s + 5, 0, 0)},
            "upper_leg.R": {"rot": (28 * s + 5, 0, 0)},
            "lower_leg.L": {"rot": (-45 * lift_l, 0, 0)},
            "lower_leg.R": {"rot": (-45 * lift_r, 0, 0)},
            "foot.L": {"rot": (20 * lift_l - 10 * max(0, s), 0, 0)},
            "foot.R": {"rot": (20 * lift_r - 10 * max(0, -s), 0, 0)},
            "upper_arm.L": {"rot": (32 * s, 0, -8)},
            "upper_arm.R": {"rot": (-32 * s, 0, 8)},
            "lower_arm.L": {"rot": (18 + 10 * max(0, s), 0, 0)},
            "lower_arm.R": {"rot": (18 + 10 * max(0, -s), 0, 0)},
            "braid.L": {"rot": (-6 + 6 * math.cos(2 * a), 0, 4 * s)},
            "braid.R": {"rot": (-6 + 6 * math.cos(2 * a), 0, 4 * s)},
            "braid.B": {"rot": (8 - 6 * math.cos(2 * a), 0, 4 * s)},
        }
    n = 36
    make_action(arm, "Walk", [(f, walk(f / n)) for f in range(0, n + 1, 3)])

    # Swing: right-arm net swing, 0.45 s one-shot (27 frames @ 60 fps).
    # Readable from the iso camera: head stays up, torso only twists a little, and the
    # arm sweeps the net at shoulder height from her right-back (wind-up) to front-right
    # (strike) to front-left (follow-through). The hoop stays ~0.7 m up and out of the
    # head's silhouette, plane kept near horizontal (the Net prop in heroine_visual.tscn
    # is rolled to match), so it reads as a ring whether she faces the camera or not.
    # upper_arm X raises the arm forward, then Y yaws it (+ = to her right).
    # Arm/hand keys were solved numerically for those hoop targets, then rounded.
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
        "braid.L": {"rot": (0, 0, -6)},
        "braid.R": {"rot": (0, 0, -6)},
        "braid.B": {"rot": (0, 0, 6)},
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
        "braid.L": {"rot": (-6, 0, 8)},
        "braid.R": {"rot": (-6, 0, 8)},
        "braid.B": {"rot": (5, 0, -6)},
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
        "braid.L": {"rot": (6, 0, 6)},
        "braid.R": {"rot": (6, 0, 6)},
        "braid.B": {"rot": (-6, 0, -4)},
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
        "braid.L": {"rot": (14, 0, 0)},
        "braid.R": {"rot": (14, 0, 0)},
        "braid.B": {"rot": (-10, 0, 0)},
    }
    make_action(arm, "Hurt", [(0, rest), (5, flinch), (12, flinch), (21, rest)])


# ---------------------------------------------------------------- main
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    build_materials()
    head_bvh = build_head()
    build_face(head_bvh)
    build_glasses(head_bvh)
    build_hair()
    shirt = build_body()
    build_necklace(shirt)

    # join all parts into one skinned mesh
    bpy.ops.object.select_all(action="DESELECT")
    for ob in PARTS:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "HeroineMesh"
    body.data.name = "HeroineMesh"
    # weld nothing (parts stay separate shells); recompute normals outward for closed shells
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("TRIANGLES", tris)
    print("PER PART", sorted(TRI_COUNT.items(), key=lambda kv: -kv[1]))

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
        export_yup=True,
        export_apply=False,
        export_force_sampling=True,
        export_materials="EXPORT",
    )
    print("WROTE", OUT)


main()

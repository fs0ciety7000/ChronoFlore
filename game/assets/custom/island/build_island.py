"""Build ChronoFlore's hand-made pastel diorama island and its decor (Blender bpy).

Usage (Python with the `bpy` module, Blender 4.2+), from the repository root:
    python game/assets/custom/island/build_island.py

Writes, next to this file:
    island.glb            floating island: meadow top, lighter rim band, path, pond, tufts,
                          flowers, layered soil cut edges tapering to a rocky underside
    tree_blossom.glb      round pink blossom tree (~4.2 m)
    tree_peach.glb        round peach blossom tree (~3.6 m)
    bush.glb              soft round green bush (~1.2 m)
    giant_flower.glb      dreamlike lavender giant flower (~3.4 m)
    giant_mushroom.glb    dreamlike pink giant mushroom (~2.6 m)
and game/data/island_shape.tres (walkable outline + pond obstacle) and
game/scenes/island/island.tscn (island, decor placement and colliders).

Conventions: coordinates below are Godot's (x right, y up, z towards the camera side), metres,
origin on the ground; colours are named materials with base colours (no vertex colours).
The walkable meadow is flat at y = 0.
"""
import math
import os
import random

import bpy  # noqa: I001 - bpy must be imported before bmesh
import bmesh

HERE = os.path.dirname(os.path.abspath(__file__))
SHAPE_PATH = os.path.normpath(os.path.join(HERE, "..", "..", "..", "data", "island_shape.tres"))
SCENE_PATH = os.path.normpath(os.path.join(HERE, "..", "..", "..", "scenes", "island", "island.tscn"))

# --- Island layout (shared with island.tscn and island_shape.tres) ---------------------------
ISLAND_RADIUS = 21.0
SEGMENTS = 72
RIM_BAND = 1.4          # width of the lighter rim band
WALK_INSET = 3.2        # walkable outline = island edge minus this
OUTLINE_POINTS = 20
POND_CENTER = (7.0, -6.0)
POND_RADIUS = 3.0
FOAM_WIDTH = 0.4
POND_OBSTACLE_RADIUS = POND_RADIUS + FOAM_WIDTH
PATH_POINTS = [(-14.5, 10.5), (-10.0, 5.0), (-4.0, 4.5), (-1.0, 0.5), (1.0, -4.5), (4.0, -6.2)]
PATH_WIDTH = 1.3

PALETTE = {
    "meadow": "bce3a6",
    "rim": "d3eec0",
    "path": "f4e6c8",
    "soil_top": "c29a7a",
    "soil_mid": "b08868",
    "soil_low": "9d7a64",
    "rock": "8f7570",
    "rock_tip": "84717c",
    "pond_bed": "72d3d6",
    "caustic": "b4f0ec",
    "water": "9ff0ea",
    "foam": "fdfcf6",
    "tuft": "a9d79a",
    "tuft_light": "bde4ab",
    "flower_pink": "ffc2d1",
    "flower_peach": "ffd6b8",
    "flower_lilac": "dccbf6",
    "flower_yellow": "fbe6a0",
    "flower_white": "fffaf2",
    "flower_heart": "f9d77e",
    "stem": "a6d49a",
    "bark": "9c7864",
    "blossom": "f7b9c9",
    "blossom_light": "fcd3dd",
    "blossom_deep": "efa2b8",
    "peach": "fcceb0",
    "peach_light": "ffe1cc",
    "bush": "add9a0",
    "bush_light": "c3e6b2",
    "giant_petal": "d8c8f5",
    "giant_petal_light": "e8dcfb",
    "mushroom_cap": "f8b4c2",
    "mushroom_dot": "fff5f0",
    "mushroom_stem": "fbefe3",
}


def edge_radius(theta):
    """Organic island edge radius at angle theta (radians, Godot XZ plane)."""
    return ISLAND_RADIUS * (1.0 + 0.055 * math.sin(3 * theta + 0.5) + 0.035 * math.sin(5 * theta + 1.3)
                            + 0.03 * math.sin(2 * theta + 2.1))


# --- bpy helpers -----------------------------------------------------------------------------
_materials = {}


def mat(name, alpha=1.0):
    key = (name, alpha)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new(name if alpha >= 1.0 else name + "_translucent")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    h = PALETTE[name]
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    m.use_backface_culling = True  # single-sided: double-sided materials render wrong in Compatibility
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.surface_render_method = "BLENDED"
    _materials[key] = m
    return m


def g2b(x, y, z):
    """Godot (x, y up, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


class Builder:
    """Accumulates faces with per-face material slots into one mesh object."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.slots = []

    def slot(self, material):
        if material not in self.slots:
            self.slots.append(material)
        return self.slots.index(material)

    def vert(self, x, y, z):
        return self.bm.verts.new(g2b(x, y, z))

    def face(self, verts, material, smooth=False):
        f = self.bm.faces.new(verts)
        f.material_index = self.slot(material)
        f.smooth = smooth
        return f

    def disk(self, cx, cz, y, radius, material, segments=32, inner=0.0, sx=1.0, sz=1.0):
        """Flat (ring) disk facing up."""
        outer = [self.vert(cx + math.cos(a) * radius * sx, y, cz + math.sin(a) * radius * sz)
                 for a in (2 * math.pi * i / segments for i in range(segments))]
        if inner <= 0.0:
            c = self.vert(cx, y, cz)
            for i in range(segments):
                self.face([c, outer[(i + 1) % segments], outer[i]], material)
        else:
            inn = [self.vert(cx + math.cos(a) * inner * sx, y, cz + math.sin(a) * inner * sz)
                   for a in (2 * math.pi * i / segments for i in range(segments))]
            for i in range(segments):
                j = (i + 1) % segments
                self.face([inn[i], inn[j], outer[j], outer[i]], material)

    def ico(self, cx, cy, cz, radius, material, sy=1.0, subdiv=2, smooth=True):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius)
        idx = self.slot(material)
        for v in res["verts"]:
            gx, gz_neg, gy = v.co.x, v.co.y, v.co.z
            v.co = g2b(cx + gx, cy + gy * sy, cz - gz_neg)
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = idx
            f.smooth = smooth

    def cone(self, x0, y0, z0, x1, y1, z1, r0, r1, material, segments=8, smooth=True, cap=True):
        """Truncated cone between two Godot points."""
        ax = (x1 - x0, y1 - y0, z1 - z0)
        length = math.sqrt(sum(a * a for a in ax))
        d = tuple(a / length for a in ax)
        ref = (1.0, 0.0, 0.0) if abs(d[1]) > 0.9 else (0.0, 1.0, 0.0)
        u = (d[1] * ref[2] - d[2] * ref[1], d[2] * ref[0] - d[0] * ref[2], d[0] * ref[1] - d[1] * ref[0])
        n = math.sqrt(sum(a * a for a in u))
        u = tuple(a / n for a in u)
        w = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
        rings = []
        for (px, py, pz), r in (((x0, y0, z0), r0), ((x1, y1, z1), r1)):
            ring = []
            for i in range(segments):
                a = 2 * math.pi * i / segments
                ring.append(self.vert(px + (u[0] * math.cos(a) + w[0] * math.sin(a)) * r,
                                      py + (u[1] * math.cos(a) + w[1] * math.sin(a)) * r,
                                      pz + (u[2] * math.cos(a) + w[2] * math.sin(a)) * r))
            rings.append(ring)
        for i in range(segments):
            j = (i + 1) % segments
            self.face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], material, smooth)
        if cap and r1 > 0.001:
            tip = self.vert(x1, y1, z1)
            for i in range(segments):
                self.face([rings[1][i], rings[1][(i + 1) % segments], tip], material, smooth)

    def finish(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.slots:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()


def export(filename):
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, filename), export_format="GLB",
                              export_apply=True, export_yup=True)


# --- Island ----------------------------------------------------------------------------------
def build_top(rng):
    top = Builder("IslandTop")
    meadow, rim = mat("meadow"), mat("rim")
    n = SEGMENTS
    thetas = [2 * math.pi * i / n for i in range(n)]
    # Ring fractions of (edge - RIM_BAND) for the meadow, then the rim band and its soft lip.
    center = top.vert(0.0, 0.0, 0.0)
    prev = None
    for frac in (0.35, 0.7, 1.0):
        ring = [top.vert(math.cos(t) * (edge_radius(t) - RIM_BAND) * frac, 0.0,
                         math.sin(t) * (edge_radius(t) - RIM_BAND) * frac) for t in thetas]
        for i in range(n):
            j = (i + 1) % n
            if prev is None:
                top.face([center, ring[j], ring[i]], meadow)
            else:
                top.face([prev[i], prev[j], ring[j], ring[i]], meadow)
        prev = ring
    for inset, y in ((0.35, -0.03), (0.0, -0.22)):
        ring = [top.vert(math.cos(t) * (edge_radius(t) - inset), y, math.sin(t) * (edge_radius(t) - inset))
                for t in thetas]
        for i in range(n):
            j = (i + 1) % n
            top.face([prev[i], prev[j], ring[j], ring[i]], rim, smooth=y < -0.1)
        prev = ring
    top.finish()


def build_sides(rng):
    sides = Builder("IslandSides")
    n = SEGMENTS
    thetas = [2 * math.pi * i / n for i in range(n)]
    # (radius scale, y, jitter, material of the band BELOW this ring)
    rings_def = [
        (1.0, -0.22, 0.0, "soil_top"),
        (0.998, -2.3, 0.01, "soil_mid"),
        (0.985, -4.3, 0.015, "soil_low"),
        (0.95, -6.0, 0.03, "rock"),
        (0.78, -8.0, 0.05, "rock"),
        (0.5, -10.2, 0.06, "rock_tip"),
        (0.22, -12.0, 0.06, "rock_tip"),
    ]
    phase = [rng.uniform(0, 2 * math.pi) for _ in rings_def]
    rings = []
    for k, (scale, y, jit, _m) in enumerate(rings_def):
        ring = []
        for t in thetas:
            r = edge_radius(t) * scale * (1.0 + jit * math.sin(7 * t + phase[k]) + rng.uniform(-jit, jit) * 0.5)
            yy = y + (0.22 * math.sin(4 * t + phase[k]) if 0 < k < 4 else 0.0)
            ring.append(sides.vert(math.cos(t) * r, yy, math.sin(t) * r))
        rings.append(ring)
    for k in range(len(rings) - 1):
        material = mat(rings_def[k][3])
        for i in range(n):
            j = (i + 1) % n
            sides.face([rings[k][i], rings[k + 1][i], rings[k + 1][j], rings[k][j]], material, smooth=True)
    tip = sides.vert(0.4, -13.0, -0.3)
    for i in range(n):
        sides.face([rings[-1][i], tip, rings[-1][(i + 1) % n]], mat("rock_tip"), smooth=True)
    sides.finish()


def _path_samples(step=0.4):
    pts = PATH_POINTS
    out = []
    for k in range(len(pts) - 1):
        p0 = pts[max(k - 1, 0)]
        p1, p2 = pts[k], pts[k + 1]
        p3 = pts[min(k + 2, len(pts) - 1)]
        seg_len = math.dist(p1, p2)
        steps = max(2, int(seg_len / step))
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                                    + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(2)))
    out.append(pts[-1])
    return out


def path_distance(x, z):
    return min(math.dist((x, z), p) for p in _path_samples(0.8))


def build_path():
    path = Builder("Path")
    m = mat("path")
    samples = _path_samples()
    left, right = [], []
    for k, p in enumerate(samples):
        a = samples[max(k - 1, 0)]
        b = samples[min(k + 1, len(samples) - 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / ln, dx / ln
        taper = min(1.0, 0.55 + 0.45 * min(k, len(samples) - 1 - k) / 3.0)
        hw = PATH_WIDTH * 0.5 * taper
        left.append(path.vert(p[0] + nx * hw, 0.012, p[1] + nz * hw))
        right.append(path.vert(p[0] - nx * hw, 0.012, p[1] - nz * hw))
    for k in range(len(samples) - 1):
        path.face([left[k], left[k + 1], right[k + 1], right[k]], m)
    for p, r in ((samples[0], PATH_WIDTH * 0.28), (samples[-1], PATH_WIDTH * 0.28)):
        path.disk(p[0], p[1], 0.011, r, m, segments=12)
    path.finish()


def build_pond(rng):
    pond = Builder("Pond")
    cx, cz = POND_CENTER
    pond.disk(cx, cz, 0.006, POND_RADIUS, mat("pond_bed"), segments=40)
    for _ in range(7):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.3, POND_RADIUS - 0.8)
        pond.disk(cx + math.cos(a) * d, cz + math.sin(a) * d, 0.012, rng.uniform(0.18, 0.4), mat("caustic"),
                  segments=10, inner=0.0, sx=rng.uniform(1.3, 2.2), sz=0.5)
    pond.disk(cx, cz, 0.03, POND_RADIUS, mat("water", 0.55), segments=40)
    pond.disk(cx, cz, 0.04, POND_RADIUS + FOAM_WIDTH, mat("foam"), segments=40, inner=POND_RADIUS - 0.05)
    pond.finish()


def build_meadow_dressing(rng):
    dress = Builder("Dressing")
    tuft, tuft_l, stem = mat("tuft"), mat("tuft_light"), mat("stem")
    heads = ["flower_pink", "flower_peach", "flower_lilac", "flower_yellow", "flower_white"]

    def free_spot(margin):
        for _ in range(200):
            t = rng.uniform(0, 2 * math.pi)
            r = math.sqrt(rng.uniform(0.0, 1.0)) * (edge_radius(t) - RIM_BAND - 0.6)
            x, z = math.cos(t) * r, math.sin(t) * r
            if math.dist((x, z), POND_CENTER) < POND_OBSTACLE_RADIUS + margin:
                continue
            if path_distance(x, z) < PATH_WIDTH * 0.5 + margin:
                continue
            if math.hypot(x, z) < 2.5:
                continue  # keep the heroine's start clean
            return x, z
        return None

    for _ in range(140):
        spot = free_spot(0.3)
        if spot is None:
            continue
        x, z = spot
        m = tuft if rng.random() < 0.6 else tuft_l
        for b in range(3):
            a = rng.uniform(0, 2 * math.pi)
            h = rng.uniform(0.18, 0.32)
            lean = rng.uniform(0.04, 0.1)
            dress.cone(x + math.cos(a) * 0.06, 0.0, z + math.sin(a) * 0.06,
                       x + math.cos(a) * lean, h, z + math.sin(a) * lean, 0.045, 0.0, m, segments=4)
    for _ in range(80):
        spot = free_spot(0.3)
        if spot is None:
            continue
        x, z = spot
        h = rng.uniform(0.18, 0.3)
        dress.cone(x, 0.0, z, x, h, z, 0.015, 0.012, stem, segments=4, cap=False)
        head = rng.choice(heads)
        for p in range(5):
            a = 2 * math.pi * p / 5
            dress.ico(x + math.cos(a) * 0.05, h + 0.01, z + math.sin(a) * 0.05, 0.045, mat(head), sy=0.5, subdiv=1)
        dress.ico(x, h + 0.025, z, 0.03, mat("flower_heart"), sy=0.7, subdiv=1)
    dress.finish()


def build_island():
    reset()
    rng = random.Random(7)
    build_top(rng)
    build_sides(rng)
    build_path()
    build_pond(rng)
    build_meadow_dressing(rng)
    export("island.glb")


# --- Decor -----------------------------------------------------------------------------------
def build_tree(filename, canopy, canopy_light, height, rng):
    reset()
    b = Builder("Tree")
    bark = mat("bark")
    trunk_top = height * 0.55
    b.cone(0, 0, 0, 0.08, trunk_top, 0.04, 0.24, 0.14, bark, segments=8)
    b.cone(0.05, trunk_top * 0.7, 0.02, 0.6, trunk_top + 0.35, -0.2, 0.08, 0.05, bark, segments=6)
    b.cone(0.0, trunk_top * 0.75, 0.0, -0.55, trunk_top + 0.3, 0.25, 0.08, 0.05, bark, segments=6)
    cy = trunk_top + height * 0.2
    blobs = [(0.0, cy + 0.25, 0.0, height * 0.3, canopy),
             (0.7, cy - 0.05, -0.25, height * 0.22, canopy_light),
             (-0.65, cy - 0.1, 0.3, height * 0.23, canopy),
             (0.15, cy - 0.15, 0.7, height * 0.2, canopy_light),
             (-0.2, cy + 0.05, -0.65, height * 0.21, canopy_light)]
    for x, y, z, r, m in blobs:
        b.ico(x, y, z, r, mat(m), sy=0.88, subdiv=2)
    b.finish()
    export(filename)


def build_bush(rng):
    reset()
    b = Builder("Bush")
    for x, z, r, m in ((0.0, 0.0, 0.62, "bush"), (0.55, 0.15, 0.45, "bush_light"),
                       (-0.5, 0.2, 0.48, "bush_light"), (0.1, -0.45, 0.44, "bush")):
        b.ico(x, r * 0.75, z, r, mat(m), sy=0.85, subdiv=2)
    b.finish()
    export("bush.glb")


def build_giant_flower():
    reset()
    b = Builder("GiantFlower")
    stem, petal, petal_l, heart = mat("stem"), mat("giant_petal"), mat("giant_petal_light"), mat("flower_heart")
    top = (0.35, 3.2, 0.1)
    b.cone(0, 0, 0, top[0], top[1], top[2], 0.09, 0.07, stem, segments=8, cap=False)
    for side, h in ((1, 0.7), (-1, 1.3)):
        b.ico(side * 0.45, h, 0.0, 0.32, stem, sy=0.25, subdiv=2)
    # Head tilted towards the camera side (+x +z).
    tilt = 0.35
    nx, ny, nz = math.sin(tilt) * 0.7, math.cos(tilt), math.sin(tilt) * 0.7
    for p in range(10):
        a = 2 * math.pi * p / 10
        ox, oz = math.cos(a) * 0.55, math.sin(a) * 0.55
        b.ico(top[0] + ox, top[1] - (ox * nx + oz * nz) * 0.6, top[2] + oz, 0.3,
              petal if p % 2 == 0 else petal_l, sy=0.35, subdiv=2)
    b.ico(top[0], top[1] + 0.08, top[2], 0.33, heart, sy=0.55, subdiv=2)
    b.finish()
    export("giant_flower.glb")


def build_giant_mushroom(rng):
    reset()
    b = Builder("GiantMushroom")
    b.cone(0, 0, 0, 0.1, 1.9, 0.0, 0.38, 0.3, mat("mushroom_stem"), segments=12, cap=False)
    b.ico(0.1, 1.95, 0.0, 1.25, mat("mushroom_cap"), sy=0.55, subdiv=3)
    for k in range(9):
        a = rng.uniform(0, 2 * math.pi)
        e = rng.uniform(0.25, 1.0)
        r = 1.0 * math.sin(e * 1.2)
        b.ico(0.1 + math.cos(a) * r, 1.95 + 0.68 * math.cos(e * 1.2) - 0.02, math.sin(a) * r,
              rng.uniform(0.11, 0.18), mat("mushroom_dot"), sy=0.45, subdiv=1)
    b.finish()
    export("giant_mushroom.glb")


# --- Walkable shape --------------------------------------------------------------------------
def write_shape():
    pts = []
    for i in range(OUTLINE_POINTS):
        t = 2 * math.pi * i / OUTLINE_POINTS
        r = edge_radius(t) - WALK_INSET
        pts.append("%g, %g" % (round(math.cos(t) * r, 2), round(math.sin(t) * r, 2)))
    text = (
        '[gd_resource type="Resource" script_class="IslandShape" format=3]\n\n'
        '[ext_resource type="Script" path="res://scripts/core/island_shape.gd" id="1_shape"]\n\n'
        '[resource]\n'
        'script = ExtResource("1_shape")\n'
        'outline = PackedVector2Array(%s)\n'
        'obstacles = PackedVector3Array(%g, %g, %g)\n'
    ) % (", ".join(pts), POND_CENTER[0], POND_CENTER[1], POND_OBSTACLE_RADIUS)
    with open(SHAPE_PATH, "w") as f:
        f.write(text)


# --- Scene -----------------------------------------------------------------------------------
# kind -> (glb, collider radius, collider height)
DECOR_KINDS = {
    "tree_blossom": ("tree_blossom.glb", 0.3, 3.0),
    "tree_peach": ("tree_peach.glb", 0.3, 2.6),
    "bush": ("bush.glb", 0.85, 1.2),
    "giant_flower": ("giant_flower.glb", 0.25, 3.2),
    "giant_mushroom": ("giant_mushroom.glb", 0.45, 2.0),
}
# (name, kind, angle in degrees on the XZ plane, inset from the island edge, yaw in degrees).
# The iso camera looks towards -x -z: tall decor sits on the far side (angles ~180-300),
# only low bushes on the near side (angles ~20-120).
DECOR = [
    ("BlossomWest", "tree_blossom", 192, 1.9, 10),
    ("GiantFlowerNorthWest", "giant_flower", 214, 1.7, 0),
    ("PeachNorthWest", "tree_peach", 234, 2.0, 40),
    ("BlossomNorth", "tree_blossom", 256, 2.0, -25),
    ("MushroomNorth", "giant_mushroom", 280, 1.9, 0),
    ("PeachNorthEast", "tree_peach", 304, 2.0, 70),
    ("BushNorthEast", "bush", 328, 1.7, 15),
    ("BlossomEast", "tree_blossom", 352, 2.0, 120),
    ("BushEast", "bush", 18, 1.6, 60),
    ("BushSouthEast", "bush", 58, 1.6, -30),
    ("BushSouth", "bush", 96, 1.6, 100),
    ("MushroomSouthWest", "giant_mushroom", 132, 1.8, 40),
    ("PeachWest", "tree_peach", 158, 2.0, -60),
    ("BushWest", "bush", 176, 1.6, 20),
]


def _fmt(v):
    t = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if t in ("-0", "") else t


def write_scene():
    kinds = list(DECOR_KINDS)
    ext = ['[ext_resource type="Script" path="res://scenes/island/island.gd" id="1_island"]',
           '[ext_resource type="Resource" path="res://data/island_shape.tres" id="2_shape"]',
           '[ext_resource type="PackedScene" path="res://assets/custom/island/island.glb" id="3_island"]']
    for k, kind in enumerate(kinds):
        ext.append('[ext_resource type="PackedScene" path="res://assets/custom/island/%s" id="%d_%s"]'
                   % (DECOR_KINDS[kind][0], 4 + k, kind))
    subs = ['[sub_resource type="BoxShape3D" id="Box_ground"]\nsize = Vector3(46, 0.5, 46)\n',
            '[sub_resource type="CylinderShape3D" id="Cylinder_pond"]\nheight = 1.0\nradius = %s\n' % _fmt(POND_RADIUS)]
    for kind in kinds:
        _glb, r, h = DECOR_KINDS[kind]
        subs.append('[sub_resource type="CylinderShape3D" id="Cylinder_%s"]\nheight = %s\nradius = %s\n'
                    % (kind, _fmt(h), _fmt(r)))
    nodes = ['[node name="Island" type="Node3D" groups=["island"]]\nscript = ExtResource("1_island")\n'
             'shape = ExtResource("2_shape")\n',
             '[node name="Model" parent="." instance=ExtResource("3_island")]\n',
             '[node name="Ground" type="StaticBody3D" parent="."]\n',
             '[node name="CollisionShape3D" type="CollisionShape3D" parent="Ground"]\n'
             'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.25, 0)\nshape = SubResource("Box_ground")\n',
             '[node name="Pond" type="StaticBody3D" parent="."]\n'
             'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0, %s)\n' % (_fmt(POND_CENTER[0]), _fmt(POND_CENTER[1])),
             '[node name="CollisionShape3D" type="CollisionShape3D" parent="Pond"]\n'
             'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0)\nshape = SubResource("Cylinder_pond")\n',
             '[node name="Decor" type="Node3D" parent="."]\n']
    for name, kind, deg, inset, yaw in DECOR:
        t = math.radians(deg)
        r = edge_radius(t) - inset
        x, z = math.cos(t) * r, math.sin(t) * r
        c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        _glb, _r, h = DECOR_KINDS[kind]
        nodes.append('[node name="%s" type="StaticBody3D" parent="Decor"]\n'
                     'transform = Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, 0, %s)\n'
                     % (name, _fmt(c), _fmt(-s_), _fmt(s_), _fmt(c), _fmt(x), _fmt(z)))
        nodes.append('[node name="Model" parent="Decor/%s" instance=ExtResource("%d_%s")]\n'
                     % (name, 4 + kinds.index(kind), kind))
        nodes.append('[node name="CollisionShape3D" type="CollisionShape3D" parent="Decor/%s"]\n'
                     'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)\nshape = SubResource("Cylinder_%s")\n'
                     % (name, _fmt(h / 2), kind))
    text = "[gd_scene load_steps=%d format=3]\n\n" % (len(ext) + len(subs) + 1)
    text += "\n".join(ext) + "\n\n" + "\n".join(subs) + "\n" + "\n".join(nodes)
    with open(SCENE_PATH, "w") as f:
        f.write(text)


def main():
    rng = random.Random(11)
    build_island()
    build_tree("tree_blossom.glb", "blossom", "blossom_light", 4.2, rng)
    build_tree("tree_peach.glb", "peach", "peach_light", 3.6, rng)
    build_bush(rng)
    build_giant_flower()
    build_giant_mushroom(rng)
    write_shape()
    write_scene()
    print("island written to", HERE)


if __name__ == "__main__":
    main()

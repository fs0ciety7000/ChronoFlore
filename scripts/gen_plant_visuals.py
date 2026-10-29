"""Generate the pastel placeholder visuals of the plant species (primitive meshes, .tscn).

Usage: python3 scripts/gen_plant_visuals.py game/scenes/plants/visuals
Front of every visual is +Z (Plant turns its Visual to face its motion).
"""
import math
import sys

OUT = sys.argv[1]

def mat_mul(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def rot_x(d):
    c, s = math.cos(math.radians(d)), math.sin(math.radians(d)); return [[1,0,0],[0,c,-s],[0,s,c]]
def rot_y(d):
    c, s = math.cos(math.radians(d)), math.sin(math.radians(d)); return [[c,0,s],[0,1,0],[-s,0,c]]
def rot_z(d):
    c, s = math.cos(math.radians(d)), math.sin(math.radians(d)); return [[c,-s,0],[s,c,0],[0,0,1]]
def euler(x, y, z):  # Godot YXZ
    return mat_mul(mat_mul(rot_y(y), rot_x(x)), rot_z(z))
def scale(m, s):
    return [[m[i][j]*s[j] for j in range(3)] for i in range(3)]
def tr(m, o):
    cols = [m[r][c] for c in range(3) for r in range(3)]
    return "Transform3D(%s)" % ", ".join(("%.5g" % v) for v in cols + list(o))

def hexcol(h):
    h = h.lstrip('#'); r, g, b = (int(h[i:i+2], 16)/255 for i in (0, 2, 4))
    return "Color(%.4g, %.4g, %.4g, 1)" % (r, g, b)

def write(name, root, parts):
    mats = {}
    subs = []
    nodes = []
    for i, p in enumerate(parts):
        col = p["color"]
        if col not in mats:
            mid = "Mat_%d" % len(mats)
            mats[col] = mid
            subs.append('[sub_resource type="StandardMaterial3D" id="%s"]\nalbedo_color = %s\nroughness = 0.85\n' % (mid, hexcol(col)))
        mesh_id = "Mesh_%d" % i
        props = "".join("%s = %s\n" % kv for kv in p["mesh"][1].items())
        subs.append('[sub_resource type="%s" id="%s"]\nmaterial = SubResource("%s")\n%s' % (p["mesh"][0], mesh_id, mats[col], props))
        m = p.get("basis") or euler(*p.get("rot", (0, 0, 0)))
        m = scale(m, p.get("scale", (1, 1, 1)))
        nodes.append('[node name="%s" type="MeshInstance3D" parent="."]\ntransform = %s\nmesh = SubResource("%s")\n' % (p["name"], tr(m, p["pos"]), mesh_id))
    txt = '[gd_scene load_steps=%d format=3]\n\n' % (len(subs) + 1)
    txt += "\n".join(subs) + '\n[node name="%s" type="Node3D"]\n\n' % root + "\n".join(nodes)
    open("%s/%s.tscn" % (OUT, name), "w").write(txt)

def sphere(r, h=None, hemi=False):
    d = {"radius": r, "height": h if h else 2*r, "radial_segments": 16, "rings": 8}
    if hemi: d["is_hemisphere"] = "true"
    return ("SphereMesh", d)
def cyl(top, bottom, h):
    return ("CylinderMesh", {"top_radius": top, "bottom_radius": bottom, "height": h, "radial_segments": 10, "rings": 1})
def y_to(d):
    # Basis whose Y axis points along unit d.
    x, y, z = d
    up = (0, 1, 0) if abs(y) < 0.99 else (1, 0, 0)
    ax = (up[1]*z - up[2]*y, up[2]*x - up[0]*z, up[0]*y - up[1]*x)
    n = math.sqrt(sum(a*a for a in ax)); ax = tuple(a/n for a in ax)
    az = (ax[1]*y - ax[2]*x, ax[2]*x - ax[0]*z, ax[0]*y - ax[1]*x)
    az = (ax[1]*z - ax[2]*y, ax[2]*x - ax[0]*z, ax[0]*y - ax[1]*x)
    return [[ax[0], x, az[0]], [ax[1], y, az[1]], [ax[2], z, az[2]]]

def eye(name, x, y, z, r=0.032, color="#3d3346"):
    return {"name": name, "mesh": sphere(r), "color": color, "pos": (x, y, z), "scale": (1, 1.25, 0.6)}


# Rêvette: soft yellow flower head with a peach petal ring on a leafy stem (~0.8 m).
HEAD_Y = 0.6
parts = [
    {"name": "Stem", "mesh": cyl(0.04, 0.055, 0.5), "color": "#b8e3bf", "pos": (0, 0.25, 0)},
    {"name": "LeafL", "mesh": sphere(0.12), "color": "#c6ecc9", "pos": (-0.15, 0.16, 0), "rot": (0, 0, 28), "scale": (1.7, 0.32, 0.9)},
    {"name": "LeafR", "mesh": sphere(0.12), "color": "#c6ecc9", "pos": (0.15, 0.24, 0), "rot": (0, 0, -28), "scale": (1.7, 0.32, 0.9)},
    {"name": "Head", "mesh": sphere(0.17), "color": "#fff0b8", "pos": (0, HEAD_Y, 0.02)},
]
for k in range(8):
    a = k * 45
    parts.append({"name": "Petal%d" % k, "mesh": sphere(0.1), "color": "#ffd2b8" if k % 2 == 0 else "#ffe0c4",
                  "pos": (0.2 * math.cos(math.radians(a)), HEAD_Y + 0.2 * math.sin(math.radians(a)), -0.03),
                  "rot": (0, 0, a), "scale": (1.4, 0.75, 0.38)})
parts += [eye("EyeL", -0.06, HEAD_Y + 0.02, 0.175), eye("EyeR", 0.06, HEAD_Y + 0.02, 0.175),
          {"name": "Blush", "mesh": sphere(0.03), "color": "#ffb3c1", "pos": (0.0, HEAD_Y - 0.05, 0.18), "scale": (2.6, 0.6, 0.4)}]
write("revette", "Revette", parts)

# Nostalgerbe: lavender-blue bulb under a tall fan of drooping blades (~0.9 m).
parts = [
    {"name": "Bulb", "mesh": sphere(0.2), "color": "#cdd5f7", "pos": (0, 0.19, 0), "scale": (1.05, 0.95, 1.05)},
    eye("EyeL", -0.07, 0.22, 0.185), eye("EyeR", 0.07, 0.22, 0.185),
]
blades = [(0, 6, 0.62, "#b4bff0"), (60, 24, 0.55, "#c8bdf0"), (120, 30, 0.5, "#b4bff0"),
          (180, 20, 0.6, "#d3c8f5"), (240, 30, 0.5, "#b4bff0"), (300, 24, 0.55, "#c8bdf0")]
for k, (yaw, tilt, h, c) in enumerate(blades):
    base_y = 0.32
    sx = math.sin(math.radians(yaw))
    sz = math.cos(math.radians(yaw))
    off = math.sin(math.radians(tilt)) * h / 2
    parts.append({"name": "Blade%d" % k, "mesh": cyl(0.0, 0.06, h), "color": c,
                  "pos": (0.05 * sx + off * sx, base_y + h / 2 * math.cos(math.radians(tilt)), 0.05 * sz + off * sz),
                  "rot": (tilt, yaw, 0), "scale": (1.0, 1.0, 0.45)})
write("nostalgerbe", "Nostalgerbe", parts)

# Timidelle: shy cream bulb under a big pink cap, blushing (~0.65 m).
parts = [
    {"name": "Body", "mesh": sphere(0.22), "color": "#fff1f0", "pos": (0, 0.2, 0), "scale": (1, 0.9, 1)},
    {"name": "Cap", "mesh": sphere(0.3, 0.3, True), "color": "#ffbfd0", "pos": (0, 0.3, 0), "scale": (1, 0.85, 1)},
    {"name": "Dot0", "mesh": sphere(0.05), "color": "#fff6f8", "pos": (0.12, 0.5, 0.12), "scale": (1, 0.5, 1)},
    {"name": "Dot1", "mesh": sphere(0.04), "color": "#fff6f8", "pos": (-0.15, 0.46, 0.05), "scale": (1, 0.5, 1)},
    {"name": "Dot2", "mesh": sphere(0.045), "color": "#fff6f8", "pos": (0.0, 0.53, -0.12), "scale": (1, 0.5, 1)},
    eye("EyeL", -0.07, 0.2, 0.2), eye("EyeR", 0.07, 0.2, 0.2),
    {"name": "CheekL", "mesh": sphere(0.04), "color": "#ff9fb7", "pos": (-0.12, 0.15, 0.17), "scale": (1.3, 0.7, 0.5)},
    {"name": "CheekR", "mesh": sphere(0.04), "color": "#ff9fb7", "pos": (0.12, 0.15, 0.17), "scale": (1.3, 0.7, 0.5)},
    {"name": "Sprout", "mesh": sphere(0.07), "color": "#c6ecc9", "pos": (0.05, 0.6, 0), "rot": (0, 0, -30), "scale": (1.4, 0.35, 0.7)},
]
write("timidelle", "Timidelle", parts)

# Ronce-Angoisse: dusty violet bramble ball bristling with grey thorns (~0.85 m).
CORE_Y = 0.42
parts = [
    {"name": "Core", "mesh": sphere(0.3), "color": "#a493b4", "pos": (0, CORE_Y, 0), "scale": (1, 0.92, 1)},
    {"name": "Root", "mesh": sphere(0.22), "color": "#8f8299", "pos": (0, 0.08, 0), "scale": (1.3, 0.4, 1.3)},
    eye("EyeL", -0.09, CORE_Y + 0.05, 0.27, 0.035, "#f6e7a6"), eye("EyeR", 0.09, CORE_Y + 0.05, 0.27, 0.035, "#f6e7a6"),
]
dirs = []
for k in range(7):
    a = math.radians(k * 360 / 7 + 15)
    dirs.append((math.cos(a) * 0.9, 0.25, math.sin(a) * 0.9))
for k in range(4):
    a = math.radians(k * 90 + 45)
    dirs.append((math.cos(a) * 0.55, 0.8, math.sin(a) * 0.55))
dirs.append((0.0, 1.0, 0.0))
for k, d in enumerate(dirs):
    n = math.sqrt(sum(c * c for c in d))
    d = tuple(c / n for c in d)
    L = 0.26
    r = 0.27 + L / 2 - 0.05
    parts.append({"name": "Thorn%d" % k, "mesh": cyl(0.0, 0.055, L), "color": "#7d7288",
                  "pos": (d[0] * r, CORE_Y + d[1] * r * 0.92, d[2] * r), "basis": y_to(d)})
write("ronce_angoisse", "RonceAngoisse", parts)

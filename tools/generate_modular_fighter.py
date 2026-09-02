"""Generate a game-ready modular N64 / early-PS1 Cyber Kingpin.

Run from the repository root:
    blender --background --python tools/generate_modular_fighter.py

Output:
    assets/models/cyber_kingpin/cyber_kingpin_modular.blend
    assets/models/cyber_kingpin/cyber_kingpin_modular.glb
    assets/models/cyber_kingpin/cyber_kingpin_modular.fbx
    assets/models/cyber_kingpin/textures/kingpin_atlas_32.png
    assets/models/cyber_kingpin/cyber_kingpin_preview.png
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "models" / "cyber_kingpin"
BLEND_PATH = OUT_DIR / "cyber_kingpin_modular.blend"
GLB_PATH = OUT_DIR / "cyber_kingpin_modular.glb"
FBX_PATH = OUT_DIR / "cyber_kingpin_modular.fbx"
PREVIEW_PATH = OUT_DIR / "cyber_kingpin_preview.png"
TEXTURE_DIR = OUT_DIR / "textures"
ATLAS_PATH = TEXTURE_DIR / "kingpin_atlas_32.png"

FPS = 30
ATLAS = 32

# 8x8 swatches in a 32x32 atlas. Origin is bottom-left (Blender / OpenGL).
UV = {
    "skin": (0, 24),
    "skin_shadow": (8, 24),
    "vest": (16, 24),
    "vest_dark": (24, 24),
    "tank": (0, 16),
    "pants": (8, 16),
    "tape": (16, 16),
    "boot": (24, 16),
    "metal": (0, 8),
    "gold": (8, 8),
    "stump": (16, 8),
    "eye": (24, 8),
    "sole": (0, 0),
    "belt": (8, 0),
    "mouth": (16, 0),
    "brow": (24, 0),
}

LIMB_SLOTS = ("head", "torso", "arm_l", "arm_r", "leg_l", "leg_r")


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

def reset_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.actions,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.curves,
    ):
        for block in list(datablocks):
            try:
                datablocks.remove(block)
            except Exception:
                pass
    scene = bpy.context.scene
    master = scene.collection
    for col in list(bpy.data.collections):
        if col == master:
            continue
        try:
            bpy.data.collections.remove(col)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Atlas
# ---------------------------------------------------------------------------

def _px(r: int, g: int, b: int, a: int = 255) -> tuple[float, float, float, float]:
    return (r / 255.0, g / 255.0, b / 255.0, a / 255.0)


def paint_atlas() -> bpy.types.Image:
    """Hand-painted 32x32 nearest-filter atlas. Each swatch is 8x8."""
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    pixels = [0.0] * (ATLAS * ATLAS * 4)

    def put(x: int, y: int, c: tuple[float, float, float, float]) -> None:
        if 0 <= x < ATLAS and 0 <= y < ATLAS:
            i = (y * ATLAS + x) * 4
            pixels[i : i + 4] = c

    def fill_swatch(ox: int, oy: int, base, shadow, highlight, mode: str = "dither") -> None:
        for y in range(8):
            for x in range(8):
                c = base
                if mode == "dither":
                    if ((x // 2) + (y // 2)) % 2 == 0:
                        c = shadow
                    if (x, y) in ((1, 6), (6, 1), (4, 5)):
                        c = highlight
                elif mode == "stripes":
                    c = shadow if (y % 3) == 0 else base
                    if x in (0, 7):
                        c = shadow
                elif mode == "metal":
                    c = base
                    if y >= 6:
                        c = highlight
                    elif y <= 1:
                        c = shadow
                    if x == 1 and 2 <= y <= 5:
                        c = highlight
                elif mode == "gold":
                    c = base if (x + y) % 2 == 0 else highlight
                    if x in (0, 7) or y in (0, 7):
                        c = shadow
                elif mode == "eye":
                    c = _px(18, 10, 8)
                    if 2 <= x <= 5 and 2 <= y <= 5:
                        c = _px(8, 4, 4)
                    if 3 <= x <= 4 and 3 <= y <= 4:
                        c = _px(220, 92, 18)
                    if (x, y) == (4, 4):
                        c = _px(255, 210, 80)
                elif mode == "mouth":
                    c = _px(42, 18, 14)
                    if 1 <= x <= 6 and 3 <= y <= 4:
                        c = _px(28, 10, 8)
                    if (x, y) == (5, 4):
                        c = _px(212, 164, 36)
                elif mode == "brow":
                    c = shadow if y >= 3 else base
                elif mode == "stump":
                    dist = abs(x - 3.5) + abs(y - 3.5)
                    c = highlight if dist < 2.2 else (base if dist < 4.2 else shadow)
                put(ox + x, oy + y, c)

    fill_swatch(0, 24, _px(168, 112, 74), _px(132, 82, 52), _px(196, 142, 98), "dither")
    fill_swatch(8, 24, _px(118, 70, 44), _px(88, 50, 30), _px(140, 88, 56), "dither")
    fill_swatch(16, 24, _px(176, 28, 24), _px(120, 14, 12), _px(210, 48, 36), "dither")
    fill_swatch(24, 24, _px(96, 12, 10), _px(64, 6, 6), _px(128, 22, 18), "dither")
    fill_swatch(0, 16, _px(14, 14, 18), _px(8, 8, 10), _px(28, 28, 34), "dither")
    fill_swatch(8, 16, _px(28, 30, 36), _px(16, 18, 22), _px(44, 48, 56), "dither")
    fill_swatch(16, 16, _px(210, 196, 160), _px(168, 150, 112), _px(232, 220, 188), "stripes")
    fill_swatch(24, 16, _px(22, 20, 22), _px(10, 10, 12), _px(40, 36, 38), "dither")
    fill_swatch(0, 8, _px(120, 132, 140), _px(72, 80, 88), _px(210, 220, 228), "metal")
    fill_swatch(8, 8, _px(196, 140, 28), _px(128, 84, 12), _px(240, 196, 64), "gold")
    fill_swatch(16, 8, _px(110, 18, 20), _px(64, 8, 10), _px(150, 36, 32), "stump")
    fill_swatch(24, 8, _px(18, 10, 8), _px(8, 4, 4), _px(220, 92, 18), "eye")
    fill_swatch(0, 0, _px(18, 12, 10), _px(8, 6, 6), _px(36, 24, 18), "dither")
    fill_swatch(8, 0, _px(48, 14, 12), _px(28, 8, 8), _px(80, 24, 20), "dither")
    fill_swatch(16, 0, _px(42, 18, 14), _px(28, 10, 8), _px(212, 164, 36), "mouth")
    fill_swatch(24, 0, _px(96, 56, 36), _px(64, 36, 22), _px(120, 74, 48), "brow")

    image = bpy.data.images.new("kingpin_atlas_32", width=ATLAS, height=ATLAS, alpha=True)
    image.pixels = pixels
    image.filepath_raw = str(ATLAS_PATH)
    image.file_format = "PNG"
    image.save()
    image.pack()
    image.colorspace_settings.name = "sRGB"
    return image


def make_material(image: bpy.types.Image) -> bpy.types.Material:
    mat = bpy.data.materials.new("Kingpin_Atlas")
    mat.use_nodes = True
    mat.diffuse_color = (0.4, 0.2, 0.15, 1.0)
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (360, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (80, 0)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (-220, 0)
    tex.image = image
    tex.interpolation = "Closest"
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = 1.0
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.0
    mat.use_backface_culling = False
    return mat


def uv_rect(name: str, pad: float = 1.1) -> tuple[float, float, float, float]:
    x, y = UV[name]
    u0 = (x + pad) / ATLAS
    v0 = (y + pad) / ATLAS
    u1 = (x + 8 - pad) / ATLAS
    v1 = (y + 8 - pad) / ATLAS
    return (u0, v0, u1, v1)


def apply_uv(bm: bmesh.types.BMesh, face: bmesh.types.BMFace, swatch: str) -> None:
    uv_layer = bm.loops.layers.uv.active
    u0, v0, u1, v1 = uv_rect(swatch)
    n = len(face.loops)
    if n == 3:
        coords = ((u0, v0), (u1, v0), (u0, v1))
    elif n == 4:
        coords = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
    else:
        coords = tuple(
            (
                u0 + (u1 - u0) * (0.5 + 0.5 * math.cos(i / n * 2 * math.pi)),
                v0 + (v1 - v0) * (0.5 + 0.5 * math.sin(i / n * 2 * math.pi)),
            )
            for i in range(n)
        )
    for loop, (u, v) in zip(face.loops, coords):
        loop[uv_layer].uv = Vector((u, v))


# ---------------------------------------------------------------------------
# BMesh builders
# ---------------------------------------------------------------------------

def new_bmesh() -> bmesh.types.BMesh:
    bm = bmesh.new()
    bm.loops.layers.uv.new("UVMap")
    return bm


def v(bm: bmesh.types.BMesh, x: float, y: float, z: float) -> bmesh.types.BMVert:
    return bm.verts.new((x, y, z))


def face(bm: bmesh.types.BMesh, verts, swatch: str) -> bmesh.types.BMFace:
    f = bm.faces.new(verts)
    f.smooth = False
    apply_uv(bm, f, swatch)
    return f


def cap_ring(bm: bmesh.types.BMesh, ring, swatch: str, flip: bool = False) -> list:
    faces = []
    if len(ring) < 3:
        return faces
    c = Vector((0, 0, 0))
    for vt in ring:
        c += vt.co
    c /= len(ring)
    center = bm.verts.new(c)
    for i in range(len(ring)):
        a = ring[i]
        b = ring[(i + 1) % len(ring)]
        verts = (center, b, a) if flip else (center, a, b)
        faces.append(face(bm, verts, swatch))
    return faces


def oriented_box(bm: bmesh.types.BMesh, center, size, x_dir, z_dir, swatches) -> list:
    """Box whose local +X follows x_dir and local +Z follows z_dir as closely as possible."""
    center = Vector(center)
    x = Vector(x_dir).normalized()
    z_hint = Vector(z_dir)
    y = z_hint.cross(x)
    if y.length < 1e-6:
        y = Vector((0, 1, 0)).cross(x)
    y.normalize()
    z = x.cross(y).normalized()
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    corners = []
    for sx in (-hx, hx):
        for sy in (-hy, hy):
            for sz in (-hz, hz):
                corners.append(bm.verts.new(center + x * sx + y * sy + z * sz))
    # index: x(0-,1+) * 4 + y(0-,1+) * 2 + z(0-,1+)
    def C(ix, iy, iz):
        return corners[ix * 4 + iy * 2 + iz]

    names = {
        "back": (C(0, 0, 0), C(0, 1, 0), C(0, 1, 1), C(0, 0, 1)),
        "front": (C(1, 0, 0), C(1, 0, 1), C(1, 1, 1), C(1, 1, 0)),
        "right": (C(0, 0, 0), C(0, 0, 1), C(1, 0, 1), C(1, 0, 0)),
        "left": (C(0, 1, 0), C(1, 1, 0), C(1, 1, 1), C(0, 1, 1)),
        "bottom": (C(0, 0, 0), C(1, 0, 0), C(1, 1, 0), C(0, 1, 0)),
        "top": (C(0, 0, 1), C(0, 1, 1), C(1, 1, 1), C(1, 0, 1)),
    }
    if isinstance(swatches, str):
        mapping = {k: swatches for k in names}
    else:
        mapping = {k: swatches.get(k, swatches.get("default", "skin")) for k in names}
    faces = []
    for key, vs in names.items():
        faces.append(face(bm, vs, mapping[key]))
    return faces


def box(bm: bmesh.types.BMesh, center, size, swatches) -> list:
    """Axis-aligned box. size is full extents. swatches may be a str or a dict of face names."""
    cx, cy, cz = center
    sx, sy, sz = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    p = [
        v(bm, cx - sx, cy - sy, cz - sz),
        v(bm, cx + sx, cy - sy, cz - sz),
        v(bm, cx + sx, cy + sy, cz - sz),
        v(bm, cx - sx, cy + sy, cz - sz),
        v(bm, cx - sx, cy - sy, cz + sz),
        v(bm, cx + sx, cy - sy, cz + sz),
        v(bm, cx + sx, cy + sy, cz + sz),
        v(bm, cx - sx, cy + sy, cz + sz),
    ]
    names = {
        "bottom": (p[0], p[3], p[2], p[1]),
        "top": (p[4], p[5], p[6], p[7]),
        "front": (p[1], p[2], p[6], p[5]),  # +X
        "back": (p[0], p[4], p[7], p[3]),  # -X
        "left": (p[2], p[3], p[7], p[6]),  # +Y
        "right": (p[0], p[1], p[5], p[4]),  # -Y
    }
    faces = []
    if isinstance(swatches, str):
        mapping = {k: swatches for k in names}
    else:
        mapping = {k: swatches.get(k, swatches.get("default", "skin")) for k in names}
    for key, vs in names.items():
        faces.append(face(bm, vs, mapping[key]))
    return faces


def tapered_prism(bm, head, tail, head_rx, head_ry, tail_rx, tail_ry, swatch, sides=4, head_cap=None, tail_cap=None):
    """Prism along head->tail. Local X is world X-ish; Y is the leftover perpendicular."""
    head = Vector(head)
    tail = Vector(tail)
    axis = tail - head
    if axis.length < 1e-6:
        axis = Vector((0, 0, 1))
    axis.normalize()
    hint = Vector((1, 0, 0)) if abs(axis.dot(Vector((1, 0, 0)))) < 0.85 else Vector((0, 0, 1))
    side = axis.cross(hint)
    if side.length < 1e-6:
        side = axis.cross(Vector((0, 1, 0)))
    side.normalize()
    up = side.cross(axis)
    up.normalize()

    def ring(origin, rx, ry):
        verts = []
        for i in range(sides):
            a = (i / sides) * 2 * math.pi + math.pi / sides
            verts.append(bm.verts.new(origin + side * (rx * math.cos(a)) + up * (ry * math.sin(a))))
        return verts

    r0 = ring(head, head_rx, head_ry)
    r1 = ring(tail, tail_rx, tail_ry)
    faces = []
    for i in range(sides):
        faces.append(face(bm, (r0[i], r0[(i + 1) % sides], r1[(i + 1) % sides], r1[i]), swatch))
    if head_cap:
        cap_ring(bm, r0, head_cap, flip=True)
    if tail_cap:
        cap_ring(bm, r1, tail_cap, flip=False)
    return r0, r1, faces


def finish_object(bm: bmesh.types.BMesh, name: str, mat: bpy.types.Material) -> bpy.types.Object:
    bm.verts.index_update()
    bm.faces.index_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    for p in mesh.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    return obj


def tag(obj: bpy.types.Object, limb_slot: str, **extra) -> bpy.types.Object:
    obj["limb_slot"] = limb_slot
    obj["detachable"] = limb_slot != "torso" and not extra.get("is_stump", False) and not extra.get("is_accessory", False)
    for k, v in extra.items():
        obj[k] = v
    return obj


def count_tris(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# ---------------------------------------------------------------------------
# Character meshes — A-pose, facing +X, Z up
# ---------------------------------------------------------------------------

# Bind pose = orthodox fighting guard, facing +X. Mesh and armature share these joints.
J = {
    "hips": Vector((0.02, 0.00, 0.90)),
    "spine": Vector((0.05, 0.00, 1.08)),
    "chest": Vector((0.08, 0.01, 1.30)),
    "neck": Vector((0.10, 0.01, 1.48)),
    "head": Vector((0.12, 0.01, 1.58)),
    "head_tip": Vector((0.13, 0.01, 1.80)),
    "shoulder_l": Vector((0.08, 0.18, 1.44)),
    "upperarm_l": Vector((0.10, 0.36, 1.42)),
    "elbow_l": Vector((0.32, 0.26, 1.24)),
    "wrist_l": Vector((0.48, 0.14, 1.18)),
    "hand_l": Vector((0.60, 0.10, 1.14)),
    "shoulder_r": Vector((0.04, -0.18, 1.44)),
    "upperarm_r": Vector((0.06, -0.36, 1.42)),
    "elbow_r": Vector((0.24, -0.22, 1.30)),
    "wrist_r": Vector((0.36, -0.08, 1.28)),
    "hand_r": Vector((0.48, -0.04, 1.26)),
    "upperleg_l": Vector((0.04, 0.19, 0.90)),
    "knee_l": Vector((0.12, 0.20, 0.50)),
    "ankle_l": Vector((0.18, 0.20, 0.10)),
    "toe_l": Vector((0.38, 0.20, 0.05)),
    "upperleg_r": Vector((-0.02, -0.19, 0.90)),
    "knee_r": Vector((-0.02, -0.20, 0.50)),
    "ankle_r": Vector((-0.10, -0.20, 0.10)),
    "toe_r": Vector((0.10, -0.20, 0.05)),
}
GUARD = {k: (v.x, v.y, v.z) for k, v in J.items()}


def build_head(mat) -> bpy.types.Object:
    bm = new_bmesh()
    c = J["head"]
    # Angular bald cranium — flat top, heavy jaw, no visor.
    # Left (+Y) verts first, then we also place right counterparts explicitly
    # so the metal implant can live on only one temple.
    def P(x, y, z):
        return v(bm, c.x + x * 1.28, c.y + y * 1.22, c.z + z * 1.22)

    # Crown (flat bald top)
    t0 = P(-0.07, 0.09, 0.13)
    t1 = P(0.06, 0.09, 0.13)
    t2 = P(0.06, -0.09, 0.13)
    t3 = P(-0.07, -0.09, 0.13)
    # Upper brow / temples
    b0 = P(-0.10, 0.12, 0.04)
    b1 = P(0.11, 0.11, 0.05)
    b2 = P(0.11, -0.11, 0.05)
    b3 = P(-0.10, -0.12, 0.04)
    # Mid face / cheeks
    m0 = P(-0.09, 0.13, -0.04)
    m1 = P(0.10, 0.12, -0.03)
    m2 = P(0.10, -0.12, -0.03)
    m3 = P(-0.09, -0.13, -0.04)
    # Jaw
    j0 = P(-0.05, 0.11, -0.13)
    j1 = P(0.09, 0.09, -0.14)
    j2 = P(0.09, -0.09, -0.14)
    j3 = P(-0.05, -0.11, -0.13)
    chin = P(0.11, 0.00, -0.16)

    # Top
    face(bm, (t0, t1, t2, t3), "skin")
    # Front upper (brow plane)
    face(bm, (t1, b1, b2, t2), "brow")
    # Back
    face(bm, (t3, t0, b0, b3), "skin_shadow")
    # Left / right upper
    face(bm, (t0, t1, b1, b0), "skin")
    face(bm, (t2, t3, b3, b2), "skin")
    # Brow to mid
    face(bm, (b1, m1, m2, b2), "skin")
    face(bm, (b0, b3, m3, m0), "skin_shadow")
    face(bm, (b0, b1, m1, m0), "skin")
    face(bm, (b2, b3, m3, m2), "skin")
    # Jaw sides
    face(bm, (m0, m1, j1, j0), "skin_shadow")
    face(bm, (m2, m3, j3, j2), "skin_shadow")
    face(bm, (m3, m0, j0, j3), "skin_shadow")
    # Front jaw to chin
    face(bm, (m1, m2, j2, j1), "skin")
    face(bm, (j1, j2, chin), "skin_shadow")
    face(bm, (j0, j1, chin), "skin_shadow")
    face(bm, (j3, chin, j2), "skin_shadow")
    face(bm, (j3, j0, chin), "skin_shadow")

    # Recessed eye quads
    el0 = P(0.115, 0.055, 0.02)
    el1 = P(0.115, 0.02, 0.02)
    el2 = P(0.115, 0.02, -0.015)
    el3 = P(0.115, 0.055, -0.015)
    face(bm, (el0, el1, el2, el3), "eye")
    er0 = P(0.115, -0.02, 0.02)
    er1 = P(0.115, -0.055, 0.02)
    er2 = P(0.115, -0.055, -0.015)
    er3 = P(0.115, -0.02, -0.015)
    face(bm, (er0, er1, er2, er3), "eye")

    # Mouth slit
    mo0 = P(0.108, 0.035, -0.09)
    mo1 = P(0.108, -0.035, -0.09)
    mo2 = P(0.108, -0.035, -0.11)
    mo3 = P(0.108, 0.035, -0.11)
    face(bm, (mo0, mo1, mo2, mo3), "mouth")

    # Ears
    box(bm, (c.x - 0.01, c.y + 0.145, c.z + 0.00), (0.04, 0.03, 0.07), "skin_shadow")
    box(bm, (c.x - 0.01, c.y - 0.145, c.z + 0.00), (0.04, 0.03, 0.07), "skin_shadow")

    # Left-temple metal implant (character left = +Y)
    box(bm, (c.x + 0.02, c.y + 0.125, c.z + 0.06), (0.08, 0.025, 0.05), "metal")

    # Short neck, closed with a stump cap so the head is removable.
    neck_top = c + Vector((0.0, 0.0, -0.14))
    neck_bot = J["neck"] + Vector((0.0, 0.0, -0.02))
    tapered_prism(
        bm,
        neck_top,
        neck_bot,
        0.07,
        0.08,
        0.06,
        0.07,
        "skin_shadow",
        sides=6,
        head_cap=None,
        tail_cap="stump",
    )

    obj = finish_object(bm, "head", mat)
    return tag(obj, "head", detach_root_bone="Head", driver_bone="Head")


def build_torso(mat) -> bpy.types.Object:
    bm = new_bmesh()
    # Stacked N64 boxes: black tank core, open red vest, belt, hip yoke.
    box(
        bm,
        (0.06, 0.00, 1.28),
        (0.28, 0.42, 0.40),
        {"front": "tank", "back": "tank", "default": "tank", "top": "skin", "bottom": "tank"},
    )
    box(
        bm,
        (0.04, 0.00, 1.06),
        (0.26, 0.38, 0.14),
        {"front": "belt", "default": "pants", "top": "belt", "bottom": "pants"},
    )
    box(bm, (0.03, 0.00, 0.96), (0.24, 0.40, 0.10), "pants")

    # Open sleeveless vest — two red slabs leaving the tank visible in the middle.
    box(
        bm,
        (0.07, 0.24, 1.32),
        (0.30, 0.20, 0.38),
        {"front": "vest", "left": "vest", "right": "vest_dark", "back": "vest_dark", "top": "vest", "bottom": "vest_dark"},
    )
    box(
        bm,
        (0.07, -0.24, 1.32),
        (0.30, 0.20, 0.38),
        {"front": "vest", "left": "vest_dark", "right": "vest", "back": "vest_dark", "top": "vest", "bottom": "vest_dark"},
    )

    # Sleeveless shoulder caps (skin)
    box(bm, (0.05, 0.34, 1.46), (0.22, 0.16, 0.14), "skin")
    box(bm, (0.05, -0.34, 1.46), (0.22, 0.16, 0.14), "skin")

    # Neck socket with dark-red stump facing up (covered by the head).
    box(bm, (0.09, 0.00, 1.50), (0.12, 0.14, 0.08), {"top": "stump", "default": "skin_shadow", "bottom": "stump"})

    # Belt buckle + small chest implant
    box(bm, (0.18, 0.00, 1.06), (0.04, 0.08, 0.06), "metal")
    box(bm, (0.20, 0.00, 1.30), (0.03, 0.09, 0.07), "metal")

    # Recessed limb sockets, kept inside the torso so they only show after a limb pops off.
    box(bm, J["upperarm_l"] + Vector((0.0, -0.10, 0.0)), (0.10, 0.03, 0.10), "stump")
    box(bm, J["upperarm_r"] + Vector((0.0, 0.10, 0.0)), (0.10, 0.03, 0.10), "stump")
    box(bm, J["upperleg_l"] + Vector((0.0, 0.0, 0.08)), (0.12, 0.12, 0.03), "stump")
    box(bm, J["upperleg_r"] + Vector((0.0, 0.0, 0.08)), (0.12, 0.12, 0.03), "stump")

    obj = finish_object(bm, "torso", mat)
    return tag(obj, "torso", detachable=False, driver_bone="Chest")


def limb_box(bm, a, b, width, height, swatch) -> None:
    a, b = Vector(a), Vector(b)
    d = b - a
    up = Vector((0.0, 0.0, 1.0))
    if abs(d.normalized().dot(up)) > 0.8:
        up = Vector((1.0, 0.0, 0.0))
    oriented_box(bm, (a + b) * 0.5, (d.length, width, height), d, up, swatch)


def end_cap(bm, origin, direction, width, height, swatch) -> None:
    d = Vector(direction).normalized()
    up = Vector((0.0, 0.0, 1.0))
    if abs(d.dot(up)) > 0.8:
        up = Vector((1.0, 0.0, 0.0))
    oriented_box(bm, Vector(origin) + d * 0.01, (0.025, width, height), d, up, swatch)


def build_arm(mat, side: str) -> bpy.types.Object:
    bm = new_bmesh()
    ua = J[f"upperarm_{side}"]
    el = J[f"elbow_{side}"]
    wr = J[f"wrist_{side}"]
    hd = J[f"hand_{side}"]

    end_cap(bm, ua, ua - el, 0.22, 0.22, "stump")
    limb_box(bm, ua, el, 0.24, 0.22, "skin")
    limb_box(bm, el, wr, 0.21, 0.20, "skin")
    tape_start = wr.lerp(el, 0.40)
    limb_box(bm, tape_start, wr, 0.22, 0.21, "tape")

    fist_dir = (hd - wr).normalized()
    fist_center = wr + fist_dir * 0.11
    up = Vector((0.0, 0.0, 1.0))
    oriented_box(bm, fist_center, (0.18, 0.16, 0.14), fist_dir, up, "tape")
    oriented_box(bm, fist_center + fist_dir * 0.07 + Vector((0, 0, 0.03)), (0.05, 0.15, 0.04), fist_dir, up, "tape")
    y_side = 1.0 if side == "l" else -1.0
    oriented_box(
        bm,
        fist_center + Vector((0.02, 0.08 * y_side, 0.01)),
        (0.08, 0.05, 0.05),
        fist_dir,
        up,
        "tape",
    )

    obj = finish_object(bm, f"arm_{side}", mat)
    return tag(obj, f"arm_{side}", detach_root_bone=f"UpperArm_{side.upper()}", driver_bone=f"UpperArm_{side.upper()}")


def build_leg(mat, side: str) -> bpy.types.Object:
    bm = new_bmesh()
    hip = J[f"upperleg_{side}"]
    knee = J[f"knee_{side}"]
    ankle = J[f"ankle_{side}"]
    toe = J[f"toe_{side}"]

    end_cap(bm, hip, Vector((0, 0, 1)), 0.22, 0.22, "stump")
    limb_box(bm, hip, knee, 0.22, 0.24, "pants")
    shin_end = ankle + Vector((0.0, 0.0, 0.08))
    limb_box(bm, knee, shin_end, 0.18, 0.18, "pants")

    foot_dir = Vector((toe.x - ankle.x, 0.0, 0.0))
    if foot_dir.length < 1e-6:
        foot_dir = Vector((1.0, 0.0, 0.0))
    boot_center = Vector((ankle.x + 0.10, ankle.y, 0.08))
    oriented_box(
        bm,
        boot_center,
        (0.30, 0.16, 0.14),
        foot_dir,
        Vector((0, 0, 1)),
        {"front": "boot", "top": "boot", "bottom": "sole", "default": "boot"},
    )
    oriented_box(
        bm,
        Vector((boot_center.x + 0.04, boot_center.y, 0.15)),
        (0.16, 0.15, 0.03),
        foot_dir,
        Vector((0, 0, 1)),
        "metal",
    )
    oriented_box(
        bm,
        Vector((ankle.x - 0.02, ankle.y, 0.04)),
        (0.10, 0.14, 0.08),
        foot_dir,
        Vector((0, 0, 1)),
        "sole",
    )

    obj = finish_object(bm, f"leg_{side}", mat)
    return tag(obj, f"leg_{side}", detach_root_bone=f"UpperLeg_{side.upper()}", driver_bone=f"UpperLeg_{side.upper()}")


def build_stump(mat, name: str, slot: str, center: Vector, axis: Vector, radius: float, bone: str) -> bpy.types.Object:
    bm = new_bmesh()
    axis = Vector(axis).normalized()
    tail = Vector(center) + axis * 0.018
    tapered_prism(
        bm,
        center,
        tail,
        radius,
        radius,
        radius * 0.85,
        radius * 0.85,
        "stump",
        sides=6,
        head_cap="stump",
        tail_cap="stump",
    )
    obj = finish_object(bm, name, mat)
    return tag(obj, slot, is_stump=True, detachable=False, hidden_until_detach=True, driver_bone=bone)


def build_chain(mat) -> bpy.types.Object:
    bm = new_bmesh()
    # Flat polygonal chain sitting on the chest — accessory, not body.
    pts = [
        (0.16, 0.10, 1.48),
        (0.22, 0.08, 1.38),
        (0.24, 0.00, 1.28),
        (0.22, -0.08, 1.38),
        (0.16, -0.10, 1.48),
    ]
    for p in pts:
        box(bm, p, (0.04, 0.035, 0.035), "gold")
    obj = finish_object(bm, "acc_chain", mat)
    return tag(obj, "torso", is_accessory=True, detachable=False, driver_bone="Chest")


def build_rings(mat, side: str) -> bpy.types.Object:
    bm = new_bmesh()
    hd = J[f"hand_{side}"]
    box(bm, hd + Vector((0.08, 0.0, 0.04)), (0.03, 0.12, 0.03), "gold")
    obj = finish_object(bm, f"acc_rings_{side}", mat)
    return tag(obj, f"arm_{side}", is_accessory=True, detachable=True, driver_bone=f"Hand_{side.upper()}")


# ---------------------------------------------------------------------------
# Armature
# ---------------------------------------------------------------------------

BONES = [
    # name, head_key, tail_key, parent, connect
    ("Root", None, None, None, False),
    ("Hips", "hips", "spine", "Root", False),
    ("Spine", "spine", "chest", "Hips", True),
    ("Chest", "chest", "neck", "Spine", True),
    ("Neck", "neck", "head", "Chest", True),
    ("Head", "head", "head_tip", "Neck", True),
    ("Shoulder_L", "shoulder_l", "upperarm_l", "Chest", False),
    ("UpperArm_L", "upperarm_l", "elbow_l", "Shoulder_L", True),
    ("LowerArm_L", "elbow_l", "wrist_l", "UpperArm_L", True),
    ("Hand_L", "wrist_l", "hand_l", "LowerArm_L", True),
    ("Shoulder_R", "shoulder_r", "upperarm_r", "Chest", False),
    ("UpperArm_R", "upperarm_r", "elbow_r", "Shoulder_R", True),
    ("LowerArm_R", "elbow_r", "wrist_r", "UpperArm_R", True),
    ("Hand_R", "wrist_r", "hand_r", "LowerArm_R", True),
    ("UpperLeg_L", "upperleg_l", "knee_l", "Hips", False),
    ("LowerLeg_L", "knee_l", "ankle_l", "UpperLeg_L", True),
    ("Foot_L", "ankle_l", "toe_l", "LowerLeg_L", True),
    ("UpperLeg_R", "upperleg_r", "knee_r", "Hips", False),
    ("LowerLeg_R", "knee_r", "ankle_r", "UpperLeg_R", True),
    ("Foot_R", "ankle_r", "toe_r", "LowerLeg_R", True),
]


def create_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("CyberKingpin_Rig")
    data.display_type = "OCTAHEDRAL"
    arm = bpy.data.objects.new("CyberKingpin_Rig", data)
    bpy.context.scene.collection.objects.link(arm)
    arm.show_in_front = True
    arm["rig_type"] = "humanoid_modular_fighter"
    arm["forward_axis"] = "+X"
    arm["gameplay_plane"] = "XZ"
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    eb = {}
    root = data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 0.12)
    eb["Root"] = root

    for name, hkey, tkey, parent, connect in BONES:
        if name == "Root":
            continue
        bone = data.edit_bones.new(name)
        bone.head = J[hkey]
        bone.tail = J[tkey]
        if (bone.tail - bone.head).length < 0.04:
            bone.tail = bone.head + Vector((0.0, 0.0, 0.08))
        bone.use_connect = False
        eb[name] = bone

    for name, hkey, tkey, parent, connect in BONES:
        if parent:
            eb[name].parent = eb[parent]
            eb[name].use_connect = connect

    # Roll so bone Z aims along world Y (character left) — local X then swings in XZ.
    for bone in data.edit_bones:
        bone.align_roll(Vector((0.0, 1.0, 0.0)))

    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.lock_location = (False, False, False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bind_mesh(obj: bpy.types.Object, arm: bpy.types.Object) -> None:
    obj.parent = arm
    obj.parent_type = "OBJECT"
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mod.use_vertex_groups = True
    mod.use_bone_envelopes = False
    mod.use_deform_preserve_volume = False


def bone_parent(obj: bpy.types.Object, arm: bpy.types.Object, bone_name: str) -> None:
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world
    obj["driver_bone"] = bone_name


def _bone_world(arm, name: str) -> tuple[Vector, Vector]:
    bone = arm.data.bones[name]
    head = arm.matrix_world @ bone.head_local
    tail = arm.matrix_world @ bone.tail_local
    return head, tail


def assign_weights(obj: bpy.types.Object, arm: bpy.types.Object, bone_names: list[str], blend: float = 0.08) -> None:
    """Weight vertices to the closest bone segment in the given chain."""
    mesh = obj.data
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    groups = {n: obj.vertex_groups.new(name=n) for n in bone_names}
    segments = []
    for n in bone_names:
        h, t = _bone_world(arm, n)
        segments.append((n, h, t, (t - h)))

    mw = obj.matrix_world
    for vert in mesh.vertices:
        p = mw @ vert.co
        weights = {}
        for n, h, t, d in segments:
            length = d.length
            if length < 1e-8:
                dist = (p - h).length
                w = max(0.0, 1.0 - dist / 0.2)
            else:
                u = max(0.0, min(1.0, (p - h).dot(d) / (length * length)))
                proj = h + d * u
                dist = (p - proj).length
                # Along-chain membership with a blend at the ends.
                axial = 1.0
                if u < blend / max(length, 1e-6):
                    axial = u / max(blend / max(length, 1e-6), 1e-6)
                elif u > 1.0 - blend / max(length, 1e-6):
                    axial = (1.0 - u) / max(blend / max(length, 1e-6), 1e-6)
                w = axial * math.exp(-dist * 8.0)
            weights[n] = max(weights.get(n, 0.0), w)
        total = sum(weights.values())
        if total <= 1e-8:
            # Fallback: nearest bone head.
            n = min(segments, key=lambda s: (p - s[1]).length)[0]
            groups[n].add([vert.index], 1.0, "REPLACE")
            continue
        for n, w in weights.items():
            nw = w / total
            if nw > 0.001:
                groups[n].add([vert.index], nw, "REPLACE")


def assign_single(obj: bpy.types.Object, bone_name: str) -> None:
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    g = obj.vertex_groups.new(name=bone_name)
    g.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")


# ---------------------------------------------------------------------------
# Posing
# ---------------------------------------------------------------------------

def set_bone_aim(pb, head: Vector, tail: Vector) -> None:
    """Aim a pose bone in armature space so it spans head->tail."""
    direction = tail - head
    if direction.length < 1e-6:
        return
    length = pb.bone.length
    direction.normalize()
    # Keep a consistent up hint so rolls don't flip.
    up = Vector((0.0, 1.0, 0.0))
    if abs(direction.dot(up)) > 0.85:
        up = Vector((1.0, 0.0, 0.0))
    quat = direction.to_track_quat("Y", "Z")
    mat = quat.to_matrix().to_4x4()
    mat.translation = head
    # Preserve rest length.
    pb.matrix = mat
    # Do not scale.


def apply_joints(arm, joints: dict, root_offset=(0, 0, 0), root_euler=(0, 0, 0)) -> None:
    """joints maps the same keys as J, in armature space."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm.pose.bones

    def G(key, default=None):
        if key in joints:
            return Vector(joints[key])
        if default is not None:
            return Vector(default)
        return Vector(J[key])

    root = pb["Root"]
    root.location = Vector(root_offset)
    root.rotation_euler = root_euler
    bpy.context.view_layer.update()

    mapping = [
        ("Hips", "hips", "spine"),
        ("Spine", "spine", "chest"),
        ("Chest", "chest", "neck"),
        ("Neck", "neck", "head"),
        ("Head", "head", "head_tip"),
        ("Shoulder_L", "shoulder_l", "upperarm_l"),
        ("UpperArm_L", "upperarm_l", "elbow_l"),
        ("LowerArm_L", "elbow_l", "wrist_l"),
        ("Hand_L", "wrist_l", "hand_l"),
        ("Shoulder_R", "shoulder_r", "upperarm_r"),
        ("UpperArm_R", "upperarm_r", "elbow_r"),
        ("LowerArm_R", "elbow_r", "wrist_r"),
        ("Hand_R", "wrist_r", "hand_r"),
        ("UpperLeg_L", "upperleg_l", "knee_l"),
        ("LowerLeg_L", "knee_l", "ankle_l"),
        ("Foot_L", "ankle_l", "toe_l"),
        ("UpperLeg_R", "upperleg_r", "knee_r"),
        ("LowerLeg_R", "knee_r", "ankle_r"),
        ("Foot_R", "ankle_r", "toe_r"),
    ]
    for name, h, t in mapping:
        set_bone_aim(pb[name], G(h), G(t))
        bpy.context.view_layer.update()


def mix(base: dict, **overrides) -> dict:
    pose = dict(base)
    pose.update(overrides)
    return pose


def v3(x, y, z):
    return (float(x), float(y), float(z))


# GUARD is defined next to J (bind pose = fighting stance).


def bake_rest_pose(arm, meshes) -> None:
    """Bake the current pose into mesh + armature rest (fighting stance bind)."""
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            if mod.type == "ARMATURE":
                bpy.ops.object.modifier_apply(modifier=mod.name)

    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    for obj in meshes:
        bind_mesh(obj, arm)


def apply_rest(arm) -> None:
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def key_all(arm, frame: int) -> None:
    for pb in arm.pose.bones:
        pb.keyframe_insert("location", frame=frame, group=pb.name)
        pb.keyframe_insert("rotation_euler", frame=frame, group=pb.name)
        pb.keyframe_insert("scale", frame=frame, group=pb.name)


def key_additive(arm, frame: int, loc=None, rot=None, root_loc=(0.0, 0.0, 0.0), root_rot=(0.0, 0.0, 0.0)) -> None:
    """Keyframe an additive pose on top of the fighting-stance rest."""
    bpy.context.scene.frame_set(frame)
    apply_rest(arm)
    arm.pose.bones["Root"].location = Vector(root_loc)
    arm.pose.bones["Root"].rotation_euler = root_rot
    for name, value in (loc or {}).items():
        arm.pose.bones[name].location = Vector(value)
    for name, value in (rot or {}).items():
        arm.pose.bones[name].rotation_euler = value
    bpy.context.view_layer.update()
    key_all(arm, frame)


def create_action(arm, name: str, length: int, keys: list) -> bpy.types.Action:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    if hasattr(action, "use_frame_range"):
        action.use_frame_range = True
        action.frame_start = 0
        action.frame_end = length
    arm.animation_data_create()
    arm.animation_data.action = action
    for item in keys:
        frame = item[0]
        payload = item[1] if len(item) > 1 else {}
        key_additive(arm, frame, **(payload or {}))
    if hasattr(action, "fcurves"):
        for fc in action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
                kp.handle_left_type = "AUTO_CLAMPED"
                kp.handle_right_type = "AUTO_CLAMPED"
    arm.animation_data.action = None
    return action


def create_animations(arm) -> None:
    rest = {}
    r = lambda **axes: (axes.get("x", 0.0), axes.get("y", 0.0), axes.get("z", 0.0))

    idle_b = {
        "loc": {"Hips": (0.0, 0.0, 0.02), "Chest": (0.005, 0.0, 0.01)},
        "rot": {
            "Chest": r(z=-0.04),
            "UpperArm_L": r(z=0.06),
            "UpperArm_R": r(z=-0.04),
            "Head": r(z=0.03),
        },
    }
    create_action(arm, "idle", 32, [(0, rest), (16, idle_b), (32, rest)])

    walk_a = {
        "loc": {"Hips": (0.02, 0.0, 0.02)},
        "rot": {
            "Hips": r(z=0.06),
            "UpperLeg_L": r(z=0.55),
            "LowerLeg_L": r(z=-0.35),
            "Foot_L": r(z=-0.15),
            "UpperLeg_R": r(z=-0.40),
            "LowerLeg_R": r(z=0.15),
            "UpperArm_L": r(z=-0.18),
            "UpperArm_R": r(z=0.18),
        },
    }
    walk_b = {
        "loc": {"Hips": (-0.02, 0.0, 0.02)},
        "rot": {
            "Hips": r(z=-0.06),
            "UpperLeg_L": r(z=-0.40),
            "LowerLeg_L": r(z=0.15),
            "UpperLeg_R": r(z=0.55),
            "LowerLeg_R": r(z=-0.35),
            "Foot_R": r(z=-0.15),
            "UpperArm_L": r(z=0.18),
            "UpperArm_R": r(z=-0.18),
        },
    }
    create_action(arm, "walk", 24, [(0, walk_a), (12, walk_b), (24, walk_a)])

    crouch = {
        "loc": {"Hips": (0.0, 0.0, -0.08)},
        "rot": {
            "UpperLeg_L": r(z=0.35),
            "LowerLeg_L": r(z=-0.55),
            "UpperLeg_R": r(z=0.30),
            "LowerLeg_R": r(z=-0.50),
            "UpperArm_L": r(z=-0.15),
            "UpperArm_R": r(z=-0.10),
        },
    }
    hang = {
        "rot": {
            "UpperLeg_L": r(z=0.45),
            "LowerLeg_L": r(z=-0.70),
            "UpperLeg_R": r(z=-0.20),
            "LowerLeg_R": r(z=-0.25),
            "UpperArm_L": r(z=0.35),
            "UpperArm_R": r(z=-0.25),
        },
        "root_loc": (0.0, 0.0, 0.42),
    }
    land = {**hang, "root_loc": (0.0, 0.0, 0.16)}
    create_action(arm, "jump", 28, [(0, rest), (6, crouch), (12, hang), (20, land), (28, rest)])

    jab_wind = {
        "rot": {
            "UpperArm_L": r(z=-0.35),
            "LowerArm_L": r(z=0.25),
            "Chest": r(z=0.08),
        }
    }
    jab_hit = {
        "loc": {"Hips": (0.05, 0.0, 0.0)},
        "rot": {
            "UpperArm_L": r(z=1.15),
            "LowerArm_L": r(z=-0.75),
            "Hand_L": r(z=-0.15),
            "Chest": r(z=-0.22),
            "Hips": r(z=-0.10),
        },
    }
    create_action(arm, "jab", 14, [(0, rest), (4, jab_wind), (7, jab_hit), (9, jab_hit), (14, rest)])

    heavy_wind = {
        "rot": {
            "UpperArm_R": r(z=-0.55),
            "LowerArm_R": r(z=0.40),
            "Chest": r(z=0.22),
            "Hips": r(z=0.12),
        }
    }
    heavy_hit = {
        "loc": {"Hips": (0.08, 0.0, 0.0)},
        "rot": {
            "UpperArm_R": r(z=1.05),
            "LowerArm_R": r(z=-0.70),
            "Hand_R": r(z=-0.15),
            "Chest": r(z=-0.28),
            "Hips": r(z=-0.16),
            "Head": r(z=-0.10),
        },
    }
    create_action(arm, "heavy_punch", 22, [(0, rest), (8, heavy_wind), (13, heavy_hit), (16, heavy_hit), (22, rest)])

    low_wind = {
        "rot": {
            "UpperLeg_L": r(z=-0.35),
            "LowerLeg_L": r(z=0.20),
            "Chest": r(z=0.10),
        }
    }
    low_hit = {
        "rot": {
            "UpperLeg_L": r(z=-0.55),
            "LowerLeg_L": r(z=-0.10),
            "Foot_L": r(z=-0.05),
            "Chest": r(z=-0.12),
            "Hips": r(z=-0.10),
            "UpperArm_L": r(z=-0.20),
        }
    }
    create_action(arm, "low_kick", 20, [(0, rest), (6, low_wind), (11, low_hit), (14, low_hit), (20, rest)])

    high_wind = {
        "rot": {
            "UpperLeg_R": r(z=-0.45),
            "LowerLeg_R": r(z=-0.20),
            "Chest": r(z=0.12),
            "UpperArm_L": r(z=0.15),
            "UpperArm_R": r(z=-0.20),
        }
    }
    high_hit = {
        "rot": {
            "UpperLeg_R": r(z=-1.45),
            "LowerLeg_R": r(z=-0.15),
            "Foot_R": r(z=-0.08),
            "Hips": r(z=0.14),
            "Chest": r(z=0.08),
            "Head": r(z=0.06),
            "UpperArm_L": r(z=-0.25),
            "UpperArm_R": r(z=-0.15),
        }
    }
    create_action(arm, "high_kick", 28, [(0, rest), (8, high_wind), (15, high_hit), (18, high_hit), (28, rest)])

    block = {
        "loc": {"Hips": (-0.03, 0.0, -0.02)},
        "rot": {
            "UpperArm_L": r(z=-0.45, x=-0.25),
            "LowerArm_L": r(z=0.55),
            "UpperArm_R": r(z=-0.55, x=0.20),
            "LowerArm_R": r(z=0.60),
            "Chest": r(z=0.10),
            "Head": r(z=0.08),
        },
    }
    create_action(arm, "block", 16, [(0, rest), (6, block), (16, block)])

    hit = {
        "loc": {"Hips": (-0.06, 0.0, 0.01)},
        "rot": {
            "Chest": r(z=0.35),
            "Head": r(z=0.40, x=0.10),
            "UpperArm_L": r(z=-0.55),
            "UpperArm_R": r(z=-0.45),
            "Hips": r(z=0.12),
        },
        "root_loc": (-0.08, 0.0, 0.02),
    }
    create_action(arm, "hit", 14, [(0, rest), (4, hit), (8, hit), (14, rest)])

    ko_mid = {
        "rot": {
            "Hips": r(z=0.45),
            "Spine": r(z=0.25),
            "Chest": r(z=0.20),
            "Head": r(z=0.35),
            "UpperArm_L": r(z=-0.80),
            "UpperArm_R": r(z=-0.70),
            "UpperLeg_L": r(z=0.25),
            "UpperLeg_R": r(z=-0.15),
        },
        "root_loc": (-0.12, 0.0, -0.06),
        "root_rot": (0.0, 0.35, 0.0),
    }
    ko_end = {
        "rot": {
            "Hips": r(z=0.15),
            "Spine": r(z=0.10),
            "Chest": r(z=0.05),
            "Head": r(z=0.20),
            "UpperArm_L": r(z=-1.1),
            "LowerArm_L": r(z=0.4),
            "UpperArm_R": r(z=-1.0),
            "LowerArm_R": r(z=0.3),
            "UpperLeg_L": r(z=0.35),
            "UpperLeg_R": r(z=0.20),
        },
        "root_loc": (-0.22, 0.0, -0.18),
        "root_rot": (0.0, 1.25, 0.0),
    }
    create_action(arm, "knockout", 40, [(0, rest), (12, ko_mid), (28, ko_end), (40, ko_end)])


# ---------------------------------------------------------------------------
# Preview / export
# ---------------------------------------------------------------------------

def look_at(obj, target) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_preview(arm) -> list[bpy.types.Object]:
    """Lights + camera exist only for the PNG. They are never exported."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.fps = FPS
    if scene.world:
        scene.world.use_nodes = False
        scene.world.color = (0.02, 0.02, 0.03)

    extras = []

    cam_data = bpy.data.cameras.new("Preview_Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.55
    cam = bpy.data.objects.new("Preview_Camera", cam_data)
    cam.location = (3.15, -3.35, 1.45)
    look_at(cam, (0.14, 0.0, 0.92))
    bpy.context.scene.collection.objects.link(cam)
    scene.camera = cam
    extras.append(cam)

    def add_light(name, loc, energy, color, size=3.0):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.color = color
        data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        look_at(obj, (0.1, 0.0, 1.1))
        bpy.context.scene.collection.objects.link(obj)
        extras.append(obj)
        return obj

    add_light("Preview_Key", (3.0, -3.2, 4.2), 900, (1.0, 0.95, 0.9), 4.0)
    add_light("Preview_Fill", (-2.2, -1.8, 1.6), 350, (0.35, 0.45, 0.7), 3.0)
    add_light("Preview_Rim", (-1.5, 2.4, 2.8), 500, (0.85, 0.15, 0.1), 2.5)
    return extras


def ensure_object_mode() -> None:
    obj = bpy.context.view_layer.objects.active
    if obj is None:
        for o in bpy.data.objects:
            if o.type == "ARMATURE":
                bpy.context.view_layer.objects.active = o
                obj = o
                break
    if obj is not None and getattr(obj, "mode", "OBJECT") != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def select_exportables(arm) -> None:
    ensure_object_mode()
    bpy.context.view_layer.objects.active = arm
    for obj in bpy.data.objects:
        obj.select_set(False)
    arm.select_set(True)
    for obj in bpy.data.objects:
        if obj == arm or obj.parent == arm:
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
            obj.select_set(True)


def patch_glb(path: Path) -> None:
    """Force nearest sampling and an unlit material so Godot doesn't import PBR."""
    import json
    import struct

    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        return
    off = 12
    clen, ctype = struct.unpack_from("<I4s", data, off)
    json_start = off + 8
    gl = json.loads(data[json_start : json_start + clen])
    bin_off = json_start + clen
    bin_off += (4 - (clen % 4)) % 4
    bin_chunk = data[bin_off:]

    for sampler in gl.get("samplers", []):
        sampler["magFilter"] = 9728  # NEAREST
        sampler["minFilter"] = 9728  # NEAREST
        sampler["wrapS"] = 33071
        sampler["wrapT"] = 33071
    used = set(gl.get("extensionsUsed", []))
    used.discard("KHR_materials_specular")
    used.add("KHR_materials_unlit")
    gl["extensionsUsed"] = sorted(used)
    gl.pop("extensionsRequired", None)
    for mat in gl.get("materials", []):
        mat.pop("extensions", None)
        mat["extensions"] = {"KHR_materials_unlit": {}}
        pbr = mat.get("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        mat["pbrMetallicRoughness"] = pbr

    raw = json.dumps(gl, separators=(",", ":")).encode("utf-8")
    pad = (4 - (len(raw) % 4)) % 4
    raw += b" " * pad
    json_chunk = struct.pack("<I4s", len(raw), b"JSON") + raw
    out = struct.pack("<4sII", b"glTF", 2, 12 + len(json_chunk) + len(bin_chunk))
    Path(path).write_bytes(out + json_chunk + bin_chunk)


def save_and_export(arm, extras) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.frame_start = 0
    scene.frame_end = 40
    scene.frame_set(0)
    arm.animation_data_create()
    # Preview the bind pose (neutral fighting stance), not a deformed clip.
    apply_rest(arm)
    bpy.ops.object.mode_set(mode="OBJECT")
    scene.frame_set(0)

    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)

    # Diagnostic snapshots of a few clips so pose bugs are visible without Godot.
    sheet_dir = OUT_DIR / "anim_preview"
    sheet_dir.mkdir(parents=True, exist_ok=True)
    shots = [("idle", 16), ("walk", 12), ("jab", 7), ("heavy_punch", 13), ("low_kick", 11), ("high_kick", 15), ("block", 8), ("hit", 4), ("jump", 12), ("knockout", 28)]
    arm.animation_data_create()
    for name, frame in shots:
        action = bpy.data.actions.get(name)
        if not action:
            continue
        arm.animation_data.action = action
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        scene.render.filepath = str(sheet_dir / f"{name}_{frame:02d}.png")
        bpy.ops.render.render(write_still=True)

    # Rest pose is already the fighting stance; don't leave a clip assigned.
    arm.animation_data.action = None
    apply_rest(arm)
    ensure_object_mode()

    # Preview camera/lights are render-only — strip them from the source file.
    for extra in extras:
        bpy.data.objects.remove(extra, do_unlink=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    select_exportables(arm)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=True,
        export_force_sampling=True,
        export_extras=True,
        export_nla_strips=False,
        export_current_frame=False,
        export_reset_pose_bones=True,
        export_rest_position_armature=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_optimize_animation_size=False,
        export_image_format="AUTO",
    )

    patch_glb(GLB_PATH)

    select_exportables(arm)
    bpy.ops.export_scene.fbx(
        filepath=str(FBX_PATH),
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        use_armature_deform_only=True,
        bake_anim=True,
        bake_anim_use_all_actions=True,
        bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True,
        path_mode="COPY",
        embed_textures=True,
        axis_forward="X",
        axis_up="Y",
        bake_space_transform=True,
        use_custom_props=True,
        use_triangles=True,
    )


def report(arm, meshes) -> None:
    print("\n=== Cyber Kingpin report ===")
    total = 0
    for obj in meshes:
        tris = count_tris(obj)
        total += tris
        print(f"  {obj.name:16} {tris:4d} tris  slot={obj.get('limb_slot')}  verts={len(obj.data.vertices)}")
    print(f"  TOTAL            {total:4d} tris")
    print("  bones:", [b.name for b in arm.data.bones])
    print("  actions:", [a.name for a in bpy.data.actions])
    print(f"  facing +X, rest = fighting guard")
    if not (700 <= total <= 1000):
        print(f"  WARNING: triangle count {total} outside 700-1000 target")
    else:
        print("  triangle budget OK")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    image = paint_atlas()
    mat = make_material(image)

    arm = create_armature()
    head = build_head(mat)
    torso = build_torso(mat)
    arm_l = build_arm(mat, "l")
    arm_r = build_arm(mat, "r")
    leg_l = build_leg(mat, "l")
    leg_r = build_leg(mat, "r")
    body = [head, torso, arm_l, arm_r, leg_l, leg_r]

    stump_neck = build_stump(mat, "stump_neck", "head", J["neck"] + Vector((0.0, 0.0, -0.03)), Vector((0, 0, 1)), 0.05, "Neck")
    stump_arm_l = build_stump(mat, "stump_arm_l", "arm_l", J["upperarm_l"] + Vector((0.0, -0.10, 0.0)), Vector((0, 1, 0)), 0.06, "Shoulder_L")
    stump_arm_r = build_stump(mat, "stump_arm_r", "arm_r", J["upperarm_r"] + Vector((0.0, 0.10, 0.0)), Vector((0, -1, 0)), 0.06, "Shoulder_R")
    stump_leg_l = build_stump(mat, "stump_leg_l", "leg_l", J["upperleg_l"] + Vector((0.0, 0.0, 0.10)), Vector((0, 0, -1)), 0.07, "Hips")
    stump_leg_r = build_stump(mat, "stump_leg_r", "leg_r", J["upperleg_r"] + Vector((0.0, 0.0, 0.10)), Vector((0, 0, -1)), 0.07, "Hips")
    stumps = [stump_neck, stump_arm_l, stump_arm_r, stump_leg_l, stump_leg_r]

    chain = build_chain(mat)
    rings_l = build_rings(mat, "l")
    rings_r = build_rings(mat, "r")
    accessories = [chain, rings_l, rings_r]

    for obj in body:
        bind_mesh(obj, arm)

    assign_weights(head, arm, ["Neck", "Head"], blend=0.04)
    assign_weights(torso, arm, ["Hips", "Spine", "Chest"], blend=0.10)
    assign_weights(arm_l, arm, ["UpperArm_L", "LowerArm_L", "Hand_L"], blend=0.07)
    assign_weights(arm_r, arm, ["UpperArm_R", "LowerArm_R", "Hand_R"], blend=0.07)
    assign_weights(leg_l, arm, ["UpperLeg_L", "LowerLeg_L", "Foot_L"], blend=0.07)
    assign_weights(leg_r, arm, ["UpperLeg_R", "LowerLeg_R", "Foot_R"], blend=0.07)

    bone_parent(stump_neck, arm, "Neck")
    bone_parent(stump_arm_l, arm, "Shoulder_L")
    bone_parent(stump_arm_r, arm, "Shoulder_R")
    bone_parent(stump_leg_l, arm, "Hips")
    bone_parent(stump_leg_r, arm, "Hips")
    bone_parent(chain, arm, "Chest")
    bone_parent(rings_l, arm, "Hand_L")
    bone_parent(rings_r, arm, "Hand_R")

    bpy.context.view_layer.update()
    create_animations(arm)
    extras = setup_preview(arm)
    save_and_export(arm, extras)
    report(arm, body + stumps + accessories)
    print(f"Wrote {BLEND_PATH}")
    print(f"Wrote {GLB_PATH}")
    print(f"Wrote {FBX_PATH}")
    print(f"Wrote {PREVIEW_PATH}")
    print(f"Wrote {ATLAS_PATH}")


if __name__ == "__main__":
    main()

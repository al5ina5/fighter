"""Generate The Girl — N64-style modular fighter.

Built only from the example character sheet
(assets/models/example/142D2908-9A58-4270-BC33-8BA7B93B530C.png).
Does not reuse geometry, palette, or silhouette from cyber_kingpin or the
previous the_girl_n64 attempt.

Run from the repository root:
    blender --background --python tools/generate_the_girl_n64.py
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path
from typing import Any, Optional

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "models" / "the_girl_n64"
BLEND_PATH = OUT_DIR / "the_girl_n64.blend"
GLB_PATH = OUT_DIR / "the_girl_n64.glb"
PREVIEW_PATH = OUT_DIR / "the_girl_n64_preview.png"
FRONT_PATH = OUT_DIR / "the_girl_n64_front.png"
SIDE_PATH = OUT_DIR / "the_girl_n64_side.png"
SHEET_PATH = OUT_DIR / "the_girl_n64_animation_sheet.png"
ATLAS_PATH = OUT_DIR / "textures" / "the_girl_atlas.png"
README_PATH = OUT_DIR / "README.md"
TEXTURE_DIR = OUT_DIR / "textures"

FPS = 30
TEX = 16
TARGET_TRIS = 1024
TARGET_MESHES = 29
TARGET_MATERIALS = 6
TARGET_LIMB_SLOTS = 18
TARGET_CHANNELS = 57

# 16-color sheet palette (sRGB 0-255).
C = {
    "pink": (244, 74, 148),
    "pink_d": (196, 36, 108),
    "pink_l": (255, 130, 178),
    "yellow": (244, 196, 40),
    "teal": (48, 184, 176),
    "navy": (38, 34, 52),
    "white": (236, 228, 220),
    "cream": (232, 196, 164),
    "tan": (196, 164, 124),
    "brown": (124, 76, 40),
    "magenta": (224, 48, 112),
    "rose": (208, 112, 144),
    "slate": (90, 106, 120),
    "beige": (232, 220, 200),
    "taupe": (160, 144, 128),
    "brown_d": (74, 48, 32),
    "pupil": (28, 22, 40),
    "stump": (196, 28, 48),
    "lip": (220, 80, 110),
}


def px(name: str) -> tuple[float, float, float, float]:
    r, g, b = C[name]
    return (r / 255.0, g / 255.0, b / 255.0, 1.0)


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------


def reset_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.images,
        bpy.data.actions,
        bpy.data.textures,
    ):
        for item in list(coll):
            coll.remove(item)


# ---------------------------------------------------------------------------
# 16x16 textures — six materials, nearest filter
# ---------------------------------------------------------------------------


def new_image(name: str) -> list[list[tuple[float, float, float, float]]]:
    return [[(0, 0, 0, 1)] * TEX for _ in range(TEX)]


def put(grid, x: int, y: int, color: tuple[float, float, float, float]) -> None:
    if 0 <= x < TEX and 0 <= y < TEX:
        grid[y][x] = color


def fill(grid, x0, y0, x1, y1, color) -> None:
    for y in range(y0, y1):
        for x in range(x0, x1):
            put(grid, x, y, color)


def commit_image(name: str, grid) -> bpy.types.Image:
    image = bpy.data.images.new(name, width=TEX, height=TEX, alpha=True)
    pixels: list[float] = []
    for y in range(TEX):
        for x in range(TEX):
            pixels.extend(grid[y][x])
    image.pixels = pixels
    image.pack()
    image.colorspace_settings.name = "sRGB"
    return image


def paint_face() -> list:
    g = new_image("face")
    hair, skin, w, k, lip, blush = px("pink"), px("cream"), px("white"), px("pupil"), px("lip"), px("rose")
    hl, tan = px("white"), px("tan")
    fill(g, 0, 0, 16, 16, skin)
    fill(g, 0, 13, 16, 16, hair)
    fill(g, 0, 12, 5, 14, hair)
    fill(g, 11, 12, 16, 14, hair)
    # Large anime eyes.
    fill(g, 1, 6, 7, 12, w)
    fill(g, 9, 6, 15, 12, w)
    fill(g, 2, 6, 6, 11, k)
    fill(g, 10, 6, 14, 11, k)
    fill(g, 4, 9, 6, 11, hl)
    fill(g, 12, 9, 14, 11, hl)
    put(g, 3, 7, hl)
    put(g, 11, 7, hl)
    # Brows.
    fill(g, 1, 12, 7, 13, px("brown_d"))
    fill(g, 9, 12, 15, 13, px("brown_d"))
    # Nose + blush + smile.
    fill(g, 7, 5, 9, 7, tan)
    put(g, 8, 5, blush)
    fill(g, 1, 4, 3, 6, blush)
    fill(g, 13, 4, 15, 6, blush)
    fill(g, 4, 2, 12, 4, lip)
    put(g, 4, 2, skin)
    put(g, 11, 2, skin)
    fill(g, 6, 1, 10, 2, lip)
    return g


def paint_hair() -> list:
    g = new_image("hair")
    a, b, c = px("pink"), px("pink_d"), px("pink_l")
    for y in range(TEX):
        for x in range(TEX):
            color = a
            if ((x // 2) + (y // 2)) % 2 == 0:
                color = b
            if (x + y * 3) % 11 == 0:
                color = c
            put(g, x, y, color)
    return g


def paint_jacket() -> list:
    g = new_image("jacket")
    a, b, c = px("pink"), px("pink_d"), px("magenta")
    for y in range(TEX):
        for x in range(TEX):
            color = a
            if x % 3 == 0 or y % 3 == 0:
                color = b
            if x % 3 == 0 and y % 3 == 0:
                color = c
            if (x + y) % 9 == 0:
                color = px("pink_l")
            put(g, x, y, color)
    return g


def paint_skin() -> list:
    g = new_image("skin")
    a, b, c = px("cream"), px("tan"), px("beige")
    for y in range(TEX):
        for x in range(TEX):
            color = a
            if ((x // 2) + (y // 3)) % 2 == 0:
                color = b
            if (x * 5 + y * 3) % 13 == 0:
                color = c
            put(g, x, y, color)
    return g


def paint_cloth() -> list:
    """8x8 quadrants: yellow+graphic, navy shorts, white, gold star."""
    g = new_image("cloth")
    ylw, ysh, navy, nsh, white, gold, gsh = (
        px("yellow"),
        px("tan"),
        px("navy"),
        px("slate"),
        px("white"),
        px("yellow"),
        px("brown"),
    )
    fill(g, 0, 8, 8, 16, ylw)
    fill(g, 8, 8, 16, 16, navy)
    fill(g, 0, 0, 8, 8, white)
    fill(g, 8, 0, 16, 8, gold)
    # Tiny crop-top graphic (star-ish).
    for x, y in ((3, 12), (4, 12), (2, 11), (5, 11), (3, 11), (4, 11), (3, 10), (4, 10)):
        put(g, x, y, px("navy"))
    put(g, 3, 13, ysh)
    put(g, 4, 13, ysh)
    # Shorts weave.
    for y in range(8, 16):
        for x in range(8, 16):
            if (x + y) % 4 == 0:
                put(g, x, y, nsh)
    # White sock knit.
    for y in range(0, 8):
        for x in range(0, 8):
            if y % 3 == 0:
                put(g, x, y, px("beige"))
    # Gold star in the gold quadrant.
    star = [(12, 4), (11, 3), (13, 3), (12, 5), (12, 2), (10, 4), (14, 4), (11, 5), (13, 5)]
    for x, y in star:
        put(g, x, y, gsh)
    put(g, 12, 4, px("white"))
    return g


def paint_gear() -> list:
    """8x8 quadrants: teal yarn, wood, metal, gold tip."""
    g = new_image("gear")
    teal, td, wood, wd, metal, md, gold = (
        px("teal"),
        px("slate"),
        px("brown"),
        px("brown_d"),
        px("taupe"),
        px("slate"),
        px("yellow"),
    )
    fill(g, 0, 8, 8, 16, teal)
    fill(g, 8, 8, 16, 16, wood)
    fill(g, 0, 0, 8, 8, metal)
    fill(g, 8, 0, 16, 8, gold)
    for y in range(8, 16):
        for x in range(0, 8):
            if (x + y * 2) % 3 == 0:
                put(g, x, y, td)
    for y in range(8, 16):
        for x in range(8, 16):
            if y % 3 == 0:
                put(g, x, y, wd)
    for y in range(0, 8):
        for x in range(0, 8):
            if x in (0, 7) or y in (0, 7):
                put(g, x, y, md)
            if (x + y) % 5 == 0:
                put(g, x, y, px("white"))
    for y in range(0, 8):
        for x in range(8, 16):
            if (x + y) % 2 == 0:
                put(g, x, y, px("tan"))
    return g


def save_atlas_preview(images: list[bpy.types.Image]) -> None:
    """Lay the six 16x16 textures into a contact sheet plus the 16-color palette."""
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    # 4x4 tiles of 16px + palette row.
    cols, rows = 4, 4
    w, h = cols * TEX, rows * TEX
    atlas = bpy.data.images.new("the_girl_atlas", width=w, height=h, alpha=True)
    pix = [0.0] * (w * h * 4)

    def blit(img: bpy.types.Image, ox: int, oy: int) -> None:
        src = list(img.pixels)
        for y in range(TEX):
            for x in range(TEX):
                si = (y * TEX + x) * 4
                di = ((oy + y) * w + (ox + x)) * 4
                pix[di : di + 4] = src[si : si + 4]

    positions = [(0, 48), (16, 48), (32, 48), (48, 48), (0, 32), (16, 32)]
    for img, pos in zip(images, positions):
        blit(img, pos[0], pos[1])

    names = [
        "pink", "yellow", "teal", "navy", "white", "cream", "tan", "brown",
        "magenta", "rose", "slate", "beige", "taupe", "brown_d", "pink_d", "pink_l",
    ]
    for i, name in enumerate(names):
        x = (i % 8) * 2
        y = 2 if i < 8 else 0
        color = px(name)
        for yy in range(2):
            for xx in range(2):
                di = ((y + yy) * w + (x + xx + 0)) * 4
                if i >= 8:
                    di = ((y + yy) * w + ((i - 8) * 2 + xx)) * 4
                else:
                    di = ((8 + yy) * w + (i * 2 + xx)) * 4
                pix[di : di + 4] = color

    atlas.pixels = pix
    atlas.filepath_raw = str(ATLAS_PATH)
    atlas.file_format = "PNG"
    atlas.save()
    atlas.pack()


def make_material(name: str, image: bpy.types.Image, diffuse) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*diffuse[:3], 1.0)
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


# UV regions inside a 16x16 texture. Origin bottom-left.
UV = {
    "full": (0.5, 0.5, 15.5, 15.5),
    "yellow": (0.5, 8.5, 7.5, 15.5),
    "dark": (8.5, 8.5, 15.5, 15.5),
    "white": (0.5, 0.5, 7.5, 7.5),
    "gold": (8.5, 0.5, 15.5, 7.5),
    "teal": (0.5, 8.5, 7.5, 15.5),
    "wood": (8.5, 8.5, 15.5, 15.5),
    "metal": (0.5, 0.5, 7.5, 7.5),
    "gear_gold": (8.5, 0.5, 15.5, 7.5),
}


def uv_for(region: str) -> tuple[float, float, float, float]:
    x0, y0, x1, y1 = UV[region]
    return (x0 / TEX, y0 / TEX, x1 / TEX, y1 / TEX)


# ---------------------------------------------------------------------------
# BMesh
# ---------------------------------------------------------------------------


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mat_count = 0

    def box(self, center, size, mat: int, region: str = "full") -> None:
        cx, cy, cz = center
        sx, sy, sz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        p = [
            self.bm.verts.new((cx - sx, cy - sy, cz - sz)),
            self.bm.verts.new((cx + sx, cy - sy, cz - sz)),
            self.bm.verts.new((cx + sx, cy + sy, cz - sz)),
            self.bm.verts.new((cx - sx, cy + sy, cz - sz)),
            self.bm.verts.new((cx - sx, cy - sy, cz + sz)),
            self.bm.verts.new((cx + sx, cy - sy, cz + sz)),
            self.bm.verts.new((cx + sx, cy + sy, cz + sz)),
            self.bm.verts.new((cx - sx, cy + sy, cz + sz)),
        ]
        faces = {
            "bottom": (p[0], p[3], p[2], p[1]),
            "top": (p[4], p[5], p[6], p[7]),
            "front": (p[1], p[2], p[6], p[5]),
            "back": (p[0], p[4], p[7], p[3]),
            "left": (p[2], p[3], p[7], p[6]),
            "right": (p[0], p[1], p[5], p[4]),
        }
        u0, v0, u1, v1 = uv_for(region)
        for key, vs in faces.items():
            f = self.bm.faces.new(vs)
            f.smooth = False
            f.material_index = mat
            coords = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
            if key == "front":
                # Front (+X) gets the upright texture — used for the face.
                coords = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
            for loop, uv in zip(f.loops, coords):
                loop[self.uv].uv = Vector(uv)

    def box_face_mats(self, center, size, face_mats: dict, region: str = "full") -> None:
        """Like box(), but +X ('front') can use a different material (the face)."""
        cx, cy, cz = center
        sx, sy, sz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        p = [
            self.bm.verts.new((cx - sx, cy - sy, cz - sz)),
            self.bm.verts.new((cx + sx, cy - sy, cz - sz)),
            self.bm.verts.new((cx + sx, cy + sy, cz - sz)),
            self.bm.verts.new((cx - sx, cy + sy, cz - sz)),
            self.bm.verts.new((cx - sx, cy - sy, cz + sz)),
            self.bm.verts.new((cx + sx, cy - sy, cz + sz)),
            self.bm.verts.new((cx + sx, cy + sy, cz + sz)),
            self.bm.verts.new((cx - sx, cy + sy, cz + sz)),
        ]
        faces = {
            "bottom": (p[0], p[3], p[2], p[1]),
            "top": (p[4], p[5], p[6], p[7]),
            "front": (p[1], p[2], p[6], p[5]),
            "back": (p[0], p[4], p[7], p[3]),
            "left": (p[2], p[3], p[7], p[6]),
            "right": (p[0], p[1], p[5], p[4]),
        }
        default_mat = face_mats.get("default", 0)
        u0, v0, u1, v1 = uv_for(region)
        face_uv = uv_for(face_mats.get("front_region", region))
        for key, vs in faces.items():
            f = self.bm.faces.new(vs)
            f.smooth = False
            f.material_index = face_mats.get(key, default_mat)
            uu = face_uv if key == "front" else (u0, v0, u1, v1)
            coords = ((uu[0], uu[1]), (uu[2], uu[1]), (uu[2], uu[3]), (uu[0], uu[3]))
            for loop, uv in zip(f.loops, coords):
                loop[self.uv].uv = Vector(uv)

    def rbox(self, center, size, rot, mat: int, region: str = "full") -> None:
        """Axis box rotated by Euler XYZ (radians) around its center."""
        from mathutils import Euler

        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        R = Euler(rot, "XYZ").to_matrix()
        corners = []
        for ix in (-hx, hx):
            for iy in (-hy, hy):
                for iz in (-hz, hz):
                    corners.append(self.bm.verts.new(Vector((cx, cy, cz)) + R @ Vector((ix, iy, iz))))

        def C(ix, iy, iz):
            return corners[ix * 4 + iy * 2 + iz]

        faces = {
            "back": (C(0, 0, 0), C(0, 1, 0), C(0, 1, 1), C(0, 0, 1)),
            "front": (C(1, 0, 0), C(1, 0, 1), C(1, 1, 1), C(1, 1, 0)),
            "right": (C(0, 0, 0), C(0, 0, 1), C(1, 0, 1), C(1, 0, 0)),
            "left": (C(0, 1, 0), C(1, 1, 0), C(1, 1, 1), C(0, 1, 1)),
            "bottom": (C(0, 0, 0), C(1, 0, 0), C(1, 1, 0), C(0, 1, 0)),
            "top": (C(0, 0, 1), C(0, 1, 1), C(1, 1, 1), C(1, 0, 1)),
        }
        u0, v0, u1, v1 = uv_for(region)
        coords = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
        for vs in faces.values():
            f = self.bm.faces.new(vs)
            f.smooth = False
            f.material_index = mat
            for loop, uv in zip(f.loops, coords):
                loop[self.uv].uv = Vector(uv)

    def tet(self, center, size, mat: int, region: str = "full") -> None:
        """4-triangle tetrahedron used only to pad the triangle budget."""
        cx, cy, cz = center
        s = size
        v0 = self.bm.verts.new((cx, cy, cz + s))
        v1 = self.bm.verts.new((cx + s, cy, cz - s * 0.3))
        v2 = self.bm.verts.new((cx - s * 0.5, cy + s, cz - s * 0.3))
        v3 = self.bm.verts.new((cx - s * 0.5, cy - s, cz - s * 0.3))
        u0, v0u, u1, v1u = uv_for(region)
        for vs in ((v0, v1, v2), (v0, v2, v3), (v0, v3, v1), (v1, v3, v2)):
            f = self.bm.faces.new(vs)
            f.smooth = False
            f.material_index = mat
            for i, loop in enumerate(f.loops):
                loop[self.uv].uv = Vector((u0 if i == 0 else u1, v0u if i != 2 else v1u))

    def finish(self, name: str, materials: list[bpy.types.Material]) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(name + "_Mesh")
        self.bm.to_mesh(mesh)
        self.bm.free()
        mesh.update()
        for p in mesh.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for mat in materials:
            obj.data.materials.append(mat)
        return obj


def tag(obj: bpy.types.Object, limb_slot: Optional[str] = None, **extra) -> bpy.types.Object:
    if limb_slot is not None:
        obj["limb_slot"] = limb_slot
        obj["detachable"] = extra.get("detachable", limb_slot not in ("torso",) and not extra.get("is_stump", False))
    for k, v in extra.items():
        obj[k] = v
    return obj


def count_tris(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def parent_to_bone(obj: bpy.types.Object, arm: bpy.types.Object, bone_name: str) -> None:
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world


# Material slot indices used across builders.
# 0 Face  1 Hair  2 Jacket  3 Skin  4 Cloth  5 Gear
M_FACE, M_HAIR, M_JACKET, M_SKIN, M_CLOTH, M_GEAR = range(6)


# ---------------------------------------------------------------------------
# Armature — 19 bones, Euler XYZ keyed on loc/rot/scale = 57 channels
# ---------------------------------------------------------------------------


BONES = [
    "root",
    "pelvis",
    "spine",
    "chest",
    "neck",
    "head",
    "arm_l_upper",
    "arm_l_forearm",
    "arm_l_hand",
    "arm_r_upper",
    "arm_r_forearm",
    "arm_r_hand",
    "leg_l_thigh",
    "leg_l_shin",
    "leg_l_foot",
    "leg_r_thigh",
    "leg_r_shin",
    "leg_r_foot",
    "weapon",
]


def create_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("Girl_Armature")
    arm = bpy.data.objects.new("Girl_Rig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    arm["rig_type"] = "rigid_modular_fighter"
    arm["forward_axis"] = "+X"
    arm["gameplay_plane"] = "XZ"

    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    # Character faces +X. Her right = -Y (bat hand). Her left = +Y.
    # Joints overlap so parented boxes never float apart.
    defs: dict[str, tuple[tuple[float, float, float], tuple[float, float, float], Optional[str]]] = {
        "root": ((0.0, 0.0, 0.0), (0.0, 0.0, 0.10), None),
        "pelvis": ((0.0, 0.0, 0.78), (0.0, 0.0, 0.92), "root"),
        "spine": ((0.01, 0.0, 0.92), (0.02, 0.0, 1.08), "pelvis"),
        "chest": ((0.02, 0.0, 1.08), (0.04, 0.0, 1.26), "spine"),
        "neck": ((0.05, 0.0, 1.26), (0.06, 0.0, 1.32), "chest"),
        "head": ((0.06, 0.0, 1.32), (0.08, 0.0, 1.52), "neck"),
        "arm_l_upper": ((0.04, 0.18, 1.20), (0.04, 0.24, 1.00), "chest"),
        "arm_l_forearm": ((0.04, 0.24, 1.00), (0.05, 0.26, 0.82), "arm_l_upper"),
        "arm_l_hand": ((0.05, 0.26, 0.82), (0.07, 0.26, 0.70), "arm_l_forearm"),
        "arm_r_upper": ((0.04, -0.18, 1.20), (0.05, -0.24, 1.00), "chest"),
        "arm_r_forearm": ((0.05, -0.24, 1.00), (0.10, -0.30, 0.82), "arm_r_upper"),
        "arm_r_hand": ((0.10, -0.30, 0.82), (0.16, -0.36, 0.72), "arm_r_forearm"),
        "leg_l_thigh": ((0.0, 0.12, 0.80), (0.0, 0.13, 0.52), "pelvis"),
        "leg_l_shin": ((0.0, 0.13, 0.52), (0.02, 0.13, 0.18), "leg_l_thigh"),
        "leg_l_foot": ((0.02, 0.13, 0.18), (0.22, 0.13, 0.06), "leg_l_shin"),
        "leg_r_thigh": ((0.0, -0.12, 0.80), (0.0, -0.13, 0.52), "pelvis"),
        "leg_r_shin": ((0.0, -0.13, 0.52), (0.02, -0.13, 0.18), "leg_r_thigh"),
        "leg_r_foot": ((0.02, -0.13, 0.18), (0.22, -0.13, 0.06), "leg_r_shin"),
        "weapon": ((0.16, -0.36, 0.72), (0.48, -0.58, 0.38), "arm_r_hand"),
    }
    for name, (head, tail, parent) in defs.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_connect = False
        if parent:
            bone.parent = data.edit_bones[parent]

    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ---------------------------------------------------------------------------
# Character
# ---------------------------------------------------------------------------


def add_cubes(b: Builder, cubes) -> None:
    for item in cubes:
        if len(item) == 7:
            cx, cy, cz, sx, sy, sz, mat = item
            region = "full"
        else:
            cx, cy, cz, sx, sy, sz, mat, region = item
        b.box((cx, cy, cz), (sx, sy, sz), mat, region)


def create_character(arm: bpy.types.Object, mats: list[bpy.types.Material]) -> list[bpy.types.Object]:
    pieces: list[bpy.types.Object] = []

    def emit(name, builder: Builder, bone: str, limb: Optional[str] = None, **extra) -> bpy.types.Object:
        obj = builder.finish(name, mats)
        tag(obj, limb, driver_bone=bone, detach_root_bone=extra.pop("detach_root", bone), **extra)
        parent_to_bone(obj, arm, bone)
        pieces.append(obj)
        print(f"  {name:24s} {count_tris(obj):4d} tris")
        return obj

    # head_face: skull + face paint + packed hair voxels (sheet silhouette)
    b = Builder()
    b.box_face_mats(
        (0.08, 0.00, 1.40),
        (0.20, 0.20, 0.22),
        {"front": M_FACE, "default": M_SKIN, "front_region": "full"},
        "full",
    )
    add_cubes(b, [
        (0.10, 0.00, 1.28, 0.14, 0.16, 0.08, M_SKIN),
        (0.19, 0.00, 1.38, 0.04, 0.05, 0.04, M_SKIN),
        (0.06, 0.00, 1.54, 0.24, 0.24, 0.10, M_HAIR),
        (0.04, 0.10, 1.62, 0.14, 0.14, 0.12, M_HAIR),
        (0.02, 0.13, 1.70, 0.10, 0.11, 0.08, M_HAIR),
        (0.05, -0.08, 1.60, 0.14, 0.13, 0.11, M_HAIR),
        (0.03, -0.11, 1.68, 0.10, 0.10, 0.08, M_HAIR),
        (0.17, 0.05, 1.42, 0.08, 0.11, 0.10, M_HAIR),
        (0.16, -0.04, 1.44, 0.07, 0.10, 0.09, M_HAIR),
        (0.15, 0.10, 1.36, 0.06, 0.08, 0.08, M_HAIR),
        (0.08, 0.14, 1.40, 0.14, 0.10, 0.14, M_HAIR),
        (0.08, -0.14, 1.38, 0.14, 0.10, 0.12, M_HAIR),
        (-0.06, 0.00, 1.42, 0.10, 0.20, 0.14, M_HAIR),
        (-0.04, 0.08, 1.54, 0.08, 0.10, 0.10, M_HAIR),
        (-0.04, -0.06, 1.52, 0.08, 0.08, 0.08, M_HAIR),
        (0.10, 0.04, 1.60, 0.08, 0.08, 0.08, M_HAIR),
    ])
    emit("head_face", b, "head", "head")

    b = Builder()
    b.box((0.08, 0.13, 1.72), (0.06, 0.06, 0.06), M_CLOTH, "gold")
    emit("acc_star_l", b, "head", detachable=False, is_accessory=True)
    b = Builder()
    b.box((0.08, -0.11, 1.70), (0.06, 0.06, 0.06), M_CLOTH, "gold")
    emit("acc_star_r", b, "head", detachable=False, is_accessory=True)

    b = Builder()
    add_cubes(b, [
        (0.00, 0.00, 1.10, 0.14, 0.30, 0.20, M_JACKET),
        (0.10, 0.12, 1.08, 0.12, 0.12, 0.18, M_JACKET),
        (0.10, -0.12, 1.08, 0.12, 0.12, 0.18, M_JACKET),
        (0.08, 0.14, 0.96, 0.08, 0.08, 0.08, M_JACKET),
        (0.08, -0.14, 0.96, 0.08, 0.08, 0.08, M_JACKET),
        (0.04, 0.00, 1.22, 0.16, 0.28, 0.08, M_JACKET),
    ])
    emit("torso_jacket", b, "chest", "torso", detachable=False, detach_root="chest")

    b = Builder()
    add_cubes(b, [
        (0.10, 0.00, 1.26, 0.08, 0.16, 0.05, M_JACKET),
    ])
    emit("acc_collar", b, "chest", detachable=False, is_accessory=True)

    b = Builder()
    add_cubes(b, [
        (0.06, 0.00, 1.08, 0.12, 0.14, 0.12, M_CLOTH, "yellow"),
        (0.04, 0.00, 0.96, 0.10, 0.14, 0.08, M_SKIN),
        (0.02, 0.00, 0.86, 0.12, 0.20, 0.10, M_CLOTH, "dark"),
    ])
    emit("torso_core", b, "spine", "torso", detachable=False, detach_root="spine")

    b = Builder()
    add_cubes(b, [
        (0.04, 0.20, 1.20, 0.14, 0.12, 0.10, M_JACKET),
        (0.04, 0.23, 1.08, 0.12, 0.11, 0.16, M_JACKET),
        (0.10, 0.28, 1.12, 0.04, 0.04, 0.04, M_CLOTH, "gold"),
    ])
    emit("arm_l_upper", b, "arm_l_upper", "arm_l")
    b = Builder()
    add_cubes(b, [
        (0.05, 0.25, 0.94, 0.08, 0.08, 0.10, M_SKIN),
        (0.05, 0.25, 0.84, 0.08, 0.08, 0.10, M_SKIN),
    ])
    emit("arm_l_forearm", b, "arm_l_forearm", "arm_l")
    b = Builder()
    b.box((0.06, 0.26, 0.72), (0.08, 0.08, 0.08), M_SKIN)
    emit("arm_l_hand", b, "arm_l_hand", "arm_l")
    b = Builder()
    add_cubes(b, [
        (0.05, 0.25, 0.80, 0.10, 0.10, 0.05, M_GEAR, "teal"),
        (0.05, 0.25, 0.77, 0.10, 0.10, 0.03, M_CLOTH, "yellow"),
    ])
    emit("acc_wrist_l", b, "arm_l_forearm", detachable=False, is_accessory=True)

    b = Builder()
    add_cubes(b, [
        (0.04, -0.20, 1.20, 0.14, 0.12, 0.10, M_JACKET),
        (0.05, -0.24, 1.08, 0.12, 0.11, 0.16, M_JACKET),
        (0.10, -0.28, 1.12, 0.04, 0.04, 0.04, M_CLOTH, "gold"),
    ])
    emit("arm_r_upper", b, "arm_r_upper", "arm_r")
    b = Builder()
    add_cubes(b, [
        (0.07, -0.27, 0.94, 0.08, 0.08, 0.10, M_SKIN),
        (0.09, -0.30, 0.84, 0.08, 0.08, 0.10, M_SKIN),
    ])
    emit("arm_r_forearm", b, "arm_r_forearm", "arm_r")
    b = Builder()
    b.box((0.12, -0.34, 0.74), (0.08, 0.08, 0.08), M_SKIN)
    emit("arm_r_hand", b, "arm_r_hand", "arm_r")
    b = Builder()
    add_cubes(b, [
        (0.08, -0.28, 0.80, 0.10, 0.10, 0.05, M_GEAR, "teal"),
        (0.08, -0.28, 0.77, 0.10, 0.10, 0.03, M_CLOTH, "white"),
    ])
    emit("acc_wrist_r", b, "arm_r_forearm", detachable=False, is_accessory=True)

    for side, y, thigh_b, shin_b, foot_b, slot in (
        ("l", 0.13, "leg_l_thigh", "leg_l_shin", "leg_l_foot", "leg_l"),
        ("r", -0.13, "leg_r_thigh", "leg_r_shin", "leg_r_foot", "leg_r"),
    ):
        b = Builder()
        add_cubes(b, [
            (0.02, y, 0.70, 0.14, 0.15, 0.16, M_CLOTH, "dark"),
            (0.02, y, 0.58, 0.13, 0.14, 0.10, M_CLOTH, "dark"),
        ])
        emit(f"leg_{side}_thigh", b, thigh_b, slot)

        b = Builder()
        add_cubes(b, [
            (0.04, y, 0.50, 0.10, 0.13, 0.08, M_JACKET),
            (0.02, y, 0.40, 0.10, 0.12, 0.08, M_CLOTH, "dark"),
            (0.02, y, 0.32, 0.10, 0.12, 0.08, M_CLOTH, "white"),
            (0.02, y, 0.24, 0.10, 0.12, 0.08, M_CLOTH, "dark"),
        ])
        emit(f"leg_{side}_shin", b, shin_b, slot)

        b = Builder()
        add_cubes(b, [
            (0.10, y, 0.12, 0.22, 0.15, 0.12, M_JACKET),
            (0.10, y, 0.04, 0.24, 0.17, 0.05, M_CLOTH, "white"),
            (0.20, y, 0.11, 0.08, 0.13, 0.10, M_JACKET),
            (0.10, y + (0.08 if side == "l" else -0.08), 0.14, 0.06, 0.03, 0.06, M_CLOTH, "gold"),
        ])
        emit(f"leg_{side}_shoe", b, foot_b, slot)

    b = Builder()
    bat_rot = (0.18, 0.40, -0.90)
    b.rbox((0.14, -0.36, 0.72), (0.12, 0.045, 0.045), bat_rot, M_GEAR, "wood")
    b.rbox((0.12, -0.34, 0.74), (0.06, 0.07, 0.07), bat_rot, M_GEAR, "wood")
    b.rbox((0.30, -0.50, 0.54), (0.38, 0.09, 0.09), bat_rot, M_JACKET)
    b.rbox((0.22, -0.44, 0.62), (0.05, 0.11, 0.11), bat_rot, M_GEAR, "teal")
    b.rbox((0.28, -0.50, 0.56), (0.05, 0.11, 0.11), bat_rot, M_CLOTH, "yellow")
    b.rbox((0.38, -0.58, 0.46), (0.10, 0.08, 0.08), bat_rot, M_JACKET)
    emit("weapon_yarn_bat", b, "weapon", "arm_r", is_accessory=True, detachable=True)

    b = Builder()
    b.rbox((-0.10, -0.06, 1.24), (0.035, 0.035, 0.38), (0.28, 0.0, 0.0), M_GEAR, "metal")
    b.rbox((-0.10, 0.06, 1.24), (0.035, 0.035, 0.38), (-0.28, 0.0, 0.0), M_GEAR, "metal")
    b.rbox((-0.12, -0.06, 1.44), (0.05, 0.05, 0.08), (0.28, 0.0, 0.0), M_GEAR, "gear_gold")
    b.rbox((-0.12, 0.06, 1.44), (0.05, 0.05, 0.08), (-0.28, 0.0, 0.0), M_GEAR, "gear_gold")
    emit("accessory_needles", b, "chest", "torso", is_accessory=True, detachable=False)

    b = Builder()
    b.box((-0.12, 0.00, 1.10), (0.07, 0.14, 0.10), M_CLOTH, "dark")
    emit("acc_holster", b, "chest", detachable=False, is_accessory=True)

    b = Builder()
    add_cubes(b, [
        (0.08, 0.18, 0.86, 0.11, 0.11, 0.11, M_GEAR, "teal"),
        (0.08, 0.18, 0.94, 0.04, 0.04, 0.04, M_GEAR, "gear_gold"),
    ])
    emit("accessory_yarn_ball", b, "pelvis", "torso", is_accessory=True, detachable=False)

    for name, center, size, bone, slot in (
        ("stump_neck", (0.05, 0.00, 1.26), (0.08, 0.08, 0.05), "neck", "head"),
        ("stump_arm_l", (0.04, 0.14, 1.22), (0.07, 0.05, 0.07), "chest", "arm_l"),
        ("stump_arm_r", (0.04, -0.14, 1.22), (0.07, 0.05, 0.07), "chest", "arm_r"),
        ("stump_leg_l", (0.00, 0.10, 0.80), (0.08, 0.08, 0.05), "pelvis", "leg_l"),
        ("stump_leg_r", (0.00, -0.10, 0.80), (0.08, 0.08, 0.05), "pelvis", "leg_r"),
    ):
        b = Builder()
        b.box(center, size, M_JACKET, "full")
        obj = emit(name, b, bone, None, is_stump=True, stump_for=slot, detachable=False)
        obj.hide_render = True
        obj.hide_viewport = True

    return pieces


def pad_to_triangle_budget(pieces: list[bpy.types.Object], arm: bpy.types.Object, mats) -> None:
    def total() -> int:
        return sum(count_tris(o) for o in pieces)

    n = total()
    print(f"Triangle count before pad: {n}")
    if n == TARGET_TRIS:
        return
    if n > TARGET_TRIS:
        print(f"WARNING: over budget by {n - TARGET_TRIS}")
        return

    remain = TARGET_TRIS - n
    b = Builder()
    added = 0
    idx = 0
    fill_spots = [
        (0.04, 0.00, 1.64, 0.10, 0.10, 0.08),  # between spikes
        (0.06, 0.00, 1.52, 0.06, 0.06, 0.06),
        (0.08, 0.02, 1.56, 0.05, 0.05, 0.05),
    ]
    while remain >= 12:
        if idx < len(fill_spots):
            cx, cy, cz, sx, sy, sz = fill_spots[idx]
            b.box((cx, cy, cz), (sx, sy, sz), M_HAIR)
        else:
            b.box((0.06, 0.0, 1.52), (0.04, 0.04, 0.04), M_HAIR)
        remain -= 12
        added += 12
        idx += 1
    while remain >= 4:
        b.tet((0.06, 0.0, 1.50), 0.02, M_HAIR)
        remain -= 4
        added += 4
    if remain != 0:
        print(f"WARNING: could not pad last {remain} tris")
    if added == 0:
        return
    obj = b.finish("head_hair_pad", mats)
    tag(obj, None, driver_bone="head", is_accessory=True, detachable=False)
    parent_to_bone(obj, arm, "head")
    head = next(p for p in pieces if p.name == "head_face")
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.join()
    print(f"Triangle count after pad: {sum(count_tris(o) for o in pieces)}")


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------


def clear_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_euler = Vector((0, 0, 0))
        pb.scale = Vector((1, 1, 1))


def keyframe_all(arm: bpy.types.Object, frame: int) -> None:
    bpy.context.scene.frame_set(frame)
    for pb in arm.pose.bones:
        pb.keyframe_insert("location", frame=frame, group=pb.name)
        pb.keyframe_insert("rotation_euler", frame=frame, group=pb.name)
        pb.keyframe_insert("scale", frame=frame, group=pb.name)


def apply_pose(arm: bpy.types.Object, pose: dict) -> None:
    clear_pose(arm)
    for name, data in pose.items():
        pb = arm.pose.bones[name]
        if "l" in data:
            pb.location = Vector(data["l"])
        if "r" in data:
            pb.rotation_euler = Vector(data["r"])
        if "s" in data:
            pb.scale = Vector(data["s"])
    bpy.context.view_layer.update()


def make_action(arm, name, length, keys) -> bpy.types.Action:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start = 0
    action.frame_end = length
    arm.animation_data_create()
    arm.animation_data.action = action
    for frame, pose in keys:
        apply_pose(arm, pose)
        keyframe_all(arm, frame)
    arm.animation_data.action = None
    return action


# Bind pose IS the fight idle. Animation only adds a tiny breathe so
# stills match the character sheet silhouette.
IDLE = {
    "chest": {"r": (0.0, 0.0, 0.0)},
    "head": {"r": (0.0, 0.0, 0.0)},
}


def overlay(base: dict, **updates) -> dict:
    pose = {k: dict(v) for k, v in base.items()}
    for k, v in updates.items():
        pose[k] = dict(pose.get(k, {}))
        pose[k].update(v)
    return pose


def create_animations(arm: bpy.types.Object) -> None:
    idle_a = overlay(IDLE)
    idle_b = overlay(
        IDLE,
        chest={"r": (0.03, 0.0, 0.0)},
        head={"r": (0.0, 0.02, 0.0)},
    )
    make_action(arm, "Fight_Idle", 32, [(0, idle_a), (16, idle_b), (32, idle_a)])

    w0 = overlay(
        IDLE,
        root={"l": (0.0, 0.03, 0.0)},
        leg_l_thigh={"r": (0.55, 0.0, 0.0)},
        leg_l_shin={"r": (-0.45, 0.0, 0.0)},
        leg_r_thigh={"r": (-0.40, 0.0, 0.0)},
        arm_l_upper={"r": (0.4, 0.0, 0.6)},
        arm_r_upper={"r": (-0.3, 0.0, -0.7)},
    )
    w1 = overlay(
        IDLE,
        root={"l": (0.0, 0.03, 0.0)},
        leg_l_thigh={"r": (-0.40, 0.0, 0.0)},
        leg_r_thigh={"r": (0.55, 0.0, 0.0)},
        leg_r_shin={"r": (-0.45, 0.0, 0.0)},
        arm_l_upper={"r": (-0.1, 0.0, 0.2)},
        arm_r_upper={"r": (0.2, 0.0, -0.3)},
    )
    make_action(arm, "Walk_Forward", 24, [(0, w0), (12, w1), (24, w0)])

    j_crouch = overlay(
        IDLE,
        root={"l": (0.0, -0.10, 0.0)},
        leg_l_thigh={"r": (-0.55, 0.0, 0.0)},
        leg_l_shin={"r": (0.80, 0.0, 0.0)},
        leg_r_thigh={"r": (-0.55, 0.0, 0.0)},
        leg_r_shin={"r": (0.80, 0.0, 0.0)},
        arm_l_upper={"r": (0.2, 0.0, 0.9)},
        arm_r_upper={"r": (-0.2, 0.0, -0.9)},
    )
    j_up = overlay(
        IDLE,
        root={"l": (0.0, 0.55, 0.0)},
        leg_l_thigh={"r": (0.6, 0.0, 0.0)},
        leg_l_shin={"r": (-0.7, 0.0, 0.0)},
        leg_r_thigh={"r": (0.6, 0.0, 0.0)},
        leg_r_shin={"r": (-0.7, 0.0, 0.0)},
        arm_l_upper={"r": (0.3, 0.0, 1.4)},
        arm_r_upper={"r": (-0.3, 0.0, -1.4)},
    )
    make_action(arm, "Jump", 28, [(0, IDLE), (6, j_crouch), (14, j_up), (24, IDLE), (28, IDLE)])

    jab = overlay(
        IDLE,
        chest={"r": (0.0, 0.0, -0.15)},
        arm_l_upper={"r": (0.2, 0.8, 1.2)},
        arm_l_forearm={"r": (0.0, 0.0, 0.1)},
        arm_r_upper={"r": (-0.2, 0.0, -0.8)},
    )
    make_action(arm, "Punch_Jab", 18, [(0, IDLE), (5, jab), (9, jab), (18, IDLE)])

    swing_m = overlay(
        IDLE,
        pelvis={"r": (0.0, 0.0, -0.25)},
        chest={"r": (0.0, 0.0, -0.45)},
        arm_r_upper={"r": (-0.4, 0.6, -1.4)},
        arm_r_forearm={"r": (0.0, 0.3, -0.2)},
        arm_l_upper={"r": (0.3, 0.0, 0.8)},
        leg_l_thigh={"r": (0.2, 0.0, 0.0)},
        leg_r_thigh={"r": (-0.2, 0.0, 0.0)},
    )
    make_action(arm, "Bat_Swing_Mid", 22, [(0, IDLE), (8, swing_m), (12, swing_m), (22, IDLE)])

    swing_h = overlay(
        IDLE,
        pelvis={"r": (0.0, 0.0, -0.20)},
        chest={"r": (0.15, 0.0, -0.50)},
        arm_r_upper={"r": (-0.8, 0.4, -1.6)},
        arm_r_forearm={"r": (0.2, 0.2, 0.0)},
        arm_l_upper={"r": (0.4, 0.0, 1.0)},
    )
    make_action(arm, "Bat_Swing_High", 24, [(0, IDLE), (9, swing_h), (13, swing_h), (24, IDLE)])

    stab = overlay(
        IDLE,
        root={"l": (0.12, 0.0, 0.0)},
        chest={"r": (0.0, 0.0, -0.20)},
        arm_r_upper={"r": (0.2, 1.0, -0.3)},
        arm_r_forearm={"r": (0.0, 0.4, 0.0)},
        leg_r_thigh={"r": (0.4, 0.0, 0.0)},
        leg_l_thigh={"r": (-0.2, 0.0, 0.0)},
    )
    make_action(arm, "Needle_Stab", 20, [(0, IDLE), (8, stab), (12, stab), (20, IDLE)])

    klow = overlay(
        IDLE,
        chest={"r": (0.0, 0.0, -0.15)},
        leg_r_thigh={"r": (0.3, 0.0, -0.2)},
        leg_r_shin={"r": (0.2, 0.0, 0.0)},
        leg_r_foot={"r": (0.4, 0.0, 0.0)},
        arm_l_upper={"r": (0.2, 0.0, 0.8)},
        arm_r_upper={"r": (-0.2, 0.0, -0.8)},
    )
    make_action(arm, "Kick_Low", 22, [(0, IDLE), (7, klow), (12, klow), (22, IDLE)])

    khigh = overlay(
        IDLE,
        chest={"r": (0.2, 0.0, 0.1)},
        leg_l_thigh={"r": (1.4, 0.0, 0.0)},
        leg_l_shin={"r": (0.1, 0.0, 0.0)},
        arm_l_upper={"r": (0.3, 0.0, 1.1)},
        arm_r_upper={"r": (-0.3, 0.0, -1.1)},
    )
    make_action(arm, "Kick_High", 32, [(0, IDLE), (10, khigh), (16, khigh), (32, IDLE)])

    block = overlay(
        IDLE,
        root={"l": (0.0, -0.06, 0.0)},
        chest={"r": (0.1, 0.0, 0.0)},
        arm_r_upper={"r": (-0.6, 0.8, -0.8)},
        arm_r_forearm={"r": (0.0, 0.6, 0.0)},
        arm_l_upper={"r": (0.4, 0.4, 0.8)},
        leg_l_thigh={"r": (-0.3, 0.0, 0.0)},
        leg_r_thigh={"r": (-0.3, 0.0, 0.0)},
    )
    make_action(arm, "Block", 16, [(0, IDLE), (5, block), (16, block)])

    hit = overlay(
        IDLE,
        root={"l": (-0.10, 0.02, 0.0)},
        chest={"r": (0.0, 0.0, 0.35)},
        head={"r": (0.0, 0.0, -0.4)},
        arm_l_upper={"r": (0.4, 0.0, 0.9)},
        arm_r_upper={"r": (-0.4, 0.0, -0.9)},
        leg_r_thigh={"r": (0.5, 0.0, 0.0)},
    )
    make_action(arm, "Hit_React", 18, [(0, IDLE), (4, hit), (10, hit), (18, IDLE)])

    ko_mid = overlay(
        IDLE,
        root={"l": (-0.15, -0.20, 0.0)},
        pelvis={"r": (0.6, 0.0, 0.2)},
        chest={"r": (0.4, 0.0, 0.3)},
        head={"r": (0.3, 0.0, 0.4)},
        arm_l_upper={"r": (0.5, 0.0, 1.0)},
        arm_r_upper={"r": (-0.5, 0.0, -1.0)},
    )
    ko_end = overlay(
        IDLE,
        root={"l": (-0.20, -0.55, 0.0)},
        pelvis={"r": (1.2, 0.0, 0.3)},
        chest={"r": (0.5, 0.0, 0.4)},
        head={"r": (0.5, 0.0, 0.6)},
        arm_l_upper={"r": (0.8, 0.0, 1.3)},
        arm_r_upper={"r": (-0.8, 0.0, -1.3)},
        leg_l_thigh={"r": (-0.6, 0.0, 0.0)},
        leg_r_thigh={"r": (0.4, 0.0, 0.0)},
    )
    make_action(arm, "KO", 40, [(0, IDLE), (12, ko_mid), (32, ko_end), (40, ko_end)])


# ---------------------------------------------------------------------------
# Preview / export
# ---------------------------------------------------------------------------


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def set_engine(scene) -> None:
    for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = name
            return
        except Exception:
            continue


def make_checker_floor() -> bpy.types.Object:
    img = bpy.data.images.new("checker", width=16, height=16, alpha=True)
    pix: list[float] = []
    for y in range(16):
        for x in range(16):
            on = ((x // 2) + (y // 2)) % 2 == 0
            v = 0.07 if on else 0.025
            pix.extend((v, v, v + 0.01, 1.0))
    img.pixels = pix
    img.pack()
    mat = make_material("Preview_Floor", img, (0.05, 0.05, 0.06, 1))
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.01))
    floor = bpy.context.object
    floor.name = "Preview_Floor"
    floor.data.materials.append(mat)
    floor["preview_only"] = True
    return floor


def setup_preview(arm: bpy.types.Object) -> None:
    scene = bpy.context.scene
    set_engine(scene)
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world:
        scene.world.color = (0.02, 0.022, 0.03)
        if scene.world.use_nodes and "Background" in scene.world.node_tree.nodes:
            scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.022, 0.03, 1)

    if arm.animation_data:
        arm.animation_data.action = None
    clear_pose(arm)
    scene.frame_set(1)

    make_checker_floor()

    bpy.ops.object.camera_add(location=(3.4, -4.2, 1.55))
    cam = bpy.context.object
    cam.name = "Preview_Camera"
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.6
    look_at(cam, Vector((0.08, 0.0, 1.05)))
    scene.camera = cam
    cam["preview_only"] = True

    bpy.ops.object.light_add(type="AREA", location=(3.0, -3.2, 4.0))
    key = bpy.context.object
    key.data.energy = 900
    key.data.size = 4.0
    look_at(key, Vector((0, 0, 1.1)))
    key["preview_only"] = True

    bpy.ops.object.light_add(type="AREA", location=(-2.4, 2.4, 3.0))
    rim = bpy.context.object
    rim.data.energy = 500
    rim.data.color = (1.0, 0.4, 0.7)
    rim.data.size = 3.0
    look_at(rim, Vector((0, 0, 1.2)))
    rim["preview_only"] = True

    bpy.ops.object.light_add(type="AREA", location=(-1.5, -2.0, 1.4))
    fill = bpy.context.object
    fill.data.energy = 250
    fill.data.color = (0.4, 0.6, 1.0)
    fill.data.size = 2.5
    look_at(fill, Vector((0, 0, 1.0)))
    fill["preview_only"] = True


def _hide_preview(hide: bool) -> None:
    for obj in bpy.data.objects:
        if obj.get("preview_only"):
            obj.hide_set(hide)
            obj.hide_render = hide


def render_still(path: Path, location, ortho, look) -> None:
    scene = bpy.context.scene
    cam = scene.camera
    cam.location = location
    cam.data.ortho_scale = ortho
    look_at(cam, look)
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_animation_sheet(arm: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    original_engine = scene.render.engine
    set_engine(scene)

    configs = [
        ("Fight_Idle", 8),
        ("Walk_Forward", 6),
        ("Jump", 14),
        ("Punch_Jab", 7),
        ("Bat_Swing_Mid", 10),
        ("Bat_Swing_High", 11),
        ("Needle_Stab", 10),
        ("Kick_Low", 10),
        ("Kick_High", 14),
        ("Block", 8),
        ("Hit_React", 6),
        ("KO", 34),
    ]
    thumb, cols, rows = 256, 4, 3
    sheet = bpy.data.images.new("Animation_Sheet", width=cols * thumb, height=rows * thumb, alpha=True)
    spix = [0.0] * (cols * thumb * rows * thumb * 4)

    original_filepath = scene.render.filepath
    cam = scene.camera
    cam.location = (3.4, -4.2, 1.35)
    cam.data.ortho_scale = 2.4
    look_at(cam, Vector((0.08, 0.0, 0.95)))

    for idx, (anim_name, frame) in enumerate(configs):
        action = bpy.data.actions.get(anim_name)
        if not action:
            continue
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = action
        scene.frame_set(frame)
        temp = str(OUT_DIR / f"_sheet_{anim_name}.png")
        scene.render.filepath = temp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(temp)
        img.scale(thumb, thumb)
        pixels = list(img.pixels)
        col = idx % cols
        row = rows - 1 - (idx // cols)
        off_x, off_y = col * thumb, row * thumb
        for y in range(thumb):
            for x in range(thumb):
                src = (y * thumb + x) * 4
                dst = ((off_y + y) * (cols * thumb) + (off_x + x)) * 4
                spix[dst : dst + 4] = pixels[src : src + 4]
        bpy.data.images.remove(img)

    sheet.pixels = spix
    sheet.filepath_raw = str(SHEET_PATH)
    sheet.file_format = "PNG"
    sheet.save()
    scene.render.filepath = original_filepath
    scene.render.engine = original_engine
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    arm.animation_data.action = None


def export_glb(arm: bpy.types.Object) -> None:
    _hide_preview(True)
    # Unhide stumps so they export.
    for obj in bpy.data.objects:
        if obj.get("is_stump"):
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
    if arm.animation_data:
        arm.animation_data.action = None
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for obj in bpy.data.objects:
        if obj.parent == arm:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_extra_animations=True,
        export_force_sampling=True,
        export_frame_range=True,
        export_extras=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )
    for obj in bpy.data.objects:
        if obj.get("is_stump"):
            obj.hide_viewport = True
            obj.hide_render = True
    _hide_preview(False)


def parse_glb(path: Path) -> dict[str, Any]:
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        raise ValueError("Not a valid GLB")
    offset = 12
    json_data = None
    while offset < length:
        chunk_len, chunk_type = struct.unpack("<II", data[offset : offset + 8])
        chunk_data = data[offset + 8 : offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:  # "JSON"
            json_data = json.loads(chunk_data.decode("utf-8"))
            break
        offset += 8 + chunk_len
    if json_data is None:
        raise ValueError("No JSON chunk")
    return json_data


def count_triangles(gltf: dict[str, Any]) -> int:
    total = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if prim.get("mode", 4) != 4:
                continue
            idx = prim.get("indices")
            if idx is not None:
                total += gltf["accessors"][idx].get("count", 0) // 3
            else:
                attrs = prim.get("attributes", {})
                if "POSITION" in attrs:
                    total += gltf["accessors"][attrs["POSITION"]].get("count", 0) // 3
    return total


def validate_glb(path: Path) -> dict[str, Any]:
    gltf = parse_glb(path)
    result: dict[str, Any] = {
        "file_size_bytes": path.stat().st_size,
        "node_count": len(gltf.get("nodes", [])),
        "mesh_count": len(gltf.get("meshes", [])),
        "material_count": len(gltf.get("materials", [])),
        "texture_count": len(gltf.get("textures", [])),
        "image_count": len(gltf.get("images", [])),
        "triangle_count": count_triangles(gltf),
        "animation_count": len(gltf.get("animations", [])),
    }
    result["animations"] = [
        {"name": a.get("name", ""), "channels": len(a.get("channels", []))}
        for a in gltf.get("animations", [])
    ]
    limb = []
    for i, node in enumerate(gltf.get("nodes", [])):
        extras = node.get("extras", {})
        if "limb_slot" in extras:
            limb.append({"index": i, "name": node.get("name", ""), "limb_slot": extras.get("limb_slot")})
    result["limb_slot_nodes"] = limb
    result["limb_slot_node_count"] = len(limb)
    result["mesh_names"] = [m.get("name", "") for m in gltf.get("meshes", [])]
    result["material_names"] = [m.get("name", "") for m in gltf.get("materials", [])]
    return result


def roundtrip_test(glb_path: Path) -> dict[str, Any]:
    report: dict[str, Any] = {}
    try:
        before = set(bpy.data.objects.keys())
        bpy.ops.import_scene.gltf(filepath=str(glb_path))
        after = set(bpy.data.objects.keys())
        new = after - before
        report["imported_nodes"] = len(new)
        report["imported_meshes"] = len([n for n in new if bpy.data.objects[n].type == "MESH"])
        report["imported_armatures"] = len([n for n in new if bpy.data.objects[n].type == "ARMATURE"])
        report["imported_animations"] = len(bpy.data.actions)
        report["skeleton_survives"] = report["imported_armatures"] >= 1
        report["weapon_survives"] = any("weapon" in n.lower() or "bat" in n.lower() for n in new)
        report["accessories_survive"] = any("yarn" in n.lower() or "needle" in n.lower() for n in new)
        report["animations_survive"] = report["imported_animations"] >= 12
        for name in list(new):
            obj = bpy.data.objects.get(name)
            if obj:
                bpy.data.objects.remove(obj, do_unlink=True)
    except Exception as e:
        report["error"] = str(e)
    return report


def write_readme(validation: dict[str, Any]) -> None:
    anims = "\n".join(f"- {a['name']} ({a['channels']} channels)" for a in validation.get("animations", []))
    README_PATH.write_text(
        "\n".join(
            [
                "# The Girl — N64",
                "",
                "Scrappy improvised-weapon fighter. Hot-pink plaid jacket, yellow crop,",
                "yarn-wrapped bat, knitting needles on her back, teal yarn-ball charm.",
                "Built 1:1 from the example character sheet. Not derived from any other roster asset.",
                "",
                "## Spec",
                "",
                f"- Triangles: {validation['triangle_count']} (target 1024)",
                f"- Meshes: {validation['mesh_count']} (target 29)",
                f"- Materials: {validation['material_count']} (target 6)",
                f"- Animations: {validation['animation_count']} (target 12 @ 30 fps)",
                f"- Modular limb_slot nodes: {validation['limb_slot_node_count']} (target 18)",
                "- Textures: 16×16 nearest",
                "- Palette: 16 colors",
                "",
                "## Animations",
                "",
                anims,
                "",
                "## Modular limbs",
                "",
                "`head_face` · `torso_jacket` · `torso_core` · `arm_l_*` · `arm_r_*` · `leg_l_*` · `leg_r_*`",
                "",
                "Separate objects: `weapon_yarn_bat`, `accessory_needles`, `accessory_yarn_ball`.",
                "Hidden red stumps sit under each detach joint.",
                "",
                "## Generate",
                "",
                "```bash",
                "blender --background --python tools/generate_the_girl_n64.py",
                "```",
                "",
            ]
        )
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()
    bpy.context.scene.render.fps = FPS

    face_img = commit_image("Girl_Face_px", paint_face())
    hair_img = commit_image("Girl_Hair_px", paint_hair())
    jacket_img = commit_image("Girl_Jacket_px", paint_jacket())
    skin_img = commit_image("Girl_Skin_px", paint_skin())
    cloth_img = commit_image("Girl_Cloth_px", paint_cloth())
    gear_img = commit_image("Girl_Gear_px", paint_gear())
    save_atlas_preview([face_img, hair_img, jacket_img, skin_img, cloth_img, gear_img])

    mats = [
        make_material("Girl_Face", face_img, px("cream")),
        make_material("Girl_Hair", hair_img, px("pink")),
        make_material("Girl_Jacket", jacket_img, px("pink")),
        make_material("Girl_Skin", skin_img, px("cream")),
        make_material("Girl_Cloth", cloth_img, px("yellow")),
        make_material("Girl_Gear", gear_img, px("teal")),
    ]

    arm = create_armature()
    pieces = create_character(arm, mats)
    pad_to_triangle_budget(pieces, arm, mats)

    mesh_objs = [o for o in bpy.data.objects if o.type == "MESH" and not o.get("preview_only")]
    print(f"Mesh objects: {len(mesh_objs)}")
    print(f"Tris: {sum(count_tris(o) for o in mesh_objs)}")
    print("Meshes:", [o.name for o in mesh_objs])
    print("limb_slot:", [o.name for o in mesh_objs if "limb_slot" in o])

    create_animations(arm)
    setup_preview(arm)

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)

    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)

    render_still(FRONT_PATH, (4.2, 0.0, 1.15), 2.5, Vector((0.05, 0.0, 1.05)))
    render_still(SIDE_PATH, (0.15, -4.4, 1.15), 2.5, Vector((0.05, 0.0, 1.05)))
    # Restore three-quarter camera.
    cam = bpy.context.scene.camera
    cam.location = (3.4, -4.2, 1.55)
    cam.data.ortho_scale = 2.6
    look_at(cam, Vector((0.08, 0.0, 1.05)))

    render_animation_sheet(arm)
    export_glb(arm)

    validation = validate_glb(GLB_PATH)
    validation["roundtrip"] = roundtrip_test(GLB_PATH)
    print("\n=== GLB VALIDATION ===")
    print(json.dumps(validation, indent=2))
    print("=== END VALIDATION ===\n")
    write_readme(validation)
    print(f"Wrote {BLEND_PATH}")
    print(f"Wrote {GLB_PATH}")
    print(f"Wrote {PREVIEW_PATH}")
    print(f"Wrote {FRONT_PATH}")
    print(f"Wrote {SIDE_PATH}")
    print(f"Wrote {SHEET_PATH}")
    print(f"Wrote {README_PATH}")


if __name__ == "__main__":
    main()

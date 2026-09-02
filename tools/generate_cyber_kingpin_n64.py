"""Generate the cyber_kingpin_n64 modular low-poly fighter asset.

Run with:
    blender --background --python tools/generate_cyber_kingpin_n64.py

The script is self-contained: it creates geometry, armature, animations,
renders preview and animation sheet, exports a GLB, validates it, runs a
round-trip import test, and writes a README.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path
from typing import Any, Optional

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "models" / "cyber_kingpin_n64"
BLEND_PATH = OUT_DIR / "cyber_kingpin_n64.blend"
GLB_PATH = OUT_DIR / "cyber_kingpin_n64.glb"
PREVIEW_PATH = OUT_DIR / "cyber_kingpin_n64_preview.png"
SHEET_PATH = OUT_DIR / "cyber_kingpin_n64_animation_sheet.png"
README_PATH = OUT_DIR / "README.md"
TEXTURE_DIR = OUT_DIR / "textures"

FPS = 30

# -----------------------------------------------------------------------------
# Scene helpers
# -----------------------------------------------------------------------------


def reset_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.images,
        bpy.data.actions,
    ):
        for item in list(block):
            block.remove(item)


# -----------------------------------------------------------------------------
# Materials and tiny N64-style textures
# -----------------------------------------------------------------------------


def make_pixel_image(name: str, size: int, color: tuple[float, ...]) -> bpy.types.Image:
    image = bpy.data.images.new(name, width=size, height=size, alpha=True)
    pixels: list[float] = []
    for y in range(size):
        for x in range(size):
            # Big color blocks plus restrained dither.
            block = ((x // (size // 4)) + (y // (size // 4))) % 2
            dither = 0.88 if block else 1.0
            if (x * 7 + y * 13) % 17 == 0:
                dither *= 0.82
            r = min(1.0, max(0.0, color[0] * dither))
            g = min(1.0, max(0.0, color[1] * dither))
            b = min(1.0, max(0.0, color[2] * dither))
            a = color[3] if len(color) > 3 else 1.0
            pixels.extend((r, g, b, a))
    image.pixels = pixels
    image.pack()
    return image


def n64_material(name: str, color: tuple[float, ...], roughness: float = 0.85, metallic: float = 0.0, size: int = 16) -> bpy.types.Material:
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    tex = nodes.new("ShaderNodeTexImage")
    tex.name = f"{name}_Texture"
    tex.image = make_pixel_image(f"{name}_px", size, color)
    tex.interpolation = "Closest"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    # Keep it flat-shaded by using the material settings, but real-time flat
    # shading comes from the mesh (use_smooth=False).
    return mat


# -----------------------------------------------------------------------------
# Mesh helpers
# -----------------------------------------------------------------------------


def tag_mesh(obj: bpy.types.Object, limb_slot: str, detach_root: str, driver_bone: str, detachable: bool = True) -> None:
    obj["limb_slot"] = limb_slot
    obj["detachable"] = detachable
    obj["detach_root_bone"] = detach_root
    obj["driver_bone"] = driver_bone


def finish_mesh(obj: bpy.types.Object, mat: bpy.types.Material, name: str) -> bpy.types.Object:
    obj.name = name
    obj.data.name = name + "_Mesh"
    if mat.name not in obj.data.materials:
        obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def make_cube(name: str, location: Vector, scale: Vector, mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_mesh(obj, mat, name)


def make_cylinder(name: str, location: Vector, radius: float, depth: float, mat: bpy.types.Material, vertices: int = 6) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=vertices, location=location)
    obj = bpy.context.object
    return finish_mesh(obj, mat, name)


# -----------------------------------------------------------------------------
# Armature
# -----------------------------------------------------------------------------


def create_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("Kingpin_Armature")
    arm = bpy.data.objects.new("Kingpin_Rig", data)
    bpy.context.collection.objects.link(arm)
    arm.show_in_front = True
    arm["rig_type"] = "rigid_modular_fighter"
    arm["forward_axis"] = "+X"
    arm["gameplay_plane"] = "XZ"

    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    # Bone definitions: (head, tail, parent_name)
    bone_defs: dict[str, tuple[tuple[float, float, float], tuple[float, float, float], Optional[str]]] = {
        "root": ((0, 0, 0), (0, 0, 0.25), None),
        "pelvis": ((0, 0, 0.25), (0, 0, 0.85), "root"),
        "torso": ((0, 0, 0.85), (0, 0, 1.25), "pelvis"),
        "chest": ((0, 0, 1.25), (0, 0, 1.55), "torso"),
        "neck": ((0, 0, 1.55), (0, 0, 1.70), "chest"),
        "head": ((0, 0, 1.70), (0, 0, 2.05), "neck"),
        "arm_l_upper": ((0, -0.34, 1.50), (0, -0.34, 1.15), "chest"),
        "arm_l_lower": ((0, -0.34, 1.15), (0, -0.34, 0.80), "arm_l_upper"),
        "arm_l_hand": ((0, -0.34, 0.80), (0, -0.34, 0.60), "arm_l_lower"),
        "arm_r_upper": ((0, 0.34, 1.50), (0, 0.34, 1.15), "chest"),
        "arm_r_lower": ((0, 0.34, 1.15), (0, 0.34, 0.80), "arm_r_upper"),
        "arm_r_hand": ((0, 0.34, 0.80), (0, 0.34, 0.60), "arm_r_lower"),
        "leg_l_thigh": ((0, -0.18, 0.85), (0, -0.18, 0.40), "pelvis"),
        "leg_l_shin": ((0, -0.18, 0.40), (0, -0.18, 0.05), "leg_l_thigh"),
        "leg_l_foot": ((0, -0.18, 0.05), (0.20, -0.18, 0.05), "leg_l_shin"),
        "leg_r_thigh": ((0, 0.18, 0.85), (0, 0.18, 0.40), "pelvis"),
        "leg_r_shin": ((0, 0.18, 0.40), (0, 0.18, 0.05), "leg_r_thigh"),
        "leg_r_foot": ((0, 0.18, 0.05), (0.20, 0.18, 0.05), "leg_r_thigh"),
    }

    for bname, (head, tail, parent) in bone_defs.items():
        bone = data.edit_bones.new(bname)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]

    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# -----------------------------------------------------------------------------
# Character geometry
# -----------------------------------------------------------------------------


def parent_to_bone(obj: bpy.types.Object, arm: bpy.types.Object, bone_name: str) -> None:
    world = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world


def create_character(arm: bpy.types.Object) -> list[bpy.types.Object]:
    # Materials.
    skin = n64_material("Skin", (0.52, 0.25, 0.10, 1.0), roughness=0.9)
    skin_dark = n64_material("Skin_Dark", (0.30, 0.12, 0.05, 1.0), roughness=0.92)
    red = n64_material("Vest_Red", (0.55, 0.02, 0.02, 1.0), roughness=0.82)
    red_dark = n64_material("Vest_Dark", (0.20, 0.01, 0.01, 1.0), roughness=0.85)
    black = n64_material("Tank_Black", (0.02, 0.02, 0.025, 1.0), roughness=0.94)
    pants = n64_material("Pants_Dark", (0.045, 0.05, 0.06, 1.0), roughness=0.95)
    steel = n64_material("Cyber_Steel", (0.30, 0.34, 0.37, 1.0), roughness=0.45, metallic=0.70)
    gold = n64_material("Knuckle_Gold", (0.78, 0.55, 0.05, 1.0), roughness=0.25, metallic=0.85)
    tape = n64_material("Hand_Tape", (0.70, 0.65, 0.54, 1.0), roughness=0.96)
    stump = n64_material("Stump_Dark", (0.18, 0.01, 0.02, 1.0), roughness=0.80)
    eye = n64_material("Eye_Amber", (1.0, 0.42, 0.05, 1.0), roughness=0.18, metallic=0.10)

    pieces: list[bpy.types.Object] = []

    # -------------------------------------------------------------------------
    # Torso
    # -------------------------------------------------------------------------
    torso_core = make_cube("torso__core", Vector((0.0, 0.0, 1.25)), Vector((0.24, 0.36, 0.32)), black)
    tag_mesh(torso_core, "torso", "torso", "torso", detachable=False)
    pieces.append(torso_core)

    # Red sleeveless vest: back panel + two front panels.
    vest_back = make_cube("torso__vest_back", Vector((-0.05, 0.0, 1.30)), Vector((0.22, 0.365, 0.30)), red)
    tag_mesh(vest_back, "torso", "torso", "torso", detachable=False)
    pieces.append(vest_back)
    vest_front_l = make_cube("torso__vest_front_l", Vector((0.10, -0.18, 1.27)), Vector((0.18, 0.08, 0.24)), red)
    tag_mesh(vest_front_l, "torso", "torso", "torso", detachable=False)
    pieces.append(vest_front_l)
    vest_front_r = make_cube("torso__vest_front_r", Vector((0.10, 0.18, 1.27)), Vector((0.18, 0.08, 0.24)), red)
    tag_mesh(vest_front_r, "torso", "torso", "torso", detachable=False)
    pieces.append(vest_front_r)

    # Belt.
    belt = make_cube("torso__belt", Vector((0.0, 0.0, 1.04)), Vector((0.245, 0.33, 0.045)), red_dark)
    tag_mesh(belt, "torso", "torso", "torso", detachable=False)
    pieces.append(belt)
    buckle = make_cube("torso__buckle", Vector((0.12, 0.0, 1.04)), Vector((0.03, 0.08, 0.06)), steel)
    tag_mesh(buckle, "torso", "torso", "torso", detachable=False)
    pieces.append(buckle)

    # -------------------------------------------------------------------------
    # Head
    # -------------------------------------------------------------------------
    # Skull: deliberately angular box, broad.
    head_skull = make_cube("head__skull", Vector((0.03, 0.0, 1.895)), Vector((0.16, 0.155, 0.185)), skin)
    tag_mesh(head_skull, "head", "head", "head")
    pieces.append(head_skull)

    # Heavy slab jaw.
    jaw = make_cube("head__jaw", Vector((0.08, 0.0, 1.72)), Vector((0.135, 0.125, 0.08)), skin_dark)
    tag_mesh(jaw, "head", "head", "head")
    pieces.append(jaw)

    # Brow ridge.
    brow = make_cube("head__brow", Vector((0.10, 0.0, 1.97)), Vector((0.03, 0.14, 0.04)), skin_dark)
    tag_mesh(brow, "head", "head", "head")
    pieces.append(brow)

    # Metal implant plate over left temple.
    implant = make_cube("head__implant", Vector((0.04, -0.148, 1.945)), Vector((0.12, 0.02, 0.065)), steel)
    tag_mesh(implant, "head", "head", "head")
    pieces.append(implant)

    # Good eye.
    good_eye = make_cube("head__eye", Vector((0.155, 0.055, 1.955)), Vector((0.015, 0.035, 0.025)), eye)
    tag_mesh(good_eye, "head", "head", "head")
    pieces.append(good_eye)

    # Head stump cap (hidden under the head, visible when head removed).
    head_stump = make_cylinder("head__stump_cap", Vector((0.0, 0.0, 1.70)), 0.08, 0.04, stump, vertices=6)
    tag_mesh(head_stump, "head", "head", "neck", detachable=False)
    pieces.append(head_stump)

    # -------------------------------------------------------------------------
    # Arms
    # -------------------------------------------------------------------------
    for side, y in (("l", -0.34), ("r", 0.34)):
        slot = f"arm_{side}"
        upper_bone = f"arm_{side}_upper"
        lower_bone = f"arm_{side}_lower"
        hand_bone = f"arm_{side}_hand"

        upper = make_cylinder(f"{slot}__upper", Vector((0.0, y, 1.325)), 0.135, 0.35, skin, vertices=6)
        tag_mesh(upper, slot, upper_bone, upper_bone)
        pieces.append(upper)

        # Shoulder plate / cap.
        shoulder = make_cube(f"{slot}__shoulder_cap", Vector((0.02, y, 1.48)), Vector((0.18, 0.06, 0.05)), steel)
        tag_mesh(shoulder, slot, upper_bone, upper_bone)
        pieces.append(shoulder)
        # Stump cap at shoulder.
        stump_cap = make_cylinder(f"{slot}__stump_cap", Vector((0.0, y * 0.6, 1.55)), 0.10, 0.04, stump, vertices=6)
        tag_mesh(stump_cap, slot, upper_bone, "chest", detachable=False)
        pieces.append(stump_cap)

        forearm = make_cylinder(f"{slot}__forearm", Vector((0.0, y, 0.975)), 0.115, 0.30, skin, vertices=6)
        tag_mesh(forearm, slot, upper_bone, lower_bone)
        pieces.append(forearm)

        # Tape wrap at wrist.
        wrist_tape = make_cylinder(f"{slot}__tape", Vector((0.0, y, 0.81)), 0.125, 0.08, tape, vertices=6)
        tag_mesh(wrist_tape, slot, upper_bone, lower_bone)
        pieces.append(wrist_tape)

        # Fist as a chunky box.
        hand = make_cube(f"{slot}__hand", Vector((0.0, y, 0.69)), Vector((0.12, 0.13, 0.13)), tape)
        tag_mesh(hand, slot, upper_bone, hand_bone)
        pieces.append(hand)

        # Gold knuckle block across the four knuckles.
        knuckles = make_cube(f"{slot}__knuckles", Vector((0.085, y, 0.705)), Vector((0.025, 0.105, 0.035)), gold)
        tag_mesh(knuckles, slot, upper_bone, hand_bone)
        pieces.append(knuckles)

    # -------------------------------------------------------------------------
    # Legs
    # -------------------------------------------------------------------------
    for side, y in (("l", -0.18), ("r", 0.18)):
        slot = f"leg_{side}"
        thigh_bone = f"leg_{side}_thigh"
        shin_bone = f"leg_{side}_shin"
        foot_bone = f"leg_{side}_foot"

        thigh = make_cylinder(f"{slot}__thigh", Vector((0.0, y, 0.625)), 0.195, 0.45, pants, vertices=6)
        tag_mesh(thigh, slot, thigh_bone, thigh_bone)
        pieces.append(thigh)

        # Hip seam / stump cap.
        hip_cap = make_cylinder(f"{slot}__stump_cap", Vector((0.0, y * 0.6, 0.85)), 0.12, 0.04, stump, vertices=6)
        tag_mesh(hip_cap, slot, thigh_bone, "pelvis", detachable=False)
        pieces.append(hip_cap)

        shin = make_cylinder(f"{slot}__shin", Vector((0.0, y, 0.225)), 0.165, 0.35, pants, vertices=6)
        tag_mesh(shin, slot, thigh_bone, shin_bone)
        pieces.append(shin)

        # Knee pad.
        knee = make_cube(f"{slot}__knee_pad", Vector((0.06, y, 0.40)), Vector((0.04, 0.15, 0.10)), steel)
        tag_mesh(knee, slot, thigh_bone, shin_bone)
        pieces.append(knee)

        # Extremely chunky boot.
        boot = make_cube(f"{slot}__boot", Vector((0.08, y, 0.09)), Vector((0.29, 0.18, 0.16)), black)
        tag_mesh(boot, slot, thigh_bone, foot_bone)
        pieces.append(boot)

        # Metal toe cap.
        toe = make_cube(f"{slot}__toe_cap", Vector((0.22, y, 0.09)), Vector((0.05, 0.16, 0.13)), steel)
        tag_mesh(toe, slot, thigh_bone, foot_bone)
        pieces.append(toe)

        # Red boot stripe.
        stripe = make_cube(f"{slot}__boot_stripe", Vector((0.08, y, 0.14)), Vector((0.27, 0.185, 0.02)), red_dark)
        tag_mesh(stripe, slot, thigh_bone, foot_bone)
        pieces.append(stripe)

    # Parent all pieces to their driver bones.
    for obj in pieces:
        driver = obj.get("driver_bone")
        if driver:
            parent_to_bone(obj, arm, driver)

    return pieces


# -----------------------------------------------------------------------------
# Animation
# -----------------------------------------------------------------------------


def clear_pose(arm: bpy.types.Object) -> None:
    for pb in arm.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_euler = Vector((0, 0, 0))


def keyframe_all(arm: bpy.types.Object, frame: int) -> None:
    bpy.context.scene.frame_set(frame)
    for pb in arm.pose.bones:
        pb.keyframe_insert("location", frame=frame, group=pb.name)
        pb.keyframe_insert("rotation_euler", frame=frame, group=pb.name)


def set_bone_rot(arm: bpy.types.Object, bone_name: str, euler: tuple[float, float, float]) -> None:
    pb = arm.pose.bones[bone_name]
    pb.rotation_euler = euler


def set_bone_loc(arm: bpy.types.Object, bone_name: str, loc: tuple[float, float, float]) -> None:
    pb = arm.pose.bones[bone_name]
    pb.location = loc


# Named poses presets.  Rotations are Euler XYZ in radians.
NEUTRAL = {
    "root": (0, 0, 0),
    "pelvis": (0, 0, 0),
    "torso": (0, 0, 0),
    "chest": (0, 0, 0),
    "neck": (0, 0, 0),
    "head": (0, 0, 0),
    "arm_l_upper": (0, 0, -0.25),
    "arm_l_lower": (0, 0, -0.10),
    "arm_l_hand": (0, 0, 0),
    "arm_r_upper": (0, 0, 0.25),
    "arm_r_lower": (0, 0, 0.10),
    "arm_r_hand": (0, 0, 0),
    "leg_l_thigh": (0, 0, 0),
    "leg_l_shin": (0, 0, 0),
    "leg_l_foot": (0, 0, 0),
    "leg_r_thigh": (0, 0, 0),
    "leg_r_shin": (0, 0, 0),
    "leg_r_foot": (0, 0, 0),
}


def apply_named_pose(arm: bpy.types.Object, pose: dict[str, tuple[float, float, float]]) -> None:
    clear_pose(arm)
    for bone_name, rot in pose.items():
        if bone_name == "root":
            set_bone_loc(arm, "root", rot)
        else:
            set_bone_rot(arm, bone_name, rot)
    bpy.context.view_layer.update()


def make_action(arm: bpy.types.Object, name: str, length: int, keyframes: list[tuple[int, dict[str, tuple[float, float, float]]]], loop: bool = False) -> bpy.types.Action:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start = 0
    action.frame_end = length

    arm.animation_data_create()
    arm.animation_data.action = action
    for frame, pose in keyframes:
        apply_named_pose(arm, pose)
        keyframe_all(arm, frame)
    arm.animation_data.action = None
    return action


def create_animations(arm: bpy.types.Object) -> None:
    # Fight_Idle: loop, subtle breathing.
    idle_a = dict(NEUTRAL)
    idle_a["torso"] = (0, 0, 0.02)
    idle_a["head"] = (0, 0, -0.02)
    idle_b = dict(NEUTRAL)
    idle_b["torso"] = (0, 0, -0.02)
    idle_b["chest"] = (0.04, 0, 0)
    idle_b["head"] = (0, 0, 0.02)
    make_action(arm, "Fight_Idle", 30, [(0, idle_a), (15, idle_b), (30, idle_a)], loop=True)

    # Walk_Forward: loop.
    w0 = dict(NEUTRAL)
    w0["root"] = (0, 0, 0.03)
    w0["leg_l_thigh"] = (0.35, 0, 0)
    w0["leg_l_shin"] = (-0.35, 0, 0)
    w0["leg_r_thigh"] = (-0.25, 0, 0)
    w0["leg_r_shin"] = (0.15, 0, 0)
    w0["arm_l_upper"] = (0, 0, -0.45)
    w0["arm_r_upper"] = (0, 0, 0.45)
    w12 = dict(NEUTRAL)
    w12["root"] = (0, 0, 0.03)
    w12["leg_l_thigh"] = (-0.25, 0, 0)
    w12["leg_l_shin"] = (0.15, 0, 0)
    w12["leg_r_thigh"] = (0.35, 0, 0)
    w12["leg_r_shin"] = (-0.35, 0, 0)
    w12["arm_l_upper"] = (0, 0, 0.45)
    w12["arm_r_upper"] = (0, 0, -0.45)
    make_action(arm, "Walk_Forward", 24, [(0, w0), (12, w12), (24, w0)], loop=True)

    # Jump.
    j0 = dict(NEUTRAL)
    j_crouch = dict(NEUTRAL)
    j_crouch["root"] = (0, 0, -0.08)
    j_crouch["leg_l_thigh"] = (-0.45, 0, 0)
    j_crouch["leg_l_shin"] = (0.70, 0, 0)
    j_crouch["leg_r_thigh"] = (-0.45, 0, 0)
    j_crouch["leg_r_shin"] = (0.70, 0, 0)
    j_crouch["arm_l_upper"] = (0, 0, -1.10)
    j_crouch["arm_r_upper"] = (0, 0, 1.10)
    j_up = dict(NEUTRAL)
    j_up["root"] = (0, 0, 0.45)
    j_up["leg_l_thigh"] = (0.50, 0, 0)
    j_up["leg_l_shin"] = (-0.75, 0, 0)
    j_up["leg_r_thigh"] = (0.50, 0, 0)
    j_up["leg_r_shin"] = (-0.75, 0, 0)
    j_up["arm_l_upper"] = (0, 0, -1.40)
    j_up["arm_r_upper"] = (0, 0, 1.40)
    make_action(arm, "Jump", 28, [(0, j0), (6, j_crouch), (14, j_up), (24, j0), (28, j0)])

    # Punch_Jab: lead arm (left).
    jab_wind = dict(NEUTRAL)
    jab_wind["arm_l_upper"] = (0, 0, -0.90)
    jab_wind["arm_l_lower"] = (0, 0, -0.60)
    jab_hit = dict(NEUTRAL)
    jab_hit["torso"] = (0, 0, -0.08)
    jab_hit["chest"] = (0, 0, -0.05)
    jab_hit["arm_l_upper"] = (0, 0, -1.55)
    jab_hit["arm_l_lower"] = (0, 0, -0.05)
    jab_hit["arm_l_hand"] = (0, 0, -0.20)
    jab_hit["arm_r_upper"] = (0, 0, 0.35)
    make_action(arm, "Punch_Jab", 18, [(0, NEUTRAL), (4, jab_wind), (8, jab_hit), (11, jab_hit), (18, NEUTRAL)])

    # Punch_Cross: rear arm (right) with heavier windup.
    cross_wind = dict(NEUTRAL)
    cross_wind["arm_r_upper"] = (0, 0, 1.00)
    cross_wind["arm_r_lower"] = (0, 0, 0.55)
    cross_wind["torso"] = (0, 0, 0.15)
    cross_hit = dict(NEUTRAL)
    cross_hit["torso"] = (0, 0, -0.12)
    cross_hit["chest"] = (0, 0, -0.08)
    cross_hit["arm_r_upper"] = (0, 0, 1.55)
    cross_hit["arm_r_lower"] = (0, 0, 0.05)
    cross_hit["arm_r_hand"] = (0, 0, 0.20)
    cross_hit["arm_l_upper"] = (0, 0, -0.35)
    make_action(arm, "Punch_Cross", 24, [(0, NEUTRAL), (8, cross_wind), (13, cross_hit), (17, cross_hit), (24, NEUTRAL)])

    # Kick_Low: left leg, shin height.
    low_wind = dict(NEUTRAL)
    low_wind["leg_l_thigh"] = (0.55, 0, 0)
    low_wind["leg_l_shin"] = (-0.85, 0, 0)
    low_wind["leg_l_foot"] = (0.45, 0, 0)
    low_wind["arm_l_upper"] = (0, 0, -0.55)
    low_hit = dict(NEUTRAL)
    low_hit["torso"] = (0, 0, -0.10)
    low_hit["leg_l_thigh"] = (0.10, 0, 0)
    low_hit["leg_l_shin"] = (0.10, 0, 0)
    low_hit["leg_l_foot"] = (0.10, 0, 0)
    low_hit["arm_l_upper"] = (0, 0, -0.80)
    make_action(arm, "Kick_Low", 22, [(0, NEUTRAL), (6, low_wind), (12, low_hit), (16, low_hit), (22, NEUTRAL)])

    # Kick_High: right leg, head height.
    high_wind = dict(NEUTRAL)
    high_wind["leg_r_thigh"] = (-0.35, 0, 0)
    high_wind["leg_r_shin"] = (-0.55, 0, 0)
    high_wind["leg_r_foot"] = (0.35, 0, 0)
    high_hit = dict(NEUTRAL)
    high_hit["torso"] = (0.15, 0, 0)
    high_hit["leg_r_thigh"] = (1.55, 0, 0)
    high_hit["leg_r_shin"] = (0.05, 0, 0)
    high_hit["leg_r_foot"] = (0.25, 0, 0)
    high_hit["arm_l_upper"] = (0, 0, -0.80)
    high_hit["arm_r_upper"] = (0, 0, 0.80)
    make_action(arm, "Kick_High", 34, [(0, NEUTRAL), (10, high_wind), (18, high_hit), (22, high_hit), (34, NEUTRAL)])

    # Block: both arms raised guard.
    block = dict(NEUTRAL)
    block["arm_l_upper"] = (0, 0, -1.10)
    block["arm_l_lower"] = (0, 0, -0.90)
    block["arm_l_hand"] = (0, 0, -0.30)
    block["arm_r_upper"] = (0, 0, 1.10)
    block["arm_r_lower"] = (0, 0, 0.90)
    block["arm_r_hand"] = (0, 0, 0.30)
    block["torso"] = (0, 0, 0.05)
    make_action(arm, "Block", 12, [(0, NEUTRAL), (4, block), (12, block)])

    # Hit_React: torso and head back.
    hit = dict(NEUTRAL)
    hit["root"] = (-0.06, 0, 0.02)
    hit["torso"] = (0, 0, 0.20)
    hit["chest"] = (0, 0, 0.12)
    hit["head"] = (0, 0, -0.25)
    hit["arm_l_upper"] = (0, 0, -0.50)
    hit["arm_r_upper"] = (0, 0, 0.50)
    make_action(arm, "Hit_React", 20, [(0, NEUTRAL), (4, hit), (12, hit), (20, NEUTRAL)])

    # KO: collapse.
    ko_mid = dict(NEUTRAL)
    ko_mid["root"] = (-0.15, 0, -0.15)
    ko_mid["torso"] = (0, 0, 0.55)
    ko_mid["chest"] = (0, 0, 0.30)
    ko_mid["head"] = (0, 0, 0.50)
    ko_mid["arm_l_upper"] = (0, 0, -0.80)
    ko_mid["arm_r_upper"] = (0, 0, 0.80)
    ko_mid["leg_l_thigh"] = (-0.45, 0, 0)
    ko_mid["leg_r_thigh"] = (0.45, 0, 0)
    ko_end = dict(NEUTRAL)
    ko_end["root"] = (-0.38, 0, -0.72)
    ko_end["torso"] = (0, 0, 1.45)
    ko_end["chest"] = (0, 0, 0.50)
    ko_end["head"] = (0, 0, 0.90)
    ko_end["arm_l_upper"] = (0, 0, -1.30)
    ko_end["arm_l_lower"] = (0, 0, -0.40)
    ko_end["arm_r_upper"] = (0, 0, 1.30)
    ko_end["arm_r_lower"] = (0, 0, 0.40)
    ko_end["leg_l_thigh"] = (-0.80, 0, 0)
    ko_end["leg_l_shin"] = (-0.40, 0, 0)
    ko_end["leg_r_thigh"] = (0.80, 0, 0)
    ko_end["leg_r_shin"] = (0.40, 0, 0)
    make_action(arm, "KO", 44, [(0, NEUTRAL), (14, ko_mid), (38, ko_end), (44, ko_end)])


# -----------------------------------------------------------------------------
# Preview, animation sheet, export
# -----------------------------------------------------------------------------


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction_vec = target - obj.location
    obj.rotation_euler = direction_vec.to_track_quat("-Z", "Y").to_euler()


def setup_preview(arm: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.015, 0.017, 0.022)

    # Set preview pose to fighting idle.
    arm.animation_data_clear()
    arm.animation_data_create()
    idle_action = bpy.data.actions.get("Fight_Idle")
    if idle_action:
        arm.animation_data.action = idle_action
    scene.frame_set(8)

    # Floor for preview only.
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, -0.015))
    floor = bpy.context.object
    floor.name = "Preview_Floor"
    floor.data.materials.append(n64_material("Preview_Floor", (0.015, 0.018, 0.024, 1.0), 0.92))
    floor["preview_only"] = True

    # Camera: orthographic, three-quarter side view.
    bpy.ops.object.camera_add(location=(3.8, -5.6, 2.35))
    camera = bpy.context.object
    camera.name = "Preview_Camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.9
    look_at(camera, Vector((0.10, 0, 1.05)))
    scene.camera = camera
    camera["preview_only"] = True

    # Key light.
    bpy.ops.object.light_add(type="AREA", location=(3.2, -3.8, 4.5))
    key = bpy.context.object
    key.name = "Preview_Key"
    key.data.energy = 1200
    key.data.size = 4.5
    look_at(key, Vector((0, 0, 1.2)))
    key["preview_only"] = True

    # Red rim.
    bpy.ops.object.light_add(type="AREA", location=(-2.6, 2.8, 3.2))
    rim_r = bpy.context.object
    rim_r.name = "Preview_Rim_Red"
    rim_r.data.energy = 900
    rim_r.data.color = (1.0, 0.05, 0.02)
    rim_r.data.size = 3.5
    look_at(rim_r, Vector((0, 0, 1.3)))
    rim_r["preview_only"] = True

    # Blue fill.
    bpy.ops.object.light_add(type="AREA", location=(-1.8, -2.2, 1.2))
    rim_b = bpy.context.object
    rim_b.name = "Preview_Rim_Blue"
    rim_b.data.energy = 500
    rim_b.data.color = (0.06, 0.22, 1.0)
    rim_b.data.size = 2.8
    look_at(rim_b, Vector((0, 0, 1.2)))
    rim_b["preview_only"] = True


def _hide_preview_objects(hide: bool) -> None:
    for obj in bpy.data.objects:
        if obj.get("preview_only"):
            obj.hide_set(hide)


def render_animation_sheet(arm: bpy.types.Object) -> None:
    scene = bpy.context.scene
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.image_settings.file_format = "PNG"
    # Use the fast workbench engine for the contact sheet so background
    # rendering of many frames stays reliable.
    original_engine = scene.render.engine
    scene.render.engine = "BLENDER_WORKBENCH"
    # Workbench flat lighting keeps the N64 look consistent.
    if hasattr(scene, "display"):
        scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "MATERIAL"

    sheet_configs = [
        ("Fight_Idle", 8),
        ("Punch_Jab", 8),
        ("Punch_Cross", 10),
        ("Kick_Low", 10),
        ("Kick_High", 16),
        ("Block", 6),
        ("Hit_React", 8),
        ("KO", 28),
    ]

    thumb_w, thumb_h = 256, 256
    rows = 2
    cols = 4
    sheet = bpy.data.images.new("Animation_Sheet", width=cols * thumb_w, height=rows * thumb_h, alpha=True)

    original_filepath = scene.render.filepath
    for idx, (anim_name, frame) in enumerate(sheet_configs):
        action = bpy.data.actions.get(anim_name)
        if not action:
            continue
        arm.animation_data.action = action
        scene.frame_set(frame)

        temp_path = str(OUT_DIR / f"_sheet_{anim_name}.png")
        scene.render.filepath = temp_path
        bpy.ops.render.render(write_still=True)

        img = bpy.data.images.load(temp_path)
        img.scale(thumb_w, thumb_h)
        pixels = list(img.pixels)

        col = idx % cols
        row = rows - 1 - (idx // cols)
        off_x = col * thumb_w
        off_y = row * thumb_h

        for y in range(thumb_h):
            for x in range(thumb_w):
                src_idx = ((thumb_h - 1 - y) * thumb_w + x) * 4
                dst_idx = ((off_y + y) * (cols * thumb_w) + (off_x + x)) * 4
                sheet.pixels[dst_idx:dst_idx + 4] = pixels[src_idx:src_idx + 4]

        bpy.data.images.remove(img)

    sheet.save_render(str(SHEET_PATH))
    sheet.pack()
    scene.render.filepath = original_filepath
    scene.render.engine = original_engine
    arm.animation_data.action = None


def export_glb(arm: bpy.types.Object) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Hide preview-only objects before export.
    _hide_preview_objects(True)

    # Ensure armature has no active action so all actions export.
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

    _hide_preview_objects(False)


# -----------------------------------------------------------------------------
# GLB validation
# -----------------------------------------------------------------------------


def parse_glb(path: Path) -> dict[str, Any]:
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF":
        raise ValueError("Not a valid GLB file")
    offset = 12
    json_data = None
    while offset < length:
        chunk_len, chunk_type = struct.unpack("<II", data[offset:offset + 8])
        chunk_data = data[offset + 8:offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            json_data = json.loads(chunk_data.decode("utf-8"))
            break
        offset += 8 + chunk_len
    if json_data is None:
        raise ValueError("GLB JSON chunk not found")
    return json_data


def count_triangles(gltf: dict[str, Any]) -> int:
    total = 0
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            mode = prim.get("mode", 4)
            if mode != 4:
                continue
            accessor_idx = prim.get("indices")
            if accessor_idx is not None:
                acc = gltf["accessors"][accessor_idx]
                total += acc.get("count", 0) // 3
            else:
                attrs = prim.get("attributes", {})
                if "POSITION" in attrs:
                    pos = gltf["accessors"][attrs["POSITION"]]
                    total += pos.get("count", 0) // 3
    return total


def validate_glb(path: Path) -> dict[str, Any]:
    gltf = parse_glb(path)
    result: dict[str, Any] = {}
    result["file_size_bytes"] = path.stat().st_size
    result["node_count"] = len(gltf.get("nodes", []))
    result["mesh_count"] = len(gltf.get("meshes", []))
    result["material_count"] = len(gltf.get("materials", []))
    result["texture_count"] = len(gltf.get("textures", []))
    result["image_count"] = len(gltf.get("images", []))
    result["triangle_count"] = count_triangles(gltf)

    images = gltf.get("images", [])
    result["texture_dimensions"] = []
    for img in images:
        result["texture_dimensions"].append((img.get("name", ""), img.get("width"), img.get("height")))

    anims = gltf.get("animations", [])
    anim_info = []
    for anim in anims:
        anim_info.append({
            "name": anim.get("name", "unnamed"),
            "channels": len(anim.get("channels", [])),
            "samplers": len(anim.get("samplers", [])),
        })
    result["animations"] = anim_info

    # Nodes with limb_slot metadata.
    limb_nodes = []
    for idx, node in enumerate(gltf.get("nodes", [])):
        extras = node.get("extras", {})
        if "limb_slot" in extras:
            limb_nodes.append({
                "index": idx,
                "name": node.get("name", ""),
                "limb_slot": extras.get("limb_slot"),
                "detachable": extras.get("detachable"),
                "detach_root_bone": extras.get("detach_root_bone"),
                "driver_bone": extras.get("driver_bone"),
            })
    result["limb_slot_nodes"] = limb_nodes
    result["limb_slot_node_count"] = len(limb_nodes)
    return result


# -----------------------------------------------------------------------------
# Round-trip import test
# -----------------------------------------------------------------------------


def roundtrip_test(glb_path: Path) -> dict[str, Any]:
    report: dict[str, Any] = {"imported_nodes": 0, "imported_meshes": 0, "imported_materials": 0, "imported_animations": 0}
    try:
        before = set(bpy.data.objects.keys())
        bpy.ops.import_scene.gltf(filepath=str(glb_path))
        after = set(bpy.data.objects.keys())
        new_objects = after - before
        armatures = [o for o in new_objects if o.type == "ARMATURE"]
        meshes = [o for o in new_objects if o.type == "MESH"]
        report["imported_nodes"] = len(new_objects)
        report["imported_meshes"] = len(meshes)
        report["imported_armatures"] = len(armatures)
        report["imported_materials"] = len([m for m in bpy.data.materials if m.users])
        report["imported_animations"] = len(bpy.data.actions)
        # Clean up imported objects to keep the main file clean.
        for name in list(new_objects):
            obj = bpy.data.objects.get(name)
            if obj:
                bpy.data.objects.remove(obj, do_unlink=True)
    except Exception as e:
        report["error"] = str(e)
    return report


# -----------------------------------------------------------------------------
# README
# -----------------------------------------------------------------------------


def write_readme(validation: dict[str, Any]) -> None:
    anims = "\n".join(f"- {a['name']} ({a['channels']} channels)" for a in validation.get("animations", []))
    lines = [
        "# Cyber Kingpin N64",
        "",
        "Low-poly modular heavyweight fighter built for a late-1990s Nintendo 64 style.",
        "",
        "## Files",
        "",
        f"- `{BLEND_PATH.name}` — editable Blender source",
        f"- `{GLB_PATH.name}` — runtime character, embeds textures and animations",
        f"- `{PREVIEW_PATH.name}` — three-quarter orthographic render",
        f"- `{SHEET_PATH.name}` — animation contact sheet",
        "",
        "## Skeleton",
        "",
        "The rig uses rigid bone parenting. Every visible piece follows a single bone.",
        "",
        "## Animations",
        "",
        anims,
        "",
        "## Validation Summary",
        "",
        f"- File size: {validation['file_size_bytes']} bytes",
        f"- Total triangles: {validation['triangle_count']}",
        f"- Nodes: {validation['node_count']}",
        f"- Meshes: {validation['mesh_count']}",
        f"- Materials: {validation['material_count']}",
        f"- Textures: {validation['texture_count']}",
        f"- Nodes with limb_slot metadata: {validation['limb_slot_node_count']}",
        "",
        "## Generation",
        "",
        "```bash",
        "blender --background --python tools/generate_cyber_kingpin_n64.py",
        "```",
        "",
    ]
    README_PATH.write_text("\n".join(lines))


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()

    bpy.context.scene.render.fps = FPS
    arm = create_armature()
    create_character(arm)
    create_animations(arm)
    setup_preview(arm)

    # Save the source .blend with preview scene intact.
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), check_existing=False)

    # Render preview from the idle pose.
    bpy.context.scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.render.render(write_still=True)

    # Animation sheet.
    render_animation_sheet(arm)

    # Export.
    export_glb(arm)

    # Validate.
    validation = validate_glb(GLB_PATH)

    # Round-trip import.
    rt_report = roundtrip_test(GLB_PATH)
    validation["roundtrip"] = rt_report

    # Print validation.
    print("\n=== GLB VALIDATION ===")
    print(json.dumps(validation, indent=2))
    print("=== END VALIDATION ===\n")

    # Write README.
    write_readme(validation)

    print(f"Wrote {BLEND_PATH}")
    print(f"Wrote {GLB_PATH}")
    print(f"Wrote {PREVIEW_PATH}")
    print(f"Wrote {SHEET_PATH}")
    print(f"Wrote {README_PATH}")


if __name__ == "__main__":
    main()

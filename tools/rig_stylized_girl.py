"""Build a single, game-ready humanoid rig from the Tripo presentation GLB.

The source file is a presentation sheet: two character copies and several
floating accessories are baked into one unrigged mesh. This script keeps the
front character, places the large bat in her right hand, creates a humanoid
armature, assigns deterministic weights, authors four loopable combat clips,
and exports both a Blender source file and an animated GLB.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector


ROOT = Path("/Users/alsinas/Projects/fighter")
SOURCE = ROOT / "assets/models/the_girl_tripo/stylized girl 3d model.glb"
OUT_DIR = ROOT / "assets/models/the_girl_rigged"
BLEND_OUT = OUT_DIR / "stylized_girl_fighter_rig.blend"
GLB_OUT = OUT_DIR / "stylized_girl_fighter_rig.glb"


def connected_components(obj):
    mesh = obj.data
    neighbors = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        neighbors[a].add(b)
        neighbors[b].add(a)

    remaining = set(range(len(mesh.vertices)))
    result = []
    while remaining:
        start = remaining.pop()
        todo = [start]
        verts = [start]
        while todo:
            current = todo.pop()
            for other in neighbors[current]:
                if other in remaining:
                    remaining.remove(other)
                    verts.append(other)
                    todo.append(other)
        coords = [obj.matrix_world @ mesh.vertices[i].co for i in verts]
        low = Vector((min(v.x for v in coords), min(v.y for v in coords), min(v.z for v in coords)))
        high = Vector((max(v.x for v in coords), max(v.y for v in coords), max(v.z for v in coords)))
        result.append({"verts": set(verts), "low": low, "high": high, "center": (low + high) * 0.5})
    return result


def isolated_copy(source, keep_indices, name):
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = name
    bpy.context.collection.objects.link(obj)
    mesh_edit = bmesh.new()
    mesh_edit.from_mesh(obj.data)
    mesh_edit.verts.ensure_lookup_table()
    remove = [vertex for vertex in mesh_edit.verts if vertex.index not in keep_indices]
    bmesh.ops.delete(mesh_edit, geom=remove, context="VERTS")
    mesh_edit.to_mesh(obj.data)
    mesh_edit.free()
    obj.data.update()
    return obj


def bounds(obj):
    coords = [obj.matrix_world @ v.co for v in obj.data.vertices]
    low = Vector((min(v.x for v in coords), min(v.y for v in coords), min(v.z for v in coords)))
    high = Vector((max(v.x for v in coords), max(v.y for v in coords), max(v.z for v in coords)))
    return low, high


def make_bone(armature, name, head, tail, parent=None, deform=True):
    bone = armature.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    bone.use_deform = deform
    if parent:
        bone.parent = armature.edit_bones[parent]
        bone.use_connect = False
    return bone


def build_armature(height, arm_span):
    data = bpy.data.armatures.new("Girl_Fighter_Skeleton")
    rig = bpy.data.objects.new("Girl_Fighter_Rig", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    hip_z = height * 0.39
    chest_z = height * 0.65
    shoulder_z = height * 0.715
    neck_z = height * 0.78
    top_z = height * 0.97
    half_arm = arm_span * 0.5
    shoulder_x = height * 0.075
    elbow_x = half_arm * 0.58
    wrist_x = half_arm * 0.87
    hand_x = half_arm * 0.98
    hip_x = height * 0.065
    knee_z = height * 0.22
    ankle_z = height * 0.065

    make_bone(data, "root", (0, 0, 0), (0, 0, hip_z), deform=False)
    make_bone(data, "pelvis", (0, 0, hip_z), (0, 0, height * 0.47), "root")
    make_bone(data, "spine", (0, 0, height * 0.47), (0, 0, height * 0.59), "pelvis")
    make_bone(data, "chest", (0, 0, height * 0.59), (0, 0, shoulder_z), "spine")
    make_bone(data, "neck", (0, 0, shoulder_z), (0, 0, neck_z), "chest")
    make_bone(data, "head", (0, 0, neck_z), (0, 0, top_z), "neck")

    for suffix, sign in (("L", -1.0), ("R", 1.0)):
        make_bone(data, f"clavicle.{suffix}", (0, 0, chest_z), (sign * shoulder_x, 0, shoulder_z), "chest", False)
        make_bone(data, f"upper_arm.{suffix}", (sign * shoulder_x, 0, shoulder_z), (sign * elbow_x, 0, shoulder_z), f"clavicle.{suffix}")
        make_bone(data, f"forearm.{suffix}", (sign * elbow_x, 0, shoulder_z), (sign * wrist_x, 0, shoulder_z), f"upper_arm.{suffix}")
        make_bone(data, f"hand.{suffix}", (sign * wrist_x, 0, shoulder_z), (sign * hand_x, 0, shoulder_z), f"forearm.{suffix}")
        make_bone(data, f"thigh.{suffix}", (sign * hip_x, 0, hip_z), (sign * hip_x, 0, knee_z), "pelvis")
        make_bone(data, f"shin.{suffix}", (sign * hip_x, 0, knee_z), (sign * hip_x, 0, ankle_z), f"thigh.{suffix}")
        make_bone(data, f"foot.{suffix}", (sign * hip_x, 0, ankle_z), (sign * hip_x, -height * 0.11, height * 0.025), f"shin.{suffix}")

    make_bone(data, "weapon.R", (hand_x, 0, shoulder_z), (hand_x, 0, shoulder_z + height * 0.11), "hand.R", False)
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def assign_body_weights(body, rig, height, arm_span):
    for bone in rig.data.bones:
        if bone.use_deform:
            body.vertex_groups.new(name=bone.name)

    half_arm = arm_span * 0.5
    shoulder_z = height * 0.715
    shoulder_x = height * 0.075
    elbow_x = half_arm * 0.58
    wrist_x = half_arm * 0.87

    for vertex in body.data.vertices:
        x, _, z = vertex.co
        ax = abs(x)
        side = "R" if x >= 0 else "L"
        # Arms win over torso in the T-pose band.
        if z >= height * 0.60 and z <= height * 0.78 and ax > shoulder_x * 0.88:
            if ax < elbow_x:
                group = f"upper_arm.{side}"
            elif ax < wrist_x:
                group = f"forearm.{side}"
            else:
                group = f"hand.{side}"
        elif z >= height * 0.77:
            group = "head"
        elif z >= height * 0.71:
            group = "neck"
        elif z < height * 0.40 and ax > height * 0.018:
            if z < height * 0.085:
                group = f"foot.{side}"
            elif z < height * 0.225:
                group = f"shin.{side}"
            else:
                group = f"thigh.{side}"
        elif z < height * 0.47:
            group = "pelvis"
        elif z < height * 0.59:
            group = "spine"
        else:
            group = "chest"
        body.vertex_groups[group].add([vertex.index], 1.0, "REPLACE")


def put_weapon_in_hand(weapon, hand_position, body_center_x):
    # The presentation bat is horizontal with its grip at the +X end. Rotate it
    # upright around that grip, then place it in the right hand.
    low, high = bounds(weapon)
    grip_world = Vector((high.x, (low.y + high.y) * 0.5, (low.z + high.z) * 0.5))
    grip_local = weapon.matrix_world.inverted() @ grip_world
    rotation = Matrix.Rotation(math.radians(82.0), 4, "Y") @ Matrix.Rotation(math.radians(-8.0), 4, "X")
    for vertex in weapon.data.vertices:
        point = rotation @ (vertex.co - grip_local)
        vertex.co = point + hand_position
    weapon.name = "Bat"


def join_meshes(body, weapon):
    body.select_set(True)
    weapon.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Stylized_Girl_Fighter"
    return body


def add_weapon_weights(body, original_body_vertex_count):
    group = body.vertex_groups.get("hand.R")
    indices = list(range(original_body_vertex_count, len(body.data.vertices)))
    if indices:
        # Clear any groups inherited during join, then rigid-bind the bat.
        for vertex_index in indices:
            for vertex_group in list(body.data.vertices[vertex_index].groups):
                body.vertex_groups[vertex_group.group].remove([vertex_index])
        group.add(indices, 1.0, "REPLACE")


def set_pose(rig, frame, rotations=None, locations=None):
    rotations = rotations or {}
    locations = locations or {}
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        angles = rotations.get(pose_bone.name, (0.0, 0.0, 0.0))
        pose_bone.rotation_euler = tuple(math.radians(v) for v in angles)
        pose_bone.location = locations.get(pose_bone.name, (0.0, 0.0, 0.0))
        pose_bone.keyframe_insert("rotation_euler", frame=frame, group=pose_bone.name)
        pose_bone.keyframe_insert("location", frame=frame, group=pose_bone.name)


def new_action(rig, name, end_frame):
    if not rig.animation_data:
        rig.animation_data_create()
    rig.animation_data.action = None
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    action.frame_start = 1
    action.frame_end = end_frame
    return action


def guard_pose(breathe=0.0):
    return {
        "pelvis": (0, 0, -3),
        "spine": (0, 0, 4 + breathe),
        "chest": (0, 0, -7 - breathe),
        "head": (0, 0, 5),
        "upper_arm.L": (-58, -8, 10),
        "forearm.L": (112, 0, -9),
        "hand.L": (-18, 0, 0),
        "upper_arm.R": (-48, 12, -18),
        "forearm.R": (92, 0, 12),
        "hand.R": (-15, 0, 0),
        "thigh.L": (0, 0, 5),
        "thigh.R": (0, 0, -5),
    }


def author_actions(rig, height):
    actions = []

    actions.append(new_action(rig, "Fight_Idle", 48))
    set_pose(rig, 1, guard_pose(), {"pelvis": (0, 0, 0)})
    set_pose(rig, 24, guard_pose(2.5), {"pelvis": (0, 0, height * 0.012)})
    set_pose(rig, 48, guard_pose(), {"pelvis": (0, 0, 0)})

    actions.append(new_action(rig, "Punch_Jab", 28))
    set_pose(rig, 1, guard_pose())
    windup = guard_pose(); windup.update({"chest": (0, 0, 10), "upper_arm.L": (-72, -10, 20), "forearm.L": (128, 0, -12)})
    set_pose(rig, 7, windup)
    strike = guard_pose(); strike.update({"chest": (0, 0, -17), "upper_arm.L": (-6, 0, -4), "forearm.L": (4, 0, 0), "hand.L": (0, 0, 0), "upper_arm.R": (-62, 8, -20)})
    set_pose(rig, 12, strike, {"pelvis": (0, -height * 0.025, 0)})
    set_pose(rig, 17, strike)
    set_pose(rig, 28, guard_pose())

    actions.append(new_action(rig, "Bat_Swing", 36))
    set_pose(rig, 1, guard_pose())
    windup = guard_pose(); windup.update({"pelvis": (0, 0, 12), "spine": (0, 0, 18), "chest": (0, 0, 25), "upper_arm.R": (-25, -15, -72), "forearm.R": (45, 0, -38), "hand.R": (-32, 0, 0)})
    set_pose(rig, 10, windup)
    swing = guard_pose(); swing.update({"pelvis": (0, 0, -14), "spine": (0, 0, -22), "chest": (0, 0, -34), "upper_arm.R": (-72, 18, 58), "forearm.R": (18, 0, 12), "hand.R": (22, 0, 0), "upper_arm.L": (-70, -8, 18)})
    set_pose(rig, 17, swing, {"pelvis": (0, -height * 0.018, 0)})
    follow = guard_pose(); follow.update({"chest": (0, 0, -16), "upper_arm.R": (-68, 10, 32), "forearm.R": (52, 0, 16)})
    set_pose(rig, 23, follow)
    set_pose(rig, 36, guard_pose())

    actions.append(new_action(rig, "Kick_High", 38))
    set_pose(rig, 1, guard_pose())
    chamber = guard_pose(); chamber.update({"pelvis": (0, 0, 7), "chest": (0, 0, -10), "thigh.R": (-12, 0, -35), "shin.R": (72, 0, 8), "upper_arm.L": (-70, 0, 16), "upper_arm.R": (-65, 0, -20)})
    set_pose(rig, 10, chamber, {"pelvis": (0, 0, height * 0.035)})
    kick = guard_pose(); kick.update({"pelvis": (0, 0, 12), "spine": (0, 0, -8), "chest": (0, 0, -15), "thigh.R": (0, 0, -88), "shin.R": (3, 0, 0), "foot.R": (0, 0, 16), "thigh.L": (0, 0, 10)})
    set_pose(rig, 17, kick, {"pelvis": (-height * 0.025, 0, height * 0.06)})
    set_pose(rig, 22, kick, {"pelvis": (-height * 0.02, 0, height * 0.045)})
    set_pose(rig, 29, chamber, {"pelvis": (0, 0, height * 0.025)})
    set_pose(rig, 38, guard_pose())

    rig.animation_data.action = actions[0]
    return actions


def add_preview_setup(rig, body, height):
    # Non-exported camera/light collection for easy Blender previewing.
    preview = bpy.data.collections.new("PREVIEW_ONLY")
    bpy.context.scene.collection.children.link(preview)

    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.color = (0.015, 0.018, 0.035)

    camera_data = bpy.data.cameras.new("Preview_Camera")
    camera = bpy.data.objects.new("Preview_Camera", camera_data)
    preview.objects.link(camera)
    camera.location = (height * 1.05, -height * 3.4, height * 0.63)
    direction = Vector((0, 0, height * 0.46)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 58
    bpy.context.scene.camera = camera

    light_data = bpy.data.lights.new("Key", "AREA")
    light_data.energy = 800
    light_data.shape = "DISK"
    light_data.size = height * 2.5
    light = bpy.data.objects.new("Key", light_data)
    preview.objects.link(light)
    light.location = (-height, -height * 2, height * 2.2)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    components = connected_components(source)

    body_components = [c for c in components if c["center"].x < -0.06 and c["center"].z < 0.80]
    weapon_components = [c for c in components if c["center"].x < -0.06 and c["center"].z >= 0.80]
    body_indices = set().union(*(c["verts"] for c in body_components))
    weapon_indices = set().union(*(c["verts"] for c in weapon_components))
    body = isolated_copy(source, body_indices, "Girl_Body")
    weapon = isolated_copy(source, weapon_indices, "Bat")
    bpy.data.objects.remove(source, do_unlink=True)

    low, high = bounds(body)
    center_x = (low.x + high.x) * 0.5
    ground_z = low.z
    for vertex in body.data.vertices:
        vertex.co.x -= center_x
        vertex.co.z -= ground_z
    low, high = bounds(body)
    height = high.z - low.z
    arm_span = high.x - low.x

    rig = build_armature(height, arm_span)
    assign_body_weights(body, rig, height, arm_span)

    original_body_vertex_count = len(body.data.vertices)
    hand_position = Vector((arm_span * 0.49, -height * 0.025, height * 0.715))
    put_weapon_in_hand(weapon, hand_position, center_x)
    body = join_meshes(body, weapon)
    add_weapon_weights(body, original_body_vertex_count)

    modifier = body.modifiers.new("Humanoid Armature", "ARMATURE")
    modifier.object = rig
    body.parent = rig
    body.matrix_parent_inverse = rig.matrix_world.inverted()

    actions = author_actions(rig, height)
    add_preview_setup(rig, body, height)

    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene.render.resolution_x = 720
    bpy.context.scene.render.resolution_y = 720
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 48
    bpy.context.scene.frame_set(1)

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

    # Only the game assets are exported; preview cameras/lights stay in the blend.
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_def_bones=True,
    )
    print(f"WROTE_BLEND {BLEND_OUT}")
    print(f"WROTE_GLB {GLB_OUT}")
    print("ACTIONS", [a.name for a in actions])
    print("BODY_VERTS", original_body_vertex_count, "TOTAL_VERTS", len(body.data.vertices))


if __name__ == "__main__":
    main()

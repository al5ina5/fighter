"""Build the textured blocky robot base model on the canonical fighter rig.

The supplied robot is an unrigged, Y-up OBJ with PBR textures but no skeleton.
To let it reuse the same twelve Mixamo actions as Girlypoppums, this script:

- imports the canonical 33-bone Mixamo armature from Girlypoppums' rig source;
- fits that armature into the robot's bounding volume so the bones run through
  the robot's head, torso, arms, and legs;
- auto-weights the robot mesh to the armature (Bone Heat / ARMATURE_AUTO);
- splits the skinned geometry into the game's detachable limb slots;
- normalizes scale, floor placement, and +X facing; and
- writes an editable Blend file plus a Godot-ready GLB.

The robot's PBR maps (base color, metallic, normal, roughness) are packed into
the GLB. Animation-only FBXs remain separate under `animations/` and are loaded
by the game, so changing a clip never requires rerunning Blender. Run the
one-time base-model preparation from the repository root:
    blender --background --python tools/prepare_robot.py
"""

from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "assets" / "models" / "robot"
SOURCE_DIR = MODEL_DIR / "source"
RIG_SOURCE = ROOT / "assets" / "models" / "girlypoppums" / "source" / "rig" / "Idle.fbx"
ROBOT_OBJ = SOURCE_DIR / "model" / "green_blocky_robot.obj"
TEXTURES = {
    "base_color": SOURCE_DIR / "model" / "green_blocky_robot_basecolor.jpg",
    "normal": SOURCE_DIR / "model" / "robot_normal.jpg",
    "metallic": SOURCE_DIR / "model" / "robot_metallic.jpg",
    "roughness": SOURCE_DIR / "model" / "robot_roughness.jpg",
}
BLEND_OUT = SOURCE_DIR / "robot_prepared.blend"
GLB_OUT = MODEL_DIR / "robot_prepared.glb"

LIMB_SLOTS = ("head", "torso", "arm_l", "arm_r", "leg_l", "leg_r")
TARGET_HEIGHT_METERS = 1.76


def reset_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.actions,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            try:
                datablocks.remove(block)
            except Exception:
                pass


def imported_objects(source: Path) -> tuple[list[bpy.types.Object], list[bpy.types.Action]]:
    before_objects = set(bpy.data.objects)
    before_actions = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=str(source), use_anim=True)
    objects = [obj for obj in bpy.data.objects if obj not in before_objects]
    actions = [action for action in bpy.data.actions if action not in before_actions]
    return objects, actions


def slot_for_bone(raw_name: str) -> str:
    name = raw_name.lower().replace("mixamorig:", "").replace("mixamorig_", "")
    if name.startswith("left"):
        if any(token in name for token in ("upleg", "leg", "foot", "toe")):
            return "leg_l"
        if any(token in name for token in ("shoulder", "arm", "hand")):
            return "arm_l"
    if name.startswith("right"):
        if any(token in name for token in ("upleg", "leg", "foot", "toe")):
            return "leg_r"
        if any(token in name for token in ("shoulder", "arm", "hand")):
            return "arm_r"
    if "head" in name or name == "neck":
        return "head"
    return "torso"


def classify_polygons(obj: bpy.types.Object) -> dict[str, set[int]]:
    group_names = {group.index: group.name for group in obj.vertex_groups}
    vertex_scores: list[dict[str, float]] = []
    for vertex in obj.data.vertices:
        scores: dict[str, float] = defaultdict(float)
        for assignment in vertex.groups:
            scores[slot_for_bone(group_names.get(assignment.group, ""))] += assignment.weight
        if not scores:
            scores["torso"] = 1.0
        vertex_scores.append(scores)

    result: dict[str, set[int]] = {slot: set() for slot in LIMB_SLOTS}
    for polygon in obj.data.polygons:
        scores: dict[str, float] = defaultdict(float)
        for vertex_index in polygon.vertices:
            for slot, value in vertex_scores[vertex_index].items():
                scores[slot] += value
        result[max(scores, key=scores.get) if scores else "torso"].add(polygon.index)
    return result


def polygon_copy(source: bpy.types.Object, polygon_indices: set[int], slot: str) -> bpy.types.Object | None:
    if not polygon_indices:
        return None
    keep_vertices: set[int] = set()
    for polygon_index in polygon_indices:
        keep_vertices.update(source.data.polygons[polygon_index].vertices)

    copied = source.copy()
    copied.data = source.data.copy()
    copied.name = f"{slot}_{source.name}"
    copied.data.name = copied.name + "_mesh"
    source.users_collection[0].objects.link(copied)

    edit_mesh = bmesh.new()
    edit_mesh.from_mesh(copied.data)
    edit_mesh.verts.ensure_lookup_table()
    bmesh.ops.delete(
        edit_mesh,
        geom=[vertex for vertex in edit_mesh.verts if vertex.index not in keep_vertices],
        context="VERTS",
    )
    edit_mesh.to_mesh(copied.data)
    edit_mesh.free()
    copied.data.update()
    if not copied.data.polygons:
        bpy.data.objects.remove(copied, do_unlink=True)
        return None
    copied["limb_slot"] = slot
    copied["detachable"] = slot != "torso"
    copied["is_stump"] = False
    return copied


def split_skinned_meshes(rig: bpy.types.Object) -> list[bpy.types.Object]:
    source_meshes = [
        obj for obj in list(bpy.data.objects)
        if obj.type == "MESH" and len(obj.data.vertices) > 0 and (
            obj.parent == rig or any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
        )
    ]
    output: list[bpy.types.Object] = []
    for source in source_meshes:
        assignments = classify_polygons(source)
        for slot in LIMB_SLOTS:
            copied = polygon_copy(source, assignments[slot], slot)
            if copied is not None:
                output.append(copied)
        bpy.data.objects.remove(source, do_unlink=True)
    return output


def apply_armature_transform(rig: bpy.types.Object, apply_location: bool = False) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.transform_apply(location=apply_location, rotation=True, scale=True)
    rig.select_set(False)


def mesh_world_height(meshes: list[bpy.types.Object]) -> tuple[float, float, float]:
    points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    low = min(point.z for point in points)
    high = max(point.z for point in points)
    return low, high, high - low


def select_hierarchy(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root


def object_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return low, high


def fit_armature_to_robot(
    rig: bpy.types.Object,
    reference_meshes: list[bpy.types.Object],
    robot: bpy.types.Object,
) -> None:
    """Fit the canonical T-pose rig to the robot using both meshes' bounds.

    Blender converts the supplied Y-up OBJ to Z-up during import. The previous
    implementation measured Y as height and compared shoulder *heights* as
    widths, which could collapse or badly offset the rig. Matching the canonical
    skinned reference bounds keeps the robot on the exact rest skeleton used by
    every loose animation.
    """
    bpy.ops.object.select_all(action="DESELECT")
    robot.select_set(True)
    bpy.context.view_layer.objects.active = robot
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()

    reference_low, reference_high = object_bounds(reference_meshes)
    robot_low, robot_high = object_bounds([robot])
    reference_size = reference_high - reference_low
    robot_size = robot_high - robot_low
    if min(reference_size) <= 0.0 or min(robot_size) <= 0.0:
        raise RuntimeError("Cannot fit a rig to a zero-volume mesh")

    # Match height exactly and allow modest horizontal/depth adaptation for the
    # robot's deliberately blockier proportions. Extreme scale factors are
    # clamped so animation rotations remain stable.
    height_scale = robot_size.z / reference_size.z
    x_scale = max(height_scale * 0.7, min(robot_size.x / reference_size.x, height_scale * 1.35))
    y_scale = max(height_scale * 0.7, min(robot_size.y / reference_size.y, height_scale * 1.35))
    rig.scale = Vector((rig.scale.x * x_scale, rig.scale.y * y_scale, rig.scale.z * height_scale))
    bpy.context.view_layer.update()

    fitted_low, fitted_high = object_bounds(reference_meshes)
    fitted_center = (fitted_low + fitted_high) * 0.5
    robot_center = (robot_low + robot_high) * 0.5
    rig.location += robot_center - fitted_center
    bpy.context.view_layer.update()
    fitted_low, _fitted_high = object_bounds(reference_meshes)
    rig.location.z += robot_low.z - fitted_low.z
    bpy.context.view_layer.update()

    print("REFERENCE_BBOX", tuple(round(value, 4) for value in reference_size))
    print("ROBOT_BBOX", tuple(round(value, 4) for value in robot_size))
    print("RIG_FIT_SCALE", tuple(round(value, 4) for value in rig.scale))


def bind_with_nearest_bones(robot: bpy.types.Object, rig: bpy.types.Object) -> None:
    """Reliable rigid-ish fallback for blocky geometry when bone heat fails."""
    from mathutils.geometry import intersect_point_line

    for group in list(robot.vertex_groups):
        robot.vertex_groups.remove(group)
    deform_bones = [bone for bone in rig.data.bones if bone.use_deform and not bone.name.endswith("_End")]
    groups = {bone.name: robot.vertex_groups.new(name=bone.name) for bone in deform_bones}
    segments = []
    for bone in deform_bones:
        head = rig.matrix_world @ bone.head_local
        tail = rig.matrix_world @ bone.tail_local
        segments.append((bone.name, head, tail))
    for vertex in robot.data.vertices:
        point = robot.matrix_world @ vertex.co
        distances = []
        for bone_name, head, tail in segments:
            nearest, factor = intersect_point_line(point, head, tail)
            nearest = head if factor < 0.0 else tail if factor > 1.0 else nearest
            distances.append(((point - nearest).length, bone_name))
        distances.sort(key=lambda item: item[0])
        chosen = distances[:2]
        raw = [1.0 / max(distance, 0.005) ** 2 for distance, _name in chosen]
        total = sum(raw)
        for weight, (_distance, bone_name) in zip(raw, chosen):
            groups[bone_name].add([vertex.index], weight / total, "REPLACE")
    robot.parent = rig
    robot.matrix_parent_inverse = rig.matrix_world.inverted()
    modifier = robot.modifiers.new(name="Canonical Mixamo rig", type="ARMATURE")
    modifier.object = rig


def bind_robot(robot: bpy.types.Object, rig: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    robot.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    except RuntimeError as error:
        print("BONE_HEAT_FALLBACK", error)
        bind_with_nearest_bones(robot, rig)
        return
    unweighted = [vertex.index for vertex in robot.data.vertices if not vertex.groups]
    if unweighted:
        print("BONE_HEAT_UNWEIGHTED", len(unweighted))
        bind_with_nearest_bones(robot, rig)


def relink_robot_texture(robot: bpy.types.Object) -> None:
    image = bpy.data.images.load(str(TEXTURES["base_color"]), check_existing=False)
    image.name = "green_blocky_robot_basecolor"
    image.colorspace_settings.name = "sRGB"
    image.pack()
    materials = {material for obj in [robot] for material in obj.data.materials if material is not None}
    if not materials:
        material = bpy.data.materials.new("green_blocky_robot_material")
        materials.add(material)
        robot.data.materials.append(material)
    for material in materials:
        material.use_nodes = True
        material.diffuse_color = (1.0, 1.0, 1.0, 1.0)
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = nodes.get("Principled BSDF")
        if principled is None:
            principled = nodes.new("ShaderNodeBsdfPrincipled")

        def bind_texture(source: Path, input_name: str, color_space: str) -> None:
            if not source.exists():
                return
            image_node = bpy.data.images.load(str(source), check_existing=False)
            image_node.colorspace_settings.name = color_space
            image_node.pack()
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = image_node
            for link in list(principled.inputs[input_name].links):
                links.remove(link)
            links.new(tex.outputs["Color"], principled.inputs[input_name])

        bind_texture(TEXTURES["base_color"], "Base Color", "sRGB")
        if TEXTURES["metallic"].exists():
            bind_texture(TEXTURES["metallic"], "Metallic", "Non-Color")
        if TEXTURES["roughness"].exists():
            bind_texture(TEXTURES["roughness"], "Roughness", "Non-Color")
        if TEXTURES["normal"].exists():
            tex = nodes.new("ShaderNodeTexImage")
            image_node = bpy.data.images.load(str(TEXTURES["normal"]), check_existing=False)
            image_node.colorspace_settings.name = "Non-Color"
            image_node.pack()
            tex.image = image_node
            normal_map = nodes.new("ShaderNodeNormalMap")
            links.new(tex.outputs["Color"], normal_map.inputs["Color"])
            for link in list(principled.inputs["Normal"].links):
                links.remove(link)
            links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])


def main() -> None:
    required = [RIG_SOURCE, ROBOT_OBJ, TEXTURES["base_color"]]
    for source in required:
        if not source.exists():
            raise FileNotFoundError(source)
    reset_scene()

    base_objects, base_actions = imported_objects(RIG_SOURCE)
    rig = next((obj for obj in base_objects if obj.type == "ARMATURE"), None)
    if rig is None:
        raise RuntimeError("Rig source did not contain an armature")
    rig.name = "Robot_Rig"
    bone_signature = tuple(bone.name for bone in rig.data.bones)
    if len(bone_signature) != 33:
        raise RuntimeError(f"Expected 33 Mixamo bones, found {len(bone_signature)}")
    if rig.animation_data:
        rig.animation_data.action = None
    for action in base_actions:
        if action.name in bpy.data.actions:
            bpy.data.actions.remove(action)
    reference_meshes = [obj for obj in base_objects if obj.type == "MESH"]
    if not reference_meshes:
        raise RuntimeError("Canonical rig source did not contain its reference mesh")

    bpy.ops.wm.obj_import(filepath=str(ROBOT_OBJ))
    robot = next((obj for obj in bpy.context.selected_objects if obj.type == "MESH"), None)
    if robot is None:
        robot = next((obj for obj in bpy.data.objects if obj.type == "MESH"), None)
    if robot is None:
        raise RuntimeError("Robot OBJ did not contain a mesh")
    robot.name = "GreenBlockyRobot"

    fit_armature_to_robot(rig, reference_meshes, robot)
    apply_armature_transform(rig, apply_location=True)
    for obj in reference_meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
    relink_robot_texture(robot)

    bind_robot(robot, rig)
    bpy.context.view_layer.update()
    if not robot.vertex_groups:
        raise RuntimeError("Rigging produced no vertex groups")
    print("VERTEX_GROUPS", len(robot.vertex_groups))

    split_meshes = split_skinned_meshes(rig)
    if not split_meshes:
        raise RuntimeError("No skinned geometry remained after limb separation")

    low, _high, current_height = mesh_world_height(split_meshes)
    final_scale = TARGET_HEIGHT_METERS / current_height
    rig.scale = (final_scale,) * 3
    rig.rotation_euler.z = math.radians(90.0)
    rig.location.z = -low * final_scale
    apply_armature_transform(rig, apply_location=True)

    root = bpy.data.objects.new("GreenBlockyRobot", None)
    bpy.context.scene.collection.objects.link(root)
    rig.parent = root
    root["model_facing"] = 1
    root["source_format"] = "Unrigged OBJ + canonical Mixamo armature"
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = None
    bpy.context.scene.render.fps = 60
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 1
    bpy.context.scene.frame_set(1)

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    select_hierarchy(root)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
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
        export_all_influences=True,
        export_animations=False,
        export_extras=True,
        export_nla_strips=False,
        export_current_frame=False,
        export_reset_pose_bones=True,
        export_rest_position_armature=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_optimize_animation_size=True,
    )

    slot_counts = {slot: sum(1 for obj in split_meshes if obj.get("limb_slot") == slot) for slot in LIMB_SLOTS}
    print("WROTE_BLEND", BLEND_OUT)
    print("WROTE_GLB", GLB_OUT)
    print("ANIMATIONS", "loaded independently from", MODEL_DIR / "animations")
    print("LIMB_OBJECTS", slot_counts)
    print("HEIGHT_METERS", round(TARGET_HEIGHT_METERS, 3))
    print("POLYGONS", sum(len(obj.data.polygons) for obj in split_meshes))


if __name__ == "__main__":
    main()

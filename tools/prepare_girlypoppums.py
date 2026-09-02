"""Build the textured Girlypoppums base model from its Mixamo rig source.

The canonical rig FBX contains the mesh, skin weights, and 33-bone skeleton.
This script keeps the source files untouched while it:

- relinks and packs the supplied base-color texture;
- splits skinned geometry into the game's detachable limb slots;
- normalizes scale, floor placement, and +X facing; and
- writes an editable Blend file plus a Godot-ready GLB.

Animation-only FBXs remain separate under `animations/` and are loaded by the
game, so replacing a clip never requires rerunning Blender.

Run from the repository root:
    blender --background --python tools/prepare_girlypoppums.py
"""

from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "assets" / "models" / "girlypoppums"
SOURCE_DIR = MODEL_DIR / "source"
RIG_SOURCE = SOURCE_DIR / "rig" / "Idle.fbx"
TEXTURE_SOURCE = SOURCE_DIR / "model" / "girlypoppums_basecolor.jpg"
BLEND_OUT = SOURCE_DIR / "girlypoppums_prepared.blend"
GLB_OUT = MODEL_DIR / "girlypoppums_prepared.glb"

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


def relink_texture(meshes: list[bpy.types.Object]) -> None:
    image = bpy.data.images.load(str(TEXTURE_SOURCE), check_existing=False)
    image.name = "girlypoppums_basecolor"
    image.colorspace_settings.name = "sRGB"
    image.pack()
    materials = {material for obj in meshes for material in obj.data.materials if material is not None}
    if not materials:
        material = bpy.data.materials.new("girlypoppums_material")
        materials.add(material)
        for obj in meshes:
            obj.data.materials.append(material)
    for material in materials:
        material.use_nodes = True
        material.diffuse_color = (1.0, 1.0, 1.0, 1.0)
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = nodes.get("Principled BSDF")
        if principled is None:
            principled = nodes.new("ShaderNodeBsdfPrincipled")
        principled.inputs["Roughness"].default_value = 0.72
        texture = next((node for node in nodes if node.type == "TEX_IMAGE"), None)
        if texture is None:
            texture = nodes.new("ShaderNodeTexImage")
        texture.name = "girlypoppums_basecolor"
        texture.image = image
        for link in list(principled.inputs["Base Color"].links):
            links.remove(link)
        links.new(texture.outputs["Color"], principled.inputs["Base Color"])


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


def main() -> None:
    required = [RIG_SOURCE, TEXTURE_SOURCE]
    for source in required:
        if not source.exists():
            raise FileNotFoundError(source)
    reset_scene()

    base_objects, base_actions = imported_objects(RIG_SOURCE)
    rig = next((obj for obj in base_objects if obj.type == "ARMATURE"), None)
    if rig is None:
        raise RuntimeError("Rig source did not contain an armature")
    rig.name = "Girlypoppums_Rig"
    bone_signature = tuple(bone.name for bone in rig.data.bones)
    if len(bone_signature) != 33:
        raise RuntimeError(f"Expected 33 Mixamo bones, found {len(bone_signature)}")
    if rig.animation_data:
        rig.animation_data.action = None
    for action in base_actions:
        if action.name in bpy.data.actions:
            bpy.data.actions.remove(action)

    canonical_meshes = [obj for obj in base_objects if obj.type == "MESH" and len(obj.data.vertices)]
    if not canonical_meshes:
        raise RuntimeError("Rig source did not contain skinned geometry")
    relink_texture(canonical_meshes)

    apply_armature_transform(rig)
    split_meshes = split_skinned_meshes(rig)
    if not split_meshes:
        raise RuntimeError("No skinned geometry remained after limb separation")

    low, _high, current_height = mesh_world_height(split_meshes)
    final_scale = TARGET_HEIGHT_METERS / current_height
    rig.scale = (final_scale,) * 3
    rig.rotation_euler.z = math.radians(90.0)
    rig.location.z = -low * final_scale
    apply_armature_transform(rig, apply_location=True)

    root = bpy.data.objects.new("Girlypoppums", None)
    bpy.context.scene.collection.objects.link(root)
    rig.parent = root
    root["model_facing"] = 1
    root["source_format"] = "Mixamo FBX + textured OBJ package"
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

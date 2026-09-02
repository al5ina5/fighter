"""Prepare the supplied Alien Girl Mixamo FBXs for the 2.5D fighter.

The source exports repeat the complete mesh/skeleton in each FBX, use a generic
animation name, contain several zero-surface placeholder nodes, have no
materials, and do not expose detachable limb meshes. This script:

- uses Idle.fbx as the canonical mesh and skeleton;
- merges the three compatible actions as idle, jab, and heavy_punch;
- removes empty geometry;
- splits every skinned surface by dominant Mixamo bone weights into the game's
  head/torso/arm_l/arm_r/leg_l/leg_r contract;
- adds simple untextured materials;
- normalizes the model to about 1.75 m, at the floor, facing +X; and
- writes an editable .blend plus a Godot-ready .glb.

Run from the repository root:
    blender --background --python tools/prepare_alien_girl.py
"""

from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "assets" / "models" / "alien-girl"
SOURCE_DIR = MODEL_DIR / "source"
SOURCES = {
    "idle": MODEL_DIR / "Idle.fbx",
    "jab": MODEL_DIR / "Punching.fbx",
    "heavy_punch": MODEL_DIR / "PunchingHeavy.fbx",
}
DOWNLOADED_DIR = SOURCE_DIR / "downloaded"
# Optional Mixamo exports. Filenames are matched by the semantic key before
# import, so users can drop in bounded FBX downloads without editing code.
OPTIONAL_SEMANTICS = (
    "walk_forward", "walk_backward", "jump", "falling", "landing",
    "guard_high", "guard_low", "hit_high", "hit_mid", "hit_low",
    "knockout", "high_attack", "mid_attack", "low_kick", "heavy_low_kick",
    "high_kick",
)
BLEND_OUT = SOURCE_DIR / "alien_girl_prepared.blend"
GLB_OUT = MODEL_DIR / "alien_girl_prepared.glb"

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


def action_for(objects: list[bpy.types.Object], actions: list[bpy.types.Action]) -> bpy.types.Action:
    for obj in objects:
        if obj.type == "ARMATURE" and obj.animation_data and obj.animation_data.action:
            return obj.animation_data.action
    if actions:
        return actions[0]
    raise RuntimeError("FBX did not contain an animation action")


def optional_sources() -> dict[str, Path]:
    """Return downloaded FBXs keyed by their normalized semantic filename."""
    found: dict[str, Path] = {}
    if not DOWNLOADED_DIR.exists():
        return found
    for path in sorted(DOWNLOADED_DIR.glob("*.fbx")):
        stem = path.stem.lower().replace("-", "_").replace(" ", "_")
        for semantic in OPTIONAL_SEMANTICS:
            if semantic in stem:
                found.setdefault(semantic, path)
                break
    return found


def remove_objects(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def make_material(name: str, color: tuple[float, float, float, float], roughness: float = 0.78) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled:
        principled.inputs["Base Color"].default_value = color
        principled.inputs["Roughness"].default_value = roughness
        if "Metallic" in principled.inputs:
            principled.inputs["Metallic"].default_value = 0.0
    return material


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
        slot = max(scores, key=scores.get) if scores else "torso"
        result[slot].add(polygon.index)
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
    delete_vertices = [vertex for vertex in edit_mesh.verts if vertex.index not in keep_vertices]
    bmesh.ops.delete(edit_mesh, geom=delete_vertices, context="VERTS")
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
    body_material = make_material("Alien_Girl_Untextured", (0.58, 0.64, 0.63, 1.0))
    eye_material = make_material("Alien_Girl_Eyes", (0.035, 0.045, 0.05, 1.0), 0.34)
    source_meshes = [
        obj for obj in list(bpy.data.objects)
        if obj.type == "MESH" and len(obj.data.vertices) > 0 and (
            obj.parent == rig or any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
        )
    ]
    output: list[bpy.types.Object] = []
    for source in source_meshes:
        assignments = classify_polygons(source)
        is_eye = "eye" in source.name.lower()
        for slot in LIMB_SLOTS:
            copied = polygon_copy(source, assignments[slot], slot)
            if copied is None:
                continue
            copied.data.materials.clear()
            copied.data.materials.append(eye_material if is_eye else body_material)
            output.append(copied)
        bpy.data.objects.remove(source, do_unlink=True)
    return output


def remove_empty_meshes() -> None:
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and len(obj.data.vertices) == 0:
            bpy.data.objects.remove(obj, do_unlink=True)


def apply_armature_transform(rig: bpy.types.Object, apply_location: bool = False) -> None:
    """Bake the FBX centimeter/axis conversion into the canonical armature.

    Leaving the imported +90-degree X rotation on the armature creates a valid
    GLB whose skinned mesh lies on its back in Godot. Applying the object
    transform preserves the visible Blender pose while producing a clean Y-up
    skeleton node in glTF.
    """
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
    for source in SOURCES.values():
        if not source.exists():
            raise FileNotFoundError(source)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()

    base_objects, base_actions = imported_objects(SOURCES["idle"])
    rig = next((obj for obj in base_objects if obj.type == "ARMATURE"), None)
    if rig is None:
        raise RuntimeError("Idle.fbx did not contain an armature")
    rig.name = "Alien_Girl_Rig"
    idle = action_for(base_objects, base_actions)
    idle.name = "idle"
    idle.use_fake_user = True

    actions = [idle]
    for clip_name in ("jab", "heavy_punch"):
        objects, imported_actions = imported_objects(SOURCES[clip_name])
        action = action_for(objects, imported_actions)
        action.name = clip_name
        action.use_fake_user = True
        actions.append(action)
        for obj in objects:
            if obj.type == "ARMATURE" and obj.animation_data:
                obj.animation_data.action = None
        remove_objects(objects)

    # Merge any explicitly downloaded bounded set. Missing optional clips are
    # represented by deterministic aliases later, preserving gameplay even
    # when Mixamo access is unavailable.
    imported_optional = optional_sources()
    for semantic, source in imported_optional.items():
        objects, imported_actions = imported_objects(source)
        action = action_for(objects, imported_actions)
        action.name = semantic
        action.use_fake_user = True
        actions.append(action)
        for obj in objects:
            if obj.type == "ARMATURE" and obj.animation_data:
                obj.animation_data.action = None
        remove_objects(objects)

    # Ensure every gameplay semantic has a stable action name. These aliases
    # intentionally reuse the closest supplied motion until a dedicated FBX is
    # downloaded; the README records which ones are approximate.
    aliases = {
        "walk_backward": "walk_forward", "falling": "jump", "landing": "jump",
        "guard_high": "idle", "guard_low": "idle", "hit_high": "idle",
        "hit_mid": "idle", "hit_low": "idle", "knockout": "idle",
        "high_attack": "jab", "mid_attack": "jab", "low_kick": "jab",
        "heavy_low_kick": "heavy_punch", "high_kick": "heavy_punch",
    }
    existing = {action.name: action for action in actions}
    for semantic in OPTIONAL_SEMANTICS:
        if semantic in existing:
            continue
        source_action = existing.get(aliases.get(semantic, "idle"), idle)
        alias = source_action.copy()
        alias.name = semantic
        alias.use_fake_user = True
        actions.append(alias)

    remove_empty_meshes()
    apply_armature_transform(rig)
    split_meshes = split_skinned_meshes(rig)
    if not split_meshes:
        raise RuntimeError("No skinned geometry remained after limb separation")

    # Normalize the evaluated character and bake the result into the armature.
    # Keeping this scale on a parent node causes Godot to apply it a second time
    # to the imported skinned AABBs. Baking produces an identity-transform GLB.
    low, _high, current_height = mesh_world_height(split_meshes)
    final_scale = TARGET_HEIGHT_METERS / current_height
    rig.scale = (final_scale,) * 3
    rig.rotation_euler.z = math.radians(90.0)  # Mixamo -Y facing to game +X.
    rig.location.z = -low * final_scale
    apply_armature_transform(rig, apply_location=True)

    root = bpy.data.objects.new("Alien_Girl", None)
    bpy.context.scene.collection.objects.link(root)
    rig.parent = root
    root["model_facing"] = 1
    root["source_format"] = "Mixamo FBX"

    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = None
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 110
    bpy.context.scene.frame_set(1)

    # This is a generated artifact, so repeated preparation should replace it
    # without accumulating Blender's numbered backup files in the repository.
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
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_merge_animation="ACTION",
        export_extra_animations=True,
        export_force_sampling=True,
        export_frame_range=True,
        export_extras=True,
        export_nla_strips=False,
        export_current_frame=False,
        export_reset_pose_bones=True,
        export_rest_position_armature=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_optimize_animation_size=False,
    )

    slot_counts = {slot: sum(1 for obj in split_meshes if obj.get("limb_slot") == slot) for slot in LIMB_SLOTS}
    print("WROTE_BLEND", BLEND_OUT)
    print("WROTE_GLB", GLB_OUT)
    print("ACTIONS", [action.name for action in actions])
    print("LIMB_OBJECTS", slot_counts)
    print("HEIGHT_METERS", round(TARGET_HEIGHT_METERS, 3))
    print("POLYGONS", sum(len(obj.data.polygons) for obj in split_meshes))


if __name__ == "__main__":
    main()

import bpy


SOURCE = "/Users/alsinas/Downloads/green+blocky+robot+3d+model/tripo_convert_e2d7f1ba-fe07-4f7f-a076-f464946c0200.obj"
OUTPUT = "/Users/alsinas/Projects/fighter/mixamo-robot-fixed/green_blocky_robot.obj"
TARGET_TRIANGLES = 100_000


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=SOURCE)

mesh_objects = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
if not mesh_objects:
    raise RuntimeError("The OBJ did not contain a mesh")

bpy.ops.object.select_all(action="DESELECT")
for obj in mesh_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_objects[0]

if len(mesh_objects) > 1:
    bpy.ops.object.join()

obj = bpy.context.active_object
original_triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
ratio = min(1.0, TARGET_TRIANGLES / original_triangles)

modifier = obj.modifiers.new(name="Mixamo polygon reduction", type="DECIMATE")
modifier.decimate_type = "COLLAPSE"
modifier.ratio = ratio
modifier.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=modifier.name)

bpy.ops.wm.obj_export(
    filepath=OUTPUT,
    export_selected_objects=True,
    export_materials=True,
    export_uv=True,
    export_normals=True,
    export_triangulated_mesh=True,
)

final_triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
print(f"MIXAMO_RESULT original_triangles={original_triangles} final_triangles={final_triangles} ratio={ratio:.8f}")

import bpy
from collections import deque
from mathutils import Vector

SOURCE = "/Users/alsinas/Projects/fighter/assets/models/the_girl_tripo/stylized girl 3d model.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SOURCE)
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
mesh = obj.data

neighbors = [set() for _ in mesh.vertices]
for edge in mesh.edges:
    a, b = edge.vertices
    neighbors[a].add(b)
    neighbors[b].add(a)

remaining = set(range(len(mesh.vertices)))
components = []
while remaining:
    start = remaining.pop()
    todo = [start]
    component = [start]
    while todo:
        current = todo.pop()
        for other in neighbors[current]:
            if other in remaining:
                remaining.remove(other)
                component.append(other)
                todo.append(other)
    components.append(component)

components.sort(key=len, reverse=True)
print("COMPONENT_COUNT", len(components))
for index, verts in enumerate(components):
    coords = [obj.matrix_world @ mesh.vertices[i].co for i in verts]
    low = Vector((min(v.x for v in coords), min(v.y for v in coords), min(v.z for v in coords)))
    high = Vector((max(v.x for v in coords), max(v.y for v in coords), max(v.z for v in coords)))
    center = (low + high) * 0.5
    size = high - low
    print(
        f"COMP {index:03d} verts={len(verts):5d} "
        f"center=({center.x:.4f},{center.y:.4f},{center.z:.4f}) "
        f"size=({size.x:.4f},{size.y:.4f},{size.z:.4f})"
    )

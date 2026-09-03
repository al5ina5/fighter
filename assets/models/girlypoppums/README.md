# Girlypoppums

This directory contains Girlypoppums' interchangeable fighter package and its
reproducible source assets.

## Sources

- `source/rig/Idle.fbx` — canonical textured mesh, skin weights, and 33-bone Mixamo rig
- `source/model/girlypoppums.obj` — reference render mesh
- `source/model/girlypoppums.mtl` — reference material
- `source/model/girlypoppums_basecolor.jpg` — 1024×1024 base-color texture
- `animations/*.fbx` — runtime animation-only Mixamo FBXs on the identical skeleton
- `animations/index.json` — gameplay-semantic arrays selecting one or more FBXs
- `source/animations/*.fbx` — original copies retained for rebuilding/auditing

The source tree is covered by `.gdignore`; Godot imports only the prepared output.

## Animation mapping

| Game semantic | Source FBX |
| --- | --- |
| `idle` | `Fighting Idle.fbx` |
| `walk` | `Walk.fbx` |
| `jump` | `Jump.fbx` |
| `block` | `Block.fbx` |
| `hit` | `Hit Reaction.fbx` |
| `knockout` | `Knockout.fbx` |
| `high_normal` | `High Normal Attack.fbx` |
| `high_heavy` | `High Heavy Attack.fbx` |
| `mid_normal` | `Mid Normal Attack.fbx` |
| `mid_heavy` | `Mid Heavy Attack.fbx` |
| `low_normal` | `Low Normal Attack.fbx` |
| `low_heavy` | `Low Heavy Attack.fbx` |

All gameplay actions share the canonical rig's exact bone signature. The runtime
FBXs are byte-for-byte copies of the supplied sources. Loading only converts the
FBX skeleton's units and rest offsets onto the live GLB skeleton; it preserves
the authored keys, duration, and root motion.

The character profile stores a measured contact point for each of the six attacks. Every clip plays at its authored 1× speed. At runtime, a per-fighter move copy derives startup from that contact point, opens its deterministic hitbox there, and assigns the rest of the clip to recovery. The original reusable move resource is never mutated.

The prepared mesh is separated into `head`, `torso`, `arm_l`, `arm_r`, `leg_l`, and `leg_r` skinned surfaces. That preserves the current limb-loss mechanic while every surface continues to animate from the same skeleton and use the supplied texture.

`animations/` is runtime-swappable: `FighterAnimationSet` loads loose skinless
Mixamo FBXs from it and maps them onto the live skeleton at startup, so replacing
a file changes the clip without rebuilding the GLB. `index.json` stores arrays
of filenames per gameplay semantic; add another filename to an array to cycle
through multiple idles, hit reactions, or attacks. Fighting Idle is currently
the only selected `idle`; it plays its full 3.3-second Mixamo loop at 1× speed.
The older `Idle.fbx` remains available but unused.
The committed `.fbx.import` files preserve Mixamo's centimeter-scale hips/root
motion before Godot optimizes tracks. Keep the matching sidecar when replacing
an FBX; no Blender step is involved.

## Rebuild

From the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/prepare_girlypoppums.py
```

This is only needed when the mesh, skin weights, skeleton, texture, or detachable
limb split changes. It regenerates:

- `source/girlypoppums_prepared.blend` — editable, texture-packed source
- `girlypoppums_prepared.glb` — Godot-ready textured fighter used by the roster

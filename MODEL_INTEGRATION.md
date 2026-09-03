# 2.5D Fighter Model Contract

The combat simulation is deliberately model-independent. `Player.gd` keeps the
single-plane movement, pushboxes, hitboxes, hurtboxes, attack timing, stance,
limb HP, blocking, and KO rules. `FighterVisual3D.gd` mirrors that state onto a
rigged model in the 3D arena.

## Recommended delivery format

- Godot-importable `.glb` / `.gltf` with mesh, skeleton, skin, materials, and
  clips in one file.
- Y-up, model root at the floor between the feet, and no baked root locomotion.
- Author the fighter facing **+X**. A model authored facing -X is also supported.
- Use meters when practical. Per-character scale and offsets can correct other
  authoring units without touching combat code.

No collision mesh is needed. Deterministic fighter-space rectangles remain
authoritative and keep the fighting game independent from render-frame skeleton
poses. These are pure combat data—not `Area2D` children attached to the legacy
2D rig. The prepared model's hips are automatically centered over the combat
root after its configured scale and rotation are applied.

## Registering a model

Set these optional fields on the character entry in `scripts/GameState.gd`:

```gdscript
{
    "name": "Girl",
    "color": Color(0.95, 0.4, 0.7),
    "model_path": "res://assets/models/girl/girl.glb",
    "animations_dir": "res://assets/models/girl/animations",
    "model_scale": 1.0,
    "model_facing": 1,
    "model_offset": Vector3.ZERO,
    "model_rotation_y": 0.0,
    "animation_map": {
        "idle": "idle",
        "walk": "walk",
        "jump": "jump",
        "block": "block",
        "hit": "hit",
        "knockout": "knockout",
        "high_normal": "high_normal",
        "high_heavy": "high_heavy",
        "mid_normal": "mid_normal",
        "mid_heavy": "mid_heavy",
        "low_normal": "low_normal",
        "low_heavy": "low_heavy",
    },
}
```

`model_facing` is `1` for +X or `-1` for -X. `model_rotation_y` is an additional
correction in degrees. If a path is empty or fails to load, the engine supplies
a fully synchronized procedural 3D fighter so the game remains playable.

## Animation names

The adapter searches case-insensitively and accepts common variations:

| Gameplay state | Preferred clip | Accepted examples |
| --- | --- | --- |
| Neutral | `idle` | `Fight_Idle`, `combat_idle` |
| Movement | `walk` | `Walk_Forward`, `run` |
| Airborne | `jump` | `Jump_Start` |
| Defense | `block` | `guard` |
| Damage | `hit` | `Hit_React`, `hurt` |
| Defeat | `knockout` | `KO`, `death` |
| High normal | `high_normal` | `jab`, `Punch_Jab`, `punching` |
| High heavy | `high_heavy` | `high_kick`, `Kick_High`, `roundhouse` |
| Mid normal | `mid_normal` | `jab`, `Punch_Jab`, `punching` |
| Mid heavy | `mid_heavy` | `heavy_punch`, `Punch_Heavy`, `PunchingHeavy` |
| Low normal | `low_normal` | `low_kick`, `Kick_Low`, `sweep` |
| Low heavy | `low_heavy` | `heavy_kick`, `Kick_Low`, `sweep` |

`animation_map` explicitly maps gameplay semantics to a model's authored clip
names, so imported clips do not need to use the preferred names. Attack clips
play continuously at their authored 1× speed. The runtime move copy derives its
startup from the configured contact ratio, opens the deterministic active
hitbox at that pose, and uses the rest of the clip as recovery. Hitstop pauses
and resumes that playback in place without changing its rate. A character can
optionally provide
`animation_contact_ratios` (values from `0.0` to `1.0`) to mark the authored
impact pose. Missing clips gracefully fall back to idle.

## Detachable limbs

Separate limb meshes are recommended for the game's core dismemberment mechanic.
Assign the `limb_slot` metadata to each detachable mesh:

`head` · `torso` · `arm_l` · `arm_r` · `leg_l` · `leg_r`

Optional stump meshes use the same `limb_slot` plus `is_stump = true`. The
adapter hides the limb and reveals its stump when that simulation limb reaches
zero HP. It also recognizes conventional names such as `arm_l_*`, `leg_r_*`,
`head_*`, `torso_*`, and names containing `stump`.

Skeleton bone names are unrestricted when animations stay embedded inside the
model. Loose animation packages must share the base model's bone-name signature;
the loader validates that signature before registering a clip. Separate skinned
mesh objects (or metadata on their mesh nodes) are what make per-limb visibility
work.

## Swappable loose animations

Every character package can carry a **loose animation folder** (`animations/`)
next to its base model. `FighterAnimationSet` scans that folder at runtime,
loads each skinless Mixamo FBX, and retargets its bone tracks onto the
character's live skeleton. Because every Mixamo export shares the canonical
33-bone rig, this works with no per-animation setup:

- Replace a file in `animations/` and the character uses the new clip on the
  next run. No re-rig, no rebuild, no code changes.
- The clip is chosen from the filename. Normalized basenames map to gameplay
  semantics; aliases like `Fighting Idle.fbx`, `fight_idle.fbx`, or `idle.fbx`
  all resolve to the `idle` semantic. The full alias table lives in
  `FighterAnimationSet.FALLBACK_SEMANTICS`.
- A character profile sets `animations_dir` to locate the folder, e.g.
  `res://assets/models/girlypoppums/animations`. Loaded clips override the
  baked animation_map for the same semantic.

Keep each committed `.fbx.import` sidecar beside its FBX when replacing a clip.
Mixamo animation-only exports use centimeter-scale bone translations. The
sidecar imports the scene at `100.0` root scale and 60 FPS before Godot reduces
animation tracks; without it, subtle hips/root keys can collapse into one
constant key and the feet appear to slide under a stationary body. Replacing an
existing FBX under the same filename automatically reuses the correct sidecar.
For a brand-new filename, copy any existing `.fbx.import` sidecar, rename it to
match, then let Godot reimport it.

At runtime, the permanent start-to-end hips trajectory is removed from every
loose clip and recentered on the combat root. Non-linear weight shifts, lunges,
and follow-through remain visible; gameplay root travel stays authored in
`FighterMoveData`, so a clip cannot accumulate drift away from its collision.

### Multiple clips per semantic

An optional `animations/index.json` maps a semantic to an array of filenames,
so a semantic can hold several variants (multiple hit reactions, multiple
idles):

```json
{
  "hit": ["Hit Reaction.fbx", "Hit Reaction 2.fbx"],
  "idle": ["Fighting Idle.fbx", "Box Idle.fbx"]
}
```

The adapter advances deterministically through the array. One-entry looping
states loop continuously; multi-entry idle/walk/block sets advance when a clip
finishes. Hit reactions and attacks advance each time the state starts, so
adding a file plus one manifest entry makes it available in-game.

### Left/right lead mirroring

No duplicate southpaw animation files are required. Every loose clip receives a
runtime-generated mirrored partner. The generator samples the animation in
skeleton space at 60 Hz, exchanges canonical `Left`/`Right` Mixamo bone pairs,
reflects their complete transforms across the hips plane, and writes ordinary
positive-scale animation tracks. Changing lead blends the character's chest
through a ±22-degree depth turn and selects the corresponding full-body clip.
Punches, kicks, idle asymmetry, walking, blocking, hit reactions, and knockouts
therefore flip together while anatomical limb identity remains unchanged.

### Locomotion direction and physical depth

The combat controller distinguishes advancing from retreating using velocity
relative to facing. Forward movement plays the supplied walk cycle normally;
retreating plays the full in-place cycle backward at the same authored 1× rate.
A future character may replace that fallback with a dedicated authored
back-walk semantic without changing combat movement.

Fighter models are not assigned per-player rendering lanes. Both presentation
roots use world Z = 0, and stance yaw plus the imported skeleton animation place
individual limbs at real depths. Normal 3D depth testing therefore determines
occlusion when two fighters overlap on screen.

When both leg regions are destroyed, `FighterVisual3D` measures the live hips
bone after animation and offsets the model root until that bone sits just above
the floor. The simulation simultaneously switches to its low pelvis pushbox and
zero locomotion, keeping the visible posture, movement rules, and collision in
the same state.

### Robot package status

`assets/models/robot/` is staged with the same twelve animation FBXs in its own
`animations/` folder plus the PBR texture set under `source/`. The base rigged
mesh (`robot_prepared.glb`) is produced by:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/prepare_robot.py
```

That one-time script fits the canonical Mixamo armature into the supplied robot
OBJ, auto-weights the mesh, splits detachable limb surfaces, and exports a
Godot-ready base GLB identical in contract to Girlypoppums'. The twelve actions
stay loose under `animations/` and do not require another Blender export.

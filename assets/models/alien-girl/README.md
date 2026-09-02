# Alien Girl

The three source FBXs are preserved unchanged:

- `Idle.fbx`
- `Punching.fbx`
- `PunchingHeavy.fbx`

Run `blender --background --python tools/prepare_alien_girl.py` from the
repository root to generate:

- `source/alien_girl_prepared.blend` — cleaned editable source
- `alien_girl_prepared.glb` — Godot-ready model used by the roster

The preparation step merges the compatible Mixamo actions as `idle`, `jab`, and
`heavy_punch`, fixes scale and facing, removes empty FBX geometry, applies simple
untextured materials, and separates the skinned surfaces into the six detachable
limb slots required by the game.

Optional bounded Mixamo downloads belong in `source/downloaded/` (the original
three FBXs above are never modified). Name each file with one of these semantic
tokens so the script picks it up automatically: `walk_forward`, `walk_backward`,
`jump`, `falling`, `landing`, `guard_high`, `guard_low`, `hit_high`, `hit_mid`,
`hit_low`, `knockout`, `high_attack`, `mid_attack`, `low_kick`, `heavy_low_kick`,
or `high_kick`. Export as FBX Binary, Without Skin, preferably In Place, then
rerun `blender --background --python tools/prepare_alien_girl.py`.

The current environment could open Mixamo but had no signed-in Adobe session,
so no new FBXs were downloadable without user authentication. The generated
asset therefore includes deterministic named aliases: locomotion/jump/guard/
hit/KO aliases reuse `idle`, attack aliases reuse `Punching`, and heavy kick
aliases reuse `PunchingHeavy`. Once optional files are added, those aliases are
automatically replaced by the real clips. Gameplay timing and hitboxes are
unaffected.

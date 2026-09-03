# Combat System Specification

This is the authoritative contract for the replacement combat system. Gameplay
uses a deterministic 60 Hz simulation; imported 3D models and animation clips
present that state but never decide whether a strike connects.

## Design goals

- Inputs should feel immediate, consistent, and learnable.
- Every grounded attack must work at the closest legal pushbox spacing.
- A hit damages a hurtbox that the strike actually touched.
- Range, damage, active-window length, guard behavior, and cancel routes are
  authored data. Startup and recovery intentionally follow each character's
  visible 1× animation rather than physics callback order or playback scaling.
- Limb damage adds tactical consequences without replacing the familiar shared
  vitality bar used to decide a round.

## Attack frame data

All values are simulation frames at 60 Hz. Total duration is startup + active +
recovery. Hitstop freezes both fighters and their visible attack animations.
Each move is a typed `FighterMoveData` resource under `data/moves/`; its active
window, damage, root travel, guard behavior, hitboxes, and optional hurtbox
overrides are one inspectable source of truth. At character load, a per-fighter
runtime copy derives startup and recovery from the actual 1× animation. The base
resource is never mutated and `Player.gd` contains no parallel attack table.

| Move | Start | Active | Recovery | Damage | Hitstun | Blockstun | Hitstop | Guard rule |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| High normal | 44 | 3 | 143 | 5.5 | 17 | 11 | 4 | Any guard |
| Mid normal | 55 | 4 | 85 | 7 | 22 | 13 | 5 | Any guard |
| Low normal | 51 | 4 | 94 | 8 | 25 | 14 | 6 | Crouch guard |
| High heavy | 49 | 5 | 82 | 15 | 36 | 18 | 9 | Stand guard; knockdown |
| Mid heavy | 156 | 5 | 91 | 12 | 29 | 16 | 7 | Any guard |
| Low heavy | 49 | 6 | 29 | 14 | 34 | 17 | 8 | Crouch guard; knockdown |

The displayed timing is generated from the current shared animation package.
Each clip plays at 1× from first frame to last. Its configured contact ratio
defines the first active frame, the authored 3–6 frame gameplay window remains
active, and every remaining animation frame becomes recovery. Replacing a clip
automatically regenerates those values for the fighter using it.

Normals chain on confirmed hit or block in the route high → mid → low → heavy.
Inputs are buffered for 10 frames during recovery or hitstun. A whiff cannot be
cancelled, preserving a punish window. Attacking or changing stance produces a
counter hit: 20% more damage and four extra hitstun frames.
Confirmed sequences of two or more clean hits produce a HUD combo counter.

## Spatial model

- The narrow blue pushbox represents the fighter's body core. Guard limbs may
  visually meet or overlap while it prevents torsos from crossing one another.
  Humanoid standing width is 34 simulation units (102 screen pixels at the
  current scale), allowing hands, shoulders, and feet to touch before core
  contact. Unusually broad characters define their own stable core width in the
  roster profile rather than relying on one skeleton-sized box for everyone.
- Green hurtboxes represent damageable anatomy.
- Red hitboxes exist only during authored active frames.
- Hitboxes are broad strike volumes extending from inside the pushbox to the end
  of the move's reach. Starting inside the pushbox eliminates the former
  point-blank dead zone.
- Collision is computed directly from current rectangles during the combat tick.
  It does not use `Area2D.get_overlapping_areas()`, whose overlap list updates on
  the physics step and can otherwise be one frame stale.
- The old rig-attached `Area2D` hitboxes and hurtboxes have been removed. Neutral
  anatomy comes from `FighterCollisionProfile`; move-specific volumes come from
  the active move resource. Moving or replacing a presentation rig cannot move
  combat collision.
- Grounded pushboxes receive a deterministic post-physics separation pass. Both
  players split any correction and inward velocity is cancelled, so simultaneous
  forward movement cannot leave them intersecting or swap their left/right order.
- Every attack may deal damage once. If several hurtboxes overlap, attack target
  priority is only a tie-breaker among boxes that were actually contacted.
- Facing locks during the attack so a fighter cannot reverse a strike halfway
  through it.
- Both 3D fighter roots share one depth plane. Animated geometry and the depth
  buffer decide which hand, foot, or torso is in front; player number never
  forces one complete model behind the other.

Press F1 in battle to display pushboxes, hurtboxes, active hitboxes, state,
attack phase/frame, vitality, guard, and fighter distance.

## Stance and limb roles

- Stance assigns an anatomical left or right side as the lead side.
- Facing maps the lead side toward the opponent and changes independently.
- High normal uses the lead arm; high heavy uses the rear leg.
- Mid normal/heavy use the lead/rear arms.
- Low normal/heavy use the lead/rear legs.
- A ten-frame stance transition visibly moves limbs before committing the role.
- The 3D presentation rotates through a squared chest during those ten frames,
  then settles into the opposite ±22-degree depth stance. At commit, the full
  skeleton switches to a mirrored animation variant, so anatomical left/right
  arms and legs exchange their visual lead/rear roles.
- If the requested limb is gone, the fighter uses a short-range, low-damage
  desperation strike with the head or torso. Inputs never silently disappear.

Target priority is high: head; mid: lead arm then torso; low: lead leg, rear leg,
lead arm, rear arm, torso. If both legs are gone, the lowered posture allows mids
to reach the head. These priorities never override actual geometric contact.

## Damage, defense, and reactions

- Every clean hit reduces universal vitality and trauma on the contacted limb.
- Head hits deal 1.12× vitality damage, torso hits 1.0×, and extremities 0.88×.
- Zero vitality, a destroyed head, or a destroyed torso causes KO.
- Other destroyed limbs disappear and their combat regions are excluded. One
  missing leg reduces movement; losing both stops locomotion, switches to a low
  pelvis pushbox, and pins the animated hip bone just above the arena floor
  without making the fighter untargetable.
- Hold away from the opponent for standing guard. Use the block/down input for
  crouch guard. Down has strict priority over horizontal, jump, attack, and
  stance inputs, so it never creeps the fighter along the floor. Lows beat
  standing guard; overheads beat crouch guard.
- Guard absorbs normal chip, takes reduced heavy chip, adds pushback and
  blockstun, and consumes a 100-point guard meter. Empty guard causes a 40-frame
  guard break. Guard begins regenerating after a 90-frame delay.
- Heavy attacks and counter hits have stronger freeze, impact sound, camera
  shake, knockback, and visual callouts. Heavy highs/lows knock down.
- Knocked-down fighters cannot be struck again until their wake-up completes;
  this avoids accidental standing-hurtbox OTG loops.
- Air-hit damage scales by 10% per follow-up to a 45% floor.

## Match rules

- A match is first to two rounds with a 99-second frame-based timer.
- The higher vitality wins on timeout; equal vitality is a draw and replays the
  round without awarding a point.
- Hits are queued and resolved together after both fighters' physics turns, so
  same-frame trades and double KOs do not depend on scene-tree order.
- The round timer pauses during hitstop and while the pause menu is open.
- A new round restores vitality, guard, limbs, collision, stance, and positions.

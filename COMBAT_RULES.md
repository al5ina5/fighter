# Combat Rules

This file records the combat behavior approved for the current prototype. It is
the specification for the combat implementation; older roadmap and concept notes
are background only when they disagree with these rules.

## Stance and limb roles

- Stance selects which anatomical side is close to the opponent.
- Facing only determines which screen direction is toward the opponent.
- Changing stance visibly swaps the close and rear arms and legs.
- Normal attacks use the close limb. Heavy attacks use a committed rear limb.
- If the required attacking limb is detached, the attack fails. The player must
  change stance or choose an attack supported by a surviving limb.

## Target rules

| Attack | Attacking limb | Heavy attacking limb | Target priority |
| --- | --- | --- | --- |
| High | Close arm (head punch) | Rear leg (head kick) | Head |
| Medium | Close arm | Rear arm | Close arm, then torso |
| Low | Close leg | Rear leg | Close leg, rear leg, close arm, rear arm, torso |

When both of the defender's legs are detached, medium attacks target the head.
Destroying the head or torso ends the fight. The heavy high head kick has a
long startup, a short contact window, and substantial whiff recovery. Heavy
attacks do not change the defender target rules.

## Collision and responsiveness

- A strike hitbox follows the endpoint of the selected attacking hand or foot.
- The strike must overlap the selected target limb's actual hurtbox. Touching a
  different body part never redirects damage into the preferred target.
- Detached-limb hurtboxes are disabled until the round resets.
- Fighter bodies collide through posture-aware physics pushboxes. A fighter
  with both legs removed uses a shorter floor-level body shape.
- Facing is locked for the duration of an attack. Stance changes have a brief
  transition, and target roles follow whichever limb is visibly closer.
- Attack input is buffered briefly during recovery and hitstun.

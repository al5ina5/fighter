# Combat Rules

This file records the combat behavior approved for the current prototype. It is
the specification for the combat implementation; older roadmap and concept notes
are background only when they disagree with these rules.

## Stance and limb roles

- Stance selects which anatomical side is close to the opponent.
- Facing only determines which screen direction is toward the opponent.
- Changing stance visibly swaps the close and rear arms and legs.
- Normal attacks use the close limb. Heavy attacks use the rear limb.
- If the required attacking limb is detached, the attack fails. The player must
  change stance or choose an attack supported by a surviving limb.

## Target rules

| Attack | Attacking limb | Heavy attacking limb | Target priority |
| --- | --- | --- | --- |
| High | Close arm | Rear arm | Head |
| Medium | Close arm | Rear arm | Close arm, then torso |
| Low | Close leg | Rear leg | Close leg, rear leg, close arm, rear arm, torso |

When both of the defender's legs are detached, medium attacks target the head.
Destroying the head or torso ends the fight. Heavy attacks have more windup,
longer commitment, and more damage, but do not change the defender target rules.

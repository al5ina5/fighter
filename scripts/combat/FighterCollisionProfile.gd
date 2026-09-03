extends RefCounted
class_name FighterCollisionProfile

## Neutral hurtboxes are combat data, not children of the legacy visual rig.
## Values use fighter-space units and are mirrored around the fighter root.

const BASE_CENTERS := {
	"head": Vector2(0, -32),
	"torso": Vector2(0, -10),
	"arm_l": Vector2(-18, -8),
	"arm_r": Vector2(18, -8),
	"leg_l": Vector2(-7, 21),
	"leg_r": Vector2(7, 21),
}

const BASE_SIZES := {
	"head": Vector2(18, 16),
	"torso": Vector2(26, 24),
	"arm_l": Vector2(9, 20),
	"arm_r": Vector2(9, 20),
	"leg_l": Vector2(11, 38),
	"leg_r": Vector2(11, 38),
}


static func local_center(limb_name: String, stance: int, facing: int, legless: bool) -> Vector2:
	var center: Vector2 = BASE_CENTERS[limb_name]
	if limb_name.contains("_"):
		center.x = CombatRules.pose_x(limb_name, stance, facing)
	if legless:
		center.y += 38.0
	return center


static func local_size(limb_name: String) -> Vector2:
	return BASE_SIZES[limb_name]


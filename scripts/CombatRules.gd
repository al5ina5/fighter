extends RefCounted
class_name CombatRules

## The authoritative, presentation-independent combat rules.
## Anatomical sides (l/r) never mean screen direction. Stance assigns one
## anatomical side to the close/lead role; facing maps that role toward the foe.

const LEFT := "l"
const RIGHT := "r"

const HIGH := "high"
const MID := "mid"
const LOW := "low"

const ARM_OFFSET_X := 18.0
const LEG_OFFSET_X := 7.0


static func opposite_side(side: String) -> String:
	return LEFT if side == RIGHT else RIGHT


static func close_side(stance: int) -> String:
	return RIGHT if stance >= 0 else LEFT


static func rear_side(stance: int) -> String:
	return opposite_side(close_side(stance))


static func source_limb(band: String, heavy: bool, stance: int) -> String:
	var side := rear_side(stance) if heavy else close_side(stance)
	match band:
		HIGH, MID:
			return "arm_" + side
		LOW:
			return "leg_" + side
	return ""


static func target_priority(band: String, target_stance: int, target_limbs: Dictionary) -> Array[String]:
	var close := close_side(target_stance)
	var rear := rear_side(target_stance)
	match band:
		HIGH:
			return ["head"]
		MID:
			# A fighter with no legs is low enough for a mid strike to reach the head.
			if _is_gone(target_limbs, "leg_l") and _is_gone(target_limbs, "leg_r"):
				return ["head"]
			return ["arm_" + close, "torso"]
		LOW:
			# Low attacks climb the body only as lower targets are destroyed.
			return [
				"leg_" + close,
				"leg_" + rear,
				"arm_" + close,
				"arm_" + rear,
				"torso",
			]
	return []


static func pick_target(band: String, target_stance: int, target_limbs: Dictionary) -> String:
	for limb_name in target_priority(band, target_stance, target_limbs):
		if not _is_gone(target_limbs, limb_name):
			return limb_name
	return ""


static func pose_x(limb_name: String, stance: int, facing: int) -> float:
	if not limb_name.contains("_"):
		return 0.0
	var side := limb_name.get_slice("_", 1)
	var toward_opponent := 1.0 if side == close_side(stance) else -1.0
	var offset := ARM_OFFSET_X if limb_name.begins_with("arm_") else LEG_OFFSET_X
	return float(facing) * toward_opponent * offset


static func is_close_limb(limb_name: String, stance: int) -> bool:
	return limb_name.ends_with("_" + close_side(stance))


static func _is_gone(limbs: Dictionary, limb_name: String) -> bool:
	if not limbs.has(limb_name):
		return true
	var data: Dictionary = limbs[limb_name]
	return bool(data.get("gone", false))

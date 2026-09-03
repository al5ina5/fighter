extends Resource
class_name FighterMoveData

## Inspector-editable source of truth for one move. Its active window, collision,
## damage, and movement are authored here. A per-fighter runtime duplicate aligns
## startup and recovery to that character's 1x animation without mutating this
## reusable base resource.

@export var move_id := ""
@export var band := "mid"
@export var heavy := false
@export var animation_semantic := "mid_normal"
@export var chain_rank := 0
@export var startup_frames := 1
@export var active_frames := 1
@export var recovery_frames := 1
@export var damage := 1.0
@export var limb_damage := 1.0
@export var hitstun_frames := 1
@export var blockstun_frames := 1
@export var hitstop_frames := 1
@export var guard_damage := 1.0
@export var chip_ratio := 0.0
@export var guard_type := "mid"
@export var knockback := 100.0
@export var launch := 0.0
@export var knockdown := false
@export var startup_travel := 0.0
@export var active_travel := 0.0
@export var recovery_travel := 0.0
@export var hitboxes: Array[CombatBoxData] = []
@export var hurtbox_overrides: Array[CombatBoxData] = []


func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames


func phase_at(frame: int) -> String:
	if frame < startup_frames:
		return "startup"
	if frame < startup_frames + active_frames:
		return "active"
	return "recovery"


func root_delta_at(frame: int) -> float:
	var phase := phase_at(frame)
	if phase == "startup":
		return startup_travel / maxf(1.0, float(startup_frames))
	if phase == "active":
		return active_travel / maxf(1.0, float(active_frames))
	return recovery_travel / maxf(1.0, float(recovery_frames))


func active_hitboxes(frame: int) -> Array[CombatBoxData]:
	var result: Array[CombatBoxData] = []
	for box in hitboxes:
		if box.active_on(frame):
			result.append(box)
	return result


func hurtbox_override(region_name: String, frame: int) -> CombatBoxData:
	for box in hurtbox_overrides:
		if box.region == region_name and box.active_on(frame):
			return box
	return null


func to_runtime_data() -> Dictionary:
	return {
		"move_resource": self,
		"move_id": move_id,
		"animation_semantic": animation_semantic,
		"band": band,
		"heavy": heavy,
		"chain_rank": chain_rank,
		"startup_frames": startup_frames,
		"active_frames": active_frames,
		"recovery_frames": recovery_frames,
		"windup": float(startup_frames) / 60.0,
		"active": float(active_frames) / 60.0,
		"recovery": float(recovery_frames) / 60.0,
		"damage": damage,
		"limb_damage": limb_damage,
		"hitstun_frames": hitstun_frames,
		"blockstun_frames": blockstun_frames,
		"hitstop_frames": hitstop_frames,
		"guard_damage": guard_damage,
		"chip_ratio": chip_ratio,
		"guard_type": guard_type,
		"knockback": knockback,
		"launch": launch,
		"knockdown": knockdown,
	}

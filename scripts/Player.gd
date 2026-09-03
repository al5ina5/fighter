extends CharacterBody2D
class_name Player

## Deterministic single-plane fighting-game controller. Combat is authored in
## integer 60 Hz frames. The 3D skeleton is presentation; these fighter-space
## hitboxes, hurtboxes, pushboxes, and frame rules are authoritative.

const SCALE := 3.0
const COMBAT_FPS := 60.0
const FORWARD_SPEED := 360.0
const BACKWARD_SPEED := 285.0
const AIR_SPEED := 245.0
const JUMP_VELOCITY := -760.0
const GRAVITY := 1900.0
const GUARD_MAX := 100.0
const GUARD_REGEN_PER_FRAME := 0.55
const GUARD_REGEN_DELAY_FRAMES := 90
const STANCE_POSE_SPEED := 220.0
const STANCE_TRANSITION_FRAMES := 10
const INPUT_BUFFER_FRAMES := 10
const ARM_LENGTH := 20.0
const LEG_LENGTH := 38.0

const LIMB_MAX := {
	"head": 65.0, "torso": 120.0, "arm_l": 55.0, "arm_r": 55.0,
	"leg_l": 60.0, "leg_r": 60.0,
}
const LIMBS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

const MOVES := {
	"high": {false: preload("res://data/moves/high_normal.tres"), true: preload("res://data/moves/high_heavy.tres")},
	"mid": {false: preload("res://data/moves/mid_normal.tres"), true: preload("res://data/moves/mid_heavy.tres")},
	"low": {false: preload("res://data/moves/low_normal.tres"), true: preload("res://data/moves/low_heavy.tres")},
}

signal died
signal combat_event(kind: String, data: Dictionary)

enum State { IDLE, STANCE, ATTACK, HITSTUN, BLOCKSTUN, KNOCKDOWN, KO }

@export var player_number: int = 1
@export var body_color: Color = Color(0.85, 0.2, 0.2)
@export var show_debug_rig := true
@export var standing_pushbox_width := 34.0
@export var airborne_pushbox_width := 30.0
@export var legless_pushbox_width := 30.0

@onready var rig: Node2D = $Rig
@onready var face: ColorRect = $Rig/Face
@onready var stance_marker: ColorRect = $Rig/StanceMarker
@onready var body_shape: CollisionShape2D = $CollisionShape2D

var health := 100.0
var guard := GUARD_MAX
var limb_hp: Dictionary = {}
var state: int = State.IDLE
var facing := 1
var stance := 1
var pending_stance := 1
var stance_timer := 0.0
var stance_frames_left := 0
var hurt_timer := 0.0
var state_frames_left := 0
var flash_timer := 0.0
var attack: Dictionary = {}
var attack_phase := ""
var attack_time := 0.0
var attack_frame := 0
var hit_landed := false
var attack_connected := false
var attack_was_blocked := false
var attack_facing := 1
var input_locked := false
var air_hits := 0
var hurt_tilt := 0.0
var stick_was_up := false
var active_move: FighterMoveData
var buffered_band := ""
var buffered_heavy := false
var input_buffer_frames := 0
var input_buffer_timer := 0.0
var guard_recover_delay_frames := 0
var combo_chain_rank := -1
var animation_timings: Dictionary = {}


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	rig.visible = show_debug_rig
	body_shape.shape = body_shape.shape.duplicate()
	_setup_limbs()
	_snap_stance_visuals()


func _physics_process(delta: float) -> void:
	_capture_attack_input()
	if not input_locked and state == State.IDLE and buffered_band == "" and not _crouch_guard_held() and Input.is_action_just_pressed(_action("stance")):
		_start_stance_change()
	if state != State.ATTACK:
		_update_facing()
	_apply_stance_visuals(delta)
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	match state:
		State.IDLE:
			_apply_idle()
		State.STANCE:
			velocity.x = 0.0
			stance_frames_left -= 1
			stance_timer = maxf(0.0, float(stance_frames_left) / COMBAT_FPS)
			if stance_frames_left <= 0:
				_finish_stance_change()
		State.ATTACK:
			_tick_attack()
		State.HITSTUN:
			_tick_reaction(0.86)
		State.BLOCKSTUN:
			_tick_reaction(0.80)
		State.KNOCKDOWN:
			_tick_knockdown()
		State.KO:
			velocity.x *= 0.90

	var tilt_target := hurt_tilt if state in [State.HITSTUN, State.KNOCKDOWN] else 0.0
	rig.rotation = lerpf(rig.rotation, tilt_target, delta * 14.0)
	rig.position.y = 38.0 if _is_legless() else 0.0
	_update_body_collision()
	move_and_slide()
	_update_flash(delta)
	_tick_guard()
	_tick_input_buffer()


func _apply_idle() -> void:
	if input_locked:
		velocity.x = 0.0
		return
	# Down is a dedicated stationary low guard. It always wins over buffered
	# offense, jumping, stance changes, and horizontal input. If the input begins
	# on the landing frame, horizontal motion still cannot leak through.
	if _crouch_guard_held():
		velocity.x = 0.0
		combo_chain_rank = -1
		_clear_input_buffer()
		return
	if buffered_band != "":
		_begin_buffered_attack(false)
		return
	if _jump_pressed() and is_on_floor() and not _is_legless():
		velocity.y = JUMP_VELOCITY
		return
	var direction := _move_dir()
	if not is_on_floor():
		velocity.x = direction * AIR_SPEED * _mobility_ratio()
	elif direction * float(facing) < 0.0:
		velocity.x = direction * BACKWARD_SPEED * _mobility_ratio()
	else:
		velocity.x = direction * FORWARD_SPEED * _mobility_ratio()
	if absf(direction) < 0.01:
		combo_chain_rank = -1


func _attack_data(band: String, heavy: bool) -> Dictionary:
	var move := (MOVES[band][heavy] as FighterMoveData).duplicate(true) as FighterMoveData
	_apply_animation_timing(move)
	return move.to_runtime_data()


func configure_animation_timing(semantic: String, duration_seconds: float, contact_ratio: float) -> void:
	var total_frames := maxi(3, roundi(duration_seconds * COMBAT_FPS))
	var contact_frame := clampi(roundi(duration_seconds * contact_ratio * COMBAT_FPS), 1, total_frames - 2)
	animation_timings[semantic] = {
		"total_frames": total_frames,
		"contact_frame": contact_frame,
	}


func _apply_animation_timing(move: FighterMoveData) -> void:
	if move == null or not animation_timings.has(move.animation_semantic):
		return
	var timing: Dictionary = animation_timings[move.animation_semantic]
	var total_frames := int(timing.total_frames)
	var startup_frames := int(timing.contact_frame)
	var active_frames := mini(move.active_frames, total_frames - startup_frames - 1)
	active_frames = maxi(1, active_frames)
	move.startup_frames = startup_frames
	move.active_frames = active_frames
	move.recovery_frames = maxi(1, total_frames - startup_frames - active_frames)
	# Active collision begins at the measured contact pose and lasts for the
	# authored gameplay window. The visible swing and deterministic hit window
	# therefore share one clock without deriving collision from skeleton bones.
	for box in move.hitboxes:
		box.start_frame = move.startup_frames
		box.end_frame = move.startup_frames + move.active_frames - 1


func estimated_attack_reach(band: String, heavy: bool) -> float:
	var data := _attack_data(band, heavy)
	var move := data.move_resource as FighterMoveData
	var maximum := 0.0
	for box in move.hitboxes:
		maximum = maxf(maximum, (box.center.x + box.size.x * 0.5) * SCALE)
	return maximum


func _requested_attacking_limb(band: String, heavy: bool) -> String:
	return CombatRules.source_limb(band, heavy, stance)


func _attacking_limb(band: String, heavy: bool) -> String:
	var requested := _requested_attacking_limb(band, heavy)
	if _limb_available(requested):
		return requested
	if band in ["high", "mid"] and _limb_available("head"):
		return "head"
	if _limb_available("torso"):
		return "torso"
	return ""


func _begin_buffered_attack(is_cancel: bool) -> void:
	var band := buffered_band
	var heavy := buffered_heavy
	var data := _attack_data(band, heavy)
	if is_cancel and int(data.chain_rank) <= combo_chain_rank:
		return
	_clear_input_buffer()
	var requested := _requested_attacking_limb(band, heavy)
	var swing_limb := _attacking_limb(band, heavy)
	if swing_limb == "":
		return
	data["name"] = swing_limb
	if swing_limb != requested:
		data = _desperation_move(band).to_runtime_data()
		data["name"] = swing_limb
		data["fallback"] = true
		_float_text(global_position + Vector2(0, -88.0), "DESPERATION", Color(1.0, 0.65, 0.2))
	_start_attack(data)


func _desperation_move(band: String) -> FighterMoveData:
	var move := FighterMoveData.new()
	move.move_id = "desperation_%s" % band
	move.band = band
	move.animation_semantic = "%s_normal" % band
	move.startup_frames = 7
	move.active_frames = 3
	move.recovery_frames = 13
	move.damage = 4.0
	move.limb_damage = 4.0
	move.hitstun_frames = 17
	move.blockstun_frames = 10
	move.hitstop_frames = 4
	move.guard_damage = 6.0
	var box := CombatBoxData.new()
	box.center = Vector2(24, -17)
	box.size = Vector2(32, 30)
	box.region = "torso"
	box.start_frame = move.startup_frames
	box.end_frame = move.startup_frames + move.active_frames - 1
	move.hitboxes = [box]
	_apply_animation_timing(move)
	return move


func _start_attack(data: Dictionary) -> void:
	state = State.ATTACK
	attack = data.duplicate(true)
	active_move = attack.get("move_resource") as FighterMoveData
	if active_move == null:
		state = State.IDLE
		attack.clear()
		return
	attack_phase = "startup"
	attack_time = 0.0
	attack_frame = 0
	hit_landed = false
	attack_connected = false
	attack_was_blocked = false
	attack_facing = facing
	combo_chain_rank = int(attack.chain_rank)


func _tick_attack() -> void:
	if active_move == null:
		_finish_attack()
		return
	if attack_frame >= active_move.total_frames():
		_finish_attack()
		return
	var startup := active_move.startup_frames
	var active := active_move.active_frames
	var recovery := active_move.recovery_frames
	velocity.x = float(attack_facing) * active_move.root_delta_at(attack_frame) * COMBAT_FPS
	if attack_frame < startup:
		attack_phase = "startup"
	elif attack_frame < startup + active:
		attack_phase = "active"
		if not hit_landed:
			_check_hits()
	else:
		attack_phase = "recovery"
		_try_attack_cancel()
		if attack_frame >= startup + active + recovery:
			_finish_attack()
			return
	attack_frame += 1
	attack_time = float(attack_frame) / COMBAT_FPS


func _try_attack_cancel() -> void:
	if buffered_band == "" or not attack_connected:
		return
	var next_data := _attack_data(buffered_band, buffered_heavy)
	if int(next_data.chain_rank) > combo_chain_rank:
		_interrupt_attack()
		_begin_buffered_attack(true)


func _check_hits() -> void:
	var victim := _find_opponent() as Player
	if victim == null or victim.state in [State.KNOCKDOWN, State.KO]:
		return
	var contacts: Array[String] = []
	for limb_name in LIMBS:
		if bool(victim.limb_hp.get(limb_name, {}).get("gone", false)):
			continue
		var hurt_rect := victim._limb_hurt_rect(limb_name)
		for strike_rect in _active_hit_rects():
			if strike_rect.intersects(hurt_rect, true):
				contacts.append(limb_name)
				break
	if contacts.is_empty():
		return
	var target := CombatRules.pick_contact_target(attack.band, victim.current_target_stance(), victim.limb_hp, contacts)
	if target == "":
		return
	hit_landed = true
	var payload := attack.duplicate(true)
	payload["target"] = target
	payload["source_x"] = global_position.x
	payload["contact_position"] = victim.limb_contact_position(target)
	var arena := get_parent()
	if arena != null and arena.has_method("queue_combat_hit"):
		arena.queue_combat_hit(self, victim, payload)
	else:
		var blocked := victim.receive_combat_hit(payload)
		notify_attack_result(blocked)


func _active_hit_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if active_move == null:
		return result
	for box in active_move.active_hitboxes(attack_frame):
		result.append(box.world_rect(global_position, attack_facing, SCALE))
	return result


func _limb_hurt_rect(limb_name: String) -> Rect2:
	if state == State.ATTACK and active_move != null:
		var override := active_move.hurtbox_override(limb_name, attack_frame)
		if override != null:
			return override.world_rect(global_position, attack_facing, SCALE)
	var center := FighterCollisionProfile.local_center(limb_name, stance, facing, _is_legless())
	var size := FighterCollisionProfile.local_size(limb_name) * SCALE
	var world_center := global_position + center * SCALE
	return Rect2(world_center - size * 0.5, size)


func limb_contact_position(limb_name: String) -> Vector2:
	return _limb_hurt_rect(limb_name).get_center()


func notify_attack_result(blocked: bool) -> void:
	if state != State.ATTACK:
		return
	attack_connected = true
	attack_was_blocked = blocked
	emit_signal("combat_event", "block" if blocked else "hit", attack)


func receive_combat_hit(data: Dictionary) -> bool:
	var blocked := _can_block_attack(str(data.get("guard_type", "mid")))
	if blocked:
		_blocked_hit_data(data)
		return true
	var counter_hit := state in [State.ATTACK, State.STANCE]
	var damage := float(data.get("damage", 0.0))
	var limb_damage := float(data.get("limb_damage", damage))
	var hitstun := int(data.get("hitstun_frames", 1))
	if counter_hit:
		damage *= 1.20
		limb_damage *= 1.20
		hitstun += 4
	_interrupt_attack()
	var limb_name := str(data.get("target", "torso"))
	if not limb_hp.has(limb_name) or bool(limb_hp[limb_name].gone):
		return false
	if not is_on_floor():
		air_hits += 1
		var scaling := maxf(0.45, 1.0 - 0.10 * float(air_hits))
		damage *= scaling
		limb_damage *= scaling
	else:
		air_hits = 0
	var vitality_multiplier := 1.12 if limb_name == "head" else (1.0 if limb_name == "torso" else 0.88)
	health = maxf(0.0, health - damage * vitality_multiplier)
	var limb: Dictionary = limb_hp[limb_name]
	limb.hp = maxf(0.0, float(limb.hp) - limb_damage)
	var limb_broken := false
	if limb.hp <= 0.0:
		limb.gone = true
		limb_broken = true
		if limb_name != "torso":
			_get_limb_body(limb_name).visible = false
	var source_x := float(data.get("source_x", global_position.x))
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * float(data.get("knockback", 160.0)), float(data.get("launch", 0.0)))
	hurt_tilt = dir_away * (0.22 if bool(data.get("heavy", false)) else 0.12)
	state_frames_left = hitstun
	hurt_timer = float(hitstun) / COMBAT_FPS
	state = State.KNOCKDOWN if bool(data.get("knockdown", false)) else State.HITSTUN
	if state == State.KNOCKDOWN:
		state_frames_left = max(state_frames_left, 38)
	flash_timer = 0.10
	var hit_position: Vector2 = data.get("contact_position", limb_contact_position(limb_name))
	_flash_limb(limb_name)
	_spawn_impact(hit_position, bool(data.get("heavy", false)))
	_float_text(hit_position, "-%d %s" % [roundi(damage * vitality_multiplier), limb_name], Color(1, 0.9, 0.3))
	if counter_hit:
		_float_text(hit_position + Vector2(0, -35.0), "COUNTER", Color(1.0, 0.25, 0.15))
	if limb_broken:
		_float_text(hit_position + Vector2(0, -65.0), "%s LOST!" % limb_name.to_upper(), Color(1, 0.4, 0.2))
	Effects.combat_impact(int(data.get("hitstop_frames", 4)), bool(data.get("heavy", false)), false, counter_hit, limb_broken)
	emit_signal("combat_event", "received_hit", data)
	if _is_ko():
		state = State.KO
		Effects.combat_impact(12, true, false, false, true)
		emit_signal("died")
	return false


## Compatibility entry point retained for development tools and older scenes.
func take_part_hit(limb_name: String, band: String, dmg: float, source_x: float, kb: float, stun: float) -> void:
	receive_combat_hit({
		"target": limb_name, "band": band, "guard_type": "mid",
		"damage": dmg, "limb_damage": dmg, "source_x": source_x,
		"knockback": kb, "launch": 0.0,
		"hitstun_frames": maxi(1, roundi(stun * COMBAT_FPS)),
		"hitstop_frames": 4, "heavy": dmg >= 10.0, "knockdown": false,
		"contact_position": limb_contact_position(limb_name),
	})


func _blocked_hit_data(data: Dictionary) -> void:
	_interrupt_attack()
	var damage := float(data.get("damage", 0.0))
	health = maxf(1.0, health - damage * float(data.get("chip_ratio", 0.0)))
	guard = maxf(0.0, guard - float(data.get("guard_damage", damage)))
	guard_recover_delay_frames = GUARD_REGEN_DELAY_FRAMES
	var source_x := float(data.get("source_x", global_position.x))
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * float(data.get("knockback", 160.0)) * 0.28, 0.0)
	rig.self_modulate = Color(1.5, 1.5, 1.5)
	flash_timer = 0.09
	state = State.BLOCKSTUN
	state_frames_left = int(data.get("blockstun_frames", 10))
	hurt_timer = float(state_frames_left) / COMBAT_FPS
	_float_text(global_position + Vector2(0, -110.0), "BLOCK", Color(0.4, 0.65, 1.0))
	Effects.combat_impact(maxi(2, int(data.get("hitstop_frames", 4)) - 2), bool(data.get("heavy", false)), true, false, false)
	if guard <= 0.0:
		state = State.HITSTUN
		state_frames_left = 40
		hurt_timer = float(state_frames_left) / COMBAT_FPS
		guard_recover_delay_frames = 150
		velocity = Vector2(dir_away * float(data.get("knockback", 160.0)) * 0.75, -100.0)
		_float_text(global_position + Vector2(0, -150.0), "GUARD BREAK!", Color(1, 0.2, 0.2))
		Effects.combat_impact(10, true, false, true, false)


func _can_block_attack(guard_type: String) -> bool:
	if state not in [State.IDLE, State.BLOCKSTUN] or input_locked:
		return false
	var mode := _block_mode()
	if mode == "":
		return false
	if guard_type == "low":
		return mode == "crouch"
	if guard_type == "overhead":
		return mode == "stand"
	return true


func _block_mode() -> String:
	if _crouch_guard_held():
		return "crouch"
	if _move_dir() * float(facing) < -0.3:
		return "stand"
	return ""


func _is_blocking() -> bool:
	return state in [State.IDLE, State.BLOCKSTUN] and not input_locked and _block_mode() != ""


func _tick_reaction(horizontal_decay: float) -> void:
	velocity.x *= horizontal_decay
	state_frames_left -= 1
	hurt_timer = maxf(0.0, float(state_frames_left) / COMBAT_FPS)
	if state_frames_left <= 0:
		state = State.IDLE
		hurt_tilt = 0.0


func _tick_knockdown() -> void:
	velocity.x *= 0.92
	state_frames_left -= 1
	hurt_timer = maxf(0.0, float(state_frames_left) / COMBAT_FPS)
	if state_frames_left <= 0 and is_on_floor():
		state = State.IDLE
		hurt_tilt = 0.0


func _interrupt_attack() -> void:
	attack.clear()
	active_move = null


func _finish_attack() -> void:
	_interrupt_attack()
	attack.clear()
	active_move = null
	attack_phase = ""
	attack_frame = 0
	state = State.IDLE
	combo_chain_rank = -1


func _update_flash(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			rig.self_modulate = Color.WHITE


func _tick_guard() -> void:
	if guard_recover_delay_frames > 0:
		guard_recover_delay_frames -= 1
	elif state == State.IDLE and not _is_blocking():
		guard = minf(GUARD_MAX, guard + GUARD_REGEN_PER_FRAME)


func _setup_limbs() -> void:
	for limb_name in LIMBS:
		limb_hp[limb_name] = {"hp": LIMB_MAX[limb_name], "gone": false}
	_refresh_limb_colors()


func _refresh_limb_colors() -> void:
	for limb_name in LIMBS:
		_get_limb_body(limb_name).color = _limb_color(limb_name)


func _limb_color(limb_name: String) -> Color:
	if limb_name == "head": return body_color.lightened(0.15)
	if limb_name == "torso": return body_color
	if limb_name.ends_with("_" + front_side()): return body_color.lightened(0.10)
	return body_color.darkened(0.10)


func _get_limb_body(limb_name: String) -> ColorRect:
	return get_node("Rig/" + limb_name + "/Body")


func _get_limb_node(limb_name: String) -> Node2D:
	return get_node("Rig/" + limb_name)


func _limb_available(limb_name: String) -> bool:
	return limb_hp.has(limb_name) and not bool(limb_hp[limb_name].gone)


func front_side() -> String:
	return CombatRules.close_side(stance)


func current_target_stance() -> int:
	return stance


func _apply_stance_visuals(delta: float) -> void:
	var pose_stance := pending_stance if state == State.STANCE else stance
	for limb_name in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		var limb_node := _get_limb_node(limb_name)
		limb_node.position.x = move_toward(limb_node.position.x, CombatRules.pose_x(limb_name, pose_stance, facing), STANCE_POSE_SPEED * delta)
	var visible_stance := current_target_stance()
	for limb_name in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		_get_limb_node(limb_name).z_index = 2 if CombatRules.is_close_limb(limb_name, visible_stance) else 0
	stance_marker.position.x = move_toward(stance_marker.position.x, float(facing) * CombatRules.LEG_OFFSET_X - stance_marker.size.x / 2.0, STANCE_POSE_SPEED * delta)


func _snap_stance_visuals() -> void:
	for limb_name in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		var limb_node := _get_limb_node(limb_name)
		limb_node.position.x = CombatRules.pose_x(limb_name, stance, facing)
		limb_node.z_index = 2 if CombatRules.is_close_limb(limb_name, stance) else 0
	stance_marker.position.x = float(facing) * CombatRules.LEG_OFFSET_X - stance_marker.size.x / 2.0


func _show_stance_change() -> void:
	var side_name := "RIGHT" if front_side() == CombatRules.RIGHT else "LEFT"
	_float_text(global_position + Vector2(0, -115.0), "%s LEAD" % side_name, Color(0.4, 0.9, 1.0))
	stance_marker.modulate = Color(2.0, 2.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(stance_marker, "modulate", Color.WHITE, 0.18)


func _start_stance_change() -> void:
	pending_stance = -stance
	stance_frames_left = STANCE_TRANSITION_FRAMES
	stance_timer = float(stance_frames_left) / COMBAT_FPS
	state = State.STANCE
	_clear_input_buffer()


func _finish_stance_change() -> void:
	stance = pending_stance
	state = State.IDLE
	_refresh_limb_colors()
	_show_stance_change()


func _rear_side() -> String:
	return CombatRules.rear_side(stance)


func _is_legless() -> bool:
	return bool(limb_hp["leg_l"].gone) and bool(limb_hp["leg_r"].gone)


func _mobility_ratio() -> float:
	var legs_lost := int(bool(limb_hp["leg_l"].gone)) + int(bool(limb_hp["leg_r"].gone))
	return [1.0, 0.58, 0.0][legs_lost]


func _move_speed() -> float:
	return FORWARD_SPEED * _mobility_ratio()


func _is_ko() -> bool:
	return health <= 0.0 or bool(limb_hp["head"].gone) or bool(limb_hp["torso"].gone)


func reset(start_pos: Vector2) -> void:
	health = 100.0
	guard = GUARD_MAX
	state = State.IDLE
	velocity = Vector2.ZERO
	position = start_pos
	hurt_timer = 0.0
	state_frames_left = 0
	flash_timer = 0.0
	input_locked = true
	air_hits = 0
	hurt_tilt = 0.0
	stick_was_up = false
	stance = 1
	pending_stance = 1
	stance_timer = 0.0
	stance_frames_left = 0
	guard_recover_delay_frames = 0
	combo_chain_rank = -1
	rig.rotation = 0.0
	rig.position = Vector2.ZERO
	rig.self_modulate = Color.WHITE
	rig.modulate = Color.WHITE
	_interrupt_attack()
	attack.clear()
	active_move = null
	_clear_input_buffer()
	for limb_name in LIMBS:
		limb_hp[limb_name].hp = LIMB_MAX[limb_name]
		limb_hp[limb_name].gone = false
		_get_limb_body(limb_name).visible = true
	_refresh_limb_colors()
	_snap_stance_visuals()


func _flash_limb(limb_name: String) -> void:
	var limb_body: ColorRect = _get_limb_body(limb_name)
	limb_body.self_modulate = Color(3.0, 3.0, 3.0)
	var tween := create_tween()
	tween.tween_interval(0.06)
	tween.tween_property(limb_body, "self_modulate", Color.WHITE, 0.08)


func _spawn_impact(pos: Vector2, heavy: bool = false) -> void:
	var burst := ColorRect.new()
	burst.color = Color(1, 0.72 if heavy else 0.95, 0.25 if heavy else 0.5, 0.95)
	burst.size = Vector2(34, 34) if heavy else Vector2(22, 22)
	burst.pivot_offset = burst.size * 0.5
	burst.z_index = 5
	get_parent().add_child(burst)
	burst.global_position = pos - burst.size * 0.5
	var tween := create_tween()
	tween.tween_property(burst, "scale", Vector2(2.1, 2.1), 0.12)
	tween.parallel().tween_property(burst, "rotation", 0.65, 0.12)
	tween.parallel().tween_property(burst, "modulate:a", 0.0, 0.12)
	tween.tween_callback(burst.queue_free)


func _float_text(pos: Vector2, message: String, color: Color) -> void:
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(240, 60)
	label.position = pos - Vector2(120, 30)
	label.z_index = 6
	get_parent().add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -70), 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


func _move_dir() -> float:
	var direction := Input.get_axis(_action("move_left"), _action("move_right"))
	var stick := Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_X)
	if absf(stick) < 0.15: stick = 0.0
	return clampf(direction + stick, -1.0, 1.0)


func _jump_pressed() -> bool:
	if Input.is_action_just_pressed(_action("jump")): return true
	var y := Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_Y)
	var up := y < -0.5
	var pressed := up and not stick_was_up
	stick_was_up = up
	return pressed


func _heavy_held() -> bool:
	if Input.is_action_pressed(_action("heavy")): return true
	return Input.get_joy_axis(_pad_device(), JOY_AXIS_TRIGGER_RIGHT) > 0.5


func _capture_attack_input() -> void:
	if input_locked or state == State.KO or _crouch_guard_held(): return
	for candidate in ["high", "mid", "low"]:
		if Input.is_action_just_pressed(_action(candidate)):
			buffered_band = candidate
			buffered_heavy = _heavy_held()
			input_buffer_frames = INPUT_BUFFER_FRAMES
			input_buffer_timer = float(input_buffer_frames) / COMBAT_FPS
			return


func _tick_input_buffer() -> void:
	if buffered_band == "": return
	input_buffer_frames -= 1
	input_buffer_timer = maxf(0.0, float(input_buffer_frames) / COMBAT_FPS)
	if input_buffer_frames <= 0: _clear_input_buffer()


func _clear_input_buffer() -> void:
	buffered_band = ""
	buffered_heavy = false
	input_buffer_frames = 0
	input_buffer_timer = 0.0


func _update_body_collision() -> void:
	var rect := body_shape.shape as RectangleShape2D
	if _is_legless():
		rect.size = Vector2(legless_pushbox_width, 38.0)
		body_shape.position = Vector2(0.0, 21.0)
	elif not is_on_floor():
		rect.size = Vector2(airborne_pushbox_width, 68.0)
		body_shape.position = Vector2.ZERO
	else:
		rect.size = Vector2(standing_pushbox_width, 80.0)
		body_shape.position = Vector2.ZERO


func pushbox_half_width() -> float:
	var rect := body_shape.shape as RectangleShape2D
	return rect.size.x * absf(scale.x) * 0.5


func set_hitstop_paused(_paused: bool) -> void:
	# Combat has no animation Tween anymore. The 3D adapter seeks its imported
	# clip from attack_frame and is paused independently by Effects.
	pass


func _action(action_name: String) -> StringName:
	return StringName("p%d_%s" % [player_number, action_name])


func _pad_device() -> int:
	return player_number - 1


func _crouch_guard_held() -> bool:
	if Input.is_action_pressed(_action("block")):
		return true
	return Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_Y) > 0.5


func _update_facing() -> void:
	var opponent := _find_opponent()
	if opponent == null: return
	facing = 1 if opponent.global_position.x >= global_position.x else -1
	var direction := float(facing)
	face.offset_left = 2.0 if direction > 0.0 else -8.0
	face.offset_right = face.offset_left + 6.0


func _find_opponent() -> Node:
	var best = null
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group("players"):
		if candidate != self:
			var distance := absf(candidate.global_position.x - global_position.x)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best

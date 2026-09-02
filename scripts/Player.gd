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

## Box coordinates use the original fighter-space units and are scaled once to
## world pixels. Each grounded normal reaches inward past pushbox contact.
const ATTACKS := {
	"high": {
		false: {
			"band": "high", "heavy": false, "chain_rank": 0,
			"startup_frames": 5, "active_frames": 3, "recovery_frames": 8,
			"damage": 5.5, "limb_damage": 6.0, "hitstun_frames": 17,
			"blockstun_frames": 11, "hitstop_frames": 4,
			"guard_damage": 7.0, "chip_ratio": 0.0, "guard_type": "high",
			"knockback": 150.0, "launch": 0.0, "knockdown": false,
			"contact_size": Vector2(38, 18), "extension": 2.15, "swing": 1.62,
			"travel": Vector3(7.0, 4.0, 0.0),
			"hitboxes": [{"offset": Vector2(35, -32), "size": Vector2(38, 18)}],
		},
		true: {
			"band": "high", "heavy": true, "chain_rank": 3,
			"startup_frames": 18, "active_frames": 5, "recovery_frames": 24,
			"damage": 15.0, "limb_damage": 18.0, "hitstun_frames": 36,
			"blockstun_frames": 18, "hitstop_frames": 9,
			"guard_damage": 20.0, "chip_ratio": 0.08, "guard_type": "overhead",
			"knockback": 330.0, "launch": -180.0, "knockdown": true,
			"contact_size": Vector2(60, 22), "extension": 2.0, "swing": 1.95,
			"travel": Vector3(12.0, 7.0, 0.0),
			"hitboxes": [{"offset": Vector2(43, -31), "size": Vector2(60, 22)}],
		},
	},
	"mid": {
		false: {
			"band": "mid", "heavy": false, "chain_rank": 1,
			"startup_frames": 7, "active_frames": 4, "recovery_frames": 12,
			"damage": 7.0, "limb_damage": 7.5, "hitstun_frames": 22,
			"blockstun_frames": 13, "hitstop_frames": 5,
			"guard_damage": 9.0, "chip_ratio": 0.0, "guard_type": "mid",
			"knockback": 180.0, "launch": 0.0, "knockdown": false,
			"contact_size": Vector2(44, 24), "extension": 2.35, "swing": 1.1,
			"travel": Vector3(9.0, 5.0, 0.0),
			"hitboxes": [{"offset": Vector2(33, -10), "size": Vector2(44, 24)}],
		},
		true: {
			"band": "mid", "heavy": true, "chain_rank": 3,
			"startup_frames": 12, "active_frames": 5, "recovery_frames": 19,
			"damage": 12.0, "limb_damage": 14.0, "hitstun_frames": 29,
			"blockstun_frames": 16, "hitstop_frames": 7,
			"guard_damage": 16.0, "chip_ratio": 0.06, "guard_type": "mid",
			"knockback": 270.0, "launch": -80.0, "knockdown": false,
			"contact_size": Vector2(60, 26), "extension": 3.25, "swing": 1.24,
			"travel": Vector3(13.0, 7.0, 0.0),
			"hitboxes": [{"offset": Vector2(40, -9), "size": Vector2(60, 26)}],
		},
	},
	"low": {
		false: {
			"band": "low", "heavy": false, "chain_rank": 2,
			"startup_frames": 9, "active_frames": 4, "recovery_frames": 15,
			"damage": 8.0, "limb_damage": 9.0, "hitstun_frames": 25,
			"blockstun_frames": 14, "hitstop_frames": 6,
			"guard_damage": 11.0, "chip_ratio": 0.0, "guard_type": "low",
			"knockback": 210.0, "launch": 0.0, "knockdown": false,
			"contact_size": Vector2(66, 24), "extension": 2.0, "swing": 1.14,
			"travel": Vector3(8.0, 5.0, 0.0),
			"hitboxes": [{"offset": Vector2(48, 21), "size": Vector2(66, 24)}],
		},
		true: {
			"band": "low", "heavy": true, "chain_rank": 3,
			"startup_frames": 15, "active_frames": 6, "recovery_frames": 22,
			"damage": 14.0, "limb_damage": 17.0, "hitstun_frames": 34,
			"blockstun_frames": 17, "hitstop_frames": 8,
			"guard_damage": 19.0, "chip_ratio": 0.07, "guard_type": "low",
			"knockback": 310.0, "launch": -110.0, "knockdown": true,
			"contact_size": Vector2(75, 28), "extension": 2.15, "swing": 1.28,
			"travel": Vector3(11.0, 8.0, 0.0),
			"hitboxes": [{"offset": Vector2(50, 20), "size": Vector2(75, 28)}],
		},
	},
}

signal died
signal combat_event(kind: String, data: Dictionary)

enum State { IDLE, STANCE, ATTACK, HITSTUN, BLOCKSTUN, KNOCKDOWN, KO }

@export var player_number: int = 1
@export var body_color: Color = Color(0.85, 0.2, 0.2)
@export var show_debug_rig := true

@onready var rig: Node2D = $Rig
@onready var face: ColorRect = $Rig/Face
@onready var stance_marker: ColorRect = $Rig/StanceMarker
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/HitboxShape

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
var attack_tween: Tween
var buffered_band := ""
var buffered_heavy := false
var input_buffer_frames := 0
var input_buffer_timer := 0.0
var guard_recover_delay_frames := 0
var combo_chain_rank := -1


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	rig.visible = show_debug_rig
	body_shape.shape = body_shape.shape.duplicate()
	hitbox_shape.shape = hitbox_shape.shape.duplicate()
	_setup_limbs()
	_snap_stance_visuals()
	_set_hitbox(false)


func _physics_process(delta: float) -> void:
	_capture_attack_input()
	if not input_locked and state == State.IDLE and buffered_band == "" and Input.is_action_just_pressed(_action("stance")):
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
	var data: Dictionary = ATTACKS[band][heavy].duplicate(true)
	data["windup"] = float(data.startup_frames) / COMBAT_FPS
	data["active"] = float(data.active_frames) / COMBAT_FPS
	data["recovery"] = float(data.recovery_frames) / COMBAT_FPS
	data["forward_speed"] = _phase_speed(data, 0)
	return data


func estimated_attack_reach(band: String, heavy: bool) -> float:
	var data := _attack_data(band, heavy)
	var maximum := 0.0
	for box in data.hitboxes:
		maximum = maxf(maximum, (float(box.offset.x) + float(box.size.x) * 0.5) * SCALE)
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
		data["fallback"] = true
		data["startup_frames"] = 7
		data["active_frames"] = 3
		data["recovery_frames"] = 13
		data["windup"] = 7.0 / COMBAT_FPS
		data["active"] = 3.0 / COMBAT_FPS
		data["recovery"] = 13.0 / COMBAT_FPS
		data["damage"] = 4.0
		data["limb_damage"] = 4.0
		data["hitstun_frames"] = 17
		data["hitboxes"] = [{"offset": Vector2(24, -17), "size": Vector2(32, 30)}]
		_float_text(global_position + Vector2(0, -88.0), "DESPERATION", Color(1.0, 0.65, 0.2))
	_start_attack(data)


func _start_attack(data: Dictionary) -> void:
	state = State.ATTACK
	attack = data.duplicate(true)
	attack_phase = "startup"
	attack_time = 0.0
	attack_frame = 0
	hit_landed = false
	attack_connected = false
	attack_was_blocked = false
	attack_facing = facing
	combo_chain_rank = int(attack.chain_rank)
	_set_hitbox(false)
	_anim_attack(attack)
	_update_strike_hitbox()


func _anim_attack(data: Dictionary) -> void:
	var limb_node: Node2D = _get_limb_node(data.name)
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()
	limb_node.rotation = 0.0
	limb_node.scale = Vector2.ONE
	attack_tween = create_tween()
	attack_tween.set_trans(Tween.TRANS_QUAD)
	attack_tween.set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(limb_node, "rotation", -attack_facing * float(data.swing), float(data.windup) + float(data.active))
	attack_tween.parallel().tween_property(limb_node, "scale", Vector2(1.0, float(data.extension)), float(data.windup) + float(data.active))
	attack_tween.set_ease(Tween.EASE_IN_OUT)
	attack_tween.tween_property(limb_node, "rotation", 0.0, float(data.recovery))
	attack_tween.parallel().tween_property(limb_node, "scale", Vector2.ONE, float(data.recovery))


func _update_strike_hitbox() -> void:
	if attack.is_empty() or not attack.has("hitboxes"):
		return
	var box: Dictionary = attack.hitboxes[0]
	hitbox_shape.shape.size = Vector2(box.size)
	hitbox.global_position = global_position + Vector2(float(box.offset.x) * float(attack_facing) * SCALE, float(box.offset.y) * SCALE)
	hitbox.global_rotation = 0.0


func _tick_attack() -> void:
	var startup := int(attack.startup_frames)
	var active := int(attack.active_frames)
	var recovery := int(attack.recovery_frames)
	if attack_frame < startup:
		attack_phase = "startup"
		velocity.x = float(attack_facing) * _phase_speed(attack, 0)
	elif attack_frame < startup + active:
		attack_phase = "active"
		velocity.x = float(attack_facing) * _phase_speed(attack, 1)
		_set_hitbox(true)
		_update_strike_hitbox()
		if not hit_landed:
			_check_hits()
	else:
		attack_phase = "recovery"
		velocity.x = float(attack_facing) * _phase_speed(attack, 2)
		_set_hitbox(false)
		_try_attack_cancel()
		if attack_frame >= startup + active + recovery:
			_finish_attack()
			return
	attack_frame += 1
	attack_time = float(attack_frame) / COMBAT_FPS


func _phase_speed(data: Dictionary, phase_index: int) -> float:
	var travel: Vector3 = data.get("travel", Vector3.ZERO)
	var distance: float = [travel.x, travel.y, travel.z][phase_index]
	var frames: int = [int(data.startup_frames), int(data.active_frames), int(data.recovery_frames)][phase_index]
	return distance * COMBAT_FPS / maxf(1.0, float(frames))


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
	payload["contact_position"] = victim._get_limb_hurtbox(target).global_position
	var arena := get_parent()
	if arena != null and arena.has_method("queue_combat_hit"):
		arena.queue_combat_hit(self, victim, payload)
	else:
		var blocked := victim.receive_combat_hit(payload)
		notify_attack_result(blocked)


func _active_hit_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for authored in attack.get("hitboxes", []):
		var data: Dictionary = authored
		var size := Vector2(data.size) * SCALE
		var center := global_position + Vector2(float(data.offset.x) * float(attack_facing) * SCALE, float(data.offset.y) * SCALE)
		result.append(Rect2(center - size * 0.5, size))
	return result


func _limb_hurt_rect(limb_name: String) -> Rect2:
	var area := _get_limb_hurtbox(limb_name)
	var shape_node := area.get_node("Shape") as CollisionShape2D
	var rect_shape := shape_node.shape as RectangleShape2D
	var size := rect_shape.size * shape_node.global_scale.abs()
	return Rect2(area.global_position - size * 0.5, size)


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
		_set_limb_hurtbox_enabled(limb_name, false)
	var source_x := float(data.get("source_x", global_position.x))
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * float(data.get("knockback", 160.0)), float(data.get("launch", 0.0)))
	hurt_tilt = dir_away * (0.22 if bool(data.get("heavy", false)) else 0.12)
	state_frames_left = hitstun
	hurt_timer = float(hitstun) / COMBAT_FPS
	state = State.KNOCKDOWN if bool(data.get("knockdown", false)) else State.HITSTUN
	if state == State.KNOCKDOWN:
		state_frames_left = max(state_frames_left, 38)
	_set_hitbox(false)
	flash_timer = 0.10
	var hit_position: Vector2 = data.get("contact_position", _get_limb_hurtbox(limb_name).global_position)
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
		"contact_position": _get_limb_hurtbox(limb_name).global_position,
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
	if Input.is_action_pressed(_action("block")):
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
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()
	attack_tween = null
	_set_hitbox(false)
	for limb_name in LIMBS:
		_get_limb_node(limb_name).rotation = 0.0
		_get_limb_node(limb_name).scale = Vector2.ONE


func _finish_attack() -> void:
	_interrupt_attack()
	attack.clear()
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


func _set_hitbox(active: bool) -> void:
	hitbox_shape.disabled = not active


func _set_limb_hurtbox_enabled(limb_name: String, enabled: bool) -> void:
	var shape := _get_limb_hurtbox(limb_name).get_node("Shape") as CollisionShape2D
	shape.disabled = not enabled


func _setup_limbs() -> void:
	for limb_name in LIMBS:
		var hurtbox: Area2D = _get_limb_hurtbox(limb_name)
		hurtbox.set_meta("limb", limb_name)
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


func _get_limb_hurtbox(limb_name: String) -> Area2D:
	return get_node("Rig/" + limb_name + "/Hurtbox")


func _get_limb_node(limb_name: String) -> Node2D:
	return get_node("Rig/" + limb_name)


func _limb_available(limb_name: String) -> bool:
	return limb_hp.has(limb_name) and not bool(limb_hp[limb_name].gone)


func front_side() -> String:
	return CombatRules.close_side(stance)


func current_target_stance() -> int:
	var toward := float(facing)
	var right_progress := _get_limb_node("leg_r").global_position.x * toward
	var left_progress := _get_limb_node("leg_l").global_position.x * toward
	return 1 if right_progress >= left_progress else -1


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
	return [1.0, 0.62, 0.28][legs_lost]


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
	_set_hitbox(false)
	rig.self_modulate = Color.WHITE
	rig.modulate = Color.WHITE
	_interrupt_attack()
	attack.clear()
	_clear_input_buffer()
	for limb_name in LIMBS:
		limb_hp[limb_name].hp = LIMB_MAX[limb_name]
		limb_hp[limb_name].gone = false
		_get_limb_body(limb_name).visible = true
		_set_limb_hurtbox_enabled(limb_name, true)
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
	if input_locked or state == State.KO: return
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
		rect.size = Vector2(44.0, 38.0)
		body_shape.position = Vector2(0.0, 21.0)
	elif not is_on_floor():
		rect.size = Vector2(42.0, 68.0)
		body_shape.position = Vector2.ZERO
	else:
		rect.size = Vector2(50.0, 80.0)
		body_shape.position = Vector2.ZERO


func set_hitstop_paused(paused: bool) -> void:
	if attack_tween == null or not attack_tween.is_valid(): return
	if paused: attack_tween.pause()
	else: attack_tween.play()


func _action(action_name: String) -> StringName:
	return StringName("p%d_%s" % [player_number, action_name])


func _pad_device() -> int:
	return player_number - 1


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

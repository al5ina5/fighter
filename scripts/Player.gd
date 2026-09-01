extends CharacterBody2D
class_name Player

const SCALE := 3.0
const SPEED := 300.0 * SCALE
const JUMP_VELOCITY := -400.0 * SCALE
const GRAVITY := 980.0 * SCALE
const GUARD_MAX := 100.0
const STANCE_POSE_SPEED := 220.0
const STANCE_TRANSITION_DURATION := 0.18
const INPUT_BUFFER_DURATION := 0.12
const ARM_LENGTH := 20.0
const LEG_LENGTH := 38.0

const LIMB_MAX := {
	"head": 30.0, "torso": 100.0, "arm_l": 40.0, "arm_r": 40.0,
	"leg_l": 40.0, "leg_r": 40.0,
}
const LIMBS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
const ATTACKS := {
	"high": {
		false: {"band": "high", "heavy": false, "windup": 0.15, "active": 0.05, "recovery": 0.34, "damage": 6.0, "knockback": 200.0, "stun": 0.24, "contact_size": Vector2(14, 10), "extension": 2.4, "swing": 1.82, "forward_speed": 30.0},
		true: {"band": "high", "heavy": true, "windup": 0.34, "active": 0.06, "recovery": 0.52, "damage": 14.0, "knockback": 380.0, "stun": 0.46, "contact_size": Vector2(14, 10), "extension": 2.05, "swing": 2.02, "forward_speed": 20.0},
	},
	"mid": {
		false: {"band": "mid", "heavy": false, "windup": 0.10, "active": 0.07, "recovery": 0.18, "damage": 5.0, "knockback": 180.0, "stun": 0.22, "contact_size": Vector2(18, 18), "extension": 2.45, "swing": 1.12, "forward_speed": 45.0},
		true: {"band": "mid", "heavy": true, "windup": 0.22, "active": 0.08, "recovery": 0.34, "damage": 10.0, "knockback": 310.0, "stun": 0.34, "contact_size": Vector2(20, 20), "extension": 4.0, "swing": 1.28, "forward_speed": 35.0},
	},
	"low": {
		false: {"band": "low", "heavy": false, "windup": 0.18, "active": 0.08, "recovery": 0.28, "damage": 8.0, "knockback": 260.0, "stun": 0.34, "contact_size": Vector2(22, 26), "extension": 2.0, "swing": 1.18, "forward_speed": 35.0},
		true: {"band": "low", "heavy": true, "windup": 0.32, "active": 0.10, "recovery": 0.46, "damage": 14.0, "knockback": 400.0, "stun": 0.46, "contact_size": Vector2(24, 30), "extension": 2.2, "swing": 1.28, "forward_speed": 25.0},
	},
}

signal died

enum State { IDLE, STANCE, ATTACK, HURT, KO }

@export var player_number: int = 1
@export var body_color: Color = Color(0.85, 0.2, 0.2)

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
var hurt_timer := 0.0
var flash_timer := 0.0
var attack: Dictionary = {}
var attack_phase := ""
var attack_time := 0.0
var hit_landed := false
var attack_facing := 1
var input_locked := false
var air_hits := 0
var hurt_tilt := 0.0
var stick_was_up := false
var attack_tween: Tween
var buffered_band := ""
var buffered_heavy := false
var input_buffer_timer := 0.0


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	body_shape.shape = body_shape.shape.duplicate()
	hitbox_shape.shape = hitbox_shape.shape.duplicate()
	_setup_limbs()
	_snap_stance_visuals()
	_set_hitbox(false)


func _physics_process(delta: float) -> void:
	_capture_attack_input()
	_tick_input_buffer(delta)
	if not input_locked and state == State.IDLE and Input.is_action_just_pressed(_action("stance")):
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
			stance_timer -= delta
			if stance_timer <= 0.0:
				_finish_stance_change()
		State.ATTACK:
			velocity.x = attack_facing * float(attack.forward_speed)
			_update_strike_hitbox()
			_tick_attack(delta)
		State.HURT:
			velocity.x *= 0.86
			hurt_timer -= delta
			if hurt_timer <= 0.0:
				state = State.IDLE
		State.KO:
			velocity.x *= 0.9

	var tilt_target := hurt_tilt if state == State.HURT else 0.0
	rig.rotation = lerpf(rig.rotation, tilt_target, delta * 12.0)
	rig.position.y = 38.0 if _is_legless() else 0.0
	_update_body_collision()
	move_and_slide()
	_update_flash(delta)


func _apply_idle() -> void:
	if input_locked:
		velocity.x = 0.0
		return
	if _jump_pressed() and is_on_floor() and not _is_legless():
		velocity.y = JUMP_VELOCITY
		return

	var band := buffered_band
	if band != "":
		var heavy := buffered_heavy
		_clear_input_buffer()
		var data: Dictionary = _attack_data(band, heavy)
		var swing_limb := _attacking_limb(data.band, heavy)
		if swing_limb == "":
			_float_text(global_position + Vector2(0, -70.0), "NO LIMB", Color(1, 0.3, 0.3))
		else:
			data["name"] = swing_limb
			_start_attack(data)
		return

	velocity.x = _move_dir() * _move_speed()


func _attack_data(band: String, heavy: bool) -> Dictionary:
	return ATTACKS[band][heavy].duplicate()


func estimated_attack_reach(band: String, heavy: bool) -> float:
	var data := _attack_data(band, heavy)
	var limb_name := CombatRules.source_limb(band, heavy, stance)
	var limb_length := LEG_LENGTH if limb_name.begins_with("leg_") else ARM_LENGTH
	var pivot_x := CombatRules.pose_x(limb_name, stance, 1)
	var endpoint_x := pivot_x + limb_length * float(data.extension) * sin(float(data.swing))
	return (endpoint_x + float(data.contact_size.x) / 2.0) * SCALE


func _attacking_limb(band: String, heavy: bool) -> String:
	var limb := CombatRules.source_limb(band, heavy, stance)
	if _limb_available(limb):
		return limb
	return ""


func _start_attack(data: Dictionary) -> void:
	state = State.ATTACK
	attack = data.duplicate()
	attack_phase = "windup"
	attack_time = 0.0
	hit_landed = false
	attack_facing = facing
	hitbox_shape.shape.size = attack.contact_size
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
	attack_tween.tween_property(limb_node, "rotation", -attack_facing * data.swing, data.windup + data.active)
	attack_tween.parallel().tween_property(limb_node, "scale", Vector2(1.0, data.extension), data.windup + data.active)
	attack_tween.set_ease(Tween.EASE_IN_OUT)
	attack_tween.tween_property(limb_node, "rotation", 0.0, data.recovery)
	attack_tween.parallel().tween_property(limb_node, "scale", Vector2.ONE, data.recovery)


func _update_strike_hitbox() -> void:
	if attack.is_empty() or not attack.has("name"):
		return
	var source_limb := _get_limb_node(attack.name)
	var limb_length := LEG_LENGTH if String(attack.name).begins_with("leg_") else ARM_LENGTH
	hitbox.global_position = source_limb.to_global(Vector2(0.0, limb_length))
	hitbox.global_rotation = source_limb.global_rotation


func _tick_attack(delta: float) -> void:
	attack_time += delta
	match attack_phase:
		"windup":
			if attack_time >= attack.windup:
				attack_phase = "active"
				attack_time = 0.0
				_set_hitbox(true)
		"active":
			if not hit_landed:
				_check_hits()
			if attack_time >= attack.active:
				attack_phase = "recovery"
				attack_time = 0.0
				_set_hitbox(false)
		"recovery":
			if attack_time >= attack.recovery:
				_finish_attack()


func _check_hits() -> void:
	var victim := _find_opponent() as Player
	if victim == null:
		return
	var target: String = _pick_target(victim, attack.band)
	if target == "":
		return
	var target_hurtbox := victim._get_limb_hurtbox(target)
	if not hitbox.overlaps_area(target_hurtbox):
		return
	hit_landed = true
	victim.take_part_hit(target, attack.band, attack.damage, global_position.x, attack.knockback, attack.stun)


func _pick_target(victim, band: String) -> String:
	return CombatRules.pick_target(band, victim.current_target_stance(), victim.limb_hp)


func take_part_hit(limb_name: String, _band: String, dmg: float, source_x: float, kb: float, stun: float) -> void:
	if _is_blocking():
		_blocked_hit(dmg, source_x, kb, stun)
		return

	var counter_hit := state == State.ATTACK or state == State.STANCE
	if counter_hit:
		dmg *= 1.25
		stun *= 1.2
	_interrupt_attack()
	var limb: Dictionary = limb_hp[limb_name]
	if limb.gone:
		return

	if not is_on_floor():
		air_hits += 1
		dmg *= maxf(0.3, 1.0 - 0.15 * air_hits)
	else:
		air_hits = 0

	limb.hp = maxf(0.0, limb.hp - dmg)
	if limb_name == "torso":
		health = limb.hp

	var hit_position := _get_limb_hurtbox(limb_name).global_position
	if limb.hp <= 0.0:
		limb.gone = true
		if limb_name != "torso":
			_get_limb_body(limb_name).visible = false
		_set_limb_hurtbox_enabled(limb_name, false)
		Effects.add_shake(8.0)
		_float_text(hit_position, "%s LOST!" % limb_name.to_upper(), Color(1, 0.4, 0.2))

	state = State.HURT
	hurt_timer = stun
	_set_hitbox(false)
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * kb * SCALE, -130.0 * SCALE)
	hurt_tilt = dir_away * 0.16
	_flash_limb(limb_name)
	_spawn_impact(hit_position)
	_float_text(hit_position, "-%d %s" % [roundi(dmg), limb_name], Color(1, 0.9, 0.3))
	if counter_hit:
		_float_text(hit_position + Vector2(0, -35.0), "COUNTER", Color(1.0, 0.25, 0.15))
	Effects.hitstop(0.05 if dmg <= 6.0 else 0.09)
	Effects.add_shake(3.0 if dmg <= 6.0 else 7.0)

	if _is_ko():
		health = maxf(health, 0.0)
		state = State.KO
		Effects.add_shake(12.0)
		emit_signal("died")


func _blocked_hit(dmg: float, source_x: float, kb: float, _stun: float) -> void:
	var torso: Dictionary = limb_hp["torso"]
	torso.hp = maxf(0.0, torso.hp - dmg * 0.15)
	health = torso.hp
	guard -= dmg * 1.5
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * kb * 0.4 * SCALE, 0.0)
	rig.self_modulate = Color(1.5, 1.5, 1.5)
	flash_timer = 0.08
	_float_text(global_position + Vector2(0, -110.0), "BLOCK", Color(0.4, 0.6, 1.0))
	Effects.hitstop(0.03)
	Effects.add_shake(2.0)
	if guard <= 0.0:
		guard = GUARD_MAX
		state = State.HURT
		hurt_timer = 0.6
		velocity = Vector2(dir_away * kb * 1.2 * SCALE, -150.0 * SCALE)
		_float_text(global_position + Vector2(0, -150.0), "GUARD BREAK!", Color(1, 0.2, 0.2))
		Effects.add_shake(9.0)
	if health <= 0.0:
		torso.gone = true
		state = State.KO
		emit_signal("died")


func _interrupt_attack() -> void:
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()
	attack_tween = null
	_set_hitbox(false)
	for name in LIMBS:
		_get_limb_node(name).rotation = 0.0
		_get_limb_node(name).scale = Vector2.ONE


func _finish_attack() -> void:
	_interrupt_attack()
	attack.clear()
	attack_phase = ""
	state = State.IDLE


func _update_flash(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			rig.self_modulate = Color.WHITE


func _set_hitbox(active: bool) -> void:
	hitbox_shape.disabled = not active


func _set_limb_hurtbox_enabled(limb_name: String, enabled: bool) -> void:
	var shape := _get_limb_hurtbox(limb_name).get_node("Shape") as CollisionShape2D
	shape.disabled = not enabled


func _setup_limbs() -> void:
	for name in LIMBS:
		var hurtbox: Area2D = _get_limb_hurtbox(name)
		hurtbox.set_meta("limb", name)
		limb_hp[name] = {"hp": LIMB_MAX[name], "gone": false}
	_refresh_limb_colors()


func _refresh_limb_colors() -> void:
	for name in LIMBS:
		_get_limb_body(name).color = _limb_color(name)


func _limb_color(name: String) -> Color:
	if name == "head":
		return body_color.lightened(0.15)
	if name == "torso":
		return body_color
	var front := front_side()
	if name.ends_with("_" + front):
		return body_color.lightened(0.10)
	return body_color.darkened(0.10)


func _get_limb_body(name: String) -> ColorRect:
	return get_node("Rig/" + name + "/Body")


func _get_limb_hurtbox(name: String) -> Area2D:
	return get_node("Rig/" + name + "/Hurtbox")


func _get_limb_node(name: String) -> Node2D:
	return get_node("Rig/" + name)


func _limb_available(name: String) -> bool:
	return not limb_hp[name].gone


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
		var target_x := CombatRules.pose_x(limb_name, pose_stance, facing)
		limb_node.position.x = move_toward(limb_node.position.x, target_x, STANCE_POSE_SPEED * delta)
	var visible_stance := current_target_stance()
	for limb_name in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		_get_limb_node(limb_name).z_index = 2 if CombatRules.is_close_limb(limb_name, visible_stance) else 0
	stance_marker.position.x = move_toward(
		stance_marker.position.x,
		float(facing) * CombatRules.LEG_OFFSET_X - stance_marker.size.x / 2.0,
		STANCE_POSE_SPEED * delta
	)


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
	var tw := create_tween()
	tw.tween_property(stance_marker, "modulate", Color.WHITE, 0.18)


func _start_stance_change() -> void:
	pending_stance = -stance
	stance_timer = STANCE_TRANSITION_DURATION
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
	return limb_hp["leg_l"].gone and limb_hp["leg_r"].gone


func _move_speed() -> float:
	var legs_lost := 0
	if limb_hp["leg_l"].gone:
		legs_lost += 1
	if limb_hp["leg_r"].gone:
		legs_lost += 1
	match legs_lost:
		1:
			return SPEED * 0.65
		2:
			return SPEED * 0.35
	return SPEED


func _is_ko() -> bool:
	return limb_hp["head"].gone or limb_hp["torso"].gone


func reset(start_pos: Vector2) -> void:
	health = 100.0
	guard = GUARD_MAX
	state = State.IDLE
	velocity = Vector2.ZERO
	position = start_pos
	hurt_timer = 0.0
	flash_timer = 0.0
	input_locked = true
	air_hits = 0
	hurt_tilt = 0.0
	stick_was_up = false
	stance = 1
	pending_stance = 1
	stance_timer = 0.0
	rig.rotation = 0.0
	rig.position = Vector2.ZERO
	_set_hitbox(false)
	rig.self_modulate = Color.WHITE
	rig.modulate = Color.WHITE
	_interrupt_attack()
	_clear_input_buffer()
	for name in LIMBS:
		limb_hp[name].hp = LIMB_MAX[name]
		limb_hp[name].gone = false
		_get_limb_body(name).visible = true
		_set_limb_hurtbox_enabled(name, true)
	_refresh_limb_colors()
	_snap_stance_visuals()


func _flash_limb(limb_name: String) -> void:
	var limb_body: ColorRect = _get_limb_body(limb_name)
	limb_body.self_modulate = Color(3.0, 3.0, 3.0)
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_property(limb_body, "self_modulate", Color.WHITE, 0.08)


func _spawn_impact(pos: Vector2) -> void:
	var burst := ColorRect.new()
	burst.color = Color(1, 0.95, 0.5, 0.9)
	burst.size = Vector2(22, 22)
	burst.z_index = 5
	get_parent().add_child(burst)
	burst.global_position = pos - Vector2(11, 11)
	var tw := create_tween()
	tw.tween_property(burst, "scale", Vector2(1.7, 1.7), 0.12)
	tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.12)
	tw.tween_callback(burst.queue_free)


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(240, 60)
	label.position = pos - Vector2(120, 30)
	label.z_index = 6
	get_parent().add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "position", label.position + Vector2(0, -70), 0.6)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(label.queue_free)


func _move_dir() -> float:
	var dir := Input.get_axis(_action("move_left"), _action("move_right"))
	var stick := Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_X)
	if absf(stick) < 0.15:
		stick = 0.0
	return clampf(dir + stick, -1.0, 1.0)


func _jump_pressed() -> bool:
	if Input.is_action_just_pressed(_action("jump")):
		return true
	var y := Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_Y)
	var up := y < -0.5
	var pressed := up and not stick_was_up
	stick_was_up = up
	return pressed


func _heavy_held() -> bool:
	if Input.is_action_pressed(_action("heavy")):
		return true
	return Input.get_joy_axis(_pad_device(), JOY_AXIS_TRIGGER_RIGHT) > 0.5


func _is_blocking() -> bool:
	if state != State.IDLE or input_locked:
		return false
	if Input.is_action_pressed(_action("block")):
		return true
	return _move_dir() * facing < -0.3


func _capture_attack_input() -> void:
	if input_locked or state == State.KO:
		return
	for candidate in ["high", "mid", "low"]:
		if Input.is_action_just_pressed(_action(candidate)):
			buffered_band = candidate
			buffered_heavy = _heavy_held()
			input_buffer_timer = INPUT_BUFFER_DURATION
			return


func _tick_input_buffer(delta: float) -> void:
	if buffered_band == "":
		return
	input_buffer_timer -= delta
	if input_buffer_timer <= 0.0:
		_clear_input_buffer()


func _clear_input_buffer() -> void:
	buffered_band = ""
	buffered_heavy = false
	input_buffer_timer = 0.0


func _update_body_collision() -> void:
	var rect := body_shape.shape as RectangleShape2D
	if _is_legless():
		rect.size = Vector2(46.0, 40.0)
		body_shape.position = Vector2(0.0, 20.0)
	else:
		rect.size = Vector2(43.0, 80.0)
		body_shape.position = Vector2.ZERO


func set_hitstop_paused(paused: bool) -> void:
	if attack_tween == null or not attack_tween.is_valid():
		return
	if paused:
		attack_tween.pause()
	else:
		attack_tween.play()


func _action(name: String) -> StringName:
	return StringName("p%d_%s" % [player_number, name])


func _pad_device() -> int:
	return player_number - 1


func _update_facing() -> void:
	var opponent := _find_opponent()
	if opponent == null:
		return
	facing = 1 if opponent.global_position.x >= global_position.x else -1
	var f := float(facing)
	face.offset_left = 2.0 if f > 0.0 else -8.0
	face.offset_right = face.offset_left + 6.0


func _find_opponent() -> Node:
	var best = null
	var best_dist := INF
	for player in get_tree().get_nodes_in_group("players"):
		if player != self:
			var dist := absf(player.global_position.x - global_position.x)
			if dist < best_dist:
				best_dist = dist
				best = player
	return best

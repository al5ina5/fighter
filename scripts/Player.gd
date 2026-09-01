extends CharacterBody2D
class_name Player

const SCALE := 3.0
const SPEED := 300.0 * SCALE
const JUMP_VELOCITY := -400.0 * SCALE
const GRAVITY := 980.0 * SCALE
const GUARD_MAX := 100.0

const LIMB_MAX := {
	"head": 30.0, "torso": 100.0, "arm_l": 40.0, "arm_r": 40.0,
	"leg_l": 40.0, "leg_r": 40.0,
}
const LIMBS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]
const LEG_BASE := {"leg_l": -7.0, "leg_r": 7.0}

const HIGH_L := {"band": "high", "windup": 0.12, "active": 0.08, "recovery": 0.20, "damage": 6.0, "knockback": 200.0, "stun": 0.24, "aim": -14.0, "reach": Vector2(80, 80), "swing": 0.9}
const HIGH_H := {"band": "high", "windup": 0.24, "active": 0.10, "recovery": 0.34, "damage": 11.0, "knockback": 320.0, "stun": 0.36, "aim": -14.0, "reach": Vector2(90, 90), "swing": 1.1}
const MID_L := {"band": "mid", "windup": 0.10, "active": 0.08, "recovery": 0.16, "damage": 5.0, "knockback": 180.0, "stun": 0.22, "aim": 0.0, "reach": Vector2(75, 75), "swing": 0.8}
const MID_H := {"band": "mid", "windup": 0.20, "active": 0.10, "recovery": 0.28, "damage": 9.0, "knockback": 300.0, "stun": 0.32, "aim": 0.0, "reach": Vector2(85, 85), "swing": 1.0}
const LOW_L := {"band": "low", "windup": 0.24, "active": 0.10, "recovery": 0.26, "damage": 8.0, "knockback": 260.0, "stun": 0.34, "aim": 14.0, "reach": Vector2(95, 100), "swing": 1.1}
const LOW_H := {"band": "low", "windup": 0.38, "active": 0.12, "recovery": 0.42, "damage": 14.0, "knockback": 400.0, "stun": 0.46, "aim": 14.0, "reach": Vector2(105, 110), "swing": 1.4}

signal died

enum State { IDLE, ATTACK, HURT, KO }

@export var player_number: int = 1
@export var body_color: Color = Color(0.85, 0.2, 0.2)

@onready var rig: Node2D = $Rig
@onready var face: ColorRect = $Rig/Face
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/HitboxShape

var health := 100.0
var guard := GUARD_MAX
var limb_hp: Dictionary = {}
var state: int = State.IDLE
var facing := 1
var hurt_timer := 0.0
var flash_timer := 0.0
var attack: Dictionary = {}
var attack_phase := ""
var attack_time := 0.0
var hit_landed := false
var input_locked := false
var air_hits := 0
var hurt_tilt := 0.0
var stick_was_up := false
var attack_tween: Tween
var stance := 1


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	_setup_limbs()
	_set_hitbox(false)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(_action("stance")):
		stance = -stance
		_refresh_limb_colors()

	_update_facing()
	_apply_stance_pose()

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	match state:
		State.IDLE:
			_apply_idle()
		State.ATTACK:
			velocity.x = facing * 60.0
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
	move_and_slide()
	_update_flash(delta)


func _apply_idle() -> void:
	if input_locked:
		velocity.x = 0.0
		return
	if _jump_pressed() and is_on_floor() and not _is_legless():
		velocity.y = JUMP_VELOCITY
		return

	var band := ""
	for suffix in ["high", "mid", "low"]:
		if Input.is_action_just_pressed(_action(suffix)):
			band = suffix
			break
	if band != "":
		var heavy := _heavy_held()
		var data := _attack_data(band, heavy)
		if _is_legless():
			data["band"] = "low"
			data["aim"] = 26.0
		var swing := _swing_limb(data.band)
		if swing != "":
			data["name"] = swing
			_start_attack(data)
		else:
			var kind := "ARM" if data.band != "low" else "LEG"
			_float_text(global_position + Vector2(0, -70.0), "NO %s" % kind, Color(1, 0.3, 0.3))
		return

	velocity.x = _move_dir() * _move_speed()


func _attack_data(band: String, heavy: bool) -> Dictionary:
	match band:
		"high":
			return (HIGH_H if heavy else HIGH_L).duplicate()
		"mid":
			return (MID_H if heavy else MID_L).duplicate()
		"low":
			return (LOW_H if heavy else LOW_L).duplicate()
	return MID_L.duplicate()


func _swing_limb(band: String) -> String:
	if band == "high" or band == "mid":
		if _limb_available(_arm_lead()):
			return _arm_lead()
		if _limb_available(_arm_other()):
			return _arm_other()
		return ""
	if _limb_available(_leg_lead()):
		return _leg_lead()
	if _limb_available(_leg_other()):
		return _leg_other()
	if _limb_available(_arm_lead()):
		return _arm_lead()
	if _limb_available(_arm_other()):
		return _arm_other()
	return ""


func _start_attack(data: Dictionary) -> void:
	state = State.ATTACK
	attack = data.duplicate()
	attack_phase = "windup"
	attack_time = 0.0
	hit_landed = false
	var reach: Vector2 = data.reach
	hitbox_shape.shape.size = reach
	hitbox.position.x = facing * (reach.x / 2.0 + 30.0)
	hitbox.position.y = data.aim
	_set_hitbox(false)
	_anim_attack(data)


func _anim_attack(data: Dictionary) -> void:
	var limb_node: Node2D = _get_limb_node(data.name)
	if attack_tween:
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_property(limb_node, "rotation", -facing * data.swing, data.windup + data.active)
	attack_tween.tween_property(limb_node, "rotation", 0.0, data.recovery)


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
				state = State.IDLE


func _check_hits() -> void:
	for area in hitbox.get_overlapping_areas():
		var victim: Node = area
		while victim != null and not (victim is Player):
			victim = victim.get_parent()
		if victim == null or victim == self:
			continue
		hit_landed = true
		var target: String = _pick_target(victim, attack.band)
		victim.take_part_hit(target, attack.damage, global_position.x, attack.knockback, attack.stun)
		return


func _pick_target(victim, band: String) -> String:
	for name in _target_priority(victim, band):
		if not victim.limb_hp[name].gone:
			return name
	return "torso"


func _target_priority(victim, band: String) -> Array:
	var lead: String = victim.lead_side()
	var other := "l" if lead == "r" else "r"
	if victim._is_legless():
		match band:
			"high":
				return ["head", "torso"]
			"mid":
				return ["head", "torso"]
			"low":
				return ["torso", "arm_" + lead, "arm_" + other]
	match band:
		"high":
			return ["head", "torso"]
		"mid":
			return ["arm_" + lead, "arm_" + other, "torso"]
		"low":
			return ["leg_" + lead, "leg_" + other, "torso"]
	return ["torso"]


func take_part_hit(limb_name: String, dmg: float, source_x: float, kb: float, stun: float) -> void:
	if _is_blocking():
		_blocked_hit(dmg, source_x, kb, stun)
		return

	_interrupt_attack()
	var limb: Dictionary = limb_hp[limb_name]
	if limb.gone:
		return

	if not is_on_floor():
		air_hits += 1
		dmg = dmg * maxf(0.3, 1.0 - 0.15 * air_hits)
		print("juggled x", air_hits)
	else:
		air_hits = 0.0

	if limb_name == "torso":
		dmg *= _torso_mult()

	limb.hp -= dmg
	if limb_name == "torso" or limb_name == "head":
		health -= dmg

	if limb.hp <= 0.0:
		limb.gone = true
		_get_limb_body(limb_name).visible = false
		Effects.add_shake(8.0)
		_float_text(_get_limb_hurtbox(limb_name).global_position, "%s LOST!" % limb_name.to_upper(), Color(1, 0.4, 0.2))
		print("LIMB LOST: ", limb_name)

	state = State.HURT
	hurt_timer = stun
	_set_hitbox(false)
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * kb * SCALE, -130.0 * SCALE)
	hurt_tilt = dir_away * 0.16
	_flash_limb(limb_name)
	_spawn_impact(_get_limb_hurtbox(limb_name).global_position)
	_float_text(_get_limb_hurtbox(limb_name).global_position, "-%d %s" % [roundi(dmg), limb_name], Color(1, 0.9, 0.3))
	Effects.hitstop(0.05 if dmg <= 6.0 else 0.09)
	Effects.add_shake(3.0 if dmg <= 6.0 else 7.0)
	print("HIT dmg=", dmg, " -> ", limb_name, " | hp=", health)

	if _is_ko():
		health = maxf(health, 0.0)
		state = State.KO
		Effects.add_shake(12.0)
		emit_signal("died")


func _blocked_hit(dmg: float, source_x: float, kb: float, _stun: float) -> void:
	health -= dmg * 0.15
	guard -= dmg * 1.5
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * kb * 0.4 * SCALE, 0.0)
	rig.self_modulate = Color(1.5, 1.5, 1.5)
	flash_timer = 0.08
	_float_text(global_position + Vector2(0, -110.0), "BLOCK", Color(0.4, 0.6, 1.0))
	Effects.hitstop(0.03)
	Effects.add_shake(2.0)
	print("BLOCKED chip=", dmg * 0.15, " guard=", guard)
	if guard <= 0.0:
		guard = GUARD_MAX
		state = State.HURT
		hurt_timer = 0.6
		velocity = Vector2(dir_away * kb * 1.2 * SCALE, -150.0 * SCALE)
		_float_text(global_position + Vector2(0, -150.0), "GUARD BREAK!", Color(1, 0.2, 0.2))
		Effects.add_shake(9.0)
		print("GUARD BREAK!")


func _interrupt_attack() -> void:
	if attack_tween:
		attack_tween.kill()
		attack_tween = null
	for name in LIMBS:
		_get_limb_node(name).rotation = 0.0


func _update_flash(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			rig.self_modulate = Color.WHITE


func _set_hitbox(active: bool) -> void:
	hitbox_shape.disabled = not active


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
	return body_color


func _apply_stance_pose() -> void:
	if state == State.KO:
		return
	var f := float(facing)
	var lead := "r" if stance == 1 else "l"
	for leg in ["leg_l", "leg_r"]:
		var node: Node2D = _get_limb_node(leg)
		var base: float = LEG_BASE[leg]
		if leg.ends_with("_" + lead):
			node.position.x = base + 8.0 * f
		else:
			node.position.x = base - 4.0 * f


func _get_limb_body(name: String) -> ColorRect:
	return get_node("Rig/" + name + "/Body")


func _get_limb_hurtbox(name: String) -> Area2D:
	return get_node("Rig/" + name + "/Hurtbox")


func _get_limb_node(name: String) -> Node2D:
	return get_node("Rig/" + name)


func _limb_available(name: String) -> bool:
	return not limb_hp[name].gone


func _has_arm() -> bool:
	return not (limb_hp["arm_l"].gone and limb_hp["arm_r"].gone)


func _has_leg() -> bool:
	return not (limb_hp["leg_l"].gone and limb_hp["leg_r"].gone)


func lead_side() -> String:
	return "r" if stance == 1 else "l"


func _arm_lead() -> String:
	return "arm_" + lead_side()


func _arm_other() -> String:
	return "arm_" + ("l" if lead_side() == "r" else "r")


func _leg_lead() -> String:
	return "leg_" + lead_side()


func _leg_other() -> String:
	return "leg_" + ("l" if lead_side() == "r" else "r")


func _torso_mult() -> float:
	var missing := 0
	if limb_hp["arm_l"].gone:
		missing += 1
	if limb_hp["arm_r"].gone:
		missing += 1
	return maxf(0.25, missing * 0.5)


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
	return health <= 0.0


func reset(start_pos: Vector2) -> void:
	health = 100.0
	guard = GUARD_MAX
	state = State.IDLE
	velocity = Vector2.ZERO
	position = start_pos
	hurt_timer = 0.0
	flash_timer = 0.0
	input_locked = true
	air_hits = 0.0
	hurt_tilt = 0.0
	stick_was_up = false
	stance = 1
	rig.rotation = 0.0
	_set_hitbox(false)
	rig.self_modulate = Color.WHITE
	rig.modulate = Color.WHITE
	_interrupt_attack()
	for name in LIMBS:
		limb_hp[name].hp = LIMB_MAX[name]
		limb_hp[name].gone = false
		_get_limb_body(name).visible = true
	_refresh_limb_colors()


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
	burst.position = pos - Vector2(11, 11)
	burst.z_index = 5
	add_child(burst)
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
	var trigger := Input.get_joy_axis(_pad_device(), JOY_AXIS_TRIGGER_RIGHT)
	return trigger > 0.5


func _is_blocking() -> bool:
	if Input.is_action_pressed(_action("block")):
		return true
	return _move_dir() * facing < -0.3


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

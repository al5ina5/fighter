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

const ARM_L := {
	"name": "arm_l", "target": "arm_l", "windup": 0.12, "active": 0.08, "recovery": 0.18,
	"damage": 6.0, "knockback": 230.0, "stun": 0.26, "reach": Vector2(70, 70), "aim": 0.0, "swing": 0.9,
}
const ARM_R := {
	"name": "arm_r", "target": "arm_r", "windup": 0.12, "active": 0.08, "recovery": 0.18,
	"damage": 6.0, "knockback": 230.0, "stun": 0.26, "reach": Vector2(70, 70), "aim": 0.0, "swing": 0.9,
}
const LEG_L := {
	"name": "leg_l", "target": "leg_l", "windup": 0.28, "active": 0.10, "recovery": 0.30,
	"damage": 10.0, "knockback": 330.0, "stun": 0.40, "reach": Vector2(95, 100), "aim": 12.0, "swing": 1.2,
}
const LEG_R := {
	"name": "leg_r", "target": "leg_r", "windup": 0.28, "active": 0.10, "recovery": 0.30,
	"damage": 10.0, "knockback": 330.0, "stun": 0.40, "reach": Vector2(95, 100), "aim": 12.0, "swing": 1.2,
}
const ATTACKS := {"arm_l": ARM_L, "arm_r": ARM_R, "leg_l": LEG_L, "leg_r": LEG_R}

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


func _ready() -> void:
	scale = Vector2(SCALE, SCALE)
	_setup_limbs()
	_set_hitbox(false)


func _physics_process(delta: float) -> void:
	_update_facing()

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	match state:
		State.IDLE:
			_apply_idle()
		State.ATTACK:
			velocity.x = facing * 70.0
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
	move_and_slide()
	_update_flash(delta)


func _apply_idle() -> void:
	if input_locked:
		velocity.x = 0.0
		return
	if _jump_pressed() and is_on_floor():
		velocity.y = JUMP_VELOCITY
		return
	for name in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if Input.is_action_just_pressed(_action(name)):
			_start_attack(ATTACKS[name])
			return
	velocity.x = _move_dir() * _move_speed()


func _start_attack(data: Dictionary) -> void:
	state = State.ATTACK
	attack = data
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
	var limb_node: Node2D = _swing_limb(data.name)
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
		var target: String = _fallback_target(victim, attack.target)
		victim.take_part_hit(target, attack.damage, global_position.x, attack.knockback, attack.stun)
		return


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

	limb.hp -= dmg
	if limb_name == "torso" or limb_name == "head":
		health -= dmg

	if limb.hp <= 0.0:
		limb.gone = true
		_get_limb_body(limb_name).visible = false
		Effects.add_shake(8.0)
		print("LIMB LOST: ", limb_name)

	state = State.HURT
	hurt_timer = stun
	_set_hitbox(false)
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * kb * SCALE, -130.0 * SCALE)
	hurt_tilt = dir_away * 0.16
	_flash_limb(limb_name)
	_spawn_impact(_get_limb_hurtbox(limb_name).global_position)
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
	Effects.hitstop(0.03)
	Effects.add_shake(2.0)
	print("BLOCKED chip=", dmg * 0.15, " guard=", guard)
	if guard <= 0.0:
		guard = GUARD_MAX
		state = State.HURT
		hurt_timer = 0.6
		velocity = Vector2(dir_away * kb * 1.2 * SCALE, -150.0 * SCALE)
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


func _setup_limbs() -> void:
	for name in LIMBS:
		var body: ColorRect = _get_limb_body(name)
		body.color = _limb_color(name)
		var hurtbox: Area2D = _get_limb_hurtbox(name)
		hurtbox.set_meta("limb", name)
		limb_hp[name] = {"hp": LIMB_MAX[name], "gone": false}


func _limb_color(name: String) -> Color:
	match name:
		"head":
			return body_color.lightened(0.15)
		"torso":
			return body_color
		"arm_l", "leg_l":
			return body_color.lightened(0.05)
		"arm_r", "leg_r":
			return body_color.darkened(0.2)
	return body_color


func _get_limb_body(name: String) -> ColorRect:
	return get_node("Rig/" + name + "/Body")


func _get_limb_hurtbox(name: String) -> Area2D:
	return get_node("Rig/" + name + "/Hurtbox")


func _get_limb_node(name: String) -> Node2D:
	return get_node("Rig/" + name)


func _swing_limb(name: String) -> Node2D:
	if not limb_hp[name].gone:
		return _get_limb_node(name)
	for n in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		if not limb_hp[n].gone:
			return _get_limb_node(n)
	return _get_limb_node("torso")


func _fallback_target(victim, desired: String) -> String:
	if not victim.limb_hp[desired].gone:
		return desired
	if not victim.limb_hp["torso"].gone:
		return "torso"
	for name in LIMBS:
		if not victim.limb_hp[name].gone:
			return name
	return "torso"


func _move_speed() -> float:
	var legs_lost := 0
	if limb_hp["leg_l"].gone:
		legs_lost += 1
	if limb_hp["leg_r"].gone:
		legs_lost += 1
	match legs_lost:
		1:
			return SPEED * 0.7
		2:
			return SPEED * 0.45
	return SPEED


func _is_ko() -> bool:
	if health <= 0.0:
		return true
	if limb_hp["head"].gone:
		return true
	if limb_hp["arm_l"].gone and limb_hp["arm_r"].gone and limb_hp["leg_l"].gone and limb_hp["leg_r"].gone:
		return true
	return false


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
	rig.rotation = 0.0
	_set_hitbox(false)
	rig.self_modulate = Color.WHITE
	rig.modulate = Color.WHITE
	_interrupt_attack()
	for name in LIMBS:
		limb_hp[name].hp = LIMB_MAX[name]
		limb_hp[name].gone = false
		_get_limb_body(name).visible = true


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

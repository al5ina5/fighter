extends CharacterBody2D
class_name Player

const SPEED := 300.0
const JUMP_VELOCITY := -400.0
const GRAVITY := 980.0

const LIGHT := {
	"windup": 0.10, "active": 0.10, "recovery": 0.20,
	"damage": 5.0, "knockback": 160.0, "reach": Vector2(70, 80),
}
const HEAVY := {
	"windup": 0.35, "active": 0.12, "recovery": 0.35,
	"damage": 12.0, "knockback": 300.0, "reach": Vector2(95, 95),
}

signal died

enum State { IDLE, ATTACK, HURT, KO }

@export var player_number: int = 1
@export var body_color: Color = Color(0.85, 0.2, 0.2)

@onready var visual: Node2D = $Visual
@onready var body: ColorRect = $Visual/Body
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/HitboxShape
@onready var hitbox_debug: ColorRect = $Hitbox/DebugRect

var health := 100.0
var state: int = State.IDLE
var facing := 1
var hurt_timer := 0.0
var flash_timer := 0.0
var attack: Dictionary = {}
var attack_phase := ""
var attack_time := 0.0
var hit_landed := false


func _ready() -> void:
	body.color = body_color
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

	move_and_slide()
	_update_flash(delta)


func _apply_idle() -> void:
	if _jump_pressed() and is_on_floor():
		velocity.y = JUMP_VELOCITY
		return
	if _light_pressed():
		_start_attack(LIGHT)
	elif _heavy_pressed():
		_start_attack(HEAVY)
	else:
		velocity.x = _move_input() * SPEED


func _start_attack(data: Dictionary) -> void:
	state = State.ATTACK
	attack = data
	attack_phase = "windup"
	attack_time = 0.0
	hit_landed = false
	var reach: Vector2 = data.reach
	hitbox_shape.shape.size = reach
	hitbox.position.x = facing * (reach.x / 2.0 + 30.0)
	_set_hitbox(false)


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
		var victim := area.get_parent()
		if victim is Player and victim != self:
			hit_landed = true
			victim.take_hit(attack.damage, global_position.x, attack.knockback)


func take_hit(dmg: float, source_x: float, kb: float) -> void:
	health -= dmg
	state = State.HURT
	hurt_timer = 0.25
	_set_hitbox(false)
	var dir_away := 1.0 if global_position.x >= source_x else -1.0
	velocity = Vector2(dir_away * kb, -130.0)
	visual.self_modulate = Color(3.0, 3.0, 3.0)
	flash_timer = 0.12
	Effects.hitstop(0.05 if dmg <= 6.0 else 0.09)
	Effects.add_shake(3.0 if dmg <= 6.0 else 7.0)
	print("HIT dmg=", dmg, " -> hp=", health)
	if health <= 0.0:
		health = 0.0
		state = State.KO
		Effects.add_shake(12.0)
		emit_signal("died")


func _update_flash(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			visual.self_modulate = Color.WHITE


func _set_hitbox(active: bool) -> void:
	hitbox_shape.disabled = not active
	hitbox_debug.visible = active


func _move_input() -> float:
	var dir := Input.get_axis(_action("move_left"), _action("move_right"))
	var stick := Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_X)
	if absf(stick) < 0.15:
		stick = 0.0
	return clampf(dir + stick, -1.0, 1.0)


func _jump_pressed() -> bool:
	return Input.is_action_just_pressed(_action("jump"))


func _light_pressed() -> bool:
	return Input.is_action_just_pressed(_action("light"))


func _heavy_pressed() -> bool:
	return Input.is_action_just_pressed(_action("heavy"))


func _action(name: String) -> StringName:
	return StringName("p%d_%s" % [player_number, name])


func _pad_device() -> int:
	return player_number - 1


func _update_facing() -> void:
	var opponent := _find_opponent()
	if opponent == null:
		return
	facing = 1 if opponent.global_position.x >= global_position.x else -1
	visual.scale.x = facing


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

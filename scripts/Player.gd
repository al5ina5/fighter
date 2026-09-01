extends CharacterBody2D

const SPEED := 300.0
const JUMP_VELOCITY := -400.0
const GRAVITY := 980.0

@export var player_number: int = 1
@export var body_color: Color = Color(0.85, 0.2, 0.2)

@onready var visual: Node2D = $Visual
@onready var body: ColorRect = $Visual/Body


func _ready() -> void:
	body.color = body_color


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if _jump_pressed() and is_on_floor():
		velocity.y = JUMP_VELOCITY

	velocity.x = _move_input() * SPEED
	move_and_slide()
	_update_facing()


func _move_input() -> float:
	var dir := Input.get_axis(_action("move_left"), _action("move_right"))
	var stick := Input.get_joy_axis(_pad_device(), JOY_AXIS_LEFT_X)
	if absf(stick) < 0.15:
		stick = 0.0
	return clampf(dir + stick, -1.0, 1.0)


func _jump_pressed() -> bool:
	if Input.is_action_just_pressed(_action("jump")):
		return true
	var d := _pad_device()
	return d >= 0 and Input.is_joy_button_pressed(d, JOY_BUTTON_A)


func _action(name: String) -> StringName:
	return StringName("p%d_%s" % [player_number, name])


func _pad_device() -> int:
	return player_number - 1


func _update_facing() -> void:
	var opponent := _find_opponent()
	if opponent == null:
		return
	visual.scale.x = 1.0 if opponent.global_position.x >= global_position.x else -1.0


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

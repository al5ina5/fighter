extends Node

var shake_amount := 0.0
var shake_decay := 8.0
var hitstop_remaining := 0.0


func add_shake(amount: float) -> void:
	shake_amount = max(shake_amount, amount)


func _process(delta: float) -> void:
	if hitstop_remaining > 0.0:
		hitstop_remaining -= delta
		if hitstop_remaining <= 0.0:
			_resume_all()
	if shake_amount > 0.0:
		shake_amount -= shake_decay * delta
		if shake_amount < 0.0:
			shake_amount = 0.0
		var cam := get_camera()
		if cam != null:
			cam.offset = Vector2(
				randf_range(-shake_amount, shake_amount),
				randf_range(-shake_amount, shake_amount)
			)


func hitstop(duration: float) -> void:
	hitstop_remaining = maxf(hitstop_remaining, duration)
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(false)
		node.set_hitstop_paused(true)


func _resume_all() -> void:
	hitstop_remaining = 0.0
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(true)
		node.set_hitstop_paused(false)


func get_camera() -> Camera2D:
	return get_tree().get_first_node_in_group("camera") as Camera2D

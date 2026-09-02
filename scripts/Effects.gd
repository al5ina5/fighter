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
		if cam is Camera2D:
			cam.offset = Vector2(
				randf_range(-shake_amount, shake_amount),
				randf_range(-shake_amount, shake_amount)
			)
		elif cam is Camera3D:
			cam.h_offset = randf_range(-shake_amount, shake_amount) / 100.0
			cam.v_offset = randf_range(-shake_amount, shake_amount) / 100.0
	elif shake_amount <= 0.0:
		var cam := get_camera()
		if cam is Camera2D:
			cam.offset = Vector2.ZERO
		elif cam is Camera3D:
			cam.h_offset = 0.0
			cam.v_offset = 0.0


func hitstop(duration: float) -> void:
	hitstop_remaining = maxf(hitstop_remaining, duration)
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(false)
		node.set_hitstop_paused(true)
	for visual in get_tree().get_nodes_in_group("fighter_visuals"):
		visual.set_hitstop_paused(true)


func _resume_all() -> void:
	hitstop_remaining = 0.0
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(true)
		node.set_hitstop_paused(false)
	for visual in get_tree().get_nodes_in_group("fighter_visuals"):
		visual.set_hitstop_paused(false)


func get_camera() -> Node:
	return get_tree().get_first_node_in_group("camera")

extends Node

var shake_amount := 0.0
var shake_decay := 8.0


func add_shake(amount: float) -> void:
	shake_amount = max(shake_amount, amount)


func _process(delta: float) -> void:
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
	var tree := get_tree()
	tree.paused = false
	for node in tree.get_nodes_in_group("players"):
		node.set_physics_process(false)
	tree.create_timer(duration).timeout.connect(_resume_all)


func _resume_all() -> void:
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(true)


func get_camera() -> Camera2D:
	return get_tree().get_first_node_in_group("camera") as Camera2D

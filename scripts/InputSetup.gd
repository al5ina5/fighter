extends Node


func _ready() -> void:
	# Player 1 — keyboard (WASD) + controller slot 0
	_setup_action("p1_move_left", [KEY_A])
	_setup_action("p1_move_right", [KEY_D])
	_setup_action("p1_jump", [KEY_W, KEY_SPACE])
	# Player 2 — keyboard (arrows) + controller slot 1
	_setup_action("p2_move_left", [KEY_LEFT])
	_setup_action("p2_move_right", [KEY_RIGHT])
	_setup_action("p2_jump", [KEY_UP, KEY_ENTER])


func _setup_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)

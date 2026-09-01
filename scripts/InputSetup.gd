extends Node


func _ready() -> void:
	_setup_action("move_left", [KEY_A, KEY_LEFT])
	_setup_action("move_right", [KEY_D, KEY_RIGHT])
	_setup_action("jump", [KEY_SPACE, KEY_W, KEY_UP])


func _setup_action(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)

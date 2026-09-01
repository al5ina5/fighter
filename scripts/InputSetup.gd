extends Node


func _ready() -> void:
	# Player 1 — keyboard (WASD) + controller slot 0
	_key_action("p1_move_left", [KEY_A], JOY_BUTTON_DPAD_LEFT, 0)
	_key_action("p1_move_right", [KEY_D], JOY_BUTTON_DPAD_RIGHT, 0)
	_key_action("p1_jump", [KEY_W, KEY_UP], JOY_BUTTON_DPAD_UP, 0)
	_key_action("p1_block", [KEY_S])
	_key_action("p1_high", [KEY_F], JOY_BUTTON_Y, 0)
	_key_action("p1_mid", [KEY_G], JOY_BUTTON_X, 0)
	_key_action("p1_low", [KEY_H], JOY_BUTTON_A, 0)
	_key_action("p1_heavy", [KEY_R], JOY_BUTTON_B, 0)
	_key_action("p1_stance", [KEY_C], JOY_BUTTON_RIGHT_STICK, 0)
	# Player 2 — keyboard (arrows) + controller slot 1
	_key_action("p2_move_left", [KEY_LEFT], JOY_BUTTON_DPAD_LEFT, 1)
	_key_action("p2_move_right", [KEY_RIGHT], JOY_BUTTON_DPAD_RIGHT, 1)
	_key_action("p2_jump", [KEY_UP], JOY_BUTTON_DPAD_UP, 1)
	_key_action("p2_block", [KEY_DOWN])
	_key_action("p2_high", [KEY_K], JOY_BUTTON_Y, 1)
	_key_action("p2_mid", [KEY_L], JOY_BUTTON_X, 1)
	_key_action("p2_low", [KEY_SEMICOLON], JOY_BUTTON_A, 1)
	_key_action("p2_heavy", [KEY_P], JOY_BUTTON_B, 1)
	_key_action("p2_stance", [KEY_V], JOY_BUTTON_RIGHT_STICK, 1)


func _key_action(action: StringName, keys: Array, pad_button: int = -1, pad_device: int = 0) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	if pad_button >= 0:
		var pad := InputEventJoypadButton.new()
		pad.button_index = pad_button
		pad.device = pad_device
		InputMap.action_add_event(action, pad)

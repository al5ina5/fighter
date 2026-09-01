extends Node2D


func _ready() -> void:
	GameState.reset()
	_build_ui()


func _process(_delta: float) -> void:
	if _should_start():
		get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")


func _build_ui() -> void:
	_add_label("FIGHTER", 150, Color(1, 0.85, 0.2), 220, 180)
	_add_label("A limb-by-limb underground fistfight", 40, Color(0.8, 0.8, 0.85), 420, 60)


func _add_label(text: String, font_size: int, color: Color, y: float, h: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, y)
	label.size = Vector2(1280, h)
	add_child(label)


func _should_start() -> bool:
	if Input.is_action_just_pressed("ui_accept"):
		return true
	for action in ["p1_jump", "p1_high", "p1_mid", "p1_low", "p1_heavy", "p1_stance", "p2_jump", "p2_high", "p2_mid", "p2_low", "p2_heavy", "p2_stance"]:
		if Input.is_action_just_pressed(action):
			return true
	for device in [0, 1]:
		if Input.is_joy_button_pressed(device, JOY_BUTTON_START):
			return true
	return false

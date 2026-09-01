extends Node2D

const CARD_SIZE := Vector2(160, 190)
const CARD_GAP := 40.0
const CARD_Y := 340.0

var cards: Array = []
var p1_cursor: ColorRect
var p2_cursor: ColorRect
var launch_timer := -1.0


func _ready() -> void:
	_build()


func _build() -> void:
	_add_label("CHOOSE YOUR FIGHTER", 60, Color(1, 0.85, 0.2), 130, 90)

	var chars := GameState.CHARACTERS
	var count := chars.size()
	var total_width := count * CARD_SIZE.x + (count - 1) * CARD_GAP
	var start_x := (1280.0 - total_width) / 2.0
	for i in count:
		var c: Dictionary = chars[i]
		var card := ColorRect.new()
		card.color = c.color
		card.size = CARD_SIZE
		card.position = Vector2(start_x + i * (CARD_SIZE.x + CARD_GAP), CARD_Y)
		add_child(card)
		var name_label := Label.new()
		name_label.text = c.name
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.position = card.position + Vector2(0, CARD_SIZE.y - 46)
		name_label.size = CARD_SIZE
		add_child(name_label)
		cards.append(card)

	p1_cursor = _make_cursor(Color(1, 0.35, 0.3))
	p2_cursor = _make_cursor(Color(0.35, 0.55, 1))

	_add_label("Player 1: A/D move, F select    |    Player 2: arrows, K select", 26, Color(1, 1, 1), 588, 40)
	_update()


func _add_label(text: String, font_size: int, color: Color, y: float, h: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, y)
	label.size = Vector2(1280, h)
	add_child(label)


func _make_cursor(col: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(col.r, col.g, col.b, 0.4)
	rect.size = CARD_SIZE
	rect.z_index = 2
	add_child(rect)
	return rect


func _physics_process(delta: float) -> void:
	if GameState.p1_ready and GameState.p2_ready:
		if launch_timer < 0.0:
			launch_timer = 0.6
		launch_timer -= delta
		if launch_timer <= 0.0:
			get_tree().change_scene_to_file("res://scenes/Battle.tscn")
		return
	launch_timer = -1.0

	if Input.is_action_just_pressed("p1_move_right"):
		GameState.p1_index = _wrap(GameState.p1_index + 1)
	elif Input.is_action_just_pressed("p1_move_left"):
		GameState.p1_index = _wrap(GameState.p1_index - 1)
	elif Input.is_action_just_pressed("p1_light"):
		GameState.p1_ready = not GameState.p1_ready
	elif Input.is_action_just_pressed("p2_move_right"):
		GameState.p2_index = _wrap(GameState.p2_index + 1)
	elif Input.is_action_just_pressed("p2_move_left"):
		GameState.p2_index = _wrap(GameState.p2_index - 1)
	elif Input.is_action_just_pressed("p2_light"):
		GameState.p2_ready = not GameState.p2_ready
	_update()


func _update() -> void:
	p1_cursor.position = cards[GameState.p1_index].position
	p2_cursor.position = cards[GameState.p2_index].position
	p1_cursor.color = Color(1, 0.35, 0.3, 0.9) if GameState.p1_ready else Color(1, 0.35, 0.3, 0.4)
	p2_cursor.color = Color(0.35, 0.55, 1, 0.9) if GameState.p2_ready else Color(0.35, 0.55, 1, 0.4)


func _wrap(index: int) -> int:
	return (index + GameState.CHARACTERS.size()) % GameState.CHARACTERS.size()

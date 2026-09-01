extends Node2D

const CARD_SIZE := Vector2(160, 190)
const CARD_GAP := 40.0
const CARD_Y := 340.0

var cards: Array = []
var p1_cursor: Panel
var p2_cursor: Panel
var p1_marker: Panel
var p2_marker: Panel
var p1_badge: Panel
var p2_badge: Panel
var status_label: Label
var banner_label: Label
var banner_time := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	_make_label("CHOOSE YOUR FIGHTER", 60, Color(1, 0.85, 0.2), 130, 90)

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

	p1_cursor = _make_cursor(Color(1, 0.3, 0.28))
	p2_cursor = _make_cursor(Color(0.32, 0.55, 1.0))
	p1_marker = _make_marker(Color(1, 0.3, 0.28))
	p2_marker = _make_marker(Color(0.32, 0.55, 1.0))
	p1_badge = _make_badge(Color(1, 0.3, 0.28), "1P")
	p2_badge = _make_badge(Color(0.32, 0.55, 1.0), "2P")

	status_label = _make_label("", 34, Color(0.85, 0.85, 0.9), 560, 60)
	banner_label = _make_label("PRESS START", 80, Color(1, 0.3, 0.2), 240, 110)
	banner_label.visible = false
	_update_status()
	_update_banner()


func _make_label(text: String, font_size: int, color: Color, y: float, h: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, y)
	label.size = Vector2(1280, h)
	add_child(label)
	return label


func _make_cursor(col: Color) -> Panel:
	var panel := Panel.new()
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.border_color = col
	outline.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", outline)
	panel.size = CARD_SIZE
	panel.z_index = 2
	panel.visible = false
	add_child(panel)
	return panel


func _make_marker(col: Color) -> Panel:
	var panel := Panel.new()
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.border_color = col
	outline.set_border_width_all(8)
	panel.add_theme_stylebox_override("panel", outline)
	panel.size = CARD_SIZE
	panel.z_index = 3
	panel.visible = false
	add_child(panel)
	return panel


func _make_badge(col: Color, text: String) -> Panel:
	var panel := Panel.new()
	var outline := StyleBoxFlat.new()
	outline.bg_color = col
	outline.border_color = Color(1, 1, 1, 1)
	outline.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", outline)
	panel.size = Vector2(56, 28)
	panel.z_index = 4
	panel.visible = false
	add_child(panel)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = panel.size
	panel.add_child(label)
	return panel


func _physics_process(delta: float) -> void:
	if GameState.p1_ready and GameState.p2_ready and _start_pressed():
		get_tree().change_scene_to_file("res://scenes/Battle.tscn")
		return

	_update_player(1, "p1_move_left", "p1_move_right", "p1_light", p1_cursor, p1_marker, p1_badge)
	_update_player(2, "p2_move_left", "p2_move_right", "p2_light", p2_cursor, p2_marker, p2_badge)
	_update_status()
	banner_time += delta
	_update_banner()


func _update_player(pn: int, move_left: String, move_right: String, confirm: String, cursor: Panel, marker: Panel, badge: Panel) -> void:
	if Input.is_action_just_pressed(move_right):
		_set_index(pn, _get_index(pn) + 1)
	elif Input.is_action_just_pressed(move_left):
		_set_index(pn, _get_index(pn) - 1)
	if Input.is_action_just_pressed(confirm):
		_set_ready(pn, true)

	var card_pos: Vector2 = cards[_get_index(pn)].position
	if pn == 1:
		cursor.position = card_pos + Vector2(-5, -5)
	else:
		cursor.position = card_pos + Vector2(5, 5)
	cursor.visible = true

	if _get_ready(pn):
		if pn == 1:
			marker.position = card_pos + Vector2(-8, -8)
			badge.position = card_pos + Vector2(-10, -34)
		else:
			marker.position = card_pos + Vector2(8, 8)
			badge.position = card_pos + Vector2(CARD_SIZE.x - 46, -34)
		marker.visible = true
		badge.visible = true
	else:
		marker.visible = false
		badge.visible = false


func _update_status() -> void:
	var s1 := "P1 ready" if GameState.p1_ready else "P1: choose a fighter"
	var s2 := "P2 ready" if GameState.p2_ready else "P2: choose a fighter"
	status_label.text = "%s          |          %s" % [s1, s2]


func _update_banner() -> void:
	var show := GameState.p1_ready and GameState.p2_ready
	banner_label.visible = show
	if show:
		banner_label.modulate.a = 0.45 + 0.55 * absf(sin(banner_time * 4.0))


func _start_pressed() -> bool:
	if Input.is_action_just_pressed("ui_accept"):
		return true
	for device in [0, 1]:
		if Input.is_joy_button_pressed(device, JOY_BUTTON_START):
			return true
	return false


func _get_index(pn: int) -> int:
	return GameState.get("p%d_index" % pn)


func _set_index(pn: int, value: int) -> void:
	GameState.set("p%d_index" % pn, _wrap(value))


func _get_ready(pn: int) -> bool:
	return GameState.get("p%d_ready" % pn)


func _set_ready(pn: int, value: bool) -> void:
	GameState.set("p%d_ready" % pn, value)


func _wrap(index: int) -> int:
	return (index + GameState.CHARACTERS.size()) % GameState.CHARACTERS.size()

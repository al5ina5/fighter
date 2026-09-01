extends Node2D

const PLAYER_TS := preload("res://scenes/Player.tscn")

enum Phase { COUNTDOWN, FIGHT, KO }

const LIMB_LIST := ["arm_l", "arm_r", "leg_l", "leg_r"]
const LIMB_MAX_HP := 40.0

@onready var p1_bar: ProgressBar = $HUD/P1Bar
@onready var p2_bar: ProgressBar = $HUD/P2Bar
@onready var p1_guard: ProgressBar = $HUD/P1Guard
@onready var p2_guard: ProgressBar = $HUD/P2Guard
@onready var count_label: Label = $HUD/CountLabel
@onready var ko_label: Label = $HUD/KOLabel
@onready var rematch_label: Label = $HUD/RematchLabel

var player1
var player2
var phase: int = Phase.COUNTDOWN
var p1_bars := {}
var p2_bars := {}
var start_menu: Panel
var start_menu_open := false


func _ready() -> void:
	_spawn_players()
	var players := get_tree().get_nodes_in_group("players")
	players.sort_custom(func(a, b): return a.player_number < b.player_number)
	player1 = players[0]
	player2 = players[1]
	player1.died.connect(_on_ko.bind(player2))
	player2.died.connect(_on_ko.bind(player1))
	_build_limb_hud()
	_build_start_menu()
	_start_round()


func _build_start_menu() -> void:
	start_menu = Panel.new()
	start_menu.name = "StartMenu"
	start_menu.position = Vector2(440, 180)
	start_menu.size = Vector2(400, 360)
	start_menu.visible = false
	start_menu.z_index = 20
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.97)
	style.border_color = Color(1, 0.85, 0.2, 1)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	start_menu.add_theme_stylebox_override("panel", style)
	$HUD.add_child(start_menu)

	var title := Label.new()
	title.text = "START MENU"
	title.position = Vector2(0, 28)
	title.size = Vector2(400, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	start_menu.add_child(title)

	var restart := Button.new()
	restart.name = "RestartFight"
	restart.text = "RESTART FIGHT"
	restart.position = Vector2(55, 120)
	restart.size = Vector2(290, 64)
	restart.add_theme_font_size_override("font_size", 26)
	restart.pressed.connect(_on_restart_pressed)
	start_menu.add_child(restart)

	var main_menu := Button.new()
	main_menu.name = "MainMenu"
	main_menu.text = "MAIN MENU"
	main_menu.position = Vector2(55, 204)
	main_menu.size = Vector2(290, 64)
	main_menu.add_theme_font_size_override("font_size", 26)
	main_menu.pressed.connect(_on_main_menu_pressed)
	start_menu.add_child(main_menu)

	var hint := Label.new()
	hint.text = "Esc / Start: close menu"
	hint.position = Vector2(0, 294)
	hint.size = Vector2(400, 36)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	start_menu.add_child(hint)


func _build_limb_hud() -> void:
	_build_limb_row(player1.body_color, 30.0, p1_bars)
	_build_limb_row(player2.body_color, 670.0, p2_bars)


func _build_limb_row(body_color: Color, x0: float, store: Dictionary) -> void:
	var y := 60.0
	var w := 140.0
	var h := 8.0
	var gap := 6.0
	for i in LIMB_LIST.size():
		var name: String = LIMB_LIST[i]
		var bx := x0 + i * (w + gap)
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.1, 0.14, 1)
		bg.position = Vector2(bx, y)
		bg.size = Vector2(w, h)
		$HUD.add_child(bg)
		var fill := ColorRect.new()
		fill.color = _limb_color(body_color, name)
		fill.position = Vector2(bx + 1, y + 1)
		fill.size = Vector2(w - 2, h - 2)
		$HUD.add_child(fill)
		store[name] = fill


func _limb_color(base: Color, name: String) -> Color:
	if name == "arm_r" or name == "leg_r":
		return base.darkened(0.2)
	return base.lightened(0.05)


func _update_limb_bars(store: Dictionary, player) -> void:
	for name in LIMB_LIST:
		var fill: ColorRect = store[name]
		var data: Dictionary = player.limb_hp[name]
		if data.gone:
			fill.visible = false
		else:
			fill.visible = true
			fill.size.x = (140.0 - 2.0) * clampf(data.hp / LIMB_MAX_HP, 0.0, 1.0)


func _spawn_players() -> void:
	var p1 = PLAYER_TS.instantiate()
	p1.player_number = 1
	p1.body_color = GameState.p1_char().color
	p1.name = GameState.p1_char().name
	p1.position = Vector2(420, 400)
	add_child(p1)

	var p2 = PLAYER_TS.instantiate()
	p2.player_number = 2
	p2.body_color = GameState.p2_char().color
	p2.name = GameState.p2_char().name
	p2.position = Vector2(860, 400)
	add_child(p2)


func _physics_process(_delta: float) -> void:
	if player1 != null and player2 != null:
		p1_bar.value = maxf(player1.health, 0.0)
		p2_bar.value = maxf(player2.health, 0.0)
		p1_guard.value = maxf(player1.guard, 0.0)
		p2_guard.value = maxf(player2.guard, 0.0)
		_update_limb_bars(p1_bars, player1)
		_update_limb_bars(p2_bars, player2)
		_separate_players()


func _separate_players() -> void:
	if not (player1.is_on_floor() and player2.is_on_floor()):
		return
	var dx: float = player2.global_position.x - player1.global_position.x
	if absf(dx) < 200.0:
		var dir: float = 1.0 if dx >= 0.0 else -1.0
		var push: float = (200.0 - absf(dx)) / 2.0
		player1.global_position.x -= dir * push
		player2.global_position.x += dir * push


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel") or _start_pressed():
		_toggle_start_menu()
		return
	if phase == Phase.KO and Input.is_physical_key_pressed(KEY_R):
		_reset_round()


func _start_pressed() -> bool:
	for device in [0, 1]:
		if Input.is_joy_button_pressed(device, JOY_BUTTON_START):
			return true
	return false


func _toggle_start_menu() -> void:
	start_menu_open = not start_menu_open
	start_menu.visible = start_menu_open
	_lock_players(start_menu_open)
	if start_menu_open:
		start_menu.get_node("RestartFight").grab_focus()


func _on_restart_pressed() -> void:
	start_menu_open = false
	start_menu.visible = false
	_reset_round()


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _start_round() -> void:
	phase = Phase.COUNTDOWN
	ko_label.visible = false
	rematch_label.visible = false
	count_label.visible = true
	_lock_players(true)
	await get_tree().create_timer(0.4).timeout
	for txt in ["3", "2", "1"]:
		count_label.text = txt
		await get_tree().create_timer(1.0).timeout
	count_label.text = "FIGHT!"
	await get_tree().create_timer(0.5).timeout
	count_label.visible = false
	_lock_players(false)
	phase = Phase.FIGHT


func _on_ko(winner) -> void:
	phase = Phase.KO
	_lock_players(true)
	ko_label.text = "%s WINS!" % winner.name
	ko_label.visible = true
	rematch_label.visible = true


func _reset_round() -> void:
	player1.reset(Vector2(420, 400))
	player2.reset(Vector2(860, 400))
	_start_round()


func _lock_players(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		player.input_locked = locked

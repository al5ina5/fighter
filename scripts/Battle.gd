extends Node2D

const PLAYER_TS := preload("res://scenes/Player.tscn")
const ROUND_TIME_FRAMES := 99 * 60
const ROUNDS_TO_WIN := 2
const START_POSITIONS := [Vector2(420, 400), Vector2(860, 400)]

enum Phase { COUNTDOWN, FIGHT, KO, MATCH_OVER }

const LIMB_LIST := ["head", "arm_l", "arm_r", "leg_l", "leg_r"]

@onready var p1_bar: ProgressBar = $HUD/P1Bar
@onready var p2_bar: ProgressBar = $HUD/P2Bar
@onready var p1_guard: ProgressBar = $HUD/P1Guard
@onready var p2_guard: ProgressBar = $HUD/P2Guard
@onready var timer_label: Label = $HUD/TimerLabel
@onready var score_label: Label = $HUD/ScoreLabel
@onready var count_label: Label = $HUD/CountLabel
@onready var ko_label: Label = $HUD/KOLabel
@onready var rematch_label: Label = $HUD/RematchLabel
@onready var arena_3d: Arena3D = $Arena3D
@onready var debug_overlay: CombatDebugOverlay = $CombatDebugOverlay
@onready var debug_data: Label = $HUD/DebugData
@onready var p1_combo_label: Label = $HUD/P1ComboLabel
@onready var p2_combo_label: Label = $HUD/P2ComboLabel

var player1: Player
var player2: Player
var player1_visual: FighterVisual3D
var player2_visual: FighterVisual3D
var phase: int = Phase.COUNTDOWN
var p1_bars := {}
var p2_bars := {}
var start_menu: Panel
var start_menu_open := false
var start_button_was_down := false
var round_time_frames := ROUND_TIME_FRAMES
var round_number := 1
var p1_rounds := 0
var p2_rounds := 0
var countdown_generation := 0
var pending_hits: Array[Dictionary] = []
var hit_resolution_scheduled := false
var round_evaluation_scheduled := false
var rematch_input_armed := false
var combo_counts := [0, 0]
var combo_display_frames := [0, 0]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spawn_players()
	var players := get_tree().get_nodes_in_group("players")
	players.sort_custom(func(a, b): return a.player_number < b.player_number)
	player1 = players[0]
	player2 = players[1]
	player1_visual = arena_3d.add_fighter(player1, GameState.p1_char())
	player2_visual = arena_3d.add_fighter(player2, GameState.p2_char())
	player1.died.connect(_on_fighter_ko)
	player2.died.connect(_on_fighter_ko)
	_build_limb_hud()
	_build_start_menu()
	debug_overlay.bind_players(player1, player2, debug_data)
	_update_score_hud()
	_start_round()


## Resolve all contacts after both fighters have taken their physics turn. This
## makes trades and double KOs independent from scene-tree processing order.
func queue_combat_hit(attacker: Player, victim: Player, payload: Dictionary) -> void:
	pending_hits.append({"attacker": attacker, "victim": victim, "payload": payload.duplicate(true)})
	if not hit_resolution_scheduled:
		hit_resolution_scheduled = true
		call_deferred("_resolve_combat_hits")


func _resolve_combat_hits() -> void:
	hit_resolution_scheduled = false
	var current_hits := pending_hits.duplicate(true)
	pending_hits.clear()
	var results: Array[Dictionary] = []
	for queued in current_hits:
		var attacker := queued.attacker as Player
		var victim := queued.victim as Player
		if not is_instance_valid(attacker) or not is_instance_valid(victim):
			continue
		var continuing_combo := victim.state == Player.State.HITSTUN
		var blocked := victim.receive_combat_hit(queued.payload)
		_record_combo(attacker, blocked, continuing_combo)
		results.append({"attacker": attacker, "blocked": blocked})
	for result in results:
		var attacker := result.attacker as Player
		if is_instance_valid(attacker):
			attacker.notify_attack_result(bool(result.blocked))
	_schedule_round_evaluation()


func _schedule_round_evaluation() -> void:
	if round_evaluation_scheduled:
		return
	round_evaluation_scheduled = true
	call_deferred("_evaluate_round_result")


func _evaluate_round_result() -> void:
	round_evaluation_scheduled = false
	if phase != Phase.FIGHT:
		return
	var p1_ko := player1.state == Player.State.KO
	var p2_ko := player2.state == Player.State.KO
	if p1_ko and p2_ko:
		_finish_round(null, "DOUBLE KO")
	elif p1_ko:
		_finish_round(player2, "%s WINS" % player2.name)
	elif p2_ko:
		_finish_round(player1, "%s WINS" % player1.name)


func _on_fighter_ko() -> void:
	_schedule_round_evaluation()


func _physics_process(_delta: float) -> void:
	if player1 == null or player2 == null:
		return
	p1_bar.value = maxf(player1.health, 0.0)
	p2_bar.value = maxf(player2.health, 0.0)
	p1_guard.value = maxf(player1.guard, 0.0)
	p2_guard.value = maxf(player2.guard, 0.0)
	_update_limb_bars(p1_bars, player1)
	_update_limb_bars(p2_bars, player2)
	if not start_menu_open and Effects.hitstop_remaining <= 0.0:
		_tick_combo_displays()
	if phase == Phase.FIGHT and not start_menu_open and Effects.hitstop_remaining <= 0.0:
		round_time_frames = maxi(0, round_time_frames - 1)
		timer_label.text = str(ceili(float(round_time_frames) / 60.0))
		if round_time_frames <= 0:
			_resolve_timeout()


func _process(_delta: float) -> void:
	_resolve_fighter_spacing()
	if Input.is_action_just_pressed("ui_cancel") or _start_just_pressed():
		_toggle_start_menu()
		return
	if phase == Phase.MATCH_OVER:
		var rematch_down := Input.is_physical_key_pressed(KEY_R)
		if not rematch_down:
			rematch_input_armed = true
		elif rematch_input_armed:
			rematch_input_armed = false
			_reset_match()


## CharacterBody2D collisions remain useful against the stage, but two moving
## character bodies can retain a small overlap depending on processing order.
## This deterministic post-step solver guarantees grounded pushboxes never
## overlap or cross, including when both players walk forward simultaneously.
func _resolve_fighter_spacing() -> void:
	if player1 == null or player2 == null:
		return
	if not player1.is_on_floor() or not player2.is_on_floor():
		return
	var left := player1 if player1.global_position.x <= player2.global_position.x else player2
	var right := player2 if left == player1 else player1
	var minimum_distance := left.pushbox_half_width() + right.pushbox_half_width()
	var current_distance := right.global_position.x - left.global_position.x
	if current_distance >= minimum_distance:
		return
	var correction := (minimum_distance - current_distance) * 0.5
	left.global_position.x -= correction
	right.global_position.x += correction
	if left.velocity.x > 0.0:
		left.velocity.x = 0.0
	if right.velocity.x < 0.0:
		right.velocity.x = 0.0


func _start_just_pressed() -> bool:
	var down := false
	for device in [0, 1]:
		down = down or Input.is_joy_button_pressed(device, JOY_BUTTON_START)
	var just_pressed := down and not start_button_was_down
	start_button_was_down = down
	return just_pressed


func _resolve_timeout() -> void:
	if phase != Phase.FIGHT:
		return
	if is_equal_approx(player1.health, player2.health):
		_finish_round(null, "TIME UP — DRAW")
	elif player1.health > player2.health:
		_finish_round(player1, "TIME UP — %s WINS" % player1.name)
	else:
		_finish_round(player2, "TIME UP — %s WINS" % player2.name)


func _finish_round(winner: Player, headline: String) -> void:
	if phase != Phase.FIGHT:
		return
	phase = Phase.KO
	_lock_players(true)
	if winner == player1:
		p1_rounds += 1
	elif winner == player2:
		p2_rounds += 1
	_update_score_hud()
	ko_label.text = headline + "!"
	ko_label.visible = true
	if p1_rounds >= ROUNDS_TO_WIN or p2_rounds >= ROUNDS_TO_WIN:
		phase = Phase.MATCH_OVER
		rematch_input_armed = false
		ko_label.text = "%s TAKES THE MATCH!" % winner.name
		rematch_label.visible = true
		return
	var completed_round := round_number
	await get_tree().create_timer(2.0, false).timeout
	if phase != Phase.KO or round_number != completed_round:
		return
	round_number += 1
	_reset_fighters()
	_start_round()


func _start_round() -> void:
	countdown_generation += 1
	var generation := countdown_generation
	phase = Phase.COUNTDOWN
	round_time_frames = ROUND_TIME_FRAMES
	timer_label.text = "99"
	ko_label.visible = false
	rematch_label.visible = false
	count_label.visible = true
	_lock_players(true)
	_update_score_hud()
	await get_tree().create_timer(0.25, false).timeout
	for txt in ["3", "2", "1"]:
		if generation != countdown_generation:
			return
		count_label.text = txt
		await get_tree().create_timer(0.7, false).timeout
	if generation != countdown_generation:
		return
	count_label.text = "FIGHT!"
	await get_tree().create_timer(0.35, false).timeout
	if generation != countdown_generation:
		return
	count_label.visible = false
	_lock_players(false)
	phase = Phase.FIGHT


func _reset_fighters() -> void:
	pending_hits.clear()
	combo_counts = [0, 0]
	combo_display_frames = [0, 0]
	p1_combo_label.visible = false
	p2_combo_label.visible = false
	player1.reset(START_POSITIONS[0])
	player2.reset(START_POSITIONS[1])


func _reset_match() -> void:
	countdown_generation += 1
	rematch_input_armed = false
	p1_rounds = 0
	p2_rounds = 0
	round_number = 1
	_reset_fighters()
	_start_round()


func _update_score_hud() -> void:
	var p1_marks := "●".repeat(p1_rounds) + "○".repeat(ROUNDS_TO_WIN - p1_rounds)
	var p2_marks := "●".repeat(p2_rounds) + "○".repeat(ROUNDS_TO_WIN - p2_rounds)
	score_label.text = "%s    ROUND %d    %s" % [p1_marks, round_number, p2_marks]


func _record_combo(attacker: Player, blocked: bool, continuing: bool) -> void:
	var index := attacker.player_number - 1
	if blocked:
		combo_counts[index] = 0
		combo_display_frames[index] = 0
	else:
		combo_counts[index] = int(combo_counts[index]) + 1 if continuing else 1
		combo_display_frames[index] = 75
	var label := p1_combo_label if index == 0 else p2_combo_label
	label.visible = int(combo_counts[index]) >= 2
	label.text = "%d HIT COMBO" % int(combo_counts[index])


func _tick_combo_displays() -> void:
	for index in 2:
		if int(combo_display_frames[index]) > 0:
			combo_display_frames[index] = int(combo_display_frames[index]) - 1
		elif int(combo_counts[index]) > 0:
			combo_counts[index] = 0
			(p1_combo_label if index == 0 else p2_combo_label).visible = false


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
	title.text = "PAUSED"
	title.position = Vector2(0, 28)
	title.size = Vector2(400, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	start_menu.add_child(title)

	var restart := Button.new()
	restart.name = "RestartFight"
	restart.text = "RESTART MATCH"
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


func _toggle_start_menu() -> void:
	start_menu_open = not start_menu_open
	start_menu.visible = start_menu_open
	_lock_players(start_menu_open or phase != Phase.FIGHT)
	get_tree().paused = start_menu_open
	start_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if start_menu_open:
		start_menu.get_node("RestartFight").grab_focus()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	start_menu_open = false
	start_menu.visible = false
	_reset_match()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


func _build_limb_hud() -> void:
	_build_limb_row(player1.body_color, 30.0, p1_bars)
	_build_limb_row(player2.body_color, 670.0, p2_bars)


func _build_limb_row(body_color: Color, x0: float, store: Dictionary) -> void:
	var y := 60.0
	var w := 110.0
	var h := 8.0
	var gap := 6.0
	for i in LIMB_LIST.size():
		var limb_name: String = LIMB_LIST[i]
		var bx := x0 + i * (w + gap)
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.1, 0.14, 1)
		bg.position = Vector2(bx, y)
		bg.size = Vector2(w, h)
		$HUD.add_child(bg)
		var fill := ColorRect.new()
		fill.color = _limb_color(body_color, limb_name)
		fill.position = Vector2(bx + 1, y + 1)
		fill.size = Vector2(w - 2, h - 2)
		$HUD.add_child(fill)
		store[limb_name] = fill
		var label := Label.new()
		label.text = {"head": "HEAD", "arm_l": "L ARM", "arm_r": "R ARM", "leg_l": "L LEG", "leg_r": "R LEG"}[limb_name]
		label.position = Vector2(bx, y + 10.0)
		label.size = Vector2(w, 20.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
		$HUD.add_child(label)


func _limb_color(base: Color, limb_name: String) -> Color:
	if limb_name == "head":
		return Color(1.0, 0.35, 0.25)
	if limb_name == "arm_r" or limb_name == "leg_r":
		return base.darkened(0.2)
	return base.lightened(0.05)


func _update_limb_bars(store: Dictionary, player: Player) -> void:
	for limb_name in LIMB_LIST:
		var fill: ColorRect = store[limb_name]
		var data: Dictionary = player.limb_hp[limb_name]
		fill.visible = not bool(data.gone)
		if fill.visible:
			fill.size.x = (110.0 - 2.0) * clampf(data.hp / float(Player.LIMB_MAX[limb_name]), 0.0, 1.0)


func _spawn_players() -> void:
	var p1_profile: Dictionary = GameState.p1_char()
	var p1 := PLAYER_TS.instantiate() as Player
	p1.player_number = 1
	p1.body_color = p1_profile.color
	p1.show_debug_rig = false
	p1.name = p1_profile.name
	p1.standing_pushbox_width = float(p1_profile.get("standing_pushbox_width", 34.0))
	p1.airborne_pushbox_width = float(p1_profile.get("airborne_pushbox_width", 30.0))
	p1.legless_pushbox_width = float(p1_profile.get("legless_pushbox_width", 30.0))
	p1.position = START_POSITIONS[0]
	add_child(p1)

	var p2_profile: Dictionary = GameState.p2_char()
	var p2 := PLAYER_TS.instantiate() as Player
	p2.player_number = 2
	p2.body_color = p2_profile.color
	p2.show_debug_rig = false
	p2.name = p2_profile.name
	p2.standing_pushbox_width = float(p2_profile.get("standing_pushbox_width", 34.0))
	p2.airborne_pushbox_width = float(p2_profile.get("airborne_pushbox_width", 30.0))
	p2.legless_pushbox_width = float(p2_profile.get("legless_pushbox_width", 30.0))
	p2.position = START_POSITIONS[1]
	add_child(p2)


func _lock_players(locked: bool) -> void:
	for player in get_tree().get_nodes_in_group("players"):
		player.input_locked = locked

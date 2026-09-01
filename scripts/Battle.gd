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


func _ready() -> void:
	_spawn_players()
	var players := get_tree().get_nodes_in_group("players")
	players.sort_custom(func(a, b): return a.player_number < b.player_number)
	player1 = players[0]
	player2 = players[1]
	player1.died.connect(_on_ko.bind(player2))
	player2.died.connect(_on_ko.bind(player1))
	_build_limb_hud()
	_start_round()


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


func _process(_delta: float) -> void:
	if phase == Phase.KO and Input.is_physical_key_pressed(KEY_R):
		_reset_round()


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

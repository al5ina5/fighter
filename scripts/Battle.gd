extends Node2D

@onready var p1_bar: ProgressBar = $HUD/P1Bar
@onready var p2_bar: ProgressBar = $HUD/P2Bar
@onready var ko_label: Label = $HUD/KOLabel

var player1: Player
var player2: Player


func _ready() -> void:
	var players := get_tree().get_nodes_in_group("players")
	players.sort_custom(func(a, b): return a.player_number < b.player_number)
	player1 = players[0]
	player2 = players[1]
	player1.died.connect(_on_ko.bind(player2))
	player2.died.connect(_on_ko.bind(player1))


func _physics_process(_delta: float) -> void:
	if player1 != null and player2 != null:
		p1_bar.value = maxf(player1.health, 0.0)
		p2_bar.value = maxf(player2.health, 0.0)


func _on_ko(winner: Player) -> void:
	ko_label.text = "%s WINS!" % winner.name
	ko_label.visible = true

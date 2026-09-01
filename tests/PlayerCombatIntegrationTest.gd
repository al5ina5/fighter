extends Node

const PLAYER_SCENE := preload("res://scenes/Player.tscn")

var failures := 0


func _ready() -> void:
	var arena := Node2D.new()
	add_child(arena)

	var player1: Player = PLAYER_SCENE.instantiate()
	player1.player_number = 1
	player1.position = Vector2(300, 400)
	arena.add_child(player1)

	var player2: Player = PLAYER_SCENE.instantiate()
	player2.player_number = 2
	player2.position = Vector2(900, 400)
	arena.add_child(player2)

	await get_tree().process_frame
	player1._update_facing()
	player2._update_facing()
	player1._snap_stance_visuals()
	player2._snap_stance_visuals()

	_expect_eq(player1.facing, 1, "left fighter faces right")
	_expect_eq(player2.facing, -1, "right fighter faces left")
	_expect_true(
		player1._get_limb_node("leg_r").global_position.x > player1._get_limb_node("leg_l").global_position.x,
		"left fighter's close leg is visibly nearer the opponent"
	)
	_expect_true(
		player2._get_limb_node("leg_r").global_position.x < player2._get_limb_node("leg_l").global_position.x,
		"right fighter's close leg is visibly nearer the opponent"
	)

	player2.stance = -1
	player2._snap_stance_visuals()
	_expect_true(
		player2._get_limb_node("leg_l").global_position.x < player2._get_limb_node("leg_r").global_position.x,
		"stance change visibly makes the other leg closest"
	)

	player1.limb_hp["arm_r"].gone = true
	_expect_eq(player1._attacking_limb("mid", false), "", "normal mid fails without its close arm")
	_expect_eq(player1._attacking_limb("mid", true), "arm_l", "heavy mid still uses the rear arm")

	var did_die := [false]
	player1.died.connect(func(): did_die[0] = true)
	player1.take_part_hit("head", "high", 1000.0, player2.global_position.x, 0.0, 0.0)
	_expect_true(player1.limb_hp["head"].gone, "head is destroyed at zero HP")
	_expect_eq(player1.state, Player.State.KO, "destroying the head enters KO")
	_expect_true(did_die[0], "destroying the head emits the fight-ending signal")

	if failures == 0:
		print("PlayerCombatIntegrationTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("PlayerCombatIntegrationTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

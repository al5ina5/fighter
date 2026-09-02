extends Node

const BATTLE_SCENE := preload("res://scenes/Battle.tscn")

var failures := 0
var battle: Node2D
var player1: Player
var player2: Player


func _ready() -> void:
	battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	player1 = battle.player1
	player2 = battle.player2
	await _wait_physics_frames(16)
	await _test_real_pushboxes()

	# Pushbox contact is the closest legal spacing. Every standing attack must
	# remain usable there; this is the regression for the old point-blank hole.
	await _run_move_test("high", false, 150.0, "head", "point-blank normal high lands")
	await _run_move_test("mid", false, 150.0, "arm_r", "point-blank normal mid lands")
	await _run_move_test("low", false, 150.0, "leg_r", "point-blank normal low lands")
	await _run_move_test("high", true, 150.0, "head", "point-blank heavy high lands")
	await _run_move_test("mid", true, 150.0, "arm_r", "point-blank heavy mid lands")
	await _run_move_test("low", true, 150.0, "leg_r", "point-blank heavy low lands")
	await _run_legless_target_test("mid", 188.0, "head", "mid strike reaches the lowered head after both legs are gone")
	await _run_legless_target_test("low", 286.0, "arm_r", "low strike cycles into the lowered close arm after both legs are gone")

	if failures == 0:
		print("BattleCombatFlowTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("BattleCombatFlowTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _run_move_test(band: String, heavy: bool, spacing: float, target: String, label: String) -> void:
	player1.reset(Vector2(450.0, 440.0))
	player2.reset(Vector2(450.0 + spacing, 440.0))
	player1.input_locked = false
	player2.input_locked = false
	player1._update_facing()
	player2._update_facing()
	player1._snap_stance_visuals()
	player2._snap_stance_visuals()
	await _wait_physics_frames(2)
	var hp_before := float(player2.limb_hp[target].hp)
	if heavy:
		Input.action_press("p1_heavy")
	Input.action_press("p1_" + band)
	await get_tree().physics_frame
	Input.action_release("p1_" + band)
	Input.action_release("p1_heavy")
	await _wait_physics_frames(90)
	_expect_true(float(player2.limb_hp[target].hp) < hp_before, label)


func _test_real_pushboxes() -> void:
	player1.reset(Vector2(450.0, 440.0))
	player2.reset(Vector2(610.0, 440.0))
	player1.input_locked = false
	player2.input_locked = false
	Input.action_press("p1_move_right")
	Input.action_press("p2_move_left")
	await _wait_physics_frames(30)
	Input.action_release("p1_move_right")
	Input.action_release("p2_move_left")
	var final_spacing := absf(player2.global_position.x - player1.global_position.x)
	_expect_true(final_spacing >= 118.0, "physics pushboxes stop fighters from overlapping (spacing %.1f)" % final_spacing)


func _run_legless_target_test(band: String, spacing: float, target: String, label: String) -> void:
	player1.reset(Vector2(450.0, 440.0))
	player2.reset(Vector2(450.0 + spacing, 440.0))
	for leg_name in ["leg_l", "leg_r"]:
		player2.limb_hp[leg_name].gone = true
		player2._get_limb_body(leg_name).visible = false
		player2._set_limb_hurtbox_enabled(leg_name, false)
	player1.input_locked = false
	player2.input_locked = false
	player1._update_facing()
	player2._update_facing()
	player1._snap_stance_visuals()
	player2._snap_stance_visuals()
	await _wait_physics_frames(2)
	var hp_before := float(player2.limb_hp[target].hp)
	Input.action_press("p1_" + band)
	await get_tree().physics_frame
	Input.action_release("p1_" + band)
	await _wait_physics_frames(90)
	_expect_true(float(player2.limb_hp[target].hp) < hp_before, label)


func _wait_physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

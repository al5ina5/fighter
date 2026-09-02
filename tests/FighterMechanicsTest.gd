extends Node

const BATTLE_SCENE := preload("res://scenes/Battle.tscn")

var failures := 0
var battle
var p1: Player
var p2: Player


func _ready() -> void:
	battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.countdown_generation += 1
	battle.phase = battle.Phase.FIGHT
	p1 = battle.player1
	p2 = battle.player2
	battle._lock_players(false)
	await _test_frame_data()
	await _test_guard_matrix()
	await _test_hit_confirm_cancel()
	await _test_simultaneous_trade()
	await _test_double_ko()
	Effects._resume_all()
	if failures == 0:
		print("FighterMechanicsTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("FighterMechanicsTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _test_frame_data() -> void:
	for band in ["high", "mid", "low"]:
		var normal: Dictionary = Player.ATTACKS[band][false]
		var heavy: Dictionary = Player.ATTACKS[band][true]
		_expect_true(int(normal.startup_frames) > 0, "%s normal has real startup" % band)
		_expect_true(int(normal.active_frames) >= 3, "%s normal has a readable active window" % band)
		_expect_true(int(heavy.recovery_frames) > int(normal.recovery_frames), "%s heavy is more punishable than normal" % band)
		_expect_true(int(normal.hitstun_frames) > int(normal.recovery_frames), "%s normal is positive on hit" % band)


func _test_guard_matrix() -> void:
	_reset_pair()
	Input.action_press("p2_move_right") # Away from P1: standing guard.
	_expect_true(p2._can_block_attack("overhead"), "standing guard blocks overheads")
	_expect_true(not p2._can_block_attack("low"), "standing guard loses to lows")
	Input.action_release("p2_move_right")
	Input.action_press("p2_block") # Dedicated down/block: crouch guard.
	_expect_true(p2._can_block_attack("low"), "crouch guard blocks lows")
	_expect_true(not p2._can_block_attack("overhead"), "crouch guard loses to overheads")
	Input.action_release("p2_block")


func _test_hit_confirm_cancel() -> void:
	_reset_pair()
	var first := p1._attack_data("high", false)
	first["name"] = p1._attacking_limb("high", false)
	p1._start_attack(first)
	p1.attack_connected = true
	p1.buffered_band = "mid"
	p1.buffered_heavy = false
	p1.input_buffer_frames = Player.INPUT_BUFFER_FRAMES
	p1.attack_frame = int(first.startup_frames) + int(first.active_frames)
	p1._tick_attack()
	_expect_eq(str(p1.attack.band), "mid", "confirmed light chains into the next normal")
	_expect_eq(p1.attack_frame, 1, "cancel starts the follow-up immediately")
	p1._finish_attack()


func _test_simultaneous_trade() -> void:
	_reset_pair()
	p1.state = Player.State.ATTACK
	p2.state = Player.State.ATTACK
	var to_p2 := _payload(p1, "mid", false, "torso")
	var to_p1 := _payload(p2, "mid", false, "torso")
	battle.queue_combat_hit(p1, p2, to_p2)
	battle.queue_combat_hit(p2, p1, to_p1)
	await get_tree().process_frame
	_expect_true(p1.health < 100.0 and p2.health < 100.0, "same-frame attacks trade instead of tree order deleting one hit")
	_expect_true(p1.state == Player.State.HITSTUN and p2.state == Player.State.HITSTUN, "both fighters enter hitstun after a trade")
	Effects._resume_all()


func _test_double_ko() -> void:
	_reset_pair()
	battle.phase = battle.Phase.FIGHT
	p1.state = Player.State.ATTACK
	p2.state = Player.State.ATTACK
	var to_p2 := _payload(p1, "high", true, "head")
	var to_p1 := _payload(p2, "high", true, "head")
	to_p2["damage"] = 1000.0
	to_p2["limb_damage"] = 1000.0
	to_p1["damage"] = 1000.0
	to_p1["limb_damage"] = 1000.0
	battle.queue_combat_hit(p1, p2, to_p2)
	battle.queue_combat_hit(p2, p1, to_p1)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_eq(p1.state, Player.State.KO, "first fighter can be KO'd in a same-frame trade")
	_expect_eq(p2.state, Player.State.KO, "second fighter can be KO'd in a same-frame trade")
	_expect_eq(battle.phase, battle.Phase.KO, "double KO ends the round without awarding a point")
	_expect_true(battle.ko_label.text.begins_with("DOUBLE KO"), "double KO gets an explicit round callout")


func _payload(attacker: Player, band: String, heavy: bool, target: String) -> Dictionary:
	var data := attacker._attack_data(band, heavy)
	data["name"] = attacker._attacking_limb(band, heavy)
	data["target"] = target
	data["source_x"] = attacker.global_position.x
	data["contact_position"] = p2._get_limb_hurtbox(target).global_position
	return data


func _reset_pair() -> void:
	Effects._resume_all()
	p1.reset(Vector2(450, 440))
	p2.reset(Vector2(600, 440))
	p1.input_locked = false
	p2.input_locked = false
	p1._update_facing()
	p2._update_facing()
	battle.pending_hits.clear()
	battle.phase = battle.Phase.FIGHT


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

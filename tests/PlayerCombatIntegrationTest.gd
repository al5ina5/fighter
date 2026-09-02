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
	player2.stance = 1
	player2._snap_stance_visuals()
	player2._start_stance_change()
	_expect_eq(player2.state, Player.State.STANCE, "stance change has a committed transition state")
	_expect_eq(player2.stance, 1, "logical stance does not teleport at transition start")
	player2._apply_stance_visuals(float(Player.STANCE_TRANSITION_FRAMES) / Player.COMBAT_FPS)
	_expect_eq(player2.current_target_stance(), -1, "target role follows the visibly forward limb during transition")
	player2._finish_stance_change()
	_expect_eq(player2.stance, -1, "stance commits after transition")
	player2.stance = 1
	player2.pending_stance = 1
	player2.state = Player.State.IDLE
	player2._snap_stance_visuals()

	_expect_true(
		player1.estimated_attack_reach("low", false) > player1.estimated_attack_reach("high", false) + 40.0,
		"normal leg kick has materially more range than the head punch"
	)
	_expect_true(
		int(Player.ATTACKS.high[true].startup_frames) > int(Player.ATTACKS.low[false].startup_frames),
		"heavy head kick has more startup than a normal leg kick"
	)
	_expect_true(
		int(Player.ATTACKS.high[true].recovery_frames) > int(Player.ATTACKS.low[false].recovery_frames),
		"heavy head kick has substantially more whiff recovery"
	)
	_expect_eq(player1._attacking_limb("high", true), "leg_l", "heavy high uses the rear leg")
	Input.action_press("p1_block")
	player1.state = Player.State.ATTACK
	_expect_true(not player1._is_blocking(), "fighter cannot block during an attack")
	player1.state = Player.State.HITSTUN
	_expect_true(not player1._is_blocking(), "fighter cannot block during hitstun")
	player1.state = Player.State.IDLE
	_expect_true(player1._is_blocking(), "idle fighter can block")
	Input.action_release("p1_block")

	player1.state = Player.State.HITSTUN
	Input.action_press("p1_mid")
	player1._capture_attack_input()
	Input.action_release("p1_mid")
	_expect_eq(player1.buffered_band, "mid", "attack input buffers during hitstun")
	player1.state = Player.State.IDLE
	player1._apply_idle()
	_expect_eq(player1.state, Player.State.ATTACK, "buffered attack executes on first idle frame")
	player1._finish_attack()

	var pause_data := player1._attack_data("mid", false)
	pause_data["name"] = player1._attacking_limb("mid", false)
	player1._start_attack(pause_data)
	var paused_limb := player1._get_limb_node(pause_data.name)
	await get_tree().process_frame
	Effects.hitstop(0.10)
	var rotation_before_pause := paused_limb.rotation
	for _i in 3:
		await get_tree().process_frame
	_expect_true(
		is_equal_approx(paused_limb.rotation, rotation_before_pause),
		"hitstop pauses the strike animation tween (%.4f -> %.4f)" % [rotation_before_pause, paused_limb.rotation]
	)
	await get_tree().create_timer(0.15).timeout
	_expect_true(player1.is_physics_processing(), "hitstop resumes fighter physics")
	player1._finish_attack()

	# Put the high strike over the torso without touching the head. The preferred
	# head target must not receive redirected damage from unrelated contact.
	player1.set_physics_process(false)
	player2.set_physics_process(false)
	var high_data := player1._attack_data("high", false)
	high_data["name"] = player1._attacking_limb("high", false)
	player1._start_attack(high_data)
	if player1.attack_tween and player1.attack_tween.is_valid():
		player1.attack_tween.kill()
		player1.attack_tween = null
	var strike_limb := player1._get_limb_node(high_data.name)
	strike_limb.rotation = -player1.attack_facing * float(high_data.swing)
	strike_limb.scale = Vector2(1.0, float(high_data.extension))
	player1._update_strike_hitbox()
	player1._set_hitbox(true)
	var torso_offset := player2._get_limb_hurtbox("torso").global_position - player2.global_position
	player2.global_position = player1.hitbox.global_position - torso_offset
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(player1.hitbox.overlaps_area(player2._get_limb_hurtbox("torso")), "high strike overlaps torso in collision test")
	_expect_true(not player1.hitbox.overlaps_area(player2._get_limb_hurtbox("head")), "high strike does not overlap head in collision test")
	var head_before := float(player2.limb_hp["head"].hp)
	player1._check_hits()
	_expect_eq(player2.limb_hp["head"].hp, head_before, "torso-only contact does not redirect damage to head")

	# On an even floor the raised fist endpoint must naturally line up with the
	# head; the test does not vertically move the victim to manufacture contact.
	player2.global_position = Vector2(player1.hitbox.global_position.x, player1.global_position.y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(player1.hitbox.overlaps_area(player2._get_limb_hurtbox("head")), "raised high strike reaches head on an even floor")
	player1.hit_landed = false
	player1._check_hits()
	_expect_true(float(player2.limb_hp["head"].hp) < head_before, "actual head contact damages head")
	player1._finish_attack()
	player2.state = Player.State.IDLE

	var head_kick := player1._attack_data("high", true)
	head_kick["name"] = player1._attacking_limb("high", true)
	player1._start_attack(head_kick)
	if player1.attack_tween and player1.attack_tween.is_valid():
		player1.attack_tween.kill()
		player1.attack_tween = null
	strike_limb = player1._get_limb_node(head_kick.name)
	strike_limb.rotation = -player1.attack_facing * float(head_kick.swing)
	strike_limb.scale = Vector2(1.0, float(head_kick.extension))
	player1._update_strike_hitbox()
	player1._set_hitbox(true)
	player2.global_position = Vector2(player1.hitbox.global_position.x, player1.global_position.y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect_true(player1.hitbox.overlaps_area(player2._get_limb_hurtbox("head")), "rear-leg head kick reaches head on an even floor")
	var kick_head_before := float(player2.limb_hp["head"].hp)
	var kick_torso_before := float(player2.limb_hp["torso"].hp)
	player1.hit_landed = false
	player1._check_hits()
	_expect_true(float(player2.limb_hp["head"].hp) < kick_head_before, "head kick prioritizes its contacted head hurtbox")
	_expect_eq(player2.limb_hp["torso"].hp, kick_torso_before, "one strike never damages two overlapping hurtboxes")
	player1._finish_attack()

	player1.limb_hp["arm_r"].gone = true
	_expect_eq(player1._attacking_limb("mid", false), "head", "lost lead arm receives a desperation head strike")
	_expect_eq(player1._attacking_limb("mid", true), "arm_l", "heavy mid still uses the rear arm")

	var did_die := [false]
	player1.died.connect(func(): did_die[0] = true)
	player1.take_part_hit("head", "high", 1000.0, player2.global_position.x, 0.0, 0.0)
	_expect_true(player1.limb_hp["head"].gone, "head is destroyed at zero HP")
	_expect_true(
		(player1._get_limb_hurtbox("head").get_node("Shape") as CollisionShape2D).disabled,
		"destroyed head hurtbox is disabled"
	)
	_expect_eq(player1.state, Player.State.KO, "destroying the head enters KO")
	_expect_true(did_die[0], "destroying the head emits the fight-ending signal")
	player1.reset(Vector2(300, 400))
	_expect_true(
		not (player1._get_limb_hurtbox("head").get_node("Shape") as CollisionShape2D).disabled,
		"round reset restores detached hurtboxes"
	)

	player2.limb_hp["leg_l"].gone = true
	player2.limb_hp["leg_r"].gone = true
	player2._update_body_collision()
	var legless_shape := player2.body_shape.shape as RectangleShape2D
	_expect_eq(legless_shape.size, Vector2(44.0, 38.0), "legless fighter uses a low body collision shape")
	_expect_eq(player2.body_shape.position, Vector2(0.0, 21.0), "legless collision follows the lowered rig")

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

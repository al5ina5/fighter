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
	var torso_rect_before := player2._limb_hurt_rect("torso")
	player2.rig.position = Vector2(300, -200)
	_expect_eq(player2._limb_hurt_rect("torso"), torso_rect_before, "combat hurtboxes do not follow the hidden fallback rig")
	player2.rig.position = Vector2.ZERO
	player2._start_stance_change()
	_expect_eq(player2.state, Player.State.STANCE, "stance change has a committed transition state")
	_expect_eq(player2.stance, 1, "logical stance does not teleport at transition start")
	player2._apply_stance_visuals(float(Player.STANCE_TRANSITION_FRAMES) / Player.COMBAT_FPS)
	_expect_eq(player2.current_target_stance(), 1, "combat stance remains stable until the transition commits")
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
	var high_heavy_move := player1._attack_data("high", true).move_resource as FighterMoveData
	_expect_eq(high_heavy_move.active_frames, 5, "heavy head kick preserves its authored active window")
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
	_expect_true(pause_data.move_resource is FighterMoveData, "attacks load typed move resources")
	pause_data["name"] = player1._attacking_limb("mid", false)
	player1._start_attack(pause_data)
	await get_tree().physics_frame
	Effects.hitstop(0.10)
	var frame_before_pause := player1.attack_frame
	for _i in 3:
		await get_tree().physics_frame
	_expect_true(
		player1.attack_frame == frame_before_pause,
		"hitstop pauses the authoritative combat frame (%d -> %d)" % [frame_before_pause, player1.attack_frame]
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
	player1.attack_frame = int(high_data.startup_frames)
	var high_rect := player1._active_hit_rects()[0]
	var torso_offset := player2._limb_hurt_rect("torso").get_center() - player2.global_position
	player2.global_position = high_rect.get_center() - torso_offset
	_expect_true(high_rect.intersects(player2._limb_hurt_rect("torso"), true), "authored high box overlaps torso in collision test")
	_expect_true(not high_rect.intersects(player2._limb_hurt_rect("head"), true), "authored high box does not overlap head in collision test")
	var head_before := float(player2.limb_hp["head"].hp)
	player1._check_hits()
	_expect_eq(player2.limb_hp["head"].hp, head_before, "torso-only contact does not redirect damage to head")

	# On an even floor the raised fist endpoint must naturally line up with the
	# head; the test does not vertically move the victim to manufacture contact.
	player2.global_position = Vector2(high_rect.get_center().x, player1.global_position.y)
	_expect_true(high_rect.intersects(player2._limb_hurt_rect("head"), true), "authored high box reaches head on an even floor")
	player1.hit_landed = false
	player1._check_hits()
	_expect_true(float(player2.limb_hp["head"].hp) < head_before, "actual head contact damages head")
	player1._finish_attack()
	player2.state = Player.State.IDLE

	var head_kick := player1._attack_data("high", true)
	head_kick["name"] = player1._attacking_limb("high", true)
	player1._start_attack(head_kick)
	player1.attack_frame = int(head_kick.startup_frames)
	var kick_rect := player1._active_hit_rects()[0]
	player2.global_position = Vector2(kick_rect.get_center().x, player1.global_position.y)
	_expect_true(kick_rect.intersects(player2._limb_hurt_rect("head"), true), "rear-leg head kick reaches head on an even floor")
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
		not player1.has_node("Rig/head/Hurtbox"),
		"combat no longer depends on legacy Area2D hurtbox nodes"
	)
	_expect_eq(player1.state, Player.State.KO, "destroying the head enters KO")
	_expect_true(did_die[0], "destroying the head emits the fight-ending signal")
	player1.reset(Vector2(300, 400))
	_expect_true(
		not player1.limb_hp["head"].gone,
		"round reset restores detached combat regions"
	)

	player2.limb_hp["leg_l"].gone = true
	player2.limb_hp["leg_r"].gone = true
	player2._update_body_collision()
	var legless_shape := player2.body_shape.shape as RectangleShape2D
	_expect_eq(legless_shape.size, Vector2(30.0, 38.0), "legless fighter uses a low pelvis collision shape")
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

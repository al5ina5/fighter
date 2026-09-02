extends Node

const BATTLE_SCENE := preload("res://scenes/Battle.tscn")
const CHARACTER_SELECT_SCENE := preload("res://scenes/CharacterSelect.tscn")

var failures := 0


func _ready() -> void:
	_expect_eq(GameState.CHARACTERS.size(), 2, "roster contains both interchangeable fighters")
	GameState.p1_index = 0
	GameState.p2_index = 1
	var character_select = CHARACTER_SELECT_SCENE.instantiate()
	add_child(character_select)
	await get_tree().process_frame
	_expect_eq(character_select.cards.size(), 2, "character select builds both cards")
	_expect_near(
		character_select.cards[0].position.x,
		(1280.0 - (character_select.CARD_SIZE.x * 2.0 + character_select.CARD_GAP)) / 2.0,
		0.001,
		"the two-character row remains centered",
	)
	character_select.queue_free()
	await get_tree().process_frame
	var battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame

	var player: Player = battle.player1
	var visual: FighterVisual3D = battle.player1_visual
	_expect_eq(player.name, "Girlypoppums", "roster spawns Girlypoppums")
	_expect_true(not visual.using_fallback, "Girlypoppums loads the prepared GLB")
	_expect_true(visual.animation_player != null, "prepared GLB exposes an AnimationPlayer")
	if visual.animation_player != null:
		for semantic in [
			"idle", "walk", "jump", "block", "hit", "knockout",
			"high_normal", "high_heavy", "mid_normal", "mid_heavy",
			"low_normal", "low_heavy",
		]:
			_expect_true(visual.animation_sets.has(semantic), "%s is loaded from the interchangeable folder" % semantic)
			_expect_true(
				String(visual._find_clip_for_semantic(semantic)).begins_with(semantic + "_"),
				"%s resolves to its external animation set" % semantic,
			)
		for looping_clip in ["idle", "walk", "block"]:
			var resolved := visual._find_clip_for_semantic(looping_clip)
			if resolved == StringName():
				continue
			var animation := visual.animation_player.get_animation(resolved)
			_expect_eq(animation.loop_mode, Animation.LOOP_LINEAR, "%s loops continuously" % looping_clip)

	var expected_counts := {"head": 1, "torso": 1, "arm_l": 1, "arm_r": 1, "leg_l": 1, "leg_r": 1}
	var textured_surfaces := 0
	for slot in expected_counts:
		_expect_eq(visual.model_parts.get(slot, []).size(), expected_counts[slot], "%s geometry is indexed for detachment" % slot)
		for mesh_node in visual.model_parts.get(slot, []):
			var mesh_instance := mesh_node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null and material.albedo_texture != null:
					textured_surfaces += 1
	_expect_eq(textured_surfaces, 6, "every detachable surface retains the base-color texture")

	player.set_physics_process(false)
	var attack_data: Dictionary = player._attack_data("mid", false)
	attack_data["name"] = player._attacking_limb("mid", false)
	player._start_attack(attack_data)
	visual._sync_presentation(true)
	var mid_clip := visual._find_clip_for_semantic("mid_normal")
	var mid_animation := visual.animation_player.get_animation(mid_clip)
	var contact_ratio := float(visual.profile.animation_contact_ratios.mid_normal)
	_expect_near(
		visual.animation_player.speed_scale,
		mid_animation.length * contact_ratio / float(attack_data.windup),
		0.001,
		"attack anticipation reaches the visual contact frame at active startup",
	)
	player.attack_phase = "active"
	visual._sync_presentation(false)
	_expect_near(
		visual.animation_player.speed_scale,
		mid_animation.length * (1.0 - contact_ratio) / (float(attack_data.active) + float(attack_data.recovery)),
		0.001,
		"post-contact animation fills active and recovery time",
	)
	player._finish_attack()
	visual._sync_presentation(true)

	player.limb_hp["arm_l"].gone = true
	visual._sync_presentation(false)
	for mesh in visual.model_parts["arm_l"]:
		_expect_true(not (mesh as Node3D).visible, "lost left arm hides every associated mesh")
	for mesh in visual.model_parts["arm_r"]:
		_expect_true((mesh as Node3D).visible, "opposite arm remains visible")

	GameState.reset()
	if failures == 0:
		print("GirlypoppumsIntegrationTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("GirlypoppumsIntegrationTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s: expected %.4f, got %.4f" % [label, expected, actual])

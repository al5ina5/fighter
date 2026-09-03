extends Node

const BATTLE_SCENE := preload("res://scenes/Battle.tscn")

var failures := 0


func _ready() -> void:
	var battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame

	var player: Player = battle.player1
	var visual: FighterVisual3D = battle.player1_visual
	_expect_true(visual != null, "battle creates a 3D presentation for player one")
	_expect_true(battle.player2_visual != null, "battle creates a 3D presentation for player two")
	_expect_true(not player.rig.visible, "battle hides the legacy placeholder rig")
	_expect_true(not visual.using_fallback, "Girlypoppums uses its prepared GLB")
	_expect_eq(battle.arena_3d.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "arena keeps side-view spacing orthographic")
	_expect_true(battle.arena_3d.get_viewport() == battle.get_viewport(), "3D arena renders directly at the main viewport resolution")

	player.set_physics_process(false)
	player.global_position = Vector2(450.0, 440.0)
	player.facing = 1
	visual._sync_presentation(true)
	var viewport_size: Vector2 = battle.get_viewport().get_visible_rect().size
	var pixels_per_meter: float = viewport_size.y / battle.arena_3d.camera.size
	var expected_x: float = (450.0 - viewport_size.x * 0.5) / pixels_per_meter
	_expect_near(visual.position.x, expected_x, 0.001, "screen X maps to arena meters at the active viewport aspect")
	_expect_near(visual.position.y, 0.0, 0.001, "standing fighter roots sit on the 3D floor")
	_expect_near(visual.position.z, 0.0, 0.001, "fighter shares the physical 3D depth plane")
	_expect_near(battle.player2_visual.position.z, 0.0, 0.001, "opponent is not forced behind by player number")
	_expect_true(visual.model_root.global_basis.z.normalized().x > 0.9, "player one faces right along the fight axis")
	_expect_near(visual.pose_pivot.rotation.y, visual.STANCE_YAW_RADIANS, 0.001, "right lead turns the chest toward its authored depth")
	var hips_index: int = visual.model_skeleton.find_bone("mixamorig_Hips")
	var hips_local: Vector3 = visual.model_skeleton.get_bone_global_pose(hips_index).origin
	var hips_screen: Vector2 = battle.arena_3d.camera.unproject_position(visual.model_skeleton.to_global(hips_local))
	_expect_near(hips_screen.x, player.global_position.x, 4.0, "rendered hips stay centered over the combat root")
	player.state = Player.State.STANCE
	player.pending_stance = -1
	player.stance_frames_left = Player.STANCE_TRANSITION_FRAMES / 2
	visual._sync_presentation(false)
	_expect_near(visual.pose_pivot.rotation.y, 0.0, 0.001, "stance transition rotates smoothly through a squared chest")
	player.state = Player.State.IDLE
	player.stance = -1
	visual._sync_presentation(false)
	_expect_near(visual.pose_pivot.rotation.y, -visual.STANCE_YAW_RADIANS, 0.001, "left lead turns the chest to the opposite depth")
	_expect_true(String(visual.animation_player.current_animation).ends_with(FighterAnimationSet.MIRRORED_SUFFIX), "left lead switches the complete idle skeleton to its mirror")
	player.stance = 1
	player.pending_stance = 1
	visual._sync_presentation(false)

	player.facing = -1
	visual._sync_presentation(false)
	_expect_near(absf(visual.facing_pivot.rotation.y), PI, 0.001, "3D model turns toward an opponent on the left")
	_expect_true(visual.model_root.global_basis.z.normalized().x < -0.9, "turned fighter faces left along the fight axis")

	player.limb_hp["arm_l"].gone = true
	visual._sync_presentation(false)
	for mesh in visual.model_parts["arm_l"]:
		_expect_true(not (mesh as Node3D).visible, "detached simulation limbs hide their 3D mesh")
	player.limb_hp["arm_l"].gone = false
	visual._sync_presentation(false)
	for mesh in visual.model_parts["arm_l"]:
		_expect_true((mesh as Node3D).visible, "restored limbs reappear after a reset")

	player.limb_hp["leg_l"].gone = true
	player.limb_hp["leg_r"].gone = true
	visual.animation_player.advance(0.0)
	visual._sync_presentation(false)
	var lowered_hips_local: Vector3 = visual.model_skeleton.get_bone_global_pose(hips_index).origin
	var lowered_hips_y: float = visual.model_skeleton.to_global(lowered_hips_local).y
	_expect_near(lowered_hips_y, visual.LEGLESS_HIP_CLEARANCE, 0.025, "losing both legs places the animated hips at floor height")
	_expect_true(visual.pose_pivot.position.y < -0.5, "legless posture lowers the actual 3D model root")
	player.limb_hp["leg_l"].gone = false
	player.limb_hp["leg_r"].gone = false
	visual._sync_presentation(false)
	_expect_near(visual.pose_pivot.position.y, 0.0, 0.001, "restoring legs restores standing model height")

	if failures == 0:
		print("Presentation3DTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("Presentation3DTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if not is_equal_approx(actual, expected) and absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s: expected %.4f, got %.4f" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

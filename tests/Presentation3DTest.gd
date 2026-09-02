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
	_expect_near(visual.position.x, -1.9, 0.001, "screen X maps to arena meters")
	_expect_near(visual.position.y, 0.0, 0.001, "standing fighter roots sit on the 3D floor")
	_expect_near(visual.position.z, 0.12, 0.001, "fighter stays in its presentation depth lane")
	_expect_true(visual.model_root.global_basis.z.normalized().x > 0.9, "player one faces right along the fight axis")

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

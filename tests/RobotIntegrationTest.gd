extends Node

const BATTLE_SCENE := preload("res://scenes/Battle.tscn")
const REQUIRED_SEMANTICS := [
	"idle", "walk", "jump", "block", "hit", "knockout",
	"high_normal", "high_heavy", "mid_normal", "mid_heavy",
	"low_normal", "low_heavy",
]
const LIMBS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

var failures := 0


func _ready() -> void:
	GameState.p1_index = 1
	GameState.p2_index = 0
	var battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame

	var player: Player = battle.player1
	var visual: FighterVisual3D = battle.player1_visual
	_expect_eq(player.name, "Green Blocky Robot", "roster spawns the robot")
	_expect_true(not visual.using_fallback, "robot loads its prepared GLB")
	_expect_true(visual.model_skeleton != null, "robot exposes a live skeleton")
	_expect_true(visual.animation_player != null, "robot exposes an animation player")
	_expect_eq(player.standing_pushbox_width, 88.0, "robot receives its broad torso pushbox profile")
	if visual.model_skeleton != null:
		_expect_eq(visual.model_skeleton.get_bone_count(), 33, "robot uses the canonical Mixamo skeleton")
	if visual.animation_player != null:
		for semantic in REQUIRED_SEMANTICS:
			_expect_true(visual.animation_sets.has(semantic), "%s has a robot animation set" % semantic)
			_expect_true(visual.animation_sets.get(semantic) is Array, "%s robot set is an array" % semantic)
			var clip := visual._find_clip_for_semantic(semantic)
			_expect_true(clip != StringName(), "%s resolves on the robot" % semantic)
			_expect_true(visual.animation_player.has_animation(clip), "%s is registered on the robot player" % semantic)

	var textured_surfaces := 0
	for slot in LIMBS:
		_expect_eq(visual.model_parts.get(slot, []).size(), 1, "%s has one detachable skinned surface" % slot)
		for mesh_node in visual.model_parts.get(slot, []):
			var mesh_instance := mesh_node as MeshInstance3D
			_expect_true(mesh_instance.skeleton != NodePath(), "%s remains attached to the skeleton" % slot)
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null and material.albedo_texture != null:
					textured_surfaces += 1
	_expect_eq(textured_surfaces, 6, "every robot limb retains the base-color texture")

	if visual.animation_player != null and visual.model_skeleton != null:
		var attack_clip := visual._find_clip_for_semantic("high_normal")
		var attack_animation := visual.animation_player.get_animation(attack_clip)
		visual.animation_player.play(attack_clip)
		visual.animation_player.seek(0.0, true)
		var start_rotations: Array[Quaternion] = []
		for bone in visual.model_skeleton.get_bone_count():
			start_rotations.append(visual.model_skeleton.get_bone_pose_rotation(bone))
		visual.animation_player.seek(attack_animation.length * 0.5, true)
		var changed_bones := 0
		for bone in visual.model_skeleton.get_bone_count():
			if start_rotations[bone].angle_to(visual.model_skeleton.get_bone_pose_rotation(bone)) > 0.01:
				changed_bones += 1
		_expect_true(changed_bones >= 3, "loose attack FBX visibly drives the robot rig")

	GameState.reset()
	if failures == 0:
		print("RobotIntegrationTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("RobotIntegrationTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

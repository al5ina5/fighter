extends Node

const BATTLE_SCENE := preload("res://scenes/Battle.tscn")
const REQUIRED_SEMANTICS := [
	"idle", "walk", "jump", "block", "hit", "knockout",
	"high_normal", "high_heavy", "mid_normal", "mid_heavy",
	"low_normal", "low_heavy",
]

var failures := 0


func _ready() -> void:
	var battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame

	var visual: FighterVisual3D = battle.player1_visual
	_expect_true(visual.model_skeleton != null, "character exposes its live skeleton")
	_expect_true(visual.animation_player != null, "character exposes its animation player")
	if visual.animation_player == null:
		_finish()
		return
	_expect_eq(visual.model_skeleton.get_bone_count(), 33, "character uses the canonical 33-bone rig")
	for semantic in REQUIRED_SEMANTICS:
		_expect_true(visual.animation_sets.has(semantic), "%s has a loose animation set" % semantic)
		_expect_true(visual.animation_sets.get(semantic) is Array, "%s animation set is an array" % semantic)
		_expect_true(not visual.animation_sets.get(semantic, []).is_empty(), "%s animation set contains a clip" % semantic)

	# The loose Fighting Idle.fbx in the animations folder must be loaded as the
	# semantic idle (clip id is normalized to idle_0).
	var idle_clip := visual._find_clip_for_semantic("idle")
	_expect_true(idle_clip != StringName(), "loose fighting idle maps to semantic idle")
	_expect_true(String(idle_clip).begins_with("idle_"), "loose clip is registered with the idle_ prefix")

	var animation := visual.animation_player.get_animation(idle_clip)
	_expect_true(animation != null, "loose idle clip is available on the player")
	if animation != null:
		_expect_near(animation.length, 3.3, 0.02, "the supplied Fighting Idle is the active idle file")
		_expect_true(
			_bone_position_key_count(animation, "mixamorig_Hips") >= 100,
			"Mixamo hips translation keys survive Godot import",
		)
		_expect_true(
			_bone_position_span(animation, "mixamorig_Hips") > 0.03,
			"Fighting Idle preserves its authored forward/back body movement",
		)
		var skeleton_path := visual.animation_player.get_path_to(visual.model_skeleton)
		var bone_tracks := 0
		var valid_bone_tracks := 0
		for track in range(animation.get_track_count()):
			var path := animation.track_get_path(track)
			if path.get_subname_count() == 0:
				continue
			bone_tracks += 1
			var node_part := path.get_name(path.get_name_count() - 1)
			if str(node_part) == str(skeleton_path.get_name(skeleton_path.get_name_count() - 1)):
				valid_bone_tracks += 1
		_expect_true(bone_tracks >= 29, "loose clip contains at least 29 bone tracks")
		_expect_true(valid_bone_tracks == bone_tracks, "all bone tracks retarget to the live skeleton")
		_expect_eq(animation.loop_mode, Animation.LOOP_LINEAR, "loose idle loops continuously")
		var hips_index := visual.model_skeleton.find_bone("mixamorig_Hips")
		var hips_rest_y := visual.model_skeleton.get_bone_rest(hips_index).origin.y
		var hips_position_y := _bone_position_y(animation, "mixamorig_Hips")
		_expect_near(
			hips_position_y,
			hips_rest_y,
			0.15,
			"loose FBX bone positions are converted into the live skeleton's units"
		)
	var walk_clip := visual._find_clip_for_semantic("walk")
	var walk_animation := visual.animation_player.get_animation(walk_clip)
	if walk_animation != null:
		var walk_start := _bone_position(walk_animation, "mixamorig_Hips", 0)
		var walk_end := _bone_position(walk_animation, "mixamorig_Hips", -1)
		_expect_true(
			walk_start.distance_to(walk_end) < 0.001,
			"walk root drift is removed while gameplay owns movement",
		)

	# The runtime stores every semantic as an array and advances deterministically
	# through multiple variants. Exercise the behavior without changing the
	# package manifest, which intentionally selects only Fighting Idle for now.
	var original_idle_set = visual.animation_sets["idle"]
	visual.animation_sets["idle"] = [idle_clip, walk_clip]
	visual.animation_set_cursors["idle"] = 0
	_expect_eq(visual._choose_clip_for_semantic("idle"), idle_clip, "animation set starts with its first variant")
	_expect_eq(visual._choose_clip_for_semantic("idle"), walk_clip, "animation set advances to its next variant")
	_expect_eq(visual._choose_clip_for_semantic("idle"), idle_clip, "animation set cycles deterministically")
	visual.animation_sets["idle"] = original_idle_set
	visual.animation_set_cursors.erase("idle")

	visual.source.set_physics_process(false)
	visual.source.global_position = Vector2(450.0, 440.0)
	visual._sync_presentation(false)
	visual._play_semantic("idle")
	visual.animation_player.advance(0.5)
	_expect_eq(visual.animation_player.current_animation, idle_clip, "loose idle clip plays as the semantic idle")
	_expect_true(visual.animation_player.is_playing(), "loose idle clip keeps playing")
	_expect_near(visual.animation_player.speed_scale, 1.0, 0.001, "idle plays at stock Mixamo speed")
	var lowest_toe_y := minf(
		_bone_world_y(visual, "mixamorig_LeftToeBase"),
		_bone_world_y(visual, "mixamorig_RightToeBase")
	)
	_expect_true(lowest_toe_y > -0.2, "retargeted idle feet stay above the arena floor")
	_expect_true(lowest_toe_y < 0.5, "retargeted idle feet stay close to the arena floor")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("AnimationSwapTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("AnimationSwapTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _bone_position_y(animation: Animation, bone_name: String) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() > 0 and str(path.get_subname(0)) == bone_name:
			return (animation.track_get_key_value(track, 0) as Vector3).y
	return -INF


func _bone_position(animation: Animation, bone_name: String, key_index: int) -> Vector3:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0 or str(path.get_subname(0)) != bone_name:
			continue
		var count := animation.track_get_key_count(track)
		var resolved_index := key_index if key_index >= 0 else count + key_index
		return animation.track_get_key_value(track, resolved_index) as Vector3
	return Vector3(INF, INF, INF)


func _bone_position_key_count(animation: Animation, bone_name: String) -> int:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() > 0 and str(path.get_subname(0)) == bone_name:
			return animation.track_get_key_count(track)
	return 0


func _bone_position_span(animation: Animation, bone_name: String) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0 or str(path.get_subname(0)) != bone_name:
			continue
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for key in animation.track_get_key_count(track):
			var value: Vector3 = animation.track_get_key_value(track, key)
			low = low.min(value)
			high = high.max(value)
		return low.distance_to(high)
	return 0.0


func _bone_world_y(visual: FighterVisual3D, bone_name: String) -> float:
	var bone_index := visual.model_skeleton.find_bone(bone_name)
	var local_position := visual.model_skeleton.get_bone_global_pose(bone_index).origin
	return visual.model_skeleton.to_global(local_position).y


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s: expected %.4f, got %.4f" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

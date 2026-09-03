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
		var mirrored_key: String = str(semantic) + FighterAnimationSet.MIRRORED_SUFFIX
		_expect_true(visual.animation_sets.has(mirrored_key), "%s has a mirrored stance set" % semantic)
		_expect_true(not visual.animation_sets.get(mirrored_key, []).is_empty(), "%s mirrored set contains a clip" % semantic)

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
		var idle_hips_start := _bone_position(animation, "mixamorig_Hips", 0)
		var idle_hips_end := _bone_position(animation, "mixamorig_Hips", -1)
		var idle_hips_rest := visual.model_skeleton.get_bone_rest(visual.model_skeleton.find_bone("mixamorig_Hips")).origin
		_expect_true(
			Vector2(idle_hips_start.x, idle_hips_start.z).distance_to(Vector2(idle_hips_rest.x, idle_hips_rest.z)) < 0.001,
			"Fighting Idle begins centered on the combat root",
		)
		_expect_true(
			Vector2(idle_hips_end.x, idle_hips_end.z).distance_to(Vector2(idle_hips_rest.x, idle_hips_rest.z)) < 0.001,
			"Fighting Idle cannot accumulate drift away from the combat root",
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
			Vector2(walk_start.x, walk_start.z).distance_to(Vector2(walk_end.x, walk_end.z)) < 0.001,
			"walk root drift is removed while gameplay owns movement",
		)

	var mid_clip := visual._find_clip_for_semantic("mid_normal")
	var mirrored_mid_clip: StringName = visual.animation_sets["mid_normal" + FighterAnimationSet.MIRRORED_SUFFIX][0]
	var mid_animation := visual.animation_player.get_animation(mid_clip)
	var mirror_time := mid_animation.length * float(visual.profile.animation_contact_ratios.mid_normal)
	visual.animation_player.play(mid_clip)
	visual.animation_player.seek(mirror_time, true)
	visual.animation_player.advance(0.0)
	var base_right_hand := _bone_skeleton_position(visual, "mixamorig_RightHand")
	visual.animation_player.play(mirrored_mid_clip)
	visual.animation_player.seek(mirror_time, true)
	visual.animation_player.advance(0.0)
	var mirrored_left_hand := _bone_skeleton_position(visual, "mixamorig_LeftHand")
	var hips_plane_x := visual.model_skeleton.get_bone_global_rest(visual.model_skeleton.find_bone("mixamorig_Hips")).origin.x
	_expect_near(mirrored_left_hand.x, hips_plane_x * 2.0 - base_right_hand.x, 0.002, "mirrored attack reflects the striking hand across the body")
	_expect_near(mirrored_left_hand.y, base_right_hand.y, 0.002, "mirrored attack preserves striking-hand height")
	_expect_near(mirrored_left_hand.z, base_right_hand.z, 0.002, "mirrored attack preserves striking-hand reach")
	visual.source.stance = 1
	visual._play_semantic("mid_normal")
	_expect_eq(visual.animation_player.current_animation, mid_clip, "right lead selects the authored attack")
	visual.source.stance = -1
	visual._play_semantic("mid_normal")
	_expect_eq(visual.animation_player.current_animation, mirrored_mid_clip, "left lead selects the mirrored attack")
	visual.source.stance = 1

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

	visual.source.facing = 1
	visual.source.state = Player.State.IDLE
	visual.source.velocity.x = 120.0
	visual._play_semantic("walk")
	_expect_true(visual.animation_player.speed_scale > 0.0, "forward movement plays the walk cycle forward")
	visual.source.velocity.x = -120.0
	visual._play_semantic("walk_backward")
	_expect_true(visual.animation_player.speed_scale < 0.0, "retreat movement plays a direction-correct backward cycle")
	_expect_true(visual._playback_state_key("walk_backward").begins_with("walk_backward"), "locomotion direction is part of animation state")

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


func _bone_skeleton_position(visual: FighterVisual3D, bone_name: String) -> Vector3:
	var bone_index := visual.model_skeleton.find_bone(bone_name)
	return visual.model_skeleton.get_bone_global_pose(bone_index).origin


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s: expected %.4f, got %.4f" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

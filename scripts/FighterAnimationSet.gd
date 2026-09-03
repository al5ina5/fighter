class_name FighterAnimationSet
extends RefCounted
## Loads loose Mixamo animation FBXs from a character's `animations/` folder and
## retargets them onto the character's live skeleton at runtime.

const MIRRORED_SUFFIX := "_mirrored"
const MIRROR_SAMPLE_FPS := 60.0

const FALLBACK_SEMANTICS := {
	"idle": ["idle", "fight_idle", "fighting_idle", "combat_idle"],
	"walk": ["walk", "walk_forward", "walking", "run"],
	"walk_backward": ["walk_backward", "back_walk", "walking_backward", "retreat"],
	"jump": ["jump", "jump_start", "airborne"],
	"block": ["block", "guard", "blocking"],
	"hit": ["hit", "hit_react", "hurt", "damage"],
	"knockout": ["knockout", "ko", "death", "defeat"],
	"high_normal": ["high_normal", "jab", "punch_jab", "head_punch", "punching"],
	"high_heavy": ["high_heavy", "high_kick", "kick_high", "roundhouse"],
	"mid_normal": ["mid_normal", "mid_normal_attack", "jab", "punch_jab"],
	"mid_heavy": ["mid_heavy", "mid_heavy_attack", "heavy_punch", "punch_heavy"],
	"low_normal": ["low_normal", "low_normal_attack", "low_kick", "kick_low"],
	"low_heavy": ["low_heavy", "low_heavy_attack", "heavy_kick", "heavy_low_kick"],
}


## Scans `anim_dir` for *.fbx files, maps each to a gameplay semantic, and
## registers the retargeted clip on `player` driving `skeleton`.
static func load_animations(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	anim_dir: String,
	configured_sets: Dictionary = {}
) -> Dictionary:
	if player == null or skeleton == null or anim_dir == "":
		return {}
	if not DirAccess.dir_exists_absolute(anim_dir) and not ResourceLoader.exists(anim_dir):
		return {}

	var result: Dictionary = {}
	var by_name := _scan_files(anim_dir)
	var manifest := _read_manifest(anim_dir)
	var node_prefix := _skeleton_track_prefix(player, skeleton)
	if node_prefix == "":
		return {}
	var library: AnimationLibrary
	if player.has_animation_library(""):
		library = player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		player.add_animation_library("", library)

	var semantic_files: Dictionary = {}
	for semantic in configured_sets:
		var wanted = configured_sets[semantic]
		if wanted is Array:
			semantic_files[semantic] = []
			for name in wanted:
				var key := _file_key(str(name))
				if by_name.has(key):
					semantic_files[semantic].append(key)
		else:
			var key := _file_key(str(wanted))
			if by_name.has(key):
				semantic_files[semantic] = [key]

	for semantic in manifest:
		var names: Array = manifest[semantic]
		var resolved: Array = []
		for name in names:
			var key := _file_key(str(name))
			if by_name.has(key):
				resolved.append(key)
		if resolved.size() > 0:
			semantic_files[semantic] = resolved

	for semantic in FALLBACK_SEMANTICS:
		if semantic_files.has(semantic):
			continue
		var matches: Array = []
		for alias in FALLBACK_SEMANTICS[semantic]:
			var key := _normalize(alias)
			if by_name.has(key):
				matches.append(key)
		if matches.size() > 0:
			semantic_files[semantic] = matches

	for semantic in semantic_files:
		var clip_names: Array[StringName] = []
		var mirrored_clip_names: Array[StringName] = []
		for filename in semantic_files[semantic]:
			var clip_name := "%s_%d" % [semantic, clip_names.size()]
			var animation := _build_animation(
				by_name[filename],
				node_prefix,
				skeleton,
				str(semantic),
			)
			if animation == null:
				continue
			if library.has_animation(clip_name):
				library.remove_animation(clip_name)
			library.add_animation(clip_name, animation)
			clip_names.append(clip_name)
			var mirrored := _build_mirrored_animation(animation, skeleton, node_prefix)
			if mirrored != null:
				var mirrored_name := clip_name + MIRRORED_SUFFIX
				if library.has_animation(mirrored_name):
					library.remove_animation(mirrored_name)
				library.add_animation(mirrored_name, mirrored)
				mirrored_clip_names.append(mirrored_name)
		if clip_names.size() > 0:
			result[semantic] = clip_names
		if mirrored_clip_names.size() > 0:
			result[str(semantic) + MIRRORED_SUFFIX] = mirrored_clip_names
	return result


static func _build_animation(
	packed: PackedScene,
	node_prefix: String,
	target_skeleton: Skeleton3D,
	semantic: String,
) -> Animation:
	if packed == null:
		return null
	var instance := packed.instantiate()
	var loose_player := _find_player(instance)
	var source_skeleton := _find_skeleton(instance)
	if loose_player == null or source_skeleton == null:
		instance.free()
		return null
	if not _skeletons_are_compatible(source_skeleton, target_skeleton):
		push_warning("Skipped an animation whose skeleton does not match the character rig")
		instance.free()
		return null
	var source := _first_authored_animation(loose_player)
	if source == null:
		instance.free()
		return null

	var target := source.duplicate(true) as Animation
	var unit_scale := _skeleton_unit_scale(source_skeleton, target_skeleton)
	var target_bones := _bones_by_normalized_name(target_skeleton)
	for track in range(target.get_track_count()):
		var path := target.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var source_bone: StringName = path.get_subname(0)
		var normalized_bone := _normalize(str(source_bone))
		if not target_bones.has(normalized_bone):
			continue
		var target_bone: StringName = target_bones[normalized_bone]
		var new_path := NodePath(node_prefix + ":" + str(target_bone))
		target.track_set_path(track, new_path)
		if target.track_get_type(track) == Animation.TYPE_POSITION_3D:
			_retarget_position_track(
				target,
				track,
				source_bone,
				target_bone,
				source_skeleton,
				target_skeleton,
				unit_scale
			)
	_anchor_hips_to_combat_root(target, target_skeleton)
	instance.free()
	return target


static func _first_authored_animation(player: AnimationPlayer) -> Animation:
	for clip in player.get_animation_list():
		if _normalize(str(clip)) == "reset":
			continue
		var animation := player.get_animation(clip)
		if animation != null and animation.get_track_count() > 0:
			return animation
	return null


static func _bones_by_normalized_name(skeleton: Skeleton3D) -> Dictionary:
	var result: Dictionary = {}
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		result[_normalize(str(bone_name))] = bone_name
	return result


static func _skeletons_are_compatible(source: Skeleton3D, target: Skeleton3D) -> bool:
	var source_bones := _bones_by_normalized_name(source)
	var target_bones := _bones_by_normalized_name(target)
	if source_bones.size() != target_bones.size():
		return false
	for bone_name in source_bones:
		if not target_bones.has(bone_name):
			return false
	return true


## FBX files commonly store their armature in centimeters even when the GLB's
## live skeleton is in meters. Rotations survive that import difference, but
## copying bone positions verbatim collapses the animated rig. Derive the unit
## conversion from matching rest-pose bone lengths instead of a per-model value.
static func _skeleton_unit_scale(source: Skeleton3D, target: Skeleton3D) -> float:
	var ratios: Array[float] = []
	for target_index in target.get_bone_count():
		var bone_name := target.get_bone_name(target_index)
		var source_index := _bone_index_by_normalized_name(source, bone_name)
		if source_index < 0:
			continue
		if source.get_bone_parent(source_index) < 0 or target.get_bone_parent(target_index) < 0:
			continue
		var source_length := source.get_bone_rest(source_index).origin.length()
		var target_length := target.get_bone_rest(target_index).origin.length()
		if source_length > 0.000001 and target_length > 0.000001:
			ratios.append(target_length / source_length)
	if ratios.is_empty():
		return 1.0
	ratios.sort()
	var middle := ratios.size() / 2
	if ratios.size() % 2 == 0:
		return (ratios[middle - 1] + ratios[middle]) * 0.5
	return ratios[middle]


static func _retarget_position_track(
	animation: Animation,
	track: int,
	source_bone_name: StringName,
	target_bone_name: StringName,
	source: Skeleton3D,
	target: Skeleton3D,
	unit_scale: float
) -> void:
	var source_index := _bone_index_by_normalized_name(source, source_bone_name)
	var target_index := _bone_index_by_normalized_name(target, target_bone_name)
	if source_index < 0 or target_index < 0:
		return
	var source_rest := source.get_bone_rest(source_index).origin
	var target_rest := target.get_bone_rest(target_index).origin
	for key in animation.track_get_key_count(track):
		var source_position: Variant = animation.track_get_key_value(track, key)
		if source_position is Vector3:
			var target_position: Vector3 = target_rest + (source_position - source_rest) * unit_scale
			animation.track_set_key_value(track, key, target_position)


static func _bone_index_by_normalized_name(skeleton: Skeleton3D, bone_name: StringName) -> int:
	var wanted := _normalize(str(bone_name))
	for index in skeleton.get_bone_count():
		if _normalize(str(skeleton.get_bone_name(index))) == wanted:
			return index
	return -1


## Imported Mixamo clips often include a large hips X/Z offset or baked travel.
## Gameplay owns fight-plane position, so remove the start-to-end trajectory and
## recenter it on the target rig. Non-linear weight shifts and lunges remain;
## only permanent drift away from the pushbox is removed.
static func _anchor_hips_to_combat_root(animation: Animation, skeleton: Skeleton3D) -> void:
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		if not _normalize(str(path.get_subname(0))).ends_with("hips"):
			continue
		var bone_index := _bone_index_by_normalized_name(skeleton, path.get_subname(0))
		if bone_index < 0:
			continue
		var key_count := animation.track_get_key_count(track)
		if key_count == 0:
			continue
		var rest_position := skeleton.get_bone_rest(bone_index).origin
		var first_time := animation.track_get_key_time(track, 0)
		var last_time := animation.track_get_key_time(track, key_count - 1)
		var duration := maxf(last_time - first_time, 0.0001)
		var first_value := animation.track_get_key_value(track, 0) as Vector3
		var last_value := animation.track_get_key_value(track, key_count - 1) as Vector3
		for key in key_count:
			var value: Variant = animation.track_get_key_value(track, key)
			if value is Vector3:
				var anchored := value as Vector3
				var progress := (animation.track_get_key_time(track, key) - first_time) / duration
				var trajectory := first_value.lerp(last_value, progress)
				anchored.x = rest_position.x + anchored.x - trajectory.x
				anchored.z = rest_position.z + anchored.z - trajectory.z
				animation.track_set_key_value(track, key, anchored)


## Build a true sagittal mirror without applying a negative transform to the
## rendered model. Poses are sampled in skeleton space, left/right bone pairs
## exchange roles, and the reflected global poses are converted back to local
## bone tracks. This works across differing left/right rest-bone orientations.
static func _build_mirrored_animation(
	source: Animation,
	skeleton: Skeleton3D,
	node_prefix: String,
) -> Animation:
	if source == null or skeleton == null:
		return null
	var bone_count := skeleton.get_bone_count()
	var source_tracks := _bone_transform_tracks(source, skeleton)
	var partner_indices := PackedInt32Array()
	partner_indices.resize(bone_count)
	for bone_index in bone_count:
		partner_indices[bone_index] = _mirror_partner_index(skeleton, bone_index)

	var mirrored := Animation.new()
	mirrored.length = source.length
	mirrored.loop_mode = source.loop_mode
	mirrored.step = 1.0 / MIRROR_SAMPLE_FPS
	var output_tracks: Array[Dictionary] = []
	for bone_index in bone_count:
		var bone_name := skeleton.get_bone_name(bone_index)
		var path := NodePath(node_prefix + ":" + str(bone_name))
		var position_track := mirrored.add_track(Animation.TYPE_POSITION_3D)
		mirrored.track_set_path(position_track, path)
		mirrored.track_set_interpolation_type(position_track, Animation.INTERPOLATION_LINEAR)
		var rotation_track := mirrored.add_track(Animation.TYPE_ROTATION_3D)
		mirrored.track_set_path(rotation_track, path)
		mirrored.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_LINEAR)
		var scale_track := mirrored.add_track(Animation.TYPE_SCALE_3D)
		mirrored.track_set_path(scale_track, path)
		mirrored.track_set_interpolation_type(scale_track, Animation.INTERPOLATION_LINEAR)
		output_tracks.append({
			"position": position_track,
			"rotation": rotation_track,
			"scale": scale_track,
		})

	var hips_index := skeleton.find_bone("mixamorig_Hips")
	var mirror_plane_x := skeleton.get_bone_global_rest(hips_index).origin.x if hips_index >= 0 else 0.0
	var frame_count := maxi(1, ceili(source.length * MIRROR_SAMPLE_FPS))
	for frame in range(frame_count + 1):
		var time := minf(float(frame) / MIRROR_SAMPLE_FPS, source.length)
		var source_globals: Array[Transform3D] = []
		source_globals.resize(bone_count)
		for bone_index in bone_count:
			var local_pose := _sample_local_bone_pose(source, source_tracks, skeleton, bone_index, time)
			var parent := skeleton.get_bone_parent(bone_index)
			source_globals[bone_index] = source_globals[parent] * local_pose if parent >= 0 else local_pose

		var mirrored_globals: Array[Transform3D] = []
		mirrored_globals.resize(bone_count)
		for bone_index in bone_count:
			var partner := partner_indices[bone_index]
			mirrored_globals[bone_index] = _reflect_skeleton_transform(source_globals[partner], mirror_plane_x)

		for bone_index in bone_count:
			var parent := skeleton.get_bone_parent(bone_index)
			var local_pose := (
				mirrored_globals[parent].affine_inverse() * mirrored_globals[bone_index]
				if parent >= 0
				else mirrored_globals[bone_index]
			)
			var local_scale := local_pose.basis.get_scale()
			var local_rotation := local_pose.basis.orthonormalized().get_rotation_quaternion()
			var tracks: Dictionary = output_tracks[bone_index]
			mirrored.position_track_insert_key(int(tracks.position), time, local_pose.origin)
			mirrored.rotation_track_insert_key(int(tracks.rotation), time, local_rotation)
			mirrored.scale_track_insert_key(int(tracks.scale), time, local_scale)
	return mirrored


static func _bone_transform_tracks(animation: Animation, skeleton: Skeleton3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(skeleton.get_bone_count())
	for bone_index in skeleton.get_bone_count():
		result[bone_index] = {"position": -1, "rotation": -1, "scale": -1}
	for track in animation.get_track_count():
		var type := animation.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		var bone_index := _bone_index_by_normalized_name(skeleton, path.get_subname(0))
		if bone_index < 0:
			continue
		if type == Animation.TYPE_POSITION_3D:
			result[bone_index].position = track
		elif type == Animation.TYPE_ROTATION_3D:
			result[bone_index].rotation = track
		else:
			result[bone_index].scale = track
	return result


static func _sample_local_bone_pose(
	animation: Animation,
	tracks: Array[Dictionary],
	skeleton: Skeleton3D,
	bone_index: int,
	time: float,
) -> Transform3D:
	var rest := skeleton.get_bone_rest(bone_index)
	var bone_tracks: Dictionary = tracks[bone_index]
	var position := rest.origin
	var rotation := rest.basis.orthonormalized().get_rotation_quaternion()
	var scale := rest.basis.get_scale()
	if int(bone_tracks.position) >= 0:
		position = animation.position_track_interpolate(int(bone_tracks.position), time)
	if int(bone_tracks.rotation) >= 0:
		rotation = animation.rotation_track_interpolate(int(bone_tracks.rotation), time)
	if int(bone_tracks.scale) >= 0:
		scale = animation.scale_track_interpolate(int(bone_tracks.scale), time)
	return Transform3D(Basis(rotation).scaled(scale), position)


static func _mirror_partner_index(skeleton: Skeleton3D, bone_index: int) -> int:
	var bone_name := str(skeleton.get_bone_name(bone_index))
	var partner_name := bone_name
	if bone_name.contains("Left"):
		partner_name = bone_name.replace("Left", "Right")
	elif bone_name.contains("Right"):
		partner_name = bone_name.replace("Right", "Left")
	var partner := skeleton.find_bone(partner_name)
	return partner if partner >= 0 else bone_index


static func _reflect_skeleton_transform(transform: Transform3D, plane_x: float) -> Transform3D:
	var reflection := Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	var origin := reflection * transform.origin
	origin.x += plane_x * 2.0
	return Transform3D(reflection * transform.basis * reflection, origin)


static func _skeleton_track_prefix(player: AnimationPlayer, skeleton: Skeleton3D) -> String:
	var animation_root := player.get_node_or_null(player.root_node)
	if animation_root == null:
		return ""
	return str(animation_root.get_path_to(skeleton))


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _scan_files(anim_dir: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(anim_dir)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".fbx"):
			var key := _normalize(file_name.get_basename())
			var packed := load(anim_dir + "/" + file_name) as PackedScene
			if packed != null:
				result[key] = packed
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


static func _read_manifest(anim_dir: String) -> Dictionary:
	var path := anim_dir + "/index.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _normalize(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_").replace("|", "_").replace(".", "_").replace(":", "_")


static func _file_key(value: String) -> String:
	return _normalize(value.get_file().get_basename())

class_name FighterAnimationSet
extends RefCounted
## Loads loose Mixamo animation FBXs from a character's `animations/` folder and
## retargets them onto the character's live skeleton at runtime.

const FALLBACK_SEMANTICS := {
	"idle": ["idle", "fight_idle", "fighting_idle", "combat_idle"],
	"walk": ["walk", "walk_forward", "walking", "run"],
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
		if clip_names.size() > 0:
			result[semantic] = clip_names
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
	if semantic == "walk":
		_remove_linear_hips_drift(target)
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


static func _remove_linear_hips_drift(animation: Animation) -> void:
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		if not _normalize(str(path.get_subname(0))).ends_with("hips"):
			continue
		var key_count := animation.track_get_key_count(track)
		if key_count < 2:
			continue
		var first_time := animation.track_get_key_time(track, 0)
		var last_time := animation.track_get_key_time(track, key_count - 1)
		var duration := last_time - first_time
		if duration <= 0.0:
			continue
		var first_value: Variant = animation.track_get_key_value(track, 0)
		var last_value: Variant = animation.track_get_key_value(track, key_count - 1)
		if not first_value is Vector3 or not last_value is Vector3:
			continue
		var drift: Vector3 = last_value - first_value
		for key in key_count:
			var time := animation.track_get_key_time(track, key)
			var progress := (time - first_time) / duration
			var value: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, value - drift * progress)


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

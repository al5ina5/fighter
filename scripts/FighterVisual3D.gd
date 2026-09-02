extends Node3D
class_name FighterVisual3D
## Presentation adapter between the deterministic 2D combat simulation and a
## rigged 3D fighter. Gameplay never depends on a model's skeleton or clips.

const PIXELS_PER_METER := 100.0
const SCREEN_CENTER_X := 640.0
const FLOOR_Y := 560.0
const STANDING_FOOT_OFFSET := 120.0
const LOOPING_STATES := ["idle", "walk", "block"]
const LIMBS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

const ANIMATION_ALIASES := {
	"idle": ["idle", "fight_idle", "fighting_idle", "combat_idle"],
	"walk": ["walk", "walk_forward", "walking", "run"],
	"jump": ["jump", "jump_start", "airborne"],
	"block": ["block", "guard", "blocking"],
	"hit": ["hit", "hit_react", "hurt", "damage"],
	"knockout": ["knockout", "ko", "death", "defeat"],
	"high_normal": ["jab", "punch_jab", "head_punch", "punching"],
	"high_heavy": ["high_kick", "kick_high", "roundhouse"],
	"mid_normal": ["jab", "punch_jab", "punching", "bat_swing_mid"],
	"mid_heavy": ["heavy_punch", "punch_heavy", "punching_heavy", "punchingheavy", "bat_swing_mid"],
	"low_normal": ["low_kick", "kick_low", "sweep"],
	"low_heavy": ["low_kick", "kick_low", "sweep", "heavy_kick"],
}

var source: Player
var profile: Dictionary = {}
var facing_pivot: Node3D
var pose_pivot: Node3D
var model_root: Node3D
var model_skeleton: Skeleton3D
var animation_player: AnimationPlayer
var stance_marker: MeshInstance3D
var flash_light: OmniLight3D
var using_fallback := false
var last_semantic := ""
var last_attack_phase := ""
var fallback_parts: Dictionary = {}
var model_parts: Dictionary = {}
var model_stumps: Dictionary = {}
var limb_visibility: Dictionary = {}
var animation_sets: Dictionary = {}
var animation_set_cursors: Dictionary = {}
var last_hurt_timer := 0.0


func bind_player(player: Player, character_profile: Dictionary) -> void:
	source = player
	profile = character_profile.duplicate(true)
	if is_inside_tree():
		_build_presentation()


func _ready() -> void:
	add_to_group("fighter_visuals")
	if source != null:
		_build_presentation()


func _build_presentation() -> void:
	_build_pivots()
	_clear_model()
	var path := str(profile.get("model_path", ""))
	if path != "" and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var instance := packed.instantiate()
			if instance is Node3D:
				model_root = instance as Node3D
				pose_pivot.add_child(model_root)
				using_fallback = false
	if model_root == null:
		_build_fallback_model()
	else:
		_configure_external_model()
	_index_model(model_root)
	model_skeleton = _find_skeleton(model_root)
	animation_player = _find_animation_player(model_root)
	if animation_player == null and model_skeleton != null:
		animation_player = AnimationPlayer.new()
		animation_player.name = "AnimationPlayer"
		animation_player.root_node = NodePath("..")
		model_root.add_child(animation_player)
	_load_loose_animations()
	_configure_animation_loops()
	last_semantic = ""
	set_process(true)
	_sync_presentation(true)


func _build_pivots() -> void:
	if facing_pivot != null:
		return
	facing_pivot = Node3D.new()
	facing_pivot.name = "FacingPivot"
	add_child(facing_pivot)
	pose_pivot = Node3D.new()
	pose_pivot.name = "PosePivot"
	facing_pivot.add_child(pose_pivot)

	stance_marker = MeshInstance3D.new()
	stance_marker.name = "StanceMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.11
	marker_mesh.bottom_radius = 0.11
	marker_mesh.height = 0.018
	marker_mesh.radial_segments = 20
	stance_marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.2, 0.85, 1.0, 0.82)
	marker_material.emission_enabled = true
	marker_material.emission = Color(0.08, 0.45, 0.8)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stance_marker.material_override = marker_material
	stance_marker.position = Vector3(0.18, 0.018, 0.05)
	facing_pivot.add_child(stance_marker)

	flash_light = OmniLight3D.new()
	flash_light.name = "HitFlash"
	flash_light.light_color = Color(1.0, 0.78, 0.35)
	flash_light.light_energy = 4.0
	flash_light.omni_range = 2.8
	flash_light.position = Vector3(0.0, 1.25, 0.55)
	flash_light.visible = false
	add_child(flash_light)


func _clear_model() -> void:
	if model_root != null and is_instance_valid(model_root):
		model_root.free()
	model_root = null
	model_skeleton = null
	animation_player = null
	using_fallback = false
	fallback_parts.clear()
	model_parts.clear()
	model_stumps.clear()
	limb_visibility.clear()
	animation_sets.clear()
	animation_set_cursors.clear()
	last_attack_phase = ""
	last_hurt_timer = 0.0


func _configure_external_model() -> void:
	var uniform_scale := float(profile.get("model_scale", 1.0))
	model_root.scale = Vector3.ONE * uniform_scale
	var offset = profile.get("model_offset", Vector3.ZERO)
	if offset is Vector3:
		model_root.position = offset
	var rotation_degrees := float(profile.get("model_rotation_y", 0.0))
	model_root.rotation.y = deg_to_rad(rotation_degrees)


func _configure_animation_loops() -> void:
	if animation_player == null:
		return
	for semantic in LOOPING_STATES:
		var clips := _clips_for_semantic(semantic)
		for clip in clips:
			var animation := animation_player.get_animation(clip)
			if animation != null:
				# A single locomotion/idle clip loops normally. A set advances to
				# its next member whenever the current variation finishes.
				animation.loop_mode = Animation.LOOP_LINEAR if clips.size() == 1 else Animation.LOOP_NONE


func _build_fallback_model() -> void:
	using_fallback = true
	model_root = Node3D.new()
	model_root.name = "FallbackFighter"
	pose_pivot.add_child(model_root)

	var base_color: Color = profile.get("color", Color(0.8, 0.2, 0.2))
	_add_box_part("torso", Vector3(0.50, 0.72, 0.34), Vector3(0.0, 0.0, 0.0), base_color)
	_add_head_part(base_color.lightened(0.18))
	_add_box_part("arm_l", Vector3(0.18, 0.60, 0.18), Vector3(0.0, -0.30, 0.0), base_color.darkened(0.12))
	_add_box_part("arm_r", Vector3(0.18, 0.60, 0.18), Vector3(0.0, -0.30, 0.0), base_color.lightened(0.08))
	_add_box_part("leg_l", Vector3(0.22, 1.14, 0.25), Vector3(0.0, -0.57, 0.0), base_color.darkened(0.28))
	_add_box_part("leg_r", Vector3(0.22, 1.14, 0.25), Vector3(0.0, -0.57, 0.0), base_color.darkened(0.18))


func _add_box_part(slot: String, size: Vector3, mesh_offset: Vector3, color: Color) -> void:
	var pivot := Node3D.new()
	pivot.name = slot
	model_root.add_child(pivot)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "%s_mesh" % slot
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = mesh_offset
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.material_override = _fighter_material(color)
	pivot.add_child(mesh_instance)
	fallback_parts[slot] = pivot


func _add_head_part(color: Color) -> void:
	var pivot := Node3D.new()
	pivot.name = "head"
	model_root.add_child(pivot)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "head_mesh"
	var mesh := SphereMesh.new()
	mesh.radius = 0.27
	mesh.height = 0.54
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, 0.24, 0.0)
	mesh_instance.material_override = _fighter_material(color)
	pivot.add_child(mesh_instance)
	fallback_parts["head"] = pivot


func _fighter_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.06
	material.roughness = 0.62
	return material


func _process(_delta: float) -> void:
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	_sync_presentation(false)


func set_hitstop_paused(paused: bool) -> void:
	set_process(not paused)
	if animation_player == null:
		return
	if paused:
		animation_player.pause()
	else:
		animation_player.play()


func _sync_presentation(force_animation: bool) -> void:
	# The 2D physics body stays on a single plane. Only its presentation is
	# converted into meters for the 3D world.
	position.x = (source.global_position.x - SCREEN_CENTER_X) / PIXELS_PER_METER
	position.y = (FLOOR_Y - source.global_position.y - STANDING_FOOT_OFFSET) / PIXELS_PER_METER
	position.z = 0.12 if source.player_number == 1 else -0.12

	var authored_facing := int(profile.get("model_facing", 1))
	facing_pivot.rotation.y = 0.0 if source.facing == authored_facing else PI
	pose_pivot.rotation.z = -source.rig.rotation * float(source.facing)
	flash_light.visible = source.flash_timer > 0.0

	if using_fallback:
		_sync_fallback_pose()
	_sync_limb_visibility()
	_sync_animation(force_animation)


func _sync_fallback_pose() -> void:
	var rig_position: Vector2 = source.rig.position
	for slot in LIMBS:
		var part := fallback_parts.get(slot) as Node3D
		if part == null:
			continue
		var limb_2d := source._get_limb_node(slot)
		var local_x := (rig_position.x + limb_2d.position.x) * source.scale.x / PIXELS_PER_METER
		var local_y := (STANDING_FOOT_OFFSET - (rig_position.y + limb_2d.position.y) * source.scale.y) / PIXELS_PER_METER
		part.position = Vector3(local_x * float(source.facing), local_y, 0.0)
		part.rotation.z = -limb_2d.rotation * float(source.facing)
		part.scale = Vector3(1.0, limb_2d.scale.y, 1.0)


func _sync_limb_visibility() -> void:
	for slot in LIMBS:
		var gone: bool = bool(source.limb_hp.get(slot, {}).get("gone", false))
		# Torso remains visible during its KO, matching the legacy presentation.
		var show_limb: bool = not gone or slot == "torso"
		if limb_visibility.get(slot, null) == show_limb:
			continue
		limb_visibility[slot] = show_limb
		if using_fallback:
			var fallback := fallback_parts.get(slot) as Node3D
			if fallback != null:
				fallback.visible = show_limb
		for node in model_parts.get(slot, []):
			(node as Node3D).visible = show_limb
		for stump in model_stumps.get(slot, []):
			(stump as Node3D).visible = gone and slot != "torso"


func _sync_animation(force: bool) -> void:
	if animation_player == null:
		return
	var semantic := _current_semantic()
	var hurt_restarted := (
		source.state == Player.State.HURT
		and last_hurt_timer > 0.0
		and source.hurt_timer > last_hurt_timer + 0.001
	)
	last_hurt_timer = source.hurt_timer if source.state == Player.State.HURT else 0.0
	if not force and semantic == last_semantic:
		if hurt_restarted:
			_play_semantic(semantic)
			return
		if source.state == Player.State.ATTACK and source.attack_phase != last_attack_phase:
			last_attack_phase = source.attack_phase
			if last_attack_phase == "active":
				_retime_attack_after_contact(semantic)
		if semantic in LOOPING_STATES and not animation_player.is_playing():
			_play_semantic(semantic)
		return
	last_semantic = semantic
	last_attack_phase = source.attack_phase if source.state == Player.State.ATTACK else ""
	_play_semantic(semantic)


func _current_semantic() -> String:
	match source.state:
		Player.State.ATTACK:
			var band := str(source.attack.get("band", "mid"))
			var weight := "heavy" if bool(source.attack.get("heavy", false)) else "normal"
			return "%s_%s" % [band, weight]
		Player.State.HURT:
			return "hit"
		Player.State.KO:
			return "knockout"
	if not source.is_on_floor():
		return "jump"
	if source._is_blocking():
		return "block"
	if absf(source.velocity.x) > 5.0:
		return "walk"
	return "idle"


func _play_semantic(semantic: String) -> void:
	var resolved_semantic := semantic
	var clip := _choose_clip_for_semantic(semantic)
	if clip == StringName():
		if semantic != "idle":
			resolved_semantic = "idle"
			clip = _choose_clip_for_semantic("idle")
		if clip == StringName():
			return
	var speed := 1.0
	if source.state == Player.State.ATTACK and resolved_semantic == semantic:
		var animation := animation_player.get_animation(clip)
		var attack_duration: float = (
			float(source.attack.get("windup", 0.0))
			+ float(source.attack.get("active", 0.0))
			+ float(source.attack.get("recovery", 0.0))
		)
		if animation != null and attack_duration > 0.0:
			var contact_ratio := _attack_contact_ratio(semantic)
			var windup := float(source.attack.get("windup", 0.0))
			if contact_ratio > 0.0 and windup > 0.0:
				speed = animation.length * contact_ratio / windup
			else:
				speed = animation.length / attack_duration
	animation_player.speed_scale = speed
	animation_player.play(clip, 0.06)


func _retime_attack_after_contact(semantic: String) -> void:
	var contact_ratio := _attack_contact_ratio(semantic)
	if contact_ratio <= 0.0:
		return
	var clip := _active_clip_for_semantic(semantic)
	if clip == StringName():
		return
	var animation := animation_player.get_animation(clip)
	var remaining_game_time := (
		float(source.attack.get("active", 0.0))
		+ float(source.attack.get("recovery", 0.0))
	)
	if animation != null and remaining_game_time > 0.0:
		animation_player.speed_scale = animation.length * (1.0 - contact_ratio) / remaining_game_time


func _attack_contact_ratio(semantic: String) -> float:
	var ratios: Dictionary = profile.get("animation_contact_ratios", {})
	return clampf(float(ratios.get(semantic, -1.0)), 0.0, 1.0)


func _find_clip_for_semantic(semantic: String) -> StringName:
	var clips := _clips_for_semantic(semantic)
	return clips[0] if not clips.is_empty() else StringName()


func _choose_clip_for_semantic(semantic: String) -> StringName:
	var clips := _clips_for_semantic(semantic)
	if clips.is_empty():
		return StringName()
	var cursor := int(animation_set_cursors.get(semantic, 0))
	var clip: StringName = clips[cursor % clips.size()]
	animation_set_cursors[semantic] = cursor + 1
	return clip


func _active_clip_for_semantic(semantic: String) -> StringName:
	var clips := _clips_for_semantic(semantic)
	var current := animation_player.current_animation
	if current in clips:
		return current
	return clips[0] if not clips.is_empty() else StringName()


func _clips_for_semantic(semantic: String) -> Array[StringName]:
	if animation_sets.has(semantic):
		var external: Array[StringName] = []
		for clip in animation_sets[semantic]:
			if animation_player.has_animation(clip):
				external.append(StringName(clip))
		if not external.is_empty():
			return external

	var aliases: Array = []
	var animation_map: Dictionary = profile.get("animation_map", {})
	if animation_map.has(semantic):
		var mapped = animation_map[semantic]
		if mapped is Array:
			aliases.append_array(mapped)
		else:
			aliases.append(str(mapped))
	aliases.append_array(ANIMATION_ALIASES.get(semantic, [semantic]))
	var available := animation_player.get_animation_list()
	var matches: Array[StringName] = []
	for alias in aliases:
		var wanted := _normalize_name(str(alias))
		for clip in available:
			var normalized := _normalize_name(str(clip))
			if (normalized == wanted or normalized.ends_with("_" + wanted)) and clip not in matches:
				matches.append(clip)
	return matches


func _normalize_name(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_").replace("|", "_").replace(".", "_").replace(":", "_")


func _index_model(node: Node) -> void:
	if node is GeometryInstance3D:
		var node_3d := node as Node3D
		var extras: Dictionary = node.get_meta("extras", {})
		var slot := str(node.get_meta("limb_slot", extras.get("limb_slot", "")))
		if slot == "":
			slot = _slot_from_name(str(node.name))
		if slot != "":
			var is_stump := bool(node.get_meta("is_stump", extras.get("is_stump", str(node.name).to_lower().contains("stump"))))
			if is_stump:
				if not model_stumps.has(slot):
					model_stumps[slot] = []
				model_stumps[slot].append(node_3d)
				node_3d.visible = false
			else:
				if not model_parts.has(slot):
					model_parts[slot] = []
				model_parts[slot].append(node_3d)
	for child in node.get_children():
		_index_model(child)


func _slot_from_name(raw_name: String) -> String:
	var name := _normalize_name(raw_name)
	if name.contains("head") or name.contains("neck"):
		return "head"
	if name.contains("torso") or name.contains("chest") or name.contains("spine"):
		return "torso"
	if name.contains("arm_l") or name.contains("arm_left") or name.contains("left_arm") or name.contains("rings_l"):
		return "arm_l"
	if name.contains("arm_r") or name.contains("arm_right") or name.contains("right_arm") or name.contains("rings_r"):
		return "arm_r"
	if name.contains("leg_l") or name.contains("leg_left") or name.contains("left_leg"):
		return "leg_l"
	if name.contains("leg_r") or name.contains("leg_right") or name.contains("right_leg"):
		return "leg_r"
	return ""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _load_loose_animations() -> void:
	if animation_player == null or model_skeleton == null:
		return
	var dir := str(profile.get("animations_dir", ""))
	if dir == "":
		return
	var configured_sets: Dictionary = profile.get("animation_sets", {})
	var loaded := FighterAnimationSet.load_animations(
		animation_player,
		model_skeleton,
		dir,
		configured_sets,
	)
	animation_sets = loaded

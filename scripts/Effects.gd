extends Node

const COMBAT_FPS := 60.0

var shake_amount := 0.0
var shake_decay := 42.0
var hitstop_remaining := 0.0
var impact_streams: Dictionary = {}


func add_shake(amount: float) -> void:
	shake_amount = max(shake_amount, amount)


func combat_impact(hitstop_frames: int, heavy: bool, blocked: bool, counter_hit: bool, limb_break: bool) -> void:
	var frames := hitstop_frames + (2 if counter_hit else 0) + (3 if limb_break else 0)
	hitstop(float(frames) / COMBAT_FPS)
	var strength := 4.0 if blocked else (11.0 if heavy else 6.0)
	if limb_break:
		strength = 16.0
	add_shake(strength)
	_play_impact_sound(heavy, blocked, limb_break)


func _play_impact_sound(heavy: bool, blocked: bool, limb_break: bool) -> void:
	var key := "%s_%s_%s" % [heavy, blocked, limb_break]
	if not impact_streams.has(key):
		impact_streams[key] = _build_impact_stream(heavy, blocked, limb_break)
	var player := AudioStreamPlayer.new()
	player.stream = impact_streams[key]
	player.volume_db = -6.0 if blocked else -2.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _build_impact_stream(heavy: bool, blocked: bool, limb_break: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.16 if limb_break else (0.12 if heavy else 0.08)
	var sample_count := roundi(float(sample_rate) * duration)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var pitch := 120.0 if limb_break else (170.0 if heavy else 260.0)
	if blocked:
		pitch = 430.0
	for i in sample_count:
		var t := float(i) / float(sample_rate)
		var envelope := pow(1.0 - t / duration, 2.5)
		var thump := sin(TAU * pitch * t) * 0.62
		var crackle := sin(TAU * (pitch * 4.7) * t + sin(t * 1800.0)) * 0.28
		var sample := clampi(roundi((thump + crackle) * envelope * 32767.0), -32768, 32767)
		pcm.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = pcm
	return stream


func _process(delta: float) -> void:
	if hitstop_remaining > 0.0:
		hitstop_remaining -= delta
		if hitstop_remaining <= 0.0:
			_resume_all()
	if shake_amount > 0.0:
		shake_amount -= shake_decay * delta
		if shake_amount < 0.0:
			shake_amount = 0.0
		var cam := get_camera()
		if cam is Camera2D:
			cam.offset = Vector2(
				randf_range(-shake_amount, shake_amount),
				randf_range(-shake_amount, shake_amount)
			)
		elif cam is Camera3D:
			cam.h_offset = randf_range(-shake_amount, shake_amount) / 100.0
			cam.v_offset = randf_range(-shake_amount, shake_amount) / 100.0
	elif shake_amount <= 0.0:
		var cam := get_camera()
		if cam is Camera2D:
			cam.offset = Vector2.ZERO
		elif cam is Camera3D:
			cam.h_offset = 0.0
			cam.v_offset = 0.0


func hitstop(duration: float) -> void:
	hitstop_remaining = maxf(hitstop_remaining, duration)
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(false)
		node.set_hitstop_paused(true)
	for visual in get_tree().get_nodes_in_group("fighter_visuals"):
		visual.set_hitstop_paused(true)


func _resume_all() -> void:
	hitstop_remaining = 0.0
	for node in get_tree().get_nodes_in_group("players"):
		node.set_physics_process(true)
		node.set_hitstop_paused(false)
	for visual in get_tree().get_nodes_in_group("fighter_visuals"):
		visual.set_hitstop_paused(false)


func get_camera() -> Node:
	return get_tree().get_first_node_in_group("camera")

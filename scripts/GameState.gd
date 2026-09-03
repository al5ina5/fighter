extends Node

const SHARED_ANIMATION_MAP := {
	"idle": "idle",
	"walk": "walk",
	"jump": "jump",
	"block": "block",
	"hit": "hit",
	"knockout": "knockout",
	"high_normal": "high_normal",
	"high_heavy": "high_heavy",
	"mid_normal": "mid_normal",
	"mid_heavy": "mid_heavy",
	"low_normal": "low_normal",
	"low_heavy": "low_heavy",
}

const SHARED_CONTACT_RATIOS := {
	"high_normal": 0.23,
	"high_heavy": 0.36,
	"mid_normal": 0.38,
	"mid_heavy": 0.62,
	"low_normal": 0.34,
	"low_heavy": 0.58,
}

const CHARACTERS := [
	{
		"name": "Girlypoppums",
		"color": Color(0.96, 0.24, 0.62),
		"model_path": "res://assets/models/girlypoppums/girlypoppums_prepared.glb",
		"animations_dir": "res://assets/models/girlypoppums/animations",
		# Match the legacy fighter's roughly 2.6 m presentation envelope while
		# keeping the prepared asset itself at a conventional 1.76 m height.
		"model_scale": 1.5,
		"standing_pushbox_width": 34.0,
		"airborne_pushbox_width": 30.0,
		"legless_pushbox_width": 30.0,
		"model_facing": 1,
		# Mixamo characters are authored on the camera axis. Turn that axis onto
		# gameplay X; FacingPivot supplies the opposite 180-degree turn for P2.
		"model_rotation_y": 90.0,
		"animation_map": SHARED_ANIMATION_MAP,
		# Authored contact points measured from the supplied clips. Runtime frame
		# data places startup/active at that pose while playback remains at 1x.
		"animation_contact_ratios": SHARED_CONTACT_RATIOS,
	},
	{
		"name": "Green Blocky Robot",
		"color": Color(0.24, 0.78, 0.34),
		"model_path": "res://assets/models/robot/robot_prepared.glb",
		"animations_dir": "res://assets/models/robot/animations",
		"model_scale": 1.5,
		# The robot's torso is materially broader than the humanoid mesh. Its
		# stable core collision is character data, while limbs may still overlap.
		"standing_pushbox_width": 88.0,
		"airborne_pushbox_width": 78.0,
		"legless_pushbox_width": 82.0,
		"model_facing": 1,
		"model_rotation_y": 90.0,
		"animation_map": SHARED_ANIMATION_MAP,
		"animation_contact_ratios": SHARED_CONTACT_RATIOS,
	},
]

var p1_index := 0
var p2_index := 1
var p1_ready := false
var p2_ready := false


func reset() -> void:
	p1_index = 0
	p2_index = 1
	p1_ready = false
	p2_ready = false


func p1_char() -> Dictionary:
	return CHARACTERS[p1_index]


func p2_char() -> Dictionary:
	return CHARACTERS[p2_index]

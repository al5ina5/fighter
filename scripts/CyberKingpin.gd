extends Node3D
class_name CyberKingpin
## Runtime helper for the modular Cyber Kingpin GLB.
## Instance the imported scene under this node, or assign `rig`.

const LIMB_SLOTS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

@export var rig: Node3D
@onready var anim: AnimationPlayer = _find_anim()

var _parts: Dictionary = {}
var _stumps: Dictionary = {}


func _ready() -> None:
	if rig == null:
		rig = self
	_index(rig)
	for slot in LIMB_SLOTS:
		_set_stump(slot, false)
	if anim and anim.has_animation("idle"):
		anim.play("idle")


func detach(slot: String) -> void:
	if slot == "torso":
		return
	_set_limb(slot, false)
	_set_stump(slot, true)


func attach(slot: String) -> void:
	_set_limb(slot, true)
	_set_stump(slot, false)


func play_clip(name: String, custom_speed: float = 1.0) -> void:
	if anim and anim.has_animation(name):
		anim.play(name, -1, custom_speed)


func _set_limb(slot: String, visible: bool) -> void:
	for node in _parts.get(slot, []):
		node.visible = visible


func _set_stump(slot: String, visible: bool) -> void:
	for node in _stumps.get(slot, []):
		node.visible = visible


func _index(node: Node) -> void:
	if node is MeshInstance3D:
		var slot := str(node.get_meta("limb_slot", ""))
		if slot == "" and "limb_slot" in node:
			slot = str(node.limb_slot)
		if slot == "":
			slot = _slot_from_name(node.name)
		if slot != "":
			if bool(node.get_meta("is_stump", node.name.begins_with("stump_"))):
				_stumps.setdefault(slot, []).append(node)
			else:
				_parts.setdefault(slot, []).append(node)
	for child in node.get_children():
		_index(child)


func _slot_from_name(mesh_name: String) -> String:
	if mesh_name == "head" or mesh_name.begins_with("stump_neck"):
		return "head"
	if mesh_name == "torso" or mesh_name.begins_with("acc_chain"):
		return "torso"
	if mesh_name == "arm_l" or mesh_name.begins_with("stump_arm_l") or mesh_name.begins_with("acc_rings_l"):
		return "arm_l"
	if mesh_name == "arm_r" or mesh_name.begins_with("stump_arm_r") or mesh_name.begins_with("acc_rings_r"):
		return "arm_r"
	if mesh_name == "leg_l" or mesh_name.begins_with("stump_leg_l"):
		return "leg_l"
	if mesh_name == "leg_r" or mesh_name.begins_with("stump_leg_r"):
		return "leg_r"
	return ""


func _find_anim() -> AnimationPlayer:
	var found := find_child("AnimationPlayer", true, false)
	return found

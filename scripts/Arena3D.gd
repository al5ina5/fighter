extends Node3D
class_name Arena3D

const FIGHTER_VISUAL_SCRIPT := preload("res://scripts/FighterVisual3D.gd")

@onready var camera: Camera3D = $Camera3D
@onready var fighters: Node3D = $Fighters


func _ready() -> void:
	# A restrained downward angle reveals the 3D floor without changing the
	# side-on gameplay axis. The orthographic projection keeps combat spacing
	# visually consistent with the authoritative 2D simulation.
	camera.look_at(Vector3(0.0, 1.8, 0.0), Vector3.UP)


func add_fighter(source: Player, profile: Dictionary) -> FighterVisual3D:
	var visual := FIGHTER_VISUAL_SCRIPT.new() as FighterVisual3D
	visual.name = "P%d_%sVisual3D" % [source.player_number, source.name]
	visual.bind_player(source, profile)
	fighters.add_child(visual)
	return visual

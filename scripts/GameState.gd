extends Node

const CHARACTERS := [
	{"name": "Swordman", "color": Color(0.85, 0.2, 0.2)},
	{"name": "Zombie", "color": Color(0.35, 0.75, 0.3)},
	{"name": "Girl", "color": Color(0.95, 0.4, 0.7)},
	{"name": "Tank", "color": Color(0.6, 0.3, 0.85)},
]

var p1_index := 0
var p2_index := 3
var p1_ready := false
var p2_ready := false


func reset() -> void:
	p1_index = 0
	p2_index = 3
	p1_ready = false
	p2_ready = false


func p1_char() -> Dictionary:
	return CHARACTERS[p1_index]


func p2_char() -> Dictionary:
	return CHARACTERS[p2_index]

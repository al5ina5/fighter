extends Resource
class_name CombatBoxData

## A deterministic box on the 2D fight plane. Coordinates are authored around
## the fighter's feet; +X means forward and is mirrored by facing at runtime.

@export var center := Vector2.ZERO
@export var size := Vector2.ONE
@export var region := "torso"
@export var start_frame := 0
@export var end_frame := 0


func active_on(frame: int) -> bool:
	return frame >= start_frame and frame <= end_frame


func world_rect(origin: Vector2, facing: int, world_scale: float) -> Rect2:
	var mirrored_center := Vector2(center.x * float(facing), center.y)
	var world_size := size * world_scale
	var world_center := origin + mirrored_center * world_scale
	return Rect2(world_center - world_size * 0.5, world_size)


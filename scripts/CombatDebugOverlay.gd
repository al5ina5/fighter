extends Node2D
class_name CombatDebugOverlay

var fighters: Array[Player] = []
var data_label: Label
var enabled := false
var toggle_was_down := false


func bind_players(first: Player, second: Player, label: Label) -> void:
	fighters = [first, second]
	data_label = label
	data_label.visible = enabled


func _process(_delta: float) -> void:
	var down := Input.is_physical_key_pressed(KEY_F1)
	if down and not toggle_was_down:
		enabled = not enabled
		if data_label != null:
			data_label.visible = enabled
	toggle_was_down = down
	if enabled and data_label != null and fighters.size() == 2:
		data_label.text = "%s\n%s\nDISTANCE  %.1f" % [
			_fighter_line(fighters[0]),
			_fighter_line(fighters[1]),
			absf(fighters[1].global_position.x - fighters[0].global_position.x),
		]
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	for fighter in fighters:
		if not is_instance_valid(fighter):
			continue
		var push_shape := fighter.body_shape.shape as RectangleShape2D
		var push_size := push_shape.size * fighter.body_shape.global_scale.abs()
		var push_rect := Rect2(fighter.body_shape.global_position - push_size * 0.5, push_size)
		draw_rect(push_rect, Color(0.2, 0.65, 1.0, 0.16), true)
		draw_rect(push_rect, Color(0.25, 0.75, 1.0, 0.9), false, 2.0)
		for limb_name in Player.LIMBS:
			if bool(fighter.limb_hp[limb_name].gone):
				continue
			var hurt_rect := fighter._limb_hurt_rect(limb_name)
			draw_rect(hurt_rect, Color(0.25, 1.0, 0.35, 0.12), true)
			draw_rect(hurt_rect, Color(0.3, 1.0, 0.4, 0.85), false, 1.5)
		if fighter.state == Player.State.ATTACK and fighter.attack_phase == "active":
			for strike_rect in fighter._active_hit_rects():
				draw_rect(strike_rect, Color(1.0, 0.15, 0.15, 0.28), true)
				draw_rect(strike_rect, Color(1.0, 0.2, 0.2, 1.0), false, 3.0)


func _fighter_line(fighter: Player) -> String:
	var detail: String = Player.State.keys()[fighter.state]
	if fighter.state == Player.State.ATTACK:
		detail += " %s %s F%d" % [
			str(fighter.attack.get("band", "")).to_upper(),
			fighter.attack_phase.to_upper(),
			fighter.attack_frame,
		]
	return "P%d  %-22s HP %5.1f  GUARD %5.1f" % [fighter.player_number, detail, fighter.health, fighter.guard]

extends Node

var failures := 0


func _ready() -> void:
	_test_source_limb_selection()
	_test_pose_tracks_facing_and_stance()
	_test_target_priorities()
	_test_destroyed_limb_fallbacks()
	_test_actual_contact_wins()
	if failures == 0:
		print("CombatRulesTest: all checks passed")
		get_tree().quit(0)
	else:
		push_error("CombatRulesTest: %d check(s) failed" % failures)
		get_tree().quit(1)


func _test_source_limb_selection() -> void:
	_expect_eq(CombatRules.source_limb("high", false, 1), "arm_r", "right-lead normal high")
	_expect_eq(CombatRules.source_limb("high", true, 1), "leg_l", "right-lead heavy high kick")
	_expect_eq(CombatRules.source_limb("mid", false, -1), "arm_l", "left-lead normal mid")
	_expect_eq(CombatRules.source_limb("mid", true, -1), "arm_r", "left-lead heavy mid")
	_expect_eq(CombatRules.source_limb("low", false, 1), "leg_r", "right-lead normal low")
	_expect_eq(CombatRules.source_limb("low", true, 1), "leg_l", "right-lead heavy low")


func _test_pose_tracks_facing_and_stance() -> void:
	_expect_true(CombatRules.pose_x("leg_r", 1, 1) > 0.0, "P1 right lead is toward right-side foe")
	_expect_true(CombatRules.pose_x("leg_r", 1, -1) < 0.0, "P2 right lead is toward left-side foe")
	_expect_true(CombatRules.pose_x("leg_l", -1, 1) > 0.0, "left lead moves forward after stance change")
	_expect_true(CombatRules.pose_x("arm_r", -1, 1) < 0.0, "old lead arm moves rearward after stance change")


func _test_target_priorities() -> void:
	var intact := _limbs()
	_expect_eq(CombatRules.pick_target("high", 1, intact), "head", "high hits head")
	_expect_eq(CombatRules.pick_target("mid", 1, intact), "arm_r", "mid hits close right arm")
	_expect_eq(CombatRules.pick_target("mid", -1, intact), "arm_l", "stance swaps close mid target")
	_expect_eq(CombatRules.pick_target("low", 1, intact), "leg_r", "low hits close right leg")
	_expect_eq(CombatRules.pick_target("low", -1, intact), "leg_l", "stance swaps close low target")


func _test_destroyed_limb_fallbacks() -> void:
	var limbs := _limbs()
	limbs["leg_r"].gone = true
	_expect_eq(CombatRules.pick_target("low", 1, limbs), "leg_l", "low advances to rear leg")
	limbs["leg_l"].gone = true
	_expect_eq(CombatRules.pick_target("low", 1, limbs), "arm_r", "low advances to close arm")
	_expect_eq(CombatRules.pick_target("mid", 1, limbs), "head", "mid hits head after both legs are gone")
	limbs["arm_r"].gone = true
	_expect_eq(CombatRules.pick_target("low", 1, limbs), "arm_l", "low advances to rear arm")
	limbs["arm_l"].gone = true
	_expect_eq(CombatRules.pick_target("low", 1, limbs), "torso", "low advances to torso")

	var mid_limbs := _limbs()
	mid_limbs["arm_r"].gone = true
	_expect_eq(CombatRules.pick_target("mid", 1, mid_limbs), "torso", "mid advances from close arm to torso")


func _test_actual_contact_wins() -> void:
	var limbs := _limbs()
	_expect_eq(
		CombatRules.pick_contact_target("high", 1, limbs, ["torso"]),
		"torso",
		"high attack damages the torso it touched instead of a distant preferred head",
	)
	_expect_eq(
		CombatRules.pick_contact_target("low", 1, limbs, ["leg_l", "leg_r"]),
		"leg_r",
		"priority only breaks a tie between contacted hurtboxes",
	)


func _limbs() -> Dictionary:
	return {
		"head": {"gone": false},
		"torso": {"gone": false},
		"arm_l": {"gone": false},
		"arm_r": {"gone": false},
		"leg_l": {"gone": false},
		"leg_r": {"gone": false},
	}


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s: expected %s, got %s" % [label, expected, actual])


func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("%s: expected true" % label)

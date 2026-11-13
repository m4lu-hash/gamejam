extends Area3D
## room3 惊吓触发：拿钥匙后走近门口 → 灯闪灭 → monster-show → 黑屏 → door-opening

@export var scare_light: OmniLight3D
@export var trigger_once := true

var _done := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _done:
		return
	if not (body is CharacterBody3D):
		return
	if not (body.name == "player" or body.is_in_group("player")):
		return
	if not GameState.has_flag(&"key_taken"):
		return
	if trigger_once:
		_done = true
	_play_scare()


func _play_scare() -> void:
	# 1) 门口灯闪烁后熄灭
	if scare_light != null:
		var tw := create_tween()
		for i in 5:
			tw.tween_property(scare_light, "light_energy", 0.0, 0.07)
			tw.tween_property(scare_light, "light_energy", 2.2, 0.05)
		tw.tween_property(scare_light, "light_energy", 0.0, 0.35)

	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play_sfx", &"monster_show")

	# 2) 等 monster-show 起势，黑屏
	await get_tree().create_timer(1.4, true).timeout
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("fade_out", 0.7)
		ui.call("set_objective", "别回头，快走")

	# 3) 黑屏里播开门声
	await get_tree().create_timer(0.9, true).timeout
	if audio != null:
		audio.call("play_sfx", &"door_opening")

	# 4) 淡回来
	await get_tree().create_timer(1.1, true).timeout
	if ui != null:
		ui.call("fade_in", 0.9)
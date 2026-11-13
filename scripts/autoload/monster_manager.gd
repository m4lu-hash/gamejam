extends Node
## 怪物管理：只在 room3 出现。
## 机制：灯闪烁 → 黑屏 → 怪物瞬移靠近玩家 → 亮灯 → 怪物停住。
## 被碰到：跳脸 → 黑屏 → 回上一个存档点。

signal caught

const MONSTER_SCENE := "res://scenes/monster/monster.tscn"
const RESPAWN_DELAY := 2.2
## 两次惊吓之间的间隔（秒）
const SCARE_INTERVAL := 6.0
## 每次黑屏怪物最多靠近多少米
const DASH_STEP := 4.0
## 黑屏持续时间
const BLACKOUT_TIME := 1.2
## 门口灯正常亮度
const LIGHT_ENERGY := 1.6

var monster: Node3D = null
var _busy := false
var _scare_timer := 0.0
var _spawned_announced := false
var _blackout := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _busy:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	if not scene.scene_file_path.ends_with("room3.tscn"):
		_scare_timer = 0.0
		_spawned_announced = false
		return
	if not GameState.has_flag(&"key_taken"):
		return
	if monster == null or not is_instance_valid(monster):
		_spawn_monster(scene)
		return

	_scare_timer += delta
	if _scare_timer >= SCARE_INTERVAL and not _blackout:
		_scare_timer = 0.0
		_blackout_step(scene)


func _spawn_monster(scene: Node) -> void:
	var packed: PackedScene = load(MONSTER_SCENE)
	if packed == null:
		return
	monster = packed.instantiate()
	var marker := scene.get_node_or_null("MonsterSpawn") as Node3D
	if marker != null:
		monster.global_position = marker.global_position
	else:
		monster.global_position = Vector3(2.0, 0.0, 2.0)
	scene.add_child(monster)
	if monster.has_signal("caught_player"):
		monster.connect("caught_player", Callable(self, "_on_caught"))
	if not _spawned_announced:
		_spawned_announced = true
		_play_sfx(&"monster_show")


## 一次"熄灯黑屏"：灯闪 → 黑屏 → 怪物瞬移 → 亮灯
func _blackout_step(scene: Node) -> void:
	if _blackout:
		return
	_blackout = true
	var light := scene.get_node_or_null("ScareLight") as OmniLight3D
	# 灯闪烁
	if light != null:
		var tw := create_tween()
		for i in 4:
			tw.tween_property(light, "light_energy", 0.0, 0.06)
			tw.tween_property(light, "light_energy", LIGHT_ENERGY, 0.05)
		tw.tween_property(light, "light_energy", 0.0, 0.12)

	UIManager.fade_out(0.25)
	await get_tree().create_timer(0.3, true).timeout
	if monster != null and is_instance_valid(monster) and monster.has_method("dash_toward_player"):
		monster.call("dash_toward_player", DASH_STEP)
	await get_tree().create_timer(BLACKOUT_TIME, true).timeout
	UIManager.fade_in(0.3)
	if light != null and is_instance_valid(light):
		light.light_energy = LIGHT_ENERGY
	_blackout = false


func _on_caught() -> void:
	if _busy:
		return
	_busy = true
	caught.emit()
	get_tree().paused = true
	UIManager.play_jumpscare()
	await get_tree().create_timer(RESPAWN_DELAY, true).timeout
	UIManager.hide_jumpscare()
	get_tree().paused = false
	SaveManager.respawn_at_checkpoint()
	if monster != null and is_instance_valid(monster):
		monster.queue_free()
	monster = null
	_scare_timer = 0.0
	_spawned_announced = false
	_blackout = false
	_busy = false


func _play_sfx(sfx: StringName) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", sfx)


## 重置（新游戏时调用）
func reset() -> void:
	if monster != null and is_instance_valid(monster):
		monster.queue_free()
	monster = null
	_scare_timer = 0.0
	_spawned_announced = false
	_blackout = false
	_busy = false
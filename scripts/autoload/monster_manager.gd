extends Node
## 怪物管理：room3 一进去就有怪物。
## 机制：灯反复闪烁 → 黑屏（怪物缓慢追逐）→ 灯亮（怪物停住）。
## 被抓：跳脸 → 黑屏 → 回上一个存档点。

signal caught

const MONSTER_SCENE := "res://scenes/monster/monster.tscn"
const RESPAWN_DELAY := 2.2
## 两次闪烁的间隔（秒）——不要太平凡
const SCARE_INTERVAL := 9.0
## 灯灭/黑屏持续时间（怪物只在这段时间追）
const BLACKOUT_TIME := 2.4
## 门口灯正常亮度
const LIGHT_ENERGY := 1.6
## 暗下去之前的闪烁时长（秒）
const FLICKER_TIME := 1.1
## 刚进 room3 后多久开始第一次闪灯
const ENTRY_FIRST_DELAY := 1.5

var monster: Node3D = null
var _busy := false
var _scare_timer := 0.0
var _blackout := false
var _in_room3 := false
var _blackout_token := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _busy:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	if not scene.scene_file_path.ends_with("room3.tscn"):
		# 黑屏途中走出房间：立刻收尾，别让走廊继续黑着
		if _blackout:
			_abort_blackout()
		_scare_timer = 0.0
		_in_room3 = false
		return
	if not _in_room3:
		# 刚进屋子就开始闪灯：把计时器拨到快触发的位置
		_in_room3 = true
		_scare_timer = SCARE_INTERVAL - ENTRY_FIRST_DELAY
	if monster == null or not is_instance_valid(monster):
		_spawn_monster(scene)
		return
	if _blackout:
		return
	# 灯亮着的时候怪物必须停住
	if monster != null and is_instance_valid(monster) and monster.has_method("set_chasing"):
		monster.call("set_chasing", false)

	_scare_timer += delta
	if _scare_timer >= SCARE_INTERVAL:
		_scare_timer = 0.0
		_blackout_step(scene)


func _spawn_monster(scene: Node) -> void:
	var packed: PackedScene = load(MONSTER_SCENE)
	if packed == null:
		return
	monster = packed.instantiate()
	scene.add_child(monster)
	# 先 add_child 再设坐标，否则 get_global_transform 会报警告
	var marker := scene.get_node_or_null("MonsterSpawn") as Node3D
	if marker != null:
		monster.global_position = marker.global_position
	else:
		monster.global_position = Vector3(2.0, 0.0, 2.0)
	if monster.has_signal("caught_player"):
		monster.connect("caught_player", Callable(self, "_on_caught"))


## 一次"熄灯黑屏"：灯闪 → 黑屏（怪物追）→ 亮灯（怪物停）
func _blackout_step(scene: Node) -> void:
	if _blackout or not is_instance_valid(scene):
		return
	_blackout = true
	_blackout_token += 1
	var token := _blackout_token
	var light := scene.get_node_or_null("ScareLight") as OmniLight3D

	# 先快速闪几下，再彻底暗下去
	if light != null:
		var tw := create_tween()
		for i in 6:
			tw.tween_property(light, "light_energy", LIGHT_ENERGY * 0.15, 0.05)
			tw.tween_property(light, "light_energy", LIGHT_ENERGY, 0.05)
			tw.tween_interval(0.06)
		tw.tween_property(light, "light_energy", 0.0, 0.12)

	await get_tree().create_timer(FLICKER_TIME, true).timeout
	if token != _blackout_token:
		return
	# 屏幕暗下去要快
	UIManager.fade_out(0.12)
	await get_tree().create_timer(0.15, true).timeout
	if token != _blackout_token:
		return
	_play_sfx(&"monster_show")
	if monster != null and is_instance_valid(monster) and monster.has_method("set_chasing"):
		monster.call("set_chasing", true)

	await get_tree().create_timer(BLACKOUT_TIME, true).timeout
	if token != _blackout_token:
		return
	if monster != null and is_instance_valid(monster) and monster.has_method("set_chasing"):
		monster.call("set_chasing", false)
	UIManager.fade_in(0.2)
	_stop_sfx(&"monster_show")
	_blackout = false
	# 黑屏期间玩家可能已经切房间，旧场景可能已被释放
	if not is_instance_valid(scene) or scene != get_tree().current_scene:
		return
	if light != null and is_instance_valid(light):
		light.light_energy = LIGHT_ENERGY
	# 黑屏结束后随机换门（room3 有两扇门，只显示一扇）
	var shuffler := scene.get_node_or_null("DoorShuffler")
	if shuffler != null and shuffler.has_method("shuffle"):
		shuffler.call("shuffle")


## 黑屏被打断（离开房间）：立刻恢复画面、停下怪物
func _abort_blackout() -> void:
	_blackout_token += 1
	_blackout = false
	if monster != null and is_instance_valid(monster) and monster.has_method("set_chasing"):
		monster.call("set_chasing", false)
	_stop_sfx(&"monster_show")
	UIManager.fade_in(0.15)


func _on_caught() -> void:
	if _busy:
		return
	_busy = true
	caught.emit()
	get_tree().paused = true
	UIManager.play_jumpscare()
	await get_tree().create_timer(RESPAWN_DELAY, true).timeout
	UIManager.hide_jumpscare()
	# 跳脸声太长：复活时淡出掉
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("fade_out_sfx"):
		audio.call("fade_out_sfx", &"jumpscare", 0.6)
		audio.call("stop_sfx", &"monster_show")
	get_tree().paused = false
	SaveManager.respawn_at_checkpoint()
	if monster != null and is_instance_valid(monster):
		monster.queue_free()
	monster = null
	_scare_timer = 0.0
	_blackout = false
	_busy = false


func _play_sfx(sfx: StringName) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", sfx)


func _stop_sfx(sfx: StringName) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("stop_sfx"):
		audio.call("stop_sfx", sfx)


## 重置（新游戏时调用）
func reset() -> void:
	_blackout_token += 1
	if _blackout:
		UIManager.fade_in(0.15)
	_blackout = false
	if monster != null and is_instance_valid(monster):
		monster.queue_free()
	monster = null
	_scare_timer = 0.0
	_blackout = false
	_busy = false

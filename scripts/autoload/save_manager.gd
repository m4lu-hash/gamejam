extends Node
## 全局存档。Autoload 名：SaveManager
## 存档路径：user://save.json
## 存：flags / 已拾取物品 / 背包物品 id / 存档点（房间 + 坐标）

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

## id -> ItemData，启动时扫描 data/items/*.tres
var _registry: Dictionary = {}
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_registry()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.3
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_save_timer)
	_save_timer.timeout.connect(_write_now)

	GameState.flag_changed.connect(_on_state_changed)
	GameState.picked_changed.connect(_on_state_changed)
	Inventory.changed.connect(_on_state_changed)
	call_deferred("load_game")


func _build_registry() -> void:
	var dir := DirAccess.open("res://data/items")
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var item: Resource = load("res://data/items/" + file_name)
		if item != null and "id" in item:
			_registry[item.id] = item


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 是否有可继续的进度（需要真的到过存档点）
func has_progress() -> bool:
	return has_save() and not GameState.checkpoint.is_empty()


func save_game() -> void:
	if _save_timer != null:
		_save_timer.stop()
	_write_now()


func _on_state_changed(_a: Variant = null, _b: Variant = null) -> void:
	if _save_timer != null:
		_save_timer.start()


func _write_now() -> void:
	var data := {
		"version": SAVE_VERSION,
		"flags": {},
		"picked": {},
		"inventory": [],
		"checkpoint": GameState.checkpoint,
	}
	for key in GameState.flags.keys():
		data["flags"][String(key)] = GameState.flags[key]
	for key in GameState.picked.keys():
		data["picked"][String(key)] = true
	for item in Inventory.items:
		if item != null:
			data["inventory"].append(String(item.id))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: 无法写入存档 %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed

	GameState.flags.clear()
	var flags: Dictionary = data.get("flags", {})
	for key in flags.keys():
		GameState.flags[StringName(key)] = flags[key]

	GameState.picked.clear()
	var picked: Dictionary = data.get("picked", {})
	for key in picked.keys():
		if bool(picked[key]):
			GameState.picked[StringName(key)] = true

	Inventory.clear()
	for item_id in data.get("inventory", []):
		var item: ItemData = _registry.get(StringName(item_id), null)
		if item != null:
			Inventory.add(item)

	var cp: Dictionary = data.get("checkpoint", {})
	GameState.checkpoint = cp
	return true


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	GameState.flags.clear()
	GameState.picked.clear()
	GameState.checkpoint = {}
	Inventory.clear()


## 存档点：房间场景路径 + 出生点名字 + 世界坐标
func set_checkpoint(room_path: String, spawn_name: String, position: Vector3) -> void:
	GameState.checkpoint = {
		"room": room_path,
		"spawn": spawn_name,
		"position": [position.x, position.y, position.z],
	}
	save_game()


## 死亡 / 被抓后回存档点；没有存档点就回 room1
func respawn_at_checkpoint() -> void:
	var cp: Dictionary = GameState.checkpoint
	var room_path := String(cp.get("room", "res://scenes/rooms/room1.tscn"))
	var spawn_name := String(cp.get("spawn", "SpawnFromCorridor"))
	var pos_arr: Array = cp.get("position", [])
	var packed: PackedScene = load(room_path)
	if packed == null:
		return
	RoomManager.change_room(packed, spawn_name)
	if pos_arr.size() == 3:
		var scene := get_tree().current_scene
		var player := scene.get_node_or_null("player") as Node3D if scene != null else null
		if player != null:
			player.global_position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
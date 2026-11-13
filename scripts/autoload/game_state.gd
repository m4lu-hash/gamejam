extends Node
## 全局状态：剧情 flag、进度。Autoload 名：GameState

signal flag_changed(key: StringName, value: Variant)
signal picked_changed(id: StringName)

var flags: Dictionary = {}
## 已拾取的物品 id（世界中的物件据此消失）
var picked: Dictionary = {}
## 存档点：{ room, spawn, position }
var checkpoint: Dictionary = {}
var chapter: int = 0


func mark_picked(id: StringName) -> void:
	if id == &"":
		return
	picked[id] = true
	picked_changed.emit(id)


func is_picked(id: StringName) -> bool:
	return picked.has(id) and bool(picked[id])


func set_flag(key: StringName, value: Variant = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)


func get_flag(key: StringName, default: Variant = null) -> Variant:
	return flags.get(key, default)


func has_flag(key: StringName) -> bool:
	return flags.has(key) and flags[key] != null and flags[key] != false


func clear() -> void:
	flags.clear()
	picked.clear()
	checkpoint = {}
	chapter = 0
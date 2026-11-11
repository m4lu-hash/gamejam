extends Node
## 全局状态：剧情 flag、进度。Autoload 名：GameState

signal flag_changed(key: StringName, value: Variant)

var flags: Dictionary = {}
var chapter: int = 0


func set_flag(key: StringName, value: Variant = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)


func get_flag(key: StringName, default: Variant = null) -> Variant:
	return flags.get(key, default)


func has_flag(key: StringName) -> bool:
	return flags.has(key) and flags[key] != null and flags[key] != false


func clear() -> void:
	flags.clear()
	chapter = 0
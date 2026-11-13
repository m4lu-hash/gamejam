extends CharacterBody3D
## 怪物：胶囊体占位。只在 room3 出现；由 MonsterManager 在"黑屏"时瞬移靠近玩家。
## 自己只负责：面向玩家 + 距离判定（抓到 → 触发跳脸）。

signal caught_player

@export var catch_distance := 1.1

var _player: Node3D
var _done := false


func _ready() -> void:
	_find_player()


func _find_player() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_player = scene.get_node_or_null("player") as Node3D


func _physics_process(_delta: float) -> void:
	if _done:
		return
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist <= catch_distance:
		_done = true
		caught_player.emit()
		return
	if dist > 0.01:
		var look := global_position + to_player.normalized()
		look.y = global_position.y
		if global_position.distance_to(look) > 0.01:
			look_at(look, Vector3.UP)


## 黑屏时被 MonsterManager 调用：朝玩家瞬移一段
func dash_toward_player(max_step: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
	if _player == null:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist <= catch_distance:
		return
	var step := minf(max_step, dist - catch_distance)
	global_position += to_player.normalized() * step
extends CharacterBody3D
class_name Monster
## 怪物：胶囊体占位。只在 room3 出现；灯灭（黑屏）时缓慢追向玩家，灯亮时停住。
## 抓到玩家 → 发 caught_player（由 MonsterManager 处理跳脸与回档）。

signal caught_player

@export var catch_distance := 1.0
## 追逐速度（米/秒）——比玩家慢，保证能跑掉
@export var chase_speed := 1.5

## 由 MonsterManager 控制：灯灭时为 true
var chasing := false

var _player: Node3D
var _done := false


func _ready() -> void:
	_find_player()


func _find_player() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_player = scene.get_node_or_null("player") as Node3D


func set_chasing(value: bool) -> void:
	chasing = value


func _physics_process(delta: float) -> void:
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
		velocity = Vector3.ZERO
		caught_player.emit()
		return

	if not chasing or dist <= 0.01:
		velocity = Vector3.ZERO
		return

	var dir := to_player.normalized()
	velocity = dir * chase_speed
	move_and_slide()
	# 面朝玩家
	var look := global_position + dir
	look.y = global_position.y
	if global_position.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
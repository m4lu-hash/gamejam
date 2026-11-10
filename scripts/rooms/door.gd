extends Area3D
class_name  Door
## 门洞触发器：玩家朝门外走进去，就无缝切换到目标房间，
## 并出现在目标房间对应的门口出生点上。
##
## 摆放方式：Area3D 放在门洞（CSGBox3D 挖出来的开口）位置，
## 用一个 BoxShape3D 把门洞盖住即可；Area3D 本身不用旋转。

## 目标房间场景（进入本房间时预加载，切换瞬间不卡顿）
@export_file("*.tscn") var target_scene: String = ""
## 目标房间里出生点 Marker3D 的名字
@export var target_spawn: String = ""
## 玩家“走出本房间”的方向（世界坐标），只有朝这个方向走才会触发
@export var exit_direction := Vector3(0.0, 0.0, -1.0)
## 方向容差：速度方向与 exit_direction 的点积要大于它才触发，0 表示不判定方向
@export_range(-1.0, 1.0, 0.05) var direction_tolerance := 0.2

var _packed: PackedScene


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if target_scene.is_empty():
		return
	_packed = load(target_scene)
	if _packed == null:
		push_error("Door: 目标场景加载失败：%s" % target_scene)


func _on_body_entered(body: Node3D) -> void:
	if _packed == null or not _is_player(body):
		return
	# 刚切完房间的一小段时间内不响应，避免两个门口来回弹
	if Time.get_ticks_msec() - RoomManager.last_change_msec < RoomManager.ENTER_GRACE_MSEC:
		return
	if not _walking_out(body):
		return
	RoomManager.change_room(_packed, target_spawn)


func _is_player(body: Node) -> bool:
	if body is not CharacterBody3D:
		return false
	return body.name == "player" or body.is_in_group("player")


func _walking_out(body: Node) -> bool:
	var velocity: Vector3 = (body as CharacterBody3D).velocity
	velocity.y = 0.0
	if velocity.length() < 0.1:
		return false
	return velocity.normalized().dot(exit_direction.normalized()) >= direction_tolerance

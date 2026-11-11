extends Area3D
class_name  Door
## 门洞触发器：玩家朝门外走进去，就无缝切换到目标房间，
## 并出现在目标房间对应的门口出生点上。
##
## 如果最近的那扇门是锁着的（door_leaf.locked = true）：
##   - 玩家走不过去（_can_pass 返回 false）；
##   - 站在门口按 E 会尝试用背包里的钥匙开锁；
##   - 开锁成功后门才会自动打开。

## 目标房间场景（进入本房间时预加载，切换瞬间不卡顿）
@export_file("*.tscn") var target_scene: String = ""
## 目标房间里出生点 Marker3D 的名字
@export var target_spawn: String = ""
## 玩家“走出本房间”的方向（世界坐标），只有朝这个方向走才会触发
@export var exit_direction := Vector3(0.0, 0.0, -1.0)
## 方向容差：速度方向与 exit_direction 的点积要大于它才触发，0 表示不判定方向
@export_range(-1.0, 1.0, 0.05) var direction_tolerance := 0.2

var _packed: PackedScene
## 离本触发器最近的那扇门（用来判断"门开够没有"和"锁没锁"）
var _door: Node3D


func _ready() -> void:
	if not target_scene.is_empty():
		_packed = load(target_scene)
		if _packed == null:
			push_error("Door: 目标场景加载失败：%s" % target_scene)
	# 找本房间离门口最近的门（用于"门开够没有 / 是否锁着"的判断）
	_find_nearby_door.call_deferred()


## 用轮询代替 body_entered：玩家站在触发区里等门开够，也能触发
func _process(_delta: float) -> void:
	if _packed == null or RoomManager.is_changing:
		return
	for body in get_overlapping_bodies():
		if _is_player(body) and _can_pass(body):
			RoomManager.change_room(_packed, target_spawn)
			return


## 锁着的门：按 E 尝试用背包里的钥匙开锁
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _door == null or not _door.has_method("is_locked") or not bool(_door.call("is_locked")):
		return
	# 触发区在门框外侧，玩家在房间内侧按 E 时并不重叠，所以按距离判定
	if _player_near_door(2.5):
		_try_unlock()
		get_viewport().set_input_as_handled()


func _player_near_door(radius: float) -> bool:
	var scene := get_tree().current_scene
	if scene != null:
		var p := scene.get_node_or_null("player") as Node3D
		if p != null:
			return p.global_position.distance_to(_door.global_position) <= radius
	for body in get_overlapping_bodies():
		if _is_player(body):
			return true
	return false


func _try_unlock() -> void:
	var found_any_key := false
	for item in Inventory.items:
		if not (item is KeyData):
			continue
		found_any_key = true
		if not (item as KeyData).can_unlock(_door.get("lock_id")):
			continue
		if bool(_door.call("try_unlock", item)):
			UIManager.toast("用「%s」打开了锁" % item.display_name)
			GameState.set_flag(StringName("unlocked_" + String(_door.get("lock_id"))), true)
			# 立刻把门打开，不用等靠近自动开
			if _door.has_method("open_with_animation"):
				_door.call("open_with_animation", 100.0, false)
		return
	if found_any_key:
		UIManager.toast("不是这个钥匙")
	else:
		UIManager.toast("需要：%s" % String(_door.get("key_hint")))


func _find_nearby_door() -> void:
	var best := 2.5
	for node in get_tree().get_nodes_in_group("door_leaf"):
		if node is not Node3D:
			continue
		var d := node as Node3D
		var dist := d.global_position.distance_to(global_position)
		if dist < best:
			best = dist
			_door = d


func _can_pass(body: Node3D) -> bool:
	# 刚换完房间的一小段时间内不响应，避免两个门口来回弹
	if Time.get_ticks_msec() - RoomManager.last_change_msec < RoomManager.ENTER_GRACE_MSEC:
		return false
	if _door != null and _door.has_method("is_locked") and bool(_door.call("is_locked")):
		return false
	# 门没开到能过人的程度就不放行（防止从半开的门缝里被"挤"出去切换）
	if _door != null and _door.has_method("get_angle_deg"):
		if absf(_door.get_angle_deg()) < 40.0:
			return false
	return _walking_out(body)


func _is_player(body: Node) -> bool:
	if body is not CharacterBody3D:
		return false
	return body.name == "player" or body.is_in_group("player")


func _walking_out(body: Node) -> bool:
	var velocity: Vector3 = (body as CharacterBody3D).velocity
	velocity.y = 0.0
	if velocity.length() < 0.1:
		# 触发区已经在门框外侧，拿不到速度时也允许触发（能走到这里就说明已经出门了）
		return true
	return velocity.normalized().dot(exit_direction.normalized()) >= direction_tolerance

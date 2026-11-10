extends Node3D
## 可交互门扇：玩家走上去用身体把门顶开（门绕合页轴旋转），玩家走远后自动关上。
##
## 场景结构：DoorLeaf(Node3D，本脚本) → Pivot(Node3D，绕 Y 轴旋转) → Leaf / StaticBody3D
## 摆放：本节点放在门框的合页位置，本地 +X 方向就是门板伸出的方向；
##       用 open_angle_deg 的正负控制往房间内开还是往房间外开。

## 推开的角度（绕 Y 轴，正负决定朝哪边开）
@export var open_angle_deg := 95.0
## 开门动画时长（秒）
@export var swing_time := 0.45
## 玩家离门中心多近、并且朝门方向走时，会用身体把门顶开
@export var push_range := 1.5
## "朝门走"的判定阈值：速度方向与"玩家→门中心"方向的点积
@export var push_direction_dot := 0.45
## 玩家离开到多远后自动关门
@export var auto_close_distance := 2.8
## 玩家走远后多久自动关门（秒）
@export var auto_close_delay := 1.0
## 是否一开局就处于打开状态
@export var open_on_start := false

@onready var pivot: Node3D = $Pivot

var is_open := false
var _closed_y := 0.0
var _away_time := 0.0
var _tween: Tween


func _ready() -> void:
	add_to_group("door_leaf")
	_closed_y = pivot.rotation.y
	if open_on_start:
		open_instant()


## 立刻变成打开状态（没有动画），用于玩家刚被传送到新房间、门口的"门还是开着的"
func open_instant() -> void:
	is_open = true
	_away_time = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	pivot.rotation.y = _closed_y + deg_to_rad(open_angle_deg)


## 开始推开门（播放绕合页的旋转动画）
func open() -> void:
	if is_open:
		return
	is_open = true
	_away_time = 0.0
	_animate_to(_closed_y + deg_to_rad(open_angle_deg))


## 播放关门动画
func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate_to(_closed_y)


func _physics_process(delta: float) -> void:
	var player := _find_player()
	if player == null:
		return

	var dist := global_position.distance_to(player.global_position)

	if not is_open:
		_try_push_open(player)
		return

	# 门开着：玩家走远一段时间后自动关上
	if dist > auto_close_distance:
		_away_time += delta
		if _away_time >= auto_close_delay:
			_away_time = 0.0
			close()
	else:
		_away_time = 0.0


## 玩家朝门的方向走、并且已经贴近门板 -> 把门顶开
func _try_push_open(player: Node3D) -> void:
	if player is not CharacterBody3D:
		return

	var body := player as CharacterBody3D
	var velocity := body.velocity
	velocity.y = 0.0
	if velocity.length() < 0.5:
		return  # 没在走，推不动

	# 门板中心的世界坐标（closed 状态下 pivot 尚未旋转）
	var leaf_center := pivot.global_transform * Vector3(0.8, 1.15, 0.0)
	var to_door := leaf_center - body.global_position
	to_door.y = 0.0

	if to_door.length() > push_range:
		return
	if to_door.length() < 0.001:
		return
	if velocity.normalized().dot(to_door.normalized()) < push_direction_dot:
		return  # 不是朝门的方向走

	open()


func _animate_to(target_y: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(pivot, "rotation:y", target_y, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _find_player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Node3D:
		return nodes[0]
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("player") as Node3D
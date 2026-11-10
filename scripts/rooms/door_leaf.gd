extends Node3D
## 门扇：只转 Hinge 节点的 Y 轴（合页在门框边缘），所以是绕边轴旋转，不是绕门板中心。
##
## 推动是**物理式**的，不是 tween 动画：
##   玩家顶着门走 -> 角速度按角加速度累积
##   松手 -> 角速度按阻尼衰减（有惯性、会多转一点）
##   玩家走远一段时间 -> 弹簧把门拉回关闭
##   角度 = 对角速度做积分，碰撞/限位都在这个积分过程里处理。
##
## 开门方向由几何自动算：门板朝向 -> 房间外 = 推开方向。
## 跨房间时由 RoomManager 把上一扇门的"门板世界朝向"复制过来（见 set_leaf_world_direction）。

## 最大开合角度（度）
@export var max_swing_deg := 100.0
## 玩家离门板多近算"在推门"
@export var push_range := 1.4
## 推门时的角加速度（rad/s²），越大越轻
@export var push_accel := 14.0
## 松手后的角速度衰减（rad/s²），越大越"涩"
@export var angular_drag := 6.0
## 玩家离开到多远后自动关门
@export var auto_close_distance := 2.8
## 玩家走远后多久开始自动关门（秒）
@export var auto_close_delay := 1.2
## 关门弹簧刚度 / 阻尼
@export var close_stiffness := 10.0
@export var close_damp := 5.0
## 角速度上限
@export var max_angular_speed := 5.0
## 是否一开局就处于打开状态
@export var open_on_start := false

## 门是否处于打开状态（角度超过阈值）
var is_open := false

var _angle := 0.0          # 当前角度（弧度，0 = 关闭）
var _ang_vel := 0.0        # 角速度（rad/s）
var _away_time := 0.0
var _closing := false
var _push_sign := 1.0      # 推开时角度的符号（由几何自动算）
var _closed_leaf_dir := Vector3.FORWARD  # 关闭时门板的世界朝向
var _last_player_pos := Vector3.ZERO
var _has_last_pos := false

@onready var hinge: Node3D = $Hinge


func _ready() -> void:
	add_to_group("door_leaf")
	hinge.rotation.y = 0.0
	_closed_leaf_dir = hinge.global_transform.basis.x
	_closed_leaf_dir.y = 0.0
	if _closed_leaf_dir.length() > 0.001:
		_closed_leaf_dir = _closed_leaf_dir.normalized()
	_compute_push_direction()
	if open_on_start:
		open_instant()


func _physics_process(delta: float) -> void:
	var player := _find_player()

	if player != null:
		_update_push(player, delta)
		_update_auto_close(player, delta)

	if _closing:
		# 弹簧 + 阻尼
		_ang_vel += (-_angle * close_stiffness - _ang_vel * close_damp) * delta
		if absf(_angle) < deg_to_rad(1.5) and absf(_ang_vel) < 0.2:
			_snap_closed()
	else:
		# 松手后按阻尼衰减（这就是"惯性"的来源）
		_ang_vel = move_toward(_ang_vel, 0.0, angular_drag * delta)

	_ang_vel = clampf(_ang_vel, -max_angular_speed, max_angular_speed)

	# 对角速度积分得到角度
	_angle += _ang_vel * delta

	var limit := deg_to_rad(max_swing_deg)
	if _angle > limit:
		_angle = limit
		_ang_vel = minf(_ang_vel, 0.0)
	elif _angle < -limit:
		_angle = -limit
		_ang_vel = maxf(_ang_vel, 0.0)

	hinge.rotation.y = _angle

	if absf(_angle) > deg_to_rad(8.0):
		is_open = true
	elif absf(_angle) < deg_to_rad(2.0):
		is_open = false


## 玩家贴着门、并且还在朝门走 -> 给门角加速度（推门）
func _update_push(player: Node3D, delta: float) -> void:
	var pos := player.global_position
	var move := pos - _last_player_pos
	_last_player_pos = pos
	if not _has_last_pos:
		_has_last_pos = true
		return

	move.y = 0.0
	if move.length() < 0.002:
		return

	var leaf_center: Vector3 = hinge.global_transform * Vector3(0.8, 0.0, 0.0)
	var to_leaf: Vector3 = leaf_center - pos
	to_leaf.y = 0.0
	if to_leaf.length() > push_range or to_leaf.length() < 0.001:
		return
	if move.normalized().dot(to_leaf.normalized()) < 0.3:
		return

	_ang_vel += _push_sign * push_accel * delta


func _update_auto_close(player: Node3D, delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist > auto_close_distance:
		_away_time += delta
		if _away_time >= auto_close_delay:
			_closing = true
	else:
		_away_time = 0.0
		_closing = false


## 被传送到新房间时：把上一扇门的"门板世界朝向"复制过来
func set_leaf_world_direction(world_dir: Vector3) -> void:
	var dir := world_dir
	dir.y = 0.0
	if dir.length() < 0.001:
		open_instant()
		return
	dir = dir.normalized()

	var target_deg := rad_to_deg(_closed_leaf_dir.signed_angle_to(dir, Vector3.UP))
	_angle = clampf(deg_to_rad(target_deg), -deg_to_rad(max_swing_deg), deg_to_rad(max_swing_deg))
	_ang_vel = 0.0
	_closing = false
	_away_time = 0.0
	hinge.rotation.y = _angle
	is_open = absf(_angle) > deg_to_rad(2.0)


## 兜底：没有可复制的朝向时，门朝房间内开着（从另一侧推过来）
func open_instant() -> void:
	var outward := _outward_dir()
	set_leaf_world_direction(-outward)


## 当前门板的世界朝向（跨房间复制用）
func get_leaf_world_dir() -> Vector3:
	var dir := hinge.global_transform.basis.x
	dir.y = 0.0
	return dir.normalized()


## 当前开合角度（度）
func get_angle_deg() -> float:
	return rad_to_deg(_angle)


func _compute_push_direction() -> void:
	var outward := _outward_dir()
	_push_sign = signf(_closed_leaf_dir.signed_angle_to(outward, Vector3.UP))
	if is_zero_approx(_push_sign):
		_push_sign = 1.0


func _outward_dir() -> Vector3:
	var room := get_tree().current_scene
	var room_center := Vector3.ZERO
	if room is Node3D:
		room_center = (room as Node3D).global_position

	var outward: Vector3 = global_position - room_center
	outward.y = 0.0
	if outward.length() < 0.01:
		return Vector3.FORWARD
	return outward.normalized()


func _snap_closed() -> void:
	_angle = 0.0
	_ang_vel = 0.0
	hinge.rotation.y = 0.0
	is_open = false
	_closing = false


func _find_player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Node3D:
		return nodes[0]
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("player") as Node3D

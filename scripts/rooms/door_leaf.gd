extends Node3D
## 门扇：只转 Hinge 节点的 Y 轴（合页在门框边缘），所以是绕边轴旋转。
##
## 三种状态：
##   AUTO_OPENING  被传送进房间时，门播放一次"自动推开"动画（角度 tween）
##   FREE          动画结束后交给玩家推：角速度积分，物理式（有加速度、惯性、阻尼）
##   CLOSING       玩家走远后弹簧把门拉回关闭
## 动画途中如果玩家撞上来，会立刻中断动画切到 FREE，由物理接管。

enum State { CLOSED, AUTO_OPENING, FREE, CLOSING }

## 最大开合角度（度）
@export var max_swing_deg := 100.0
## 玩家离门板多近算"在推门"
@export var push_range := 1.4
## 推门角加速度（rad/s²）
@export var push_accel := 14.0
## 松手后角速度衰减（rad/s²）
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
## 自动开启动画时长（秒）
@export var auto_open_time := 0.45
## 是否一开局就处于打开状态
@export var open_on_start := false

var is_open := false

var _angle := 0.0
var _ang_vel := 0.0
var _state := State.CLOSED
var _auto_from := 0.0
var _auto_to := 0.0
var _auto_t := 0.0
var _away_time := 0.0
var _push_sign := 1.0     # 推开时角度方向
var _inward_sign := -1.0  # 朝房间内时角度方向
var _closed_leaf_dir := Vector3.FORWARD
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
	_compute_directions()
	if open_on_start:
		open_with_animation(max_swing_deg)


func _physics_process(delta: float) -> void:
	var player := _find_player()
	var pushing := false
	if player != null:
		pushing = _is_pushing(player, delta)
		_update_away_time(player, delta)

	match _state:
		State.CLOSED:
			# 关着的门：玩家一推就进入物理状态
			if pushing:
				_state = State.FREE
		State.AUTO_OPENING:
			_auto_t += delta
			var k := clampf(_auto_t / maxf(auto_open_time, 0.01), 0.0, 1.0)
			_angle = lerpf(_auto_from, _auto_to, ease(k, 0.5))
			if pushing and _auto_t > 0.2:
				_state = State.FREE
				_ang_vel = 0.0
			elif k >= 1.0:
				_angle = _auto_to
				_state = State.FREE
				_ang_vel = 0.0
		State.FREE:
			if pushing:
				_ang_vel += _push_sign * push_accel * delta
			else:
				_ang_vel = move_toward(_ang_vel, 0.0, angular_drag * delta)
			if _away_time >= auto_close_delay:
				_state = State.CLOSING
		State.CLOSING:
			_ang_vel += (-_angle * close_stiffness - _ang_vel * close_damp) * delta
			if pushing:
				_state = State.FREE
				_away_time = 0.0
			elif absf(_angle) < deg_to_rad(1.5) and absf(_ang_vel) < 0.2:
				_snap_closed()

	if _state == State.FREE or _state == State.CLOSING:
		_ang_vel = clampf(_ang_vel, -max_angular_speed, max_angular_speed)
		_angle += _ang_vel * delta

		var limit := deg_to_rad(max_swing_deg)
		if _angle > limit:
			_angle = limit
			_ang_vel = minf(_ang_vel, 0.0)
		elif _angle < -limit:
			_angle = -limit
			_ang_vel = maxf(_ang_vel, 0.0)

	hinge.rotation.y = _angle
	is_open = absf(_angle) > deg_to_rad(8.0)


## 传送进房间时调用：播放"自动推开"动画，随后进入可被玩家推的物理状态
func open_with_animation(angle_deg_arg: float = 100.0) -> void:
	var mag := clampf(absf(angle_deg_arg), 5.0, max_swing_deg)
	_auto_from = _angle
	_auto_to = _inward_sign * deg_to_rad(mag)
	_auto_t = 0.0
	_ang_vel = 0.0
	_away_time = 0.0
	_state = State.AUTO_OPENING
	is_open = true


## 兜底：直接开（没有来源角度时）
func open_instant() -> void:
	open_with_animation(max_swing_deg)


## 当前开合角度（度）
func get_angle_deg() -> float:
	return rad_to_deg(_angle)


## 门板当前世界朝向（调试/测试用）
func get_leaf_world_dir() -> Vector3:
	var dir := hinge.global_transform.basis.x
	dir.y = 0.0
	return dir.normalized()


## 玩家是否在朝门走（并更新上一帧位置）
func _is_pushing(player: Node3D, _delta: float) -> bool:
	var pos := player.global_position
	var move := pos - _last_player_pos
	_last_player_pos = pos
	if not _has_last_pos:
		_has_last_pos = true
		return false

	move.y = 0.0
	if move.length() > 1.0:
		return false  # 传送/复位造成的位移，不算推门
	if move.length() < 0.002:
		return false

	var leaf_center: Vector3 = hinge.global_transform * Vector3(0.8, 0.0, 0.0)
	var to_leaf: Vector3 = leaf_center - pos
	to_leaf.y = 0.0
	if to_leaf.length() > push_range or to_leaf.length() < 0.001:
		return false
	return move.normalized().dot(to_leaf.normalized()) >= 0.3


func _update_away_time(player: Node3D, delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist > auto_close_distance:
		_away_time = minf(_away_time + delta, 999.0)
	else:
		_away_time = 0.0


func _compute_directions() -> void:
	var outward := _outward_dir()
	var open_deg := rad_to_deg(_closed_leaf_dir.signed_angle_to(outward, Vector3.UP))
	_push_sign = signf(open_deg)
	if is_zero_approx(_push_sign):
		_push_sign = 1.0
	_inward_sign = -_push_sign


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
	_state = State.CLOSED


func _find_player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Node3D:
		return nodes[0]
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("player") as Node3D
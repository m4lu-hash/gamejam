extends Node3D
## 门扇：只转 Hinge 节点的 Y 轴（合页在门框边缘），所以是绕边轴旋转。
##
## 没有"推门"了，规则很简单：
##   玩家靠近 open_range 内 -> 播放开门动画（朝房间外开，不会朝玩家扑）
##   玩家离开 auto_close_distance 外持续 auto_close_delay 秒 -> 弹簧关回去
##   传送到达时不受上述限制，由 RoomManager 调 open_at_angle() 瞬间设定角度

enum State { CLOSED, AUTO_OPENING, FREE, CLOSING }

## 最大开合角度（度）
@export var max_swing_deg := 100.0
## 玩家进入多近的范围就自动开门
@export var open_range := 2.5
## 自动开门动画时长（秒）
@export var auto_open_time := 0.5
## 玩家离开到多远后自动关门
@export var auto_close_distance := 3.0
## 玩家走远后多久开始自动关门（秒）
@export var auto_close_delay := 3.0
## 关门弹簧刚度 / 阻尼
@export var close_stiffness := 10.0
@export var close_damp := 5.0
## 角速度上限
@export var max_angular_speed := 5.0
## 是否一开局就处于打开状态
@export var open_on_start := false

## 门是否处于打开状态（角度超过阈值）
var is_open := false

var _angle := 0.0
var _ang_vel := 0.0
var _state := State.CLOSED
var _auto_from := 0.0
var _auto_to := 0.0
var _auto_t := 0.0
var _away_time := 0.0
var _push_sign := 1.0     # 朝"房间外"的角度方向
var _inward_sign := -1.0  # 朝"房间内"的角度方向
var _closed_leaf_dir := Vector3.FORWARD
var _ignore_until := 0    # 出生保护期：这段时间内不自动开门、碰撞关闭

@onready var hinge: Node3D = $Hinge
@onready var _collision: CollisionShape3D = $Hinge/StaticBody3D/CollisionShape3D


func _ready() -> void:
	add_to_group("door_leaf")
	hinge.rotation.y = 0.0
	_closed_leaf_dir = hinge.global_transform.basis.x
	_closed_leaf_dir.y = 0.0
	if _closed_leaf_dir.length() > 0.001:
		_closed_leaf_dir = _closed_leaf_dir.normalized()
	_compute_directions()
	if open_on_start:
		open_at_angle(max_swing_deg)


func _physics_process(delta: float) -> void:
	var player := _find_player()
	var ignoring := Time.get_ticks_msec() < _ignore_until
	var dist := 999.0
	if player != null:
		dist = global_position.distance_to(player.global_position)

	match _state:
		State.CLOSED:
			# 靠近自动开门（朝房间外开，不会朝玩家扑）
			if not ignoring and player != null and dist <= open_range:
				open_with_animation(max_swing_deg, false)
		State.AUTO_OPENING:
			_auto_t += delta
			var k := clampf(_auto_t / maxf(auto_open_time, 0.01), 0.0, 1.0)
			_angle = lerpf(_auto_from, _auto_to, ease(k, 0.5))
			if k >= 1.0 or _auto_t > auto_open_time * 2.0 + 0.5:
				_angle = _auto_to
				_state = State.FREE
				_ang_vel = 0.0
		State.FREE:
			if dist > auto_close_distance:
				_away_time += delta
				if _away_time >= auto_close_delay:
					_state = State.CLOSING
			else:
				_away_time = 0.0
		State.CLOSING:
			_ang_vel += (-_angle * close_stiffness - _ang_vel * close_damp) * delta
			# 玩家回到附近就取消关门
			if player != null and dist <= auto_close_distance:
				_state = State.FREE
				_away_time = 0.0
				_ang_vel = 0.0
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

	# 门在自动转动、或出生保护期内，且玩家在门口附近时：临时关掉碰撞，避免把人挤出去
	if player != null:
		var near := dist < 2.2
		var auto_moving := _state == State.AUTO_OPENING or _state == State.CLOSING
		_collision.disabled = ignoring or (auto_moving and near)
	else:
		_collision.disabled = ignoring


## 传送进房间时调用：瞬间设为指定角度（不播动画）
func open_at_angle(angle_deg_arg: float) -> void:
	var mag := clampf(absf(angle_deg_arg), 0.0, max_swing_deg)
	_angle = _inward_sign * deg_to_rad(mag)
	_ang_vel = 0.0
	_auto_t = 0.0
	_away_time = 0.0
	hinge.rotation.y = _angle
	is_open = mag > 8.0
	_state = State.FREE if mag > 2.0 else State.CLOSED


## 播放一次开门动画；inward=true 朝房间内开，false 朝房间外开
func open_with_animation(angle_deg_arg: float = 100.0, inward := false) -> void:
	var mag := clampf(absf(angle_deg_arg), 5.0, max_swing_deg)
	var sign_dir := _inward_sign if inward else _push_sign
	_auto_from = _angle
	_auto_to = sign_dir * deg_to_rad(mag)
	_auto_t = 0.0
	_ang_vel = 0.0
	_away_time = 0.0
	_state = State.AUTO_OPENING
	is_open = true


## 兜底：直接开
func open_instant() -> void:
	open_at_angle(max_swing_deg)


## 玩家刚被传送到新房间：这段时间内不自动开门、碰撞关闭，避免把人挤出去
func begin_spawn_grace(seconds := 0.6) -> void:
	_ignore_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_collision.disabled = true
	_ang_vel = 0.0
	_state = State.FREE if absf(_angle) > deg_to_rad(2.0) else State.CLOSED


## 当前开合角度（度）
func get_angle_deg() -> float:
	return rad_to_deg(_angle)


## 推门方向符号（调试用）
func get_push_sign() -> float:
	return _push_sign


## 门板当前世界朝向（调试/测试用）
func get_leaf_world_dir() -> Vector3:
	var dir := hinge.global_transform.basis.x
	dir.y = 0.0
	return dir.normalized()


## 玩家相对本门的坐标：x=沿门板方向的横向距离，z=朝房间内的纵向距离（米）
func get_player_local_offset(player: Node3D) -> Vector3:
	var offset: Vector3 = player.global_position - global_position
	offset.y = 0.0
	var lateral := offset.dot(_closed_leaf_dir)
	var inward := offset.dot(-_outward_dir())
	return Vector3(lateral, player.global_position.y - global_position.y, inward)


## 把"相对门的坐标"换算成本门坐标系下的世界位置（严格照搬旧场景的距离）
func place_player_from_offset(offset: Vector3) -> Vector3:
	var lateral: Vector3 = _closed_leaf_dir * offset.x
	var inward: Vector3 = (-_outward_dir()) * offset.z
	return global_position + lateral + inward + Vector3.UP * offset.y


func _compute_directions() -> void:
	var outward := _outward_dir()
	var basis := hinge.global_transform.basis
	var leaf_local := Vector3(1.0, 0.0, 0.0)
	var dir_plus: Vector3 = (basis * Basis(Vector3.UP, PI / 2.0)) * leaf_local
	var dir_minus: Vector3 = (basis * Basis(Vector3.UP, -PI / 2.0)) * leaf_local
	_push_sign = 1.0 if dir_plus.dot(outward) >= dir_minus.dot(outward) else -1.0
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
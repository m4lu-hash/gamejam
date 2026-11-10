extends RigidBody3D
## 真物理门扇：RigidBody3D + 脚本实现的合页约束。
##
## 为什么不用 HingeJoint3D：这个 Godot 版本的关节在该项目里表现不可靠（最小场景复现过，
## 门根本不按预期轴旋转）。这里改用 `_integrate_forces` 手动锁死：位置钉在合页上、
## 只允许绕 Y 轴转，角速度/质量/冲量仍是真实物理。
##
## 场景结构：DoorLeaf(容器) → DoorBody(RigidBody3D，本脚本) → Leaf / CollisionShape3D
## 开门方向自动计算：门板朝"房间外"的方向 = 被推开的方向；玩家传送到达时门朝房间内。

## 被传送到新房间时，门朝房间内开着（从另一侧推过去的）
@export var arrive_opens_inward := true
## 玩家离开到多远后自动关门
@export var auto_close_distance := 2.8
## 玩家走远后多久开始自动关门（秒）
@export var auto_close_delay := 1.2
## 关门弹簧刚度 / 阻尼
@export var close_stiffness := 60.0
@export var close_damping := 8.0
## 角速度上限，防止被推飞
@export var max_angular_speed := 5.0
## 最大开合角度（度），超过就夹住
@export var max_swing_deg := 100.0
## 玩家顶着门走时施加的力矩（牛·米/秒）
@export var push_torque := 26.0
## 玩家离门多近算"在推门"
@export var push_range := 1.4
## 是否一开局就处于打开状态
@export var open_on_start := false

## 门是否处于打开状态（角度超过阈值）
var is_open := false

var _hinge_origin := Vector3.ZERO
var _closed_y := 0.0
var _closed_basis := Basis.IDENTITY
var _outward_deg := 90.0
var _inward_deg := -90.0
var _away_time := 0.0
var _closing := false
var _last_player_pos := Vector3.ZERO
var _has_last_pos := false


func _ready() -> void:
	add_to_group("door_leaf")
	_closed_y = rotation.y
	_closed_basis = global_transform.basis
	_hinge_origin = global_position
	can_sleep = false
	_compute_open_direction()
	if open_on_start:
		open_instant()


## 合页约束由场景里的 axis_lock_* 提供：锁死三轴平移 + 锁死 X/Z 旋转，只允许绕 Y 旋转。
## 设置角度必须走 _integrate_forces（物理服务器会覆盖冻结时的 transform）。

var _pending_angle := INF  # 待设置的角度（度），INF 表示没有


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	state.linear_velocity = Vector3.ZERO
	if _pending_angle != INF:
		var t := state.transform
		t.basis = _closed_basis * Basis(Vector3.UP, deg_to_rad(_pending_angle))
		state.transform = t
		state.angular_velocity = Vector3.ZERO
		_pending_angle = INF


func _physics_process(delta: float) -> void:
	var angle := _angle()

	if absf(angle) > deg_to_rad(8.0):
		is_open = true
	elif absf(angle) < deg_to_rad(2.0):
		is_open = false

	_update_auto_close(delta)
	_update_push(delta)

	# 自动关门：弹簧 + 阻尼（轴锁刚体要用角冲量，apply_torque 会被锁掉）
	if _closing:
		var torque := -angle * close_stiffness - angular_velocity.y * close_damping
		apply_torque_impulse(Vector3(0.0, torque * delta, 0.0))
		if absf(angle) < deg_to_rad(1.5) and absf(angular_velocity.y) < 0.25:
			_snap_closed()

	# 限速 + 软件限位
	if absf(angular_velocity.y) > max_angular_speed:
		angular_velocity = Vector3(angular_velocity.x, signf(angular_velocity.y) * max_angular_speed, angular_velocity.z)
	angle = _angle()
	if absf(angle) > deg_to_rad(max_swing_deg) and not _closing:
		_set_angle(signf(angle) * max_swing_deg)


func _update_auto_close(delta: float) -> void:
	var player := _find_player()
	if player == null:
		return

	var dist := global_position.distance_to(player.global_position)
	if dist > auto_close_distance:
		_away_time += delta
		if _away_time >= auto_close_delay:
			_closing = true
	else:
		_away_time = 0.0
		_closing = false


## 玩家贴着门、并且还在朝门走 -> 给门一个力矩把它顶开
## （门是轴锁刚体，线性冲量会被锁掉，只能用力矩冲量）
func _update_push(delta: float) -> void:
	var player := _find_player()
	if player == null:
		return

	var pos := player.global_position
	var move := pos - _last_player_pos
	_last_player_pos = pos
	if not _has_last_pos:
		_has_last_pos = true
		return

	move.y = 0.0
	if move.length() < 0.005:
		return

	var leaf_center: Vector3 = global_transform * Vector3(0.8, 0.0, 0.0)
	var to_leaf: Vector3 = leaf_center - pos
	to_leaf.y = 0.0
	if to_leaf.length() > push_range or to_leaf.length() < 0.001:
		return
	if move.normalized().dot(to_leaf.normalized()) < 0.3:
		return

	var torque_sign := signf(_outward_deg)
	if torque_sign == 0.0:
		torque_sign = 1.0
	apply_torque_impulse(Vector3(0.0, torque_sign * push_torque * delta, 0.0))


## 玩家刚被传送到新房间：门立刻摆到"从另一侧被推开"的姿态（朝房间内）
func open_instant() -> void:
	_set_angle(_inward_deg if arrive_opens_inward else _outward_deg)
	is_open = true
	_closing = false
	_away_time = 0.0


## 需要脚本直接开门时调用（正常玩法由玩家身体推动）
func open() -> void:
	_closing = false
	apply_torque_impulse(Vector3(0.0, deg_to_rad(_outward_deg) * 30.0, 0.0))


## 开始自动关门
func close() -> void:
	_closing = true


## 当前开合角度（度），正负表示两个方向
func get_angle_deg() -> float:
	return rad_to_deg(_angle())


func _angle() -> float:
	return wrapf(rotation.y - _closed_y, -PI, PI)


## 门板初始方向（合页指向门板中心）与"房间外"方向的夹角 = 推开角度
func _compute_open_direction() -> void:
	var room := get_tree().current_scene
	var room_center := Vector3.ZERO
	if room is Node3D:
		room_center = (room as Node3D).global_position

	var outward: Vector3 = global_position - room_center
	outward.y = 0.0
	if outward.length() < 0.01:
		outward = Vector3.FORWARD
	outward = outward.normalized()

	var leaf_dir := global_transform.basis.x
	leaf_dir.y = 0.0
	if leaf_dir.length() < 0.01:
		return
	leaf_dir = leaf_dir.normalized()

	_outward_deg = rad_to_deg(leaf_dir.signed_angle_to(outward, Vector3.UP))
	_inward_deg = -_outward_deg


func _set_angle(deg: float) -> void:
	_pending_angle = deg
	angular_velocity = Vector3.ZERO
	linear_velocity = Vector3.ZERO


func _snap_closed() -> void:
	_set_angle(0.0)
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
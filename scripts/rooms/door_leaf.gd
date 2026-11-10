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
var _has_auto_opened := false  # 第一次开门是否已经播过动画
var _closed_leaf_dir := Vector3.FORWARD
var _last_player_pos := Vector3.ZERO
var _has_last_pos := false

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
		open_with_animation(max_swing_deg)


func _physics_process(delta: float) -> void:
	var player := _find_player()
	var pushing := false
	if player != null:
		pushing = _is_pushing(player, delta)
		_update_away_time(player, delta)

	match _state:
		State.CLOSED:
			# 关着的门被推：
			#   第一次 -> 播放"自动推开"动画（第一次开门看动画）
			#   之后   -> 直接进物理状态，由玩家推
			if pushing:
				if not _has_auto_opened:
					_has_auto_opened = true
					open_with_animation(max_swing_deg, false)
				else:
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
			# 兜底：动画卡住（比如被外部改状态）超过两倍时长就强制收尾，避免门永远卡在动画里
			if _auto_t > auto_open_time * 2.0 + 0.5:
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

	# 门在自动开/关（转动）时，如果玩家就在门口，临时关掉门的碰撞，
	# 避免门板扫到角色把人弹开/甩出去；门停下后会重新打开碰撞。
	if player != null:
		var near := global_position.distance_to(player.global_position) < 2.2
		var auto_moving := _state == State.AUTO_OPENING or _state == State.CLOSING
		_collision.disabled = auto_moving and near


## 传送进房间时调用：瞬间设为指定角度（不播动画），随后进入可被玩家推的物理状态
func open_at_angle(angle_deg_arg: float) -> void:
	var mag := clampf(absf(angle_deg_arg), 0.0, max_swing_deg)
	_angle = _inward_sign * deg_to_rad(mag)
	_ang_vel = 0.0
	_auto_t = 0.0
	_away_time = 0.0
	hinge.rotation.y = _angle
	is_open = mag > 8.0
	_state = State.FREE if mag > 2.0 else State.CLOSED


## 播放"自动推开"动画，随后进入可被玩家推的物理状态
## inward=true 朝房间内开（传送到达用），false 朝房间外开（玩家推门用）
func open_with_animation(angle_deg_arg: float = 100.0, inward := true) -> void:
	var mag := clampf(absf(angle_deg_arg), 5.0, max_swing_deg)
	var sign_dir := _inward_sign if inward else _push_sign
	_auto_from = _angle
	_auto_to = sign_dir * deg_to_rad(mag)
	_auto_t = 0.0
	_ang_vel = 0.0
	_away_time = 0.0
	_state = State.AUTO_OPENING
	is_open = true


## 兜底：直接开（没有来源角度时）
func open_instant() -> void:
	open_at_angle(max_swing_deg)


## 玩家相对本门的坐标：x=沿门板方向的横向距离，z=朝房间内的纵向距离（米）
func get_player_local_offset(player: Node3D) -> Vector3:
	var offset: Vector3 = player.global_position - global_position
	offset.y = 0.0
	var lateral := offset.dot(_closed_leaf_dir)
	var inward := offset.dot(-_outward_dir())
	return Vector3(lateral, player.global_position.y - global_position.y, inward)


## 把"相对门的坐标"换算成本门坐标系下的世界位置
## 纵向距离至少留 1.9m，避免角色刷在门板旋转的扫掠范围里、被门挤着推
func place_player_from_offset(offset: Vector3) -> Vector3:
	var lateral: Vector3 = _closed_leaf_dir * offset.x
	var inward_dist := maxf(offset.z, 1.9)
	var inward: Vector3 = (-_outward_dir()) * inward_dist
	return global_position + lateral + inward + Vector3.UP * offset.y


## 当前开合角度（度）
func get_angle_deg() -> float:
	return rad_to_deg(_angle)


## 调试用：推门方向符号（+1 / -1）
func get_push_sign() -> float:
	return _push_sign


## 门板当前世界朝向（调试/测试用）
func get_leaf_world_dir() -> Vector3:
	var dir := hinge.global_transform.basis.x
	dir.y = 0.0
	return dir.normalized()


## 玩家是否在朝门走：优先用玩家的输入意图方向（被门挡住时 velocity/位移都是 0）
func _is_pushing(player: Node3D, _delta: float) -> bool:
	var dir := Vector3.ZERO
	if player.has_method("get_intended_dir"):
		dir = player.get_intended_dir()
	dir.y = 0.0
	if dir.length() < 0.01:
		return false

	var leaf_center: Vector3 = hinge.global_transform * Vector3(0.8, 0.0, 0.0)
	var to_leaf: Vector3 = leaf_center - player.global_position
	to_leaf.y = 0.0
	# 贴得极近（甚至已经和门板重叠）时不做方向判定，直接算在推门，
	# 否则玩家被门卡住时方向可能判定失败，就会"顶着门原地跑"。
	if to_leaf.length() < 0.8:
		return true
	if to_leaf.length() > push_range:
		return false
	return dir.normalized().dot(to_leaf.normalized()) >= 0.3


func _update_away_time(player: Node3D, delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	if dist > auto_close_distance:
		_away_time = minf(_away_time + delta, 999.0)
	else:
		_away_time = 0.0


func _compute_directions() -> void:
	var outward := _outward_dir()

	# 直接试：把门板绕 Y 轴转 +90° 和 -90°，哪边更接近"房间外"，哪边就是推门方向。
	# 不依赖 atan2/signed_angle_to 的符号约定。
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
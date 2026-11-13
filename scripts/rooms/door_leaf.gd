extends Node3D
## 门扇：只转 Hinge 节点的 Y 轴（合页在门框边缘），所以是绕边轴旋转。
##
## 没有"推门"了，规则很简单：
##   玩家靠近 open_range 内 -> 播放开门动画（朝房间外开，不会朝玩家扑）
##   玩家离开 auto_close_distance 外持续 auto_close_delay 秒 -> 弹簧关回去
##   传送到达时不受上述限制，由 RoomManager 调 open_at_angle() 瞬间设定角度

enum State { CLOSED, AUTO_OPENING, FREE, CLOSING }

## 开门音效（每个门自己持有一个 3D 播放器，多扇门同时开也不会互相打断）
const DOOR_OPEN_SFX = preload("res://Assets/audio/sfx/door_opening.ogg")
## 两次开门音的冷却（毫秒），防止开门/关门状态抖动时每帧重复播放
const OPEN_SFX_COOLDOWN_MSEC := 200

## 最大开合角度（度）
@export var max_swing_deg := 100.0
## 玩家进入多近的范围就自动开门
@export var open_range := 2.5
## 自动开门动画时长（秒）
@export var auto_open_time := 0.5
## 玩家离开到多远后自动关门
@export var auto_close_distance := 3.0
## 玩家走远后多久开始自动关门（秒）
@export var auto_close_delay := 1.0
## 关门弹簧刚度 / 阻尼
@export var close_stiffness := 10.0
@export var close_damp := 5.0
## 角速度上限
@export var max_angular_speed := 5.0
## 是否一开局就处于打开状态
@export var open_on_start := false

@export_group("锁")
## 是否锁着（锁着时不会自动开，必须用钥匙开锁）
@export var locked := false
## 锁的编号：钥匙的 unlock_ids 里包含它才能开
@export var lock_id: StringName = &""
## 没钥匙时的提示里显示的钥匙名（仅用于文案）
@export var key_hint := "钥匙"
## 开锁时播的对话（可空）
@export var unlock_dialogue_id: StringName = &""

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
var _lock_prompt: Label3D  # 锁着时在门上的「按 E 开锁」提示
var _door_sfx: AudioStreamPlayer3D  # 本门专属的开门音
var _last_open_sfx_msec := -1000000  # 上次播放开门音的时间戳（毫秒）

@onready var hinge: Node3D = $Hinge
@onready var _collision: CollisionShape3D = $Hinge/StaticBody3D/CollisionShape3D


func _ready() -> void:
	add_to_group("door_leaf")
	_create_door_sfx()
	hinge.rotation.y = 0.0
	_closed_leaf_dir = hinge.global_transform.basis.x
	_closed_leaf_dir.y = 0.0
	if _closed_leaf_dir.length() > 0.001:
		_closed_leaf_dir = _closed_leaf_dir.normalized()
	_compute_directions()
	# 房间场景每次进入都会重新实例化：从全局 flag 恢复“已经开过锁”的状态，
	# 否则回到房间后门又变回锁着，会重复播开锁对话、甚至把玩家关在门外。
	if lock_id != &"" and GameState.has_flag(_unlocked_flag_id()):
		locked = false
	if open_on_start:
		open_at_angle(max_swing_deg)
	_lock_prompt = Label3D.new()
	_lock_prompt.text = "按 E 开锁（需要：%s）" % key_hint
	_lock_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_lock_prompt.pixel_size = 0.008
	_lock_prompt.outline_size = 8
	_lock_prompt.position = Vector3(0.8, 2.0, 0.0)
	_lock_prompt.visible = false
	add_child(_lock_prompt)


func _physics_process(delta: float) -> void:
	var player := _find_player()
	var ignoring := Time.get_ticks_msec() < _ignore_until
	var dist := 999.0
	if player != null:
		dist = global_position.distance_to(player.global_position)

	match _state:
		State.CLOSED:
			# 靠近自动开门（朝房间外开，不会朝玩家扑）；锁着时不开
			if not ignoring and not locked and player != null and dist <= open_range:
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
			# 玩家靠近但门没全开（比如刚被中断的关门）：重新开到全开
			if player != null and dist <= open_range and absf(_angle) < deg_to_rad(max_swing_deg - 5.0):
				open_with_animation(max_swing_deg, false)
			elif dist > auto_close_distance:
				_away_time += delta
				if _away_time >= auto_close_delay:
					_state = State.CLOSING
			else:
				_away_time = 0.0
		State.CLOSING:
			_ang_vel += (-_angle * close_stiffness - _ang_vel * close_damp) * delta
			# 玩家走过来就重新打开，而不是停在半路
			if player != null and dist <= open_range:
				open_with_animation(max_swing_deg, false)
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

	# 锁着且玩家靠近时显示开锁提示
	if _lock_prompt != null:
		_lock_prompt.visible = locked and player != null and dist < 2.2
		if not locked:
			_lock_prompt.text = ""

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
	_play_open_sfx()


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


## 是否锁着
func is_locked() -> bool:
	return locked


## 尝试用一把钥匙开锁；成功返回 true 并解除锁定。
## 已经解锁的门直接返回 false：调用方（door.gd）据此避免重复 toast / 重复播对话。
func try_unlock(key: ItemData) -> bool:
	if not locked:
		return false
	if key == null or not (key is KeyData):
		return false
	if not (key as KeyData).can_unlock(lock_id):
		return false
	locked = false
	# 记录到全局 flag：房间重载后 _ready 会把 locked 恢复成 false，不再重复开锁
	if lock_id != &"":
		GameState.set_flag(_unlocked_flag_id(), true)
	# 开锁对话用非阻塞模式，避免暂停导致门不开、玩家动不了
	if unlock_dialogue_id != &"":
		UIManager.show_dialogue(unlock_dialogue_id, false)
	# 开门提示立刻消失，不等下一次 _physics_process
	if _lock_prompt != null:
		_lock_prompt.visible = false
		_lock_prompt.text = ""
	return true


## 本门对应的“已解锁”全局 flag 名（和 door.gd 里 set_flag 的规则保持一致）
func _unlocked_flag_id() -> StringName:
	return StringName("unlocked_" + String(lock_id))


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


## 创建本门专属的 3D 开门音播放器（不依赖门场景资源，实例化时就地挂上）
func _create_door_sfx() -> void:
	_door_sfx = AudioStreamPlayer3D.new()
	_door_sfx.name = "DoorOpeningSound"
	_door_sfx.stream = DOOR_OPEN_SFX
	_door_sfx.volume_db = 0.0
	_door_sfx.unit_size = 8.0
	_door_sfx.max_distance = 40.0
	# 声音放在门板中间偏上，而不是合页原点
	_door_sfx.position = Vector3(0.8, 1.2, 0.0)
	add_child(_door_sfx)


## 门开始打开时播一次（带冷却，不会每帧重复播放）
func _play_open_sfx() -> void:
	if _door_sfx == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_open_sfx_msec < OPEN_SFX_COOLDOWN_MSEC:
		return
	_last_open_sfx_msec = now
	_door_sfx.play()


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

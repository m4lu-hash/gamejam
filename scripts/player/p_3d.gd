extends CharacterBody3D

# 动画状态：对应 SophiaSkin 状态机里的 Idle / Move / Jump / Fall
enum AnimState { IDLE, MOVE, JUMP, FALL }

@export var speed = 5.0
@export var camera: Camera3D  # 在检查器里把场景中的摄像机拖进来
@export var jump_velocity = 8.0  # 跳跃初速度（米/秒）
@export var gravity_scale = 2.0  # 重力倍率：1.0 是引擎默认的 9.8，越大落地越快
@export var fall_gravity_scale = 1.35  # 下落阶段额外重力倍率，落地更干脆
@export var turn_smoothing = 10.0  # 转身插值速度，越大转得越急
@export var tilt_speed = 6.0  # run_tilt 每秒过渡量，越大倾斜回正越快
@export var tilt_full_angle = 45.0  # 转向差达到多少度时倾斜到 ±1

# 皮肤节点可能不存在（例如别的场景复用这个脚本），用 get_node_or_null 安全降级
@onready var skin: SophiaSkin = get_node_or_null("SophiaSkin") as SophiaSkin

var _anim_state := -1  # 当前动画状态，-1 表示还没跟状态机同步过
var _run_tilt := 0.0  # 跑动倾斜量（-1..1），平滑过渡后再写给皮肤
var _intended_dir := Vector3.ZERO  # 本帧输入想走的方向（被门挡住时 velocity 会被清零，门要用它判断"在推门"）
## 传送后自动走一小段：方向 / 剩余时间 / 速度
var _auto_walk_dir := Vector3.ZERO
var _auto_walk_time := 0.0
var _auto_walk_speed := 4.0

func _physics_process(delta):
	var auto_walking := _auto_walk_time > 0.0
	if auto_walking:
		_auto_walk_time -= delta
	var input_vec = Vector2.ZERO if auto_walking else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wants_move = auto_walking or input_vec.length() > 0.1
	var target_tilt = 0.0

	if wants_move:
		# 用摄像机的 basis 把输入方向转到世界空间
		var cam_basis = camera.global_transform.basis
		var forward = -cam_basis.z
		var right = cam_basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()

		var direction = _auto_walk_dir if auto_walking else (right * input_vec.x + forward * -input_vec.y).normalized()

		# 让角色平滑转向移动方向（模型正面朝 +Z，atan2 直接给出 yaw）
		var target_angle = atan2(direction.x, direction.z)

		# 倾斜量：用「还差多少角度要转」来近似转向角速度。
		# 模型自己会转向移动方向，若直接拿输入算，摆正之后会一直卡在 ±1；
		# 用角度差则只在转弯时倾斜，转正后自然回中。正数=向右转(RunTiltR)，负数=向左转(RunTiltL)
		var turn_diff = angle_difference(rotation.y, target_angle)
		target_tilt = clamp(turn_diff / deg_to_rad(tilt_full_angle), -1.0, 1.0)

		rotation.y = lerp_angle(rotation.y, target_angle, turn_smoothing * delta)

		var move_speed: float = _auto_walk_speed if auto_walking else speed
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		_intended_dir = direction
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		_intended_dir = Vector3.ZERO

	# —— 重力 ——
	if is_on_floor():
		# 贴地时清空竖直速度，避免在斜坡上越滑越快
		velocity.y = 0.0
	else:
		var gravity = get_gravity().y
		if velocity.y < 0.0:
			gravity *= fall_gravity_scale
		velocity.y += gravity * gravity_scale * delta

	# —— 跳跃：只有踩在地面上才能起跳 ——
	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	# 倾斜值平滑过渡，避免瞬变
	_run_tilt = move_toward(_run_tilt, target_tilt, tilt_speed * delta)
	if skin:
		skin.run_tilt = _run_tilt

	global_transform = global_transform.orthonormalized()
	move_and_slide()
	global_transform = global_transform.orthonormalized()
	#get_viewport().scaling_3d_scale = 0.40

	# move_and_slide 之后才判断落地/腾空，这样起跳当帧就能切到 Jump
	_update_anim_state(wants_move)

# 只在状态真正变化时才 travel，避免每帧重置动画
func _update_anim_state(wants_move: bool) -> void:
	var next_state
	if is_on_floor():
		next_state = AnimState.MOVE if wants_move else AnimState.IDLE
	elif velocity.y > 0.0:
		next_state = AnimState.JUMP
	else:
		next_state = AnimState.FALL

	if next_state == _anim_state:
		return
	_anim_state = next_state

	if skin == null:
		return  # 没有皮肤节点时安全降级，只保留移动和重力

	match next_state:
		AnimState.IDLE:
			skin.idle()
		AnimState.MOVE:
			skin.move()
		AnimState.JUMP:
			skin.jump()
		AnimState.FALL:
			skin.fall()


## 门用来判断"玩家是否正朝门走"：被门挡住时 velocity 会被 move_and_slide 清零，
## 但输入意图仍然是朝门的，所以单独暴露这个方向。
func get_intended_dir() -> Vector3:
	return _intended_dir


## 传送后自动朝某个方向走一小段（忽略玩家输入）
func start_auto_walk(dir: Vector3, duration := 0.6, walk_speed := 4.0) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_auto_walk_dir = dir.normalized()
	_auto_walk_time = duration
	_auto_walk_speed = walk_speed

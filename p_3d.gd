extends CharacterBody3D

@export var speed = 2.3
@export var camera: Camera3D  # 在检查器里把场景中的摄像机拖进来

func _physics_process(delta):
	var input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if input_vec.length() > 0.1:
		# 用摄像机的 basis 把输入方向转到世界空间
		var cam_basis = camera.global_transform.basis
		var forward = -cam_basis.z
		var right = cam_basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()

		var direction = (right * input_vec.x + forward * -input_vec.y).normalized()

		# 让角色平滑转向移动方向（模型正面朝 +Z，所以加 PI 补偿）
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	global_transform = global_transform.orthonormalized()
	move_and_slide()
	global_transform = global_transform.orthonormalized()
	get_viewport().scaling_3d_scale = 0.40

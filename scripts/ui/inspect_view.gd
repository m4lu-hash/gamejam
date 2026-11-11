class_name InspectView
extends CanvasLayer
## 3D 物品检视视图：暂停游戏，在独立 SubViewport 中展示物品模型。
## 支持按住左键拖动旋转、滚轮缩放、未拖动时缓慢自转，Esc / E 关闭。

## 关闭完成时发出，外部可据此恢复自己的 UI 状态
signal closed

## 不拖动时的自转速度（弧度 / 秒）
@export var auto_spin_speed: float = 0.3
## 拖动灵敏度（弧度 / 像素）
@export var drag_sensitivity: float = 0.01
## 滚轮每一格的缩放倍率
@export var zoom_step: float = 1.1
## 缩放范围（相对 item.inspect_scale）
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
## 垂直方向旋转限制（度）
@export_range(1.0, 89.0, 1.0) var max_pitch_degrees: float = 60.0

## 当前展示的物品
var _item: ItemData
## 基础缩放（ItemData.inspect_scale）与滚轮缩放叠加
var _base_scale: float = 1.0
var _zoom: float = 1.0
## 模型欧拉角，自己维护以避免和自转互相干扰
var _yaw: float = 0.0
var _pitch: float = 0.0
var _dragging: bool = false
var _has_model: bool = false
## 当前模型包围球半径，用于相机自适应与窗口缩放
var _fit_radius: float = 1.0
var _paused_by_me := false

@onready var _viewport_container: SubViewportContainer = $ViewportContainer
@onready var _sub_viewport: SubViewport = $ViewportContainer/SubViewport
@onready var _camera: Camera3D = $ViewportContainer/SubViewport/Camera3D
@onready var _key_light: OmniLight3D = $ViewportContainer/SubViewport/KeyLight
@onready var _fill_light: OmniLight3D = $ViewportContainer/SubViewport/FillLight
@onready var _model_root: Node3D = $ViewportContainer/SubViewport/ModelRoot
@onready var _name_label: Label = $InfoPanel/InfoVBox/NameLabel
@onready var _desc_label: RichTextLabel = $InfoPanel/InfoVBox/DescriptionLabel
@onready var _close_button: Button = $CloseButton


func _ready() -> void:
	# 暂停时依然要处理输入与渲染
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 85
	_close_button.pressed.connect(close)
	_sub_viewport.size_changed.connect(_on_sub_viewport_size_changed)
	# 环境光：即使灯光位置不对，模型也不会全黑
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9, 1)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_sub_viewport.add_child(world_env)
	# 点击背景空白处也能关闭
	var backdrop := get_node_or_null("Backdrop") as ColorRect
	if backdrop != null:
		backdrop.gui_input.connect(_on_backdrop_gui_input)
	visible = false


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## 打开检视：生成模型、按 AABB 居中、应用缩放并暂停游戏。
func open(item: ItemData) -> void:
	if item == null:
		push_warning("InspectView.open: item 为空")
		return

	_reset_model()
	_item = item
	_name_label.text = item.display_name if not item.display_name.is_empty() else String(item.id)
	_desc_label.text = item.description
	_base_scale = item.inspect_scale if item.inspect_scale > 0.0 else 1.0
	_zoom = 1.0
	_yaw = 0.0
	_pitch = 0.0

	# model_scene 为空时给一个占位方块，避免玩家看到一片空白
	if item.model_scene != null:
		_has_model = _spawn_model(item.model_scene)
	else:
		_spawn_placeholder()
		_has_model = true

	_model_root.rotation = Vector3.ZERO
	_apply_zoom()
	_viewport_container.visible = _has_model
	visible = true
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true


## 关闭检视：清空模型、取消暂停并发出 closed。
func close() -> void:
	if not visible:
		return

	_reset_model()
	_name_label.text = ""
	_desc_label.text = ""
	_viewport_container.visible = false
	visible = false
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	# 鼠标在窗口外松开时收不到抬起事件，这里兜底
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false

	if not _has_model or _dragging:
		return
	_yaw += auto_spin_speed * delta
	_model_root.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey:
		_handle_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _dragging:
		_handle_drag(event as InputEventMouseMotion)


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E or event.physical_keycode == KEY_E:
		close()
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_by(zoom_step)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_by(1.0 / zoom_step)
		get_viewport().set_input_as_handled()


func _handle_drag(event: InputEventMouseMotion) -> void:
	# 水平方向不限制圈数，垂直方向夹在 ±max_pitch_degrees
	_yaw -= event.relative.x * drag_sensitivity
	var limit := deg_to_rad(max_pitch_degrees)
	_pitch = clampf(_pitch - event.relative.y * drag_sensitivity, -limit, limit)
	_model_root.rotation = Vector3(_pitch, _yaw, 0.0)
	get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, min_zoom, max_zoom)
	_apply_zoom()


func _apply_zoom() -> void:
	var scale_value := maxf(_base_scale * _zoom, 0.001)
	_model_root.scale = Vector3.ONE * scale_value


## 实例化模型并让其 AABB 中心落在 ModelRoot 原点。
func _spawn_model(packed: PackedScene) -> bool:
	var instance := packed.instantiate()
	if instance == null:
		push_warning("InspectView: model_scene 实例化失败")
		return false

	_model_root.add_child(instance)
	var bounds := _get_model_bounds()
	if bounds.has_volume() and instance is Node3D:
		(instance as Node3D).position -= bounds.get_center()

	var radius := 1.0
	if bounds.has_volume():
		radius = maxf(bounds.size.length() * 0.5, 0.05)
	_frame_model(radius * _base_scale)
	return true


func _spawn_placeholder() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 0.7, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.6, 0.7, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.18, 0.25, 1)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	mi.mesh = mesh
	_model_root.add_child(mi)
	_frame_model(0.7)


## 遍历所有可见网格，求 ModelRoot 局部空间中的合并 AABB。
func _get_model_bounds() -> AABB:
	var result := AABB()
	var has_bounds := false
	var to_local := _model_root.global_transform.affine_inverse()
	for node in _model_root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var local_aabb := (to_local * visual.global_transform) * visual.get_aabb()
		if has_bounds:
			result = result.merge(local_aabb)
		else:
			result = local_aabb
			has_bounds = true
	return result


## 根据包围球半径调整相机和灯光，保证任何尺寸的模型都能完整入镜。
func _frame_model(radius: float) -> void:
	_fit_radius = maxf(radius, 0.05)
	_update_camera_size()

	var distance := maxf(4.0, _fit_radius * 4.0 + 2.0)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.near = 0.05
	_camera.far = distance + _fit_radius * 4.0 + 10.0

	var light_distance := maxf(2.0, _fit_radius * 3.2)
	_key_light.position = Vector3(1.0, 1.1, 1.5).normalized() * light_distance
	_fill_light.position = Vector3(-1.3, -0.1, 0.9).normalized() * light_distance
	var light_range := maxf(8.0, _fit_radius * 14.0)
	_key_light.omni_range = light_range
	_fill_light.omni_range = light_range


func _update_camera_size() -> void:
	var view_size := _sub_viewport.size
	var aspect := 1.0
	if view_size.y > 0:
		aspect = float(view_size.x) / float(view_size.y)

	# 正交相机 size 是纵向高度；留 15% 余量方便旋转
	var height := maxf(_fit_radius * 2.3, 0.05)
	if aspect > 0.0 and aspect < 1.0:
		height = maxf(height, _fit_radius * 2.3 / aspect)
	_camera.size = height


func _on_sub_viewport_size_changed() -> void:
	_update_camera_size()


func _reset_model() -> void:
	for child in _model_root.get_children():
		_model_root.remove_child(child)
		child.queue_free()
	_model_root.transform = Transform3D.IDENTITY
	_has_model = false
	_dragging = false
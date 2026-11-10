extends Node3D
## 可交互的门扇：玩家靠近后按 E 把门推开；玩家走远后自动关上。
##
## 场景结构：DoorLeaf(Node3D，本脚本) → Pivot(Node3D，绕 Y 轴旋转) → Leaf / StaticBody3D
## 摆放：本节点放在门框的合页位置，本地 +X 方向就是门板伸出的方向；
##       用 open_angle_deg 的正负控制往房间内开还是往房间外开。

## 推开的角度（绕 Y 轴，正负决定朝哪边开）
@export var open_angle_deg := 95.0
## 开关门动画时长（秒）
@export var swing_time := 0.45
## 玩家进入多近的范围后可以按 E 开门
@export var interact_range := 2.2
## 玩家离开到多远后自动关门
@export var auto_close_distance := 2.8
## 玩家走远后多久自动关门（秒）
@export var auto_close_delay := 1.0
## 是否一开局就处于打开状态
@export var open_on_start := false

@onready var pivot: Node3D = $Pivot
@onready var prompt: Label3D = get_node_or_null("Prompt")

var is_open := false
var _closed_y := 0.0
var _away_time := 0.0
var _tween: Tween


func _ready() -> void:
	add_to_group("door_leaf")
	_closed_y = pivot.rotation.y
	if open_on_start:
		open_instant()
	_update_prompt(false)


## 立刻变成打开状态（没有动画），用于玩家刚被传送到新房间、门口的"门还是开着的"
func open_instant() -> void:
	is_open = true
	_away_time = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	pivot.rotation.y = _closed_y + deg_to_rad(open_angle_deg)
	_update_prompt(false)


## 播放开门动画
func open() -> void:
	if is_open:
		return
	is_open = true
	_away_time = 0.0
	_animate_to(_closed_y + deg_to_rad(open_angle_deg))
	_update_prompt(false)


## 播放关门动画
func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate_to(_closed_y)


func _process(delta: float) -> void:
	var player := _find_player()
	if player == null:
		_update_prompt(false)
		return

	var dist := global_position.distance_to(player.global_position)
	_update_prompt(not is_open and dist <= interact_range)

	if not is_open:
		return

	if dist > auto_close_distance:
		_away_time += delta
		if _away_time >= auto_close_delay:
			_away_time = 0.0
			close()
	else:
		_away_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or is_open:
		return
	var player := _find_player()
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= interact_range:
		open()
		get_viewport().set_input_as_handled()


func _animate_to(target_y: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(pivot, "rotation:y", target_y, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _update_prompt(show_now: bool) -> void:
	if prompt != null:
		prompt.visible = show_now


func _find_player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Node3D:
		return nodes[0]
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("player") as Node3D
extends Area3D
## 通用互动区：玩家进入范围显示提示，按 E 触发。
## - toggle_target：指定一个灯光节点，按 E 开关它（用于电视/台灯）
## - sit_point：指定一个 Marker3D，按 E 把玩家移过去（坐下/躺下）
## 两者都不填时，按 E 只播放一个轻微的提示（无副作用）。

@export var prompt_text := "按 E 互动"
@export var toggle_target: NodePath
@export var sit_point: NodePath

var _prompt: Label3D
var _player: Node3D
var _inside := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.text = prompt_text
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.008
	_prompt.outline_size = 8
	_prompt.visible = false
	_prompt.position = Vector3(0.0, 1.6, 0.0)
	add_child(_prompt)


func _on_body_entered(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player = body
	_inside = true
	_prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body != _player:
		return
	_inside = false
	_player = null
	_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _inside or _player == null:
		return
	if not event.is_action_pressed("interact"):
		return
	_interact()
	get_viewport().set_input_as_handled()


func _interact() -> void:
	# 1) 开关灯光
	if not toggle_target.is_empty():
		var target := get_node_or_null(toggle_target)
		if target is Light3D:
			var light := target as Light3D
			light.visible = not light.visible
			return
	# 2) 坐下 / 躺下
	if not sit_point.is_empty():
		var point := get_node_or_null(sit_point)
		if point is Node3D and _player != null:
			var p := point as Node3D
			_player.global_position = p.global_position
			_player.rotation.y = p.rotation.y
			if _player is CharacterBody3D:
				(_player as CharacterBody3D).velocity = Vector3.ZERO
			return


func _is_player(body: Node) -> bool:
	return body is CharacterBody3D and (body.name == "player" or body.is_in_group("player"))

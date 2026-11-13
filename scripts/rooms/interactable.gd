extends Area3D
## 通用互动区：玩家进入范围显示提示，按 E 触发。
##
## 支持（按优先级）：
##   1. requires_item 不满足 → 提示缺东西
##   2. item_to_give        → 拾取进背包（可换模型 / 一次性）
##   3. dialogue_id         → 播对话
##   4. inspect_item        → 打开 360° 检视
##   5. toggle_target       → 开关灯
##   6. sit_point           → 坐下 / 躺下

@export var prompt_text := ""
@export var toggle_target: NodePath
@export var sit_point: NodePath

@export_group("对话与检视")
@export var dialogue_id: StringName = &""
@export var inspect_item: ItemData
@export var flag_to_set: StringName = &""

@export_group("拾取与容器")
@export var item_to_give: ItemData
@export var requires_item: ItemData
@export var consume_required := false
@export var consume_on_use := false
@export var swap_target: NodePath
@export var swap_scene: PackedScene
## 拾取后要一起隐藏的模型节点（比如桌面上的纸条）
@export var visual_target: NodePath
## 拾取/开容器时播放的音效名（AudioManager 里注册的）
@export var use_sound: StringName = &""
## 拾取/开容器后要显示出来的节点（例如柜子里的钥匙模型）
@export var reveal_target: NodePath

var _prompt: Label3D
var _player: Node3D
var _inside := false
var _used := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt_text.is_empty():
		prompt_text = _default_prompt()
	# 一次性互动如果已经做过了（场景重载后靠 flag / 已拾取记录判断），不再显示提示
	if _is_one_shot() and flag_to_set != &"" and GameState.has_flag(flag_to_set):
		_used = true
	if item_to_give != null and GameState.is_picked(item_to_give.id):
		_used = true
	if _used:
		_hide_visual()
		if flag_to_set != &"" and GameState.has_flag(flag_to_set):
			_reveal()
		hide()
		if swap_scene != null and not swap_target.is_empty() and flag_to_set != &"" and GameState.has_flag(flag_to_set):
			_swap_model()
	_prompt = Label3D.new()
	_prompt.text = prompt_text
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.008
	_prompt.outline_size = 8
	_prompt.visible = false
	# top_level：不继承 Area3D 的缩放/旋转，互动区缩小后文字不会跟着变小
	_prompt.top_level = true
	add_child(_prompt)


func _process(_delta: float) -> void:
	# 有 UI 打开（暂停）或这次互动已经用完时隐藏提示，避免文字叠在检视/对话画面上
	if _prompt != null:
		_prompt.global_position = global_position + Vector3(0.0, 1.6, 0.0)
		var want := _inside and not get_tree().paused and not _used
		if _prompt.visible != want:
			_prompt.visible = want


func _default_prompt() -> String:
	if requires_item != null:
		return "按 E 使用"
	if dialogue_id != &"":
		return "按 E 交谈"
	if inspect_item != null:
		return "按 E 检视"
	if item_to_give != null:
		return "按 E 拾取"
	if not toggle_target.is_empty():
		return "按 E 开关"
	if not sit_point.is_empty():
		return "按 E 使用"
	return "按 E 互动"


func _on_body_entered(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player = body
	_inside = true
	_prompt.visible = not _used and not get_tree().paused


func _on_body_exited(body: Node3D) -> void:
	if body != _player:
		return
	_inside = false
	_player = null
	_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _inside or _player == null or _used:
		return
	# 有 UI 打开（检视/背包/对话）时由 UI 处理按键，交互区不要抢
	if get_tree().paused:
		return
	if not event.is_action_pressed("interact"):
		return
	_interact()
	get_viewport().set_input_as_handled()


func _interact() -> void:
	if _used:
		return
	# 1) 前置条件
	if requires_item != null and not Inventory.has_item(requires_item.id):
		UIManager.toast("需要：" + requires_item.display_name)
		return

	# 2) 拾取 / 开容器（先给东西，再播对话）
	if item_to_give != null:
		Inventory.add(item_to_give)
		UIManager.toast("获得：" + item_to_give.display_name)
		if flag_to_set != &"":
			GameState.set_flag(flag_to_set)
		if requires_item != null and consume_required:
			Inventory.remove(requires_item.id)
		if swap_scene != null and not swap_target.is_empty():
			_swap_model()
		if dialogue_id != &"":
			UIManager.show_dialogue(dialogue_id)
		# 拾取是一次性的：标记后提示框立刻隐藏，场景重载也靠 flag 不再触发
		_consume_interaction()
		_hide_visual()
		_reveal()
		GameState.mark_picked(item_to_give.id)
		if use_sound != &"":
			var audio := get_node_or_null("/root/AudioManager")
			if audio != null and audio.has_method("play_sfx"):
				audio.call("play_sfx", use_sound)
		if consume_on_use:
			hide()
		return

	# 3) 纯对话
	if dialogue_id != &"":
		UIManager.show_dialogue(dialogue_id)
		if flag_to_set != &"":
			GameState.set_flag(flag_to_set)
		_consume_interaction()
		return

	# 4) 检视
	if inspect_item != null:
		UIManager.open_inspect(inspect_item)
		if flag_to_set != &"":
			GameState.set_flag(flag_to_set)
		_consume_interaction()
		return

	# 5) 开关灯光
	if not toggle_target.is_empty():
		var target := get_node_or_null(toggle_target)
		if target is Light3D:
			var light := target as Light3D
			light.visible = not light.visible
			return

	# 6) 坐下 / 躺下
	if not sit_point.is_empty():
		var point := get_node_or_null(sit_point)
		if point is Node3D and _player != null:
			var p := point as Node3D
			_player.global_position = p.global_position
			_player.rotation.y = p.rotation.y
			if _player is CharacterBody3D:
				(_player as CharacterBody3D).velocity = Vector3.ZERO
			return


## 这个互动是否只允许触发一次
func _is_one_shot() -> bool:
	return dialogue_id != &"" or inspect_item != null or item_to_give != null


## 标记互动已用完，并立刻隐藏「按 E …」提示
func _consume_interaction() -> void:
	_used = true
	if _prompt != null:
		_prompt.visible = false


func _swap_model() -> void:
	var target := get_node_or_null(swap_target)
	if target == null:
		return
	for child in target.get_children():
		child.queue_free()
	var inst := swap_scene.instantiate()
	target.add_child(inst)


## 隐藏拾取后应该消失的模型
func _hide_visual() -> void:
	var node := get_node_or_null(visual_target)
	if node is Node3D:
		(node as Node3D).visible = false


## 显示"容器里的东西"
func _reveal() -> void:
	var node := get_node_or_null(reveal_target)
	if node is Node3D:
		(node as Node3D).visible = true


func _is_player(body: Node) -> bool:
	return body is CharacterBody3D and (body.name == "player" or body.is_in_group("player"))

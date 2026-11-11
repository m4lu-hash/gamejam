extends Node
## 新手教程流程。Autoload 名：TutorialManager
## 顺序：开场对话 → WASD → 空格 → E 检视台灯 → I 背包 → 用纸条开文件柜

var _step := 0
var _intro_done := false
var _start_pos := Vector3.ZERO
var _tracking := false


func start() -> void:
	if GameState.has_flag(&"tutorial_seen"):
		return
	if _step != 0:
		return
	_step = 1
	UIManager.set_objective("先听他们说两句")
	UIManager.show_dialogue(&"intro_prank", false)  # 旁白不暂停，玩家可以边走边听
	DialogueManager.dialogue_finished.connect(_on_intro_done, CONNECT_ONE_SHOT)


func _on_intro_done(_id: StringName) -> void:
	_intro_done = true
	UIManager.set_objective("在房间里走两步")
	UIManager.toast("WASD 移动", 3.0)
	var p := _find_player()
	if p != null:
		_start_pos = p.global_position
		_tracking = true


func _process(_delta: float) -> void:
	if not _intro_done:
		return
	var p := _find_player()
	if p == null:
		return
	if not _tracking:
		_start_pos = p.global_position
		_tracking = true

	match _step:
		1:
			if p.global_position.distance_to(_start_pos) > 2.5:
				_step = 2
				UIManager.set_objective("试试跳跃")
				UIManager.toast("空格 跳跃", 3.0)
		2:
			if p.global_position.y > 0.25:
				_step = 3
				UIManager.set_objective("找找桌上的线索")
				UIManager.toast("走近台灯，按 E 检视", 3.5)
		3:
			if GameState.has_flag(&"tutorial_inspected"):
				_step = 4
				UIManager.set_objective("打开背包看看")
				UIManager.toast("按 I 打开背包", 3.0)
		4:
			if Inventory.has_item(&"paper"):
				_step = 5
				UIManager.set_objective("用纸条打开文件柜")
				UIManager.toast("选中纸条点「使用」，再走到文件柜按 E", 4.0)
		5:
			if GameState.has_flag(&"cabinet_opened"):
				_step = 6
				GameState.set_flag(&"tutorial_seen", true)
				UIManager.set_objective("找到逃出去的办法")
				UIManager.toast("干得漂亮。接下来，靠你自己了。", 4.0)


func _find_player() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("player") as Node3D
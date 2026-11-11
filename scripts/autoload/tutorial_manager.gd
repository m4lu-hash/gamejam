extends Node
## 新手教程流程。Autoload 名：TutorialManager
## 顺序：开场旁白 → 走到电视那边 → 跳一下 → 检视台灯 → 捡纸条 → 打开背包 → 用纸条开文件柜

var _step := 0
var _intro_done := false
var _start_pos := Vector3.ZERO
var _tracking := false


func _ready() -> void:
	# 背包/检视会暂停场景树，教程要能继续检测步骤
	process_mode = Node.PROCESS_MODE_ALWAYS


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
	_step = 2
	UIManager.set_objective("走到房间那头的电视机旁边（WASD）")
	UIManager.toast("WASD 移动，去电视机那边", 3.5)
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

	match _step:
		2:
			var tv := _find_node("TVInteract")
			if tv != null and p.global_position.distance_to(tv.global_position) < 2.2:
				_step = 3
				UIManager.set_objective("原地跳一下（空格）")
				UIManager.toast("空格 跳跃", 3.0)
		3:
			# 用「正在向上跳」的竖直速度判断，避免站在高处被误判
			var body := p as CharacterBody3D
			if body != null and body.velocity.y > 0.5:
				_step = 4
				UIManager.set_objective("回到书桌，按 E 检视台灯")
				UIManager.toast("走近台灯，按 E 检视，可以拖动看灯底", 4.0)
		4:
			if GameState.has_flag(&"tutorial_inspected"):
				_step = 5
				UIManager.set_objective("捡起桌上的纸条（按 E）")
				UIManager.toast("桌上有一张纸条，按 E 捡起来", 4.0)
		5:
			if Inventory.has_item(&"paper"):
				_step = 6
				UIManager.set_objective("按 I 打开背包")
				UIManager.toast("按 I 打开背包，看看刚捡到的纸条", 3.5)
		6:
			var ui := UIManager.inventory()
			if ui != null and ui.has_method("is_open") and bool(ui.call("is_open")):
				_step = 7
				UIManager.set_objective("选中纸条点「使用」，再走到文件柜按 E")
				UIManager.toast("选中纸条点「使用」（要点两次确认），然后去文件柜按 E", 5.0)
		7:
			if GameState.has_flag(&"cabinet_opened"):
				_step = 8
				GameState.set_flag(&"tutorial_seen", true)
				UIManager.set_objective("找到逃出去的办法")
				UIManager.toast("干得漂亮。接下来，靠你自己了。", 4.0)


func _find_player() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("player") as Node3D


func _find_node(path: String) -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var direct := scene.get_node_or_null(path) as Node3D
	if direct != null:
		return direct
	# 兼容节点挂在其它父节点下的情况（比如 TVInteract 在 TV2 下面）
	return scene.find_child(path.get_file(), true, false) as Node3D
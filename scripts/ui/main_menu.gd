extends CanvasLayer
## 开始界面：叠在游戏场景上，暂停游戏，玩家不能操作。
## 开始游戏 = 新游戏（清档）；继续游戏 = 读存档并回到存档点。

signal started

@export var continue_button: Button
@export var start_button: Button
@export var quit_button: Button

var _refs: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	# 从走廊回到 room1 时菜单不应该再出现
	if GameState.has_flag(&"menu_seen"):
		queue_free()
		return

	_refs = [continue_button, start_button, quit_button]
	for i in _refs.size():
		assert(_refs[i] != null, "MainMenu: node ref %d is null, check scene bindings" % i)

	if continue_button != null:
		continue_button.visible = SaveManager.has_progress()
	if start_button != null:
		start_button.pressed.connect(_on_new_game)
	if continue_button != null:
		continue_button.pressed.connect(_on_continue)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit)

	_hide_hud.call_deferred()
	get_tree().paused = true


func _hide_hud() -> void:
	var hud := UIManager.hud()
	if hud != null:
		hud.visible = false


func _start_common() -> void:
	GameState.set_flag(&"menu_seen", true)
	get_tree().paused = false
	var hud := UIManager.hud()
	if hud != null:
		hud.visible = true
	started.emit()
	queue_free()


func _on_new_game() -> void:
	SaveManager.delete_save()
	GameState.clear()
	if has_node("/root/MonsterManager"):
		MonsterManager.reset()
	_start_common()
	if has_node("/root/TutorialManager"):
		TutorialManager.start()


func _on_continue() -> void:
	var ok: bool = SaveManager.load_game()
	_start_common()
	if ok:
		SaveManager.respawn_at_checkpoint()


func _on_quit() -> void:
	get_tree().quit()
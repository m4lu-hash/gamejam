extends CanvasLayer
## 开始界面：直接叠在游戏场景上，暂停游戏，玩家不能操作。
## 「开始游戏」→ 取消暂停、关闭菜单、开始教程。

signal started


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	# 从走廊回到 room1 时菜单不应该再出现
	if GameState.has_flag(&"menu_seen"):
		queue_free()
		return
	# 菜单期间隐藏 HUD（延迟一帧，避免在 root setup 阶段 add_child 失败）
	_hide_hud.call_deferred()
	get_tree().paused = true


func _hide_hud() -> void:
	var hud := UIManager.hud()
	if hud != null:
		hud.visible = false
	var start_btn := get_node_or_null("Panel/Buttons/StartButton") as Button
	var quit_btn := get_node_or_null("Panel/Buttons/QuitButton") as Button
	assert(start_btn != null and quit_btn != null, "MainMenu: StartButton/QuitButton node missing")
	if start_btn != null:
		start_btn.pressed.connect(_on_start)
	if quit_btn != null:
		quit_btn.pressed.connect(_on_quit)


func _on_start() -> void:
	GameState.set_flag(&"menu_seen", true)
	get_tree().paused = false
	var hud := UIManager.hud()
	if hud != null:
		hud.visible = true
	started.emit()
	queue_free()
	if has_node("/root/TutorialManager"):
		TutorialManager.start()


func _on_quit() -> void:
	get_tree().quit()
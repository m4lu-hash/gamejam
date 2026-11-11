extends Node
## 临时集成验证（跑完即删）：走 UIManager 懒加载路径。


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var started := UIManager.show_dialogue(&"intro_prank")
	var box := UIManager.dialogue()
	await get_tree().process_frame
	if not started or box == null:
		printerr("[ITEST] FAIL 无法通过 UIManager 打开对话")
		get_tree().quit(1)
		return
	var text := box.get_node("Panel/Layout/Text") as RichTextLabel
	var ok := box.visible and get_tree().paused and text.text == "……你醒了。"
	print("[ITEST] UIManager 路径: visible=%s paused=%s text=%s" % [box.visible, get_tree().paused, text.text])
	if not ok:
		printerr("[ITEST] FAIL 状态不正确")
		get_tree().quit(1)
		return
	DialogueManager.stop()
	await get_tree().process_frame
	ok = not box.visible and not get_tree().paused
	print("[ITEST] 结束后: visible=%s paused=%s" % [box.visible, get_tree().paused])
	if ok:
		print("[ITEST] ALL PASS")
		get_tree().quit(0)
	else:
		printerr("[ITEST] FAIL 未恢复")
		get_tree().quit(1)
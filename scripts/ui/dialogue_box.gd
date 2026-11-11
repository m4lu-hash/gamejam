extends CanvasLayer
## 对话 UI：打字机、按键推进、分支选项。
## 由 UIManager 懒加载；DialogueManager 发出 line_started 后自动显示。

const TYPEWRITER_CPS := 40.0  # 打字机速度：字/秒
const CONTINUE_TEXT := "▼ 按 E 继续"

@onready var _speaker: Label = $Panel/Layout/Speaker
@onready var _text: RichTextLabel = $Panel/Layout/Text
@onready var _continue: Label = $Panel/Layout/Continue
@onready var _choices: VBoxContainer = $Panel/Layout/Choices

var _typing := false
var _awaiting_choice := false
var _type_tween: Tween
var _breath_tween: Tween
var _opened_frame := -1  # 打开对话的帧号，用于忽略触发对话的同一次按键
var blocking := true     # 是否暂停游戏（旁白可以设为 false，让玩家边走边听）
var _paused_by_me := false


func _ready() -> void:
	# 暂停时 UI 仍要处理输入与 Tween
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	visible = false
	_continue.text = CONTINUE_TEXT
	_continue.visible = false
	_choices.visible = false
	DialogueManager.line_started.connect(_on_line_started)
	DialogueManager.choices_shown.connect(_on_choices_shown)
	DialogueManager.dialogue_finished.connect(_on_dialogue_finished)


## 显示对话框并暂停游戏。对话数据仍由外部的 DialogueManager.start() 驱动。
func show_dialogue() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	if blocking:
		get_tree().paused = true
		_paused_by_me = true


## 隐藏对话框并恢复游戏。
func hide_dialogue() -> void:
	_kill_type_tween()
	_stop_breath()
	_typing = false
	_awaiting_choice = false
	_continue.visible = false
	_choices.visible = false
	_clear_choices()
	visible = false
	if _paused_by_me:
		_paused_by_me = false
		var tree := get_tree()
		if tree != null:
			tree.paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 触发对话的那一帧不响应，避免同一次 E 键被立刻当成“继续”
	if _opened_frame == Engine.get_process_frames():
		return
	if not (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		return
	get_viewport().set_input_as_handled()
	if _awaiting_choice:
		return  # 选项由按钮自己处理（鼠标 / 键盘焦点）
	if _typing:
		_finish_typing()  # 打字中：立即显示完整
	else:
		DialogueManager.advance()


func _on_line_started(speaker: String, text: String) -> void:
	show_dialogue()
	_kill_type_tween()
	_stop_breath()
	_awaiting_choice = false
	_choices.visible = false
	_clear_choices()
	_speaker.text = speaker
	_speaker.visible = not speaker.strip_edges().is_empty()
	_text.text = text
	_text.visible_ratio = 0.0
	_typing = true
	var count := _text.get_total_character_count()
	if count <= 0:
		_finish_typing()
		return
	_type_tween = create_tween()
	# 游戏暂停时 Tween 仍然运行
	_type_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_type_tween.tween_property(_text, "visible_ratio", 1.0, float(count) / TYPEWRITER_CPS).from(0.0)
	_type_tween.finished.connect(_finish_typing)


## 结束打字机：立即显示整行，并出现“继续”提示
func _finish_typing() -> void:
	_typing = false
	_kill_type_tween()
	_text.visible_ratio = 1.0
	_update_continue()


func _on_choices_shown(options: Array) -> void:
	show_dialogue()
	_typing = false
	_kill_type_tween()
	_text.visible_ratio = 1.0
	_awaiting_choice = true
	_continue.visible = false
	_stop_breath()
	_clear_choices()
	_choices.visible = true
	for i in options.size():
		var label := "……"
		var item: Variant = options[i]
		if item is Dictionary:
			var opt: Dictionary = item
			label = String(opt.get("text", "……"))
		var btn := Button.new()
		btn.text = label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choices.add_child(btn)
	# 键盘玩家可以直接用上下键选择、空格/回车确认
	if _choices.get_child_count() > 0:
		var first := _choices.get_child(0) as Button
		if first != null:
			first.grab_focus()


func _on_choice_pressed(index: int) -> void:
	if not _awaiting_choice:
		return
	_awaiting_choice = false
	DialogueManager.choose(index)


func _on_dialogue_finished(_id: StringName) -> void:
	hide_dialogue()


## “继续”提示的呼吸闪烁
func _update_continue() -> void:
	var should_show := visible and not _typing and not _awaiting_choice
	_continue.visible = should_show
	if should_show:
		_start_breath()
	else:
		_stop_breath()


func _start_breath() -> void:
	if _breath_tween != null and _breath_tween.is_valid():
		return
	_continue.modulate.a = 1.0
	_breath_tween = create_tween().set_loops()
	_breath_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_breath_tween.tween_property(_continue, "modulate:a", 0.35, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_continue, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_breath() -> void:
	if _breath_tween != null and _breath_tween.is_valid():
		_breath_tween.kill()
	_breath_tween = null
	_continue.modulate.a = 1.0


func _kill_type_tween() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
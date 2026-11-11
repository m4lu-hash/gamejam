extends Node
## 对话运行时。Autoload 名：DialogueManager
## 数据：data/dialogue/<id>.json
## {
##   "lines": [ { "speaker": "", "text": "...", "pause": 0.3, "voice": "", "next": "hint", "set_flag": "x" } ],
##   "choices": { "hint": [ { "text": "好", "next": "end", "set_flag": "y" } ] }
## }

signal line_started(speaker: String, text: String)
signal choices_shown(options: Array)
signal dialogue_finished(id: StringName)

var _lines: Array = []
var _choices: Dictionary = {}
var _options: Array = []
var _index := 0
var _active := false
var _id: StringName = &""


func is_active() -> bool:
	return _active


func start(id: StringName) -> bool:
	var path := "res://data/dialogue/%s.json" % String(id)
	if not FileAccess.file_exists(path):
		push_error("DialogueManager: 找不到对话文件 %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DialogueManager: 无法打开 %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DialogueManager: JSON 格式错误 %s" % path)
		return false

	var data: Dictionary = parsed
	_lines = data.get("lines", [])
	_choices = data.get("choices", {})
	_options = []
	_index = 0
	_id = id
	_active = true
	_show_current()
	return true


## 推进到下一行（UI 在玩家按 E/空格 时调用）
func advance() -> void:
	if not _active:
		return
	if not _options.is_empty():
		return  # 正在等待选择
	var line: Dictionary = _lines[_index] if _index < _lines.size() else {}
	_index += 1

	if line.has("next"):
		var nxt := String(line["next"])
		if nxt == "end":
			_finish()
			return
		if _choices.has(nxt):
			_show_choices(nxt)
			return
	_show_current()


## 选择分支选项
func choose(index: int) -> void:
	if not _active or index < 0 or index >= _options.size():
		return
	var opt: Dictionary = _options[index]
	_options = []
	if opt.has("set_flag"):
		GameState.set_flag(StringName(opt["set_flag"]), true)
	var nxt := String(opt.get("next", "end"))
	if nxt != "end" and _choices.has(nxt):
		_show_choices(nxt)
		return
	_finish()


func stop() -> void:
	if _active:
		_finish()


func _show_current() -> void:
	if _index >= _lines.size():
		_finish()
		return
	var line: Dictionary = _lines[_index]
	if line.has("set_flag"):
		GameState.set_flag(StringName(line["set_flag"]), true)
	var text := String(line.get("text", ""))
	line_started.emit(String(line.get("speaker", "")), text)
	# 合成旁白（噪声语音）
	var synth := get_node_or_null("/root/VoiceSynth")
	if synth != null and not text.is_empty():
		synth.call("speak", text)


func _show_choices(key: String) -> void:
	if not _choices.has(key):
		_finish()
		return
	_options = _choices[key]
	choices_shown.emit(_options)


func _finish() -> void:
	_active = false
	var finished_id := _id
	_id = &""
	_options = []
	dialogue_finished.emit(finished_id)
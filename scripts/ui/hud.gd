extends CanvasLayer
## HUD：右上角目标 + 底部临时提示

var _objective: Label
var _toast: Label
var _fade: ColorRect
var _toast_tween: Tween
var _fade_tween: Tween
var _pending_objective := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 70
	_objective = get_node_or_null("Objective") as Label
	_toast = get_node_or_null("Toast") as Label
	_fade = get_node_or_null("FadeLayer/Fade") as ColorRect
	assert(_objective != null and _toast != null, "HUD: Objective/Toast node missing")
	if _fade != null:
		_fade.modulate.a = 0.0
	if _toast != null:
		_toast.modulate.a = 0.0
	if not _pending_objective.is_empty() and _objective != null:
		_objective.text = "目标：" + _pending_objective
		_pending_objective = ""


func set_objective(text: String) -> void:
	if _objective == null:
		# 节点还没 ready（deferred add），先存下来，ready 时再显示
		_pending_objective = text
		return
	_objective.text = "目标：" + text


func toast(text: String, duration := 2.0) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(maxf(duration, 0.2))
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


## 黑屏淡入（遮住整个画面）
func fade_out(duration := 0.6) -> void:
	if _fade == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade, "modulate:a", 1.0, duration)


## 黑屏淡出
func fade_in(duration := 0.8) -> void:
	if _fade == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade, "modulate:a", 0.0, duration)
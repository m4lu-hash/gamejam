extends CanvasLayer
## HUD：右上角目标 + 底部临时提示

var _objective: Label
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 70
	_objective = get_node_or_null("Objective") as Label
	_toast = get_node_or_null("Toast") as Label
	if _toast != null:
		_toast.modulate.a = 0.0


func set_objective(text: String) -> void:
	if _objective != null:
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
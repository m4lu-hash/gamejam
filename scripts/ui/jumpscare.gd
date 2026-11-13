extends CanvasLayer
## 跳脸 Overlay：全屏图 + 变红 + 抖动 + 音效

@export var image: TextureRect
@export var red: ColorRect

var _refs: Array = []
var _shake_tween: Tween
var _base_pos := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	visible = false
	_refs = [image, red]
	for i in _refs.size():
		assert(_refs[i] != null, "Jumpscare: node ref %d is null, check scene bindings" % i)
	if red != null:
		red.visible = false
	if image != null:
		_base_pos = image.position


func play() -> void:
	visible = true
	if red != null:
		red.visible = true
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.set_loops(6)
	_shake_tween.tween_property(image, "position", _base_pos + Vector2(12, -8), 0.04)
	_shake_tween.tween_property(image, "position", _base_pos + Vector2(-14, 10), 0.04)
	_shake_tween.tween_property(image, "position", _base_pos + Vector2(8, 12), 0.04)
	_shake_tween.tween_property(image, "position", _base_pos, 0.04)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", "jumpscare")


func hide_it() -> void:
	visible = false
	if red != null:
		red.visible = false
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	if image != null:
		image.position = _base_pos
extends Area3D
## 存档点：玩家靠近按 E，保存当前进度并记录复活位置。

@export var prompt_text := "按 E 存档"
@export var respawn_offset := Vector3(0, 0, 1.0)

var _prompt: Label3D
var _player: Node3D
var _inside := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.text = prompt_text
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.pixel_size = 0.008
	_prompt.outline_size = 8
	_prompt.position = Vector3(0, 1.8, 0)
	_prompt.visible = false
	add_child(_prompt)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and (body.name == "player" or body.is_in_group("player")):
		_player = body
		_inside = true
		_prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_inside = false
		_player = null
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _inside or _player == null:
		return
	if not event.is_action_pressed("interact"):
		return
	_save()
	get_viewport().set_input_as_handled()


func _save() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var room_path := scene.scene_file_path
	var pos := global_position + respawn_offset
	SaveManager.set_checkpoint(room_path, "SpawnFromCorridor", pos)
	UIManager.toast("进度已保存", 2.0)
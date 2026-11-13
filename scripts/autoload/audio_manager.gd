extends Node
## 全局音频管理器。Autoload 名：AudioManager
##
## 负责三件事：
##   1. 统一播放 UI 点击音与通用 SFX（非 3D 的 AudioStreamPlayer，带小音效池）
##   2. 自动给场景里所有 Button 的 pressed、ItemList 的 item_selected 接点击音
##      （启动时补扫一次 + 监听 node_added，动态生成的 UI 也能覆盖）
##   3. 环境音兜底循环：OGG 导入参数里 loop=false，这里监听 finished 重播
##      （场景里名为 Ambience 的 AudioStreamPlayer 会被自动挂钩）

## 已注册的音效：名字 -> 资源路径
const SFX_PATHS := {
	&"mouse_click": "res://Assets/audio/sfx/mouse_click.ogg",
	&"door_opening": "res://Assets/audio/sfx/door_opening.ogg",
	&"cabinet_open": "res://Assets/audio/sfx/cabinet_open.ogg",
	&"cabinet_close": "res://Assets/audio/sfx/cabinet_close.ogg",
	&"monster_show": "res://Assets/audio/monster/monster_show.ogg",
	&"jumpscare": "res://Assets/audio/sfx/jumpscare.ogg",
}

## UI 点击音音量（dB）
const UI_CLICK_DB := -8.0
## 普通 SFX 音量（dB）
const SFX_DB := -4.0
## 传了世界坐标时，每远一米衰减多少 dB
const DISTANCE_FALLOFF_DB := 1.5
## 最小音量，避免远处算成 -inf
const MIN_VOLUME_DB := -40.0
## 音效池大小：允许同时叠几个音，不会互相打断
const UI_POOL_SIZE := 4
const SFX_POOL_SIZE := 6

var _streams: Dictionary = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _sfx_players: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _sfx_next := 0


func _ready() -> void:
	_build_pools()
	_load_sfx()
	# 之后进树的节点（主场景、动态生成的 UI）全部自动挂钩
	get_tree().node_added.connect(_on_node_added)
	# 已经在树里的节点补扫一遍（Autoload 比主场景先 _ready，这里兜底）
	_scan_existing.call_deferred()


## 播放一次 UI 点击音
func play_ui_click() -> void:
	if _ui_players.is_empty():
		return
	var stream: AudioStream = _streams.get(&"mouse_click")
	if stream == null:
		return
	_ui_next = (_ui_next + 1) % _ui_players.size()
	var player := _ui_players[_ui_next]
	player.stream = stream
	player.volume_db = UI_CLICK_DB
	player.play()


## 播放一个已注册的 SFX；position 传世界坐标时按与当前相机的距离衰减（非 3D 播放器）
func play_sfx(sfx_name: StringName, position: Variant = null) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null:
		push_warning("AudioManager：未注册的音效 %s" % sfx_name)
		return
	if _sfx_players.is_empty():
		return
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	var player := _sfx_players[_sfx_next]
	player.stream = stream
	player.volume_db = _volume_for_position(position)
	player.play()


func _build_pools() -> void:
	for i in UI_POOL_SIZE:
		_ui_players.append(_create_player("UIPlayer%d" % i, UI_CLICK_DB))
	for i in SFX_POOL_SIZE:
		_sfx_players.append(_create_player("SfxPlayer%d" % i, SFX_DB))


func _create_player(player_name: String, volume_db_value: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.volume_db = volume_db_value
	# 暂停时点击音也要能响
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func _load_sfx() -> void:
	for key in SFX_PATHS:
		var stream_path: String = SFX_PATHS[key]
		if not ResourceLoader.exists(stream_path):
			push_warning("AudioManager：音效文件不存在 %s" % stream_path)
			continue
		_streams[key] = load(stream_path)


func _volume_for_position(position: Variant) -> float:
	if position == null or not (position is Vector3):
		return SFX_DB
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return SFX_DB
	var world_pos: Vector3 = position
	var dist := camera.global_position.distance_to(world_pos)
	return maxf(SFX_DB - dist * DISTANCE_FALLOFF_DB, MIN_VOLUME_DB)


# ---------------------------------------------------------------- 自动挂接 UI

func _scan_existing() -> void:
	if get_tree() == null:
		return
	_scan_node(get_tree().root)


func _scan_node(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_scan_node(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)
	elif node is ItemList:
		_hook_item_list(node as ItemList)
	elif node is AudioStreamPlayer and String(node.name) == "Ambience":
		_hook_ambience(node as AudioStreamPlayer)


func _hook_button(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return
	# 避免同一个按钮被重复连接（node_added 与补扫可能都会遇到它）
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _hook_item_list(list: ItemList) -> void:
	if list == null or not is_instance_valid(list):
		return
	if not list.item_selected.is_connected(_on_item_selected):
		list.item_selected.connect(_on_item_selected)


func _hook_ambience(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_meta(&"_audio_manager_looping"):
		return
	player.set_meta(&"_audio_manager_looping", true)
	player.finished.connect(_on_ambience_finished.bind(player))
	# autoplay 在暂停的树里不会启动（room1 开局的 MainMenu 会暂停），这里补一次
	_ensure_ambience_playing.bind(player).call_deferred()


func _ensure_ambience_playing(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player) or player.stream == null:
		return
	if not player.playing:
		player.play()


func _on_button_pressed() -> void:
	play_ui_click()


func _on_item_selected(_index: int) -> void:
	play_ui_click()


## OGG 导入里 loop=false，播完手动重播实现循环
func _on_ambience_finished(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player) or player.stream == null:
		return
	player.play()
## 停止某个音效（正在播放的池子播放器）
func stop_sfx(sfx_name: StringName) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null:
		return
	for player in _sfx_players:
		if player.playing and player.stream == stream:
			player.stop()


## 停止全部普通音效
func stop_all_sfx() -> void:
	for player in _sfx_players:
		player.stop()

## 带淡出停止某个音效（用于跳脸声太长的情况）
func fade_out_sfx(sfx_name: StringName, duration := 0.8) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null:
		return
	for player in _sfx_players:
		if not player.playing or player.stream != stream:
			continue
		var tw := player.create_tween()
		tw.tween_property(player, "volume_db", -60.0, duration)
		tw.tween_callback(player.stop)

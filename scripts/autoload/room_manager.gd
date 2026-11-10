extends Node
## 房间切换管理器（Autoload：RoomManager）
##
## 无缝切换的做法：先把新房间实例化并挂进场景树，同一帧内再释放旧房间，
## 中间不插入黑屏/加载画面，所以玩家从门口走出去会立刻出现在另一个房间的门口。
##
## 用法：门口 Area3D 里调用 RoomManager.change_room(packed_scene, "出生点名字")

## 切换后的保护时间（毫秒），避免刚落地就被门口再触发一次
const ENTER_GRACE_MSEC := 600

var is_changing := false
var last_change_msec := -1000000
var current_room := ""


## 切换到 packed 场景，并把玩家放到目标场景里名为 spawn_name 的 Marker3D 上
func change_room(packed: PackedScene, spawn_name: String = "") -> void:
	if is_changing or packed == null:
		return

	is_changing = true

	var tree := get_tree()
	var old_scene := tree.current_scene
	var old_player := _find_player(old_scene)

	# 记录出发门的开合角度 + 玩家相对这扇门的位置（传送后要一模一样）
	var source_angle := 0.0
	var has_source_angle := false
	var source_offset := Vector3.ZERO
	var has_source_offset := false
	if old_player != null:
		var src_door := _nearest_door_to(old_player, old_scene)
		if src_door != null:
			if src_door.has_method("get_angle_deg"):
				source_angle = absf(src_door.get_angle_deg())
				has_source_angle = true
			if src_door.has_method("get_player_local_offset"):
				source_offset = src_door.get_player_local_offset(old_player)
				has_source_offset = true

	var new_scene := packed.instantiate()

	# 先把新房间挂进来（旧房间还在，屏幕上不会出现空帧）
	tree.root.add_child(new_scene)
	tree.current_scene = new_scene

	var new_player := _find_player(new_scene)

	_apply_spawn(new_player, new_scene, spawn_name)
	_open_nearest_door(new_player, new_scene, source_angle, has_source_angle, source_offset, has_source_offset)

	# 继承原来的速度：切换后角色继续沿原方向走，手感更连贯
	if old_player is CharacterBody3D and new_player is CharacterBody3D:
		(new_player as CharacterBody3D).velocity = (old_player as CharacterBody3D).velocity

	if old_scene != null:
		old_scene.queue_free()

	if new_scene is Node:
		current_room = new_scene.scene_file_path
	last_change_msec = Time.get_ticks_msec()
	is_changing = false


func _apply_spawn(player: Node3D, scene: Node, spawn_name: String) -> void:
	if player == null or spawn_name.is_empty():
		return

	var marker := scene.find_child(spawn_name, true, false)
	if marker is not Node3D:
		push_warning("RoomManager: 目标房间缺少出生点：%s" % spawn_name)
		return

	var target := marker as Node3D
	player.global_position = target.global_position
	player.rotation.y = target.rotation.y
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


func _find_player(root: Node) -> Node3D:
	if root == null:
		return null
	var direct := root.get_node_or_null("player")
	if direct is Node3D:
		return direct
	for node in root.find_children("*", "CharacterBody3D", true, false):
		if node.name == "player" or node.is_in_group("player"):
			return node
	return null


## 玩家刚落到新房间时，把离他最近的那扇门立刻打开（"像上个场景一样是被推开的"）；
## 之后门自己会在玩家走远时自动关上。
func _open_nearest_door(player: Node3D, scene: Node, source_angle := 0.0, has_source_angle := false, source_offset := Vector3.ZERO, has_source_offset := false) -> void:
	if player == null:
		return

	var nearest := _nearest_door_to(player, scene)
	if nearest == null:
		return

	# 复制旧门的开合角度；角度太小（玩家几乎贴着关着的门挤过去）就按全开处理
	var angle := 100.0
	if has_source_angle and source_angle >= 20.0:
		angle = source_angle

	# 瞬间就是那个角度，不播动画
	if nearest.has_method("open_at_angle"):
		nearest.open_at_angle(angle)
	elif nearest.has_method("open_instant"):
		nearest.open_instant()

	# 用旧场景里"玩家相对门的位置"来摆放新玩家：距离/方位保持一致
	if has_source_offset and nearest.has_method("place_player_from_offset"):
		var pos: Vector3 = nearest.place_player_from_offset(source_offset)
		player.global_position = pos

	# 传送后朝角色面朝的方向自动走一小段（忽略玩家输入），把角色带离门口
	if player.has_method("start_auto_walk"):
		var facing: Vector3 = player.global_transform.basis.z
		facing.y = 0.0
		if facing.length() > 0.01:
			player.start_auto_walk(facing.normalized())


func _nearest_door_to(target: Node3D, root: Node = null) -> Node3D:
	var nearest: Node3D = null
	var best := 3.2
	for node in get_tree().get_nodes_in_group("door_leaf"):
		if node is not Node3D:
			continue
		# 只认 root 场景里的门：换场瞬间旧场景还没释放，组里会有两套门
		if root != null and not root.is_ancestor_of(node):
			continue
		var door := node as Node3D
		var dist := door.global_position.distance_to(target.global_position)
		if dist < best:
			best = dist
			nearest = door
	return nearest

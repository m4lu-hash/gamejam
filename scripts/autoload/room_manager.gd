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

## 每次换场的序号：配合 _clear_changing_guard 的延迟兜底，避免旧的一次兜底
## 把后来新发起的换场状态提前清掉。
var _change_token := 0


## 切换到 packed 场景，并把玩家放到目标场景里名为 spawn_name 的 Marker3D 上
func change_room(packed: PackedScene, spawn_name: String = "") -> void:
	if is_changing or packed == null:
		return

	# 先实例化并校验，所有可能失败的步骤都放在设置 is_changing 之前
	var new_scene := packed.instantiate()
	if new_scene == null:
		push_error("RoomManager: 目标场景实例化失败：%s" % packed.resource_path)
		return

	is_changing = true
	_change_token += 1
	var token := _change_token
	# 兜底：即使换场过程中出现运行时错误导致函数提前中断，也会在帧末复位，
	# 不会让 is_changing 永久卡 true 把后续所有换场都堵死。
	_clear_changing_guard.call_deferred(token)

	var tree := get_tree()
	var old_scene := tree.current_scene
	var old_player := _find_player(old_scene)

	# 记录出发门的开合角度：到达后复制给目标门，看起来像“门一直开着”
	var source_angle := 0.0
	var has_source_angle := false
	if old_player != null and old_scene != null:
		var src_door := _nearest_door_to(old_player, old_scene)
		if src_door != null and src_door.has_method("get_angle_deg"):
			source_angle = absf(float(src_door.call("get_angle_deg")))
			has_source_angle = true

	# 从换场开始就进入保护期，避免新场景门触发器在落地同一帧再次触发
	last_change_msec = Time.get_ticks_msec()

	# 先把新房间挂进来（旧房间还在，屏幕上不会出现空帧）
	tree.root.add_child(new_scene)
	tree.current_scene = new_scene

	var new_player := _find_player(new_scene)

	# 出生点以目标场景的 Marker3D 为准（房间重载后依然存在，且一定在房间内侧）。
	# 不再用旧场景的相对坐标反推位置：那个算法依赖“房间中心”近似，侧门会把
	# 玩家放到门外/地板外，落地后自动走一段也可能摔出场景。
	_apply_spawn(new_player, new_scene, spawn_name)
	_open_nearest_door(new_player, new_scene, source_angle, has_source_angle)

	# 出生后速度清零：不继承旧速度，避免角色继续朝旧门方向漂回触发区（表现为"出门又回到原房间"）
	if new_player is CharacterBody3D:
		(new_player as CharacterBody3D).velocity = Vector3.ZERO

	if old_scene != null:
		old_scene.queue_free()

	current_room = new_scene.scene_file_path
	is_changing = false


## 延迟兜底：正常情况下换场已经同步结束（is_changing 已经是 false），这里什么也不做。
func _clear_changing_guard(token: int) -> void:
	if is_changing and token == _change_token:
		push_warning("RoomManager: 换场未正常结束，已复位 is_changing")
		is_changing = false


func _apply_spawn(player: Node3D, scene: Node, spawn_name: String) -> void:
	if player == null:
		push_warning("RoomManager: 目标场景里没有 player 节点")
		return

	var marker: Node3D = null
	if not spawn_name.is_empty():
		marker = scene.find_child(spawn_name, true, false) as Node3D
		if marker == null:
			push_warning("RoomManager: 目标房间缺少出生点：%s，改用场景内的 Spawn 兜底" % spawn_name)
	# 出生点名字写错时也不要让玩家留在场景默认原点：任选一个 Spawn* 标记兜底
	if marker == null:
		marker = _find_fallback_spawn(scene)
	if marker == null:
		push_warning("RoomManager: 目标房间没有任何 Spawn 标记，保留场景默认位置")
		return

	player.global_position = marker.global_position
	player.rotation.y = marker.rotation.y
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


func _find_fallback_spawn(scene: Node) -> Node3D:
	for node in scene.find_children("*", "Marker3D", true, false):
		if node is Node3D and String(node.name).begins_with("Spawn"):
			return node as Node3D
	return null


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
func _open_nearest_door(player: Node3D, scene: Node, source_angle := 0.0, has_source_angle := false) -> void:
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

	# 出生保护期：这段时间内门不响应推门、碰撞关闭，让角色先走开
	if nearest.has_method("begin_spawn_grace"):
		nearest.begin_spawn_grace(0.6)

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
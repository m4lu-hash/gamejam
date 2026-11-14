extends Node
## room3 随机门：两扇门（都通往走廊）只显示一扇，黑屏后随机切换。
## 隐藏的那扇门用 Blocker 挡住门洞，避免玩家从"没有门的洞"走出去。

@export var door_a: Node3D
@export var trigger_a: Node
@export var blocker_a: Node3D
@export var hole_a: Node3D
@export var door_b: Node3D
@export var trigger_b: Node
@export var blocker_b: Node3D
@export var hole_b: Node3D

var _pairs: Array = []


func _ready() -> void:
	randomize()
	# 场景里 node_paths 偶尔没绑定成功，按名字兜底解析
	var root := get_parent()
	if root != null:
		if door_a == null:
			door_a = root.get_node_or_null("Doors/DoorLeafLeft") as Node3D
		if trigger_a == null:
			trigger_a = root.get_node_or_null("Doors/DoorToCorridor")
		if door_b == null:
			door_b = root.get_node_or_null("Doors/DoorLeafAlt") as Node3D
		if trigger_b == null:
			trigger_b = root.get_node_or_null("Doors/DoorToCorridorAlt")
		if blocker_a == null:
			blocker_a = root.get_node_or_null("BlockerA") as Node3D
		if blocker_b == null:
			blocker_b = root.get_node_or_null("BlockerB") as Node3D
		if hole_a == null:
			hole_a = root.get_node_or_null("Geometry/DoorWall_X/DoorHole") as Node3D
		if hole_b == null:
			hole_b = root.get_node_or_null("Geometry/DoorWall_Z/DoorHoleZ") as Node3D
	_pairs = [
		[door_a, trigger_a, blocker_a, hole_a],
		[door_b, trigger_b, blocker_b, hole_b],
	]
	shuffle()


## 随机只激活其中一扇
func shuffle() -> void:
	if _pairs.is_empty():
		return
	var pick := randi() % _pairs.size()
	for i in _pairs.size():
		_set_pair(_pairs[i][0], _pairs[i][1], _pairs[i][2], _pairs[i][3], i == pick)


func _set_pair(door: Node3D, trigger: Node, blocker: Node3D, hole: Node3D, active: bool) -> void:
	if door != null and is_instance_valid(door):
		if door.has_method("set_active"):
			door.call("set_active", active)
		else:
			door.visible = active
	if trigger != null and is_instance_valid(trigger):
		if "monitoring" in trigger:
			trigger.set("monitoring", active)
		var cs := trigger.get_node_or_null("Trigger") as CollisionShape3D
		if cs != null:
			cs.disabled = not active
	if blocker != null and is_instance_valid(blocker):
		var shape := blocker.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape != null:
			shape.disabled = active
	# 隐藏门时把墙洞也补上，看起来就是一整面墙
	if hole != null and is_instance_valid(hole):
		hole.visible = active
extends Node
## room3 随机门：两扇门（都通往走廊）轮流出现，每次黑屏后换另一扇。
## 门洞一直保留；隐藏的那扇门用墙板(Plug)挡住、Blocker 封路。

@export var door_a: Node3D
@export var trigger_a: Node
@export var blocker_a: Node3D
@export var plug_a: Node3D
@export var door_b: Node3D
@export var trigger_b: Node
@export var blocker_b: Node3D
@export var plug_b: Node3D

var _pairs: Array = []
var _index := 0


func _ready() -> void:
	randomize()
	var root := get_parent()
	if root != null:
		if door_a == null:
			door_a = root.get_node_or_null("Doors/DoorLeafLeft") as Node3D
		if trigger_a == null:
			trigger_a = root.get_node_or_null("Doors/DoorToCorridor")
		if blocker_a == null:
			blocker_a = root.get_node_or_null("BlockerA") as Node3D
		if plug_a == null:
			plug_a = root.get_node_or_null("PlugA") as Node3D
		if door_b == null:
			door_b = root.get_node_or_null("Doors/DoorLeafAlt") as Node3D
		if trigger_b == null:
			trigger_b = root.get_node_or_null("Doors/DoorToCorridorAlt")
		if blocker_b == null:
			blocker_b = root.get_node_or_null("BlockerB") as Node3D
		if plug_b == null:
			plug_b = root.get_node_or_null("PlugB") as Node3D
	_pairs = [
		[door_a, trigger_a, blocker_a, plug_a],
		[door_b, trigger_b, blocker_b, plug_b],
	]
	_index = randi() % maxi(_pairs.size(), 1)
	_apply()


## 切到下一扇（轮流出现）
func shuffle() -> void:
	if _pairs.is_empty():
		return
	_index = (_index + 1) % _pairs.size()
	_apply()


func _apply() -> void:
	for i in _pairs.size():
		_set_pair(_pairs[i][0], _pairs[i][1], _pairs[i][2], _pairs[i][3], i == _index)


func _set_pair(door: Node3D, trigger: Node, blocker: Node3D, plug: Node3D, active: bool) -> void:
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
	# 隐藏门时用墙板把门洞遮住
	if plug != null and is_instance_valid(plug):
		plug.visible = not active
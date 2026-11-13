extends Node
## room3 随机门：两扇门（都通往走廊）只显示一扇，黑屏后随机切换。

@export var door_a: Node3D
@export var trigger_a: Node
@export var door_b: Node3D
@export var trigger_b: Node

var _pairs: Array = []


func _ready() -> void:
	randomize()
	# 场景里 node_paths 偶尔没绑定成功，按名字兜底解析
	var root := get_parent()
	if door_a == null and root != null:
		door_a = root.get_node_or_null("Doors/DoorLeafLeft") as Node3D
	if trigger_a == null and root != null:
		trigger_a = root.get_node_or_null("Doors/DoorToCorridor")
	if door_b == null and root != null:
		door_b = root.get_node_or_null("Doors/DoorLeafAlt") as Node3D
	if trigger_b == null and root != null:
		trigger_b = root.get_node_or_null("Doors/DoorToCorridorAlt")
	_pairs = [
		[door_a, trigger_a],
		[door_b, trigger_b],
	]
	shuffle()


## 随机只激活其中一扇
func shuffle() -> void:
	if _pairs.is_empty():
		return
	var pick := randi() % _pairs.size()
	for i in _pairs.size():
		_set_pair(_pairs[i][0], _pairs[i][1], i == pick)


func _set_pair(door: Node3D, trigger: Node, active: bool) -> void:
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
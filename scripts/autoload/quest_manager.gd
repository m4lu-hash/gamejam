extends Node
## 实时目标：根据 GameState / Inventory 计算右上角显示的下一步。
## 教程期间不接管（由 TutorialManager 显示小步骤）；教程结束后按进度自动更新。

const REFRESH := 0.3

var _timer := 0.0
var _last := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH:
		return
	_timer = 0.0
	var text := compute_objective()
	if text == _last:
		return
	_last = text
	if not text.is_empty():
		UIManager.set_objective(text)


## 当前应该显示的目标（空字符串 = 不接管）
func compute_objective() -> String:
	if not GameState.has_flag(&"tutorial_seen"):
		return ""

	# 1) room1 的门
	if not GameState.has_flag(&"unlocked_room1_door"):
		if Inventory.has_item(&"rusty_key"):
			return "用锈钥匙打开房间1的门"
		return "在房间1里找到钥匙"

	# 2) room2 的黄铜钥匙
	if not Inventory.has_item(&"bronze_key"):
		return "去中间的房间找黄铜钥匙"

	# 3) room3 的门
	if not GameState.has_flag(&"unlocked_room3_door"):
		return "用黄铜钥匙打开最左边的门"

	# 4) room3 的下一层钥匙
	if not GameState.has_flag(&"key_taken"):
		return "在最左边的房间找到下一层的钥匙"

	# 5) 拿到钥匙后
	return "找到下一层的出口"
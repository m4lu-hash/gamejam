extends GridMap
## room3 地板修正：把 (0,0,-1) 那个"洞"格子换回普通地板，
## 否则玩家去后墙那扇门时会掉下去。

func _ready() -> void:
	set_cell_item(Vector3i(0, 0, -1), 0)
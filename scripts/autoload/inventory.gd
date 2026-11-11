extends Node
## 背包数据。Autoload 名：Inventory

signal changed
signal item_added(item: ItemData)

var items: Array[ItemData] = []


func add(item: ItemData) -> bool:
	if item == null:
		return false
	items.append(item)
	item_added.emit(item)
	changed.emit()
	return true


func remove(id: StringName) -> bool:
	for i in range(items.size()):
		if items[i] != null and items[i].id == id:
			items.remove_at(i)
			changed.emit()
			return true
	return false


func has_item(id: StringName) -> bool:
	return get_item(id) != null


func get_item(id: StringName) -> ItemData:
	for item in items:
		if item != null and item.id == id:
			return item
	return null


func clear() -> void:
	items.clear()
	changed.emit()

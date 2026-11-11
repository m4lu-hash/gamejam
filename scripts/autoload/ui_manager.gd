extends Node
## UI 总入口。Autoload 名：UIManager
## 懒加载并持有：HUD、背包、检视、对话框。其它系统只通过这里调用 UI。

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const INVENTORY_SCENE := "res://scenes/ui/inventory.tscn"
const INSPECT_SCENE := "res://scenes/ui/inspect_view.tscn"
const DIALOGUE_SCENE := "res://scenes/ui/dialogue_box.tscn"

var _hud: CanvasLayer
var _inventory: CanvasLayer
var _inspect: CanvasLayer
var _dialogue: CanvasLayer


func _ready() -> void:
	# 开局就把背包/对话框实例化好，否则按 I 时节点还不存在，输入没人接
	_warm_up.call_deferred()


func _warm_up() -> void:
	hud()
	inventory()
	dialogue()


func hud() -> CanvasLayer:
	if _hud == null or not is_instance_valid(_hud):
		_hud = _ensure(HUD_SCENE)
	return _hud


func inventory() -> CanvasLayer:
	if _inventory == null or not is_instance_valid(_inventory):
		_inventory = _ensure(INVENTORY_SCENE)
		if _inventory != null and _inventory.has_signal("use_requested"):
			_inventory.connect("use_requested", Callable(self, "_on_item_used"))
	return _inventory


## 背包里点「使用」→ 关背包、打开该物品的检视
func _on_item_used(item: ItemData) -> void:
	if _inventory != null and _inventory.has_method("close"):
		_inventory.call("close")
	open_inspect(item)


func inspect() -> CanvasLayer:
	if _inspect == null or not is_instance_valid(_inspect):
		_inspect = _ensure(INSPECT_SCENE)
	return _inspect


func dialogue() -> CanvasLayer:
	if _dialogue == null or not is_instance_valid(_dialogue):
		_dialogue = _ensure(DIALOGUE_SCENE)
	return _dialogue


## 打开检视
func open_inspect(item: ItemData) -> void:
	var view := inspect()
	if view != null and view.has_method("open"):
		view.call("open", item)


## 打开/关闭背包
func toggle_inventory() -> void:
	var ui := inventory()
	if ui == null:
		return
	if ui.has_method("toggle"):
		ui.call("toggle")
	elif ui.has_method("open") and ui.has_method("close"):
		if ui.get("visible"):
			ui.call("close")
		else:
			ui.call("open")


## 开始一段对话；blocking=false 时不暂停游戏（用于开场旁白）
func show_dialogue(id: StringName, blocking := true) -> bool:
	var box := dialogue()
	if box == null:
		return false
	if "blocking" in box:
		box.set("blocking", blocking)
	return DialogueManager.start(id)


## HUD：目标文字
func set_objective(text: String) -> void:
	var h := hud()
	if h != null and h.has_method("set_objective"):
		h.call("set_objective", text)


## HUD：底部提示
func toast(text: String, duration := 2.0) -> void:
	var h := hud()
	if h != null and h.has_method("toast"):
		h.call("toast", text, duration)


func _ensure(path: String) -> CanvasLayer:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var inst := packed.instantiate()
	if inst == null:
		return null
	get_tree().root.add_child(inst)
	return inst as CanvasLayer
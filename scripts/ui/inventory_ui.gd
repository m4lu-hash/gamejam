extends CanvasLayer
## 背包界面：显示 Inventory 里的物品，支持悬停 / 选中查看详情。
## 本界面只负责发 use_requested，真正的使用效果由外部连接处理。

signal use_requested(item: ItemData)

## 场景里固定的节点路径
const ITEM_LIST_PATH := "Center/Panel/Margin/Columns/Left/ItemList"
const EMPTY_LABEL_PATH := "Center/Panel/Margin/Columns/Left/EmptyLabel"
const ICON_PATH := "Center/Panel/Margin/Columns/Right/Icon"
const NAME_PATH := "Center/Panel/Margin/Columns/Right/ItemName"
const DESC_PATH := "Center/Panel/Margin/Columns/Right/Description"
const USE_BUTTON_PATH := "Center/Panel/Margin/Columns/Right/Actions/UseButton"
const CANCEL_BUTTON_PATH := "Center/Panel/Margin/Columns/Right/Actions/CancelButton"
const WARNING_PATH := "Center/Panel/Margin/Columns/Right/WarningLabel"

var _is_open := false
var _hovered_index := -1
var _confirming := false
var _confirm_item: ItemData = null
var _warning_serial := 0
var _paused_by_me := false
var _refs: Array = []

var _item_list: ItemList
var _empty_label: Label
var _icon: TextureRect
var _item_name: Label
var _description: RichTextLabel
var _use_button: Button
var _cancel_button: Button
var _warning_label: Label


func _ready() -> void:
	# 暂停时也要能响应输入，节点自身必须 ALWAYS（场景里也设置了）
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	visible = false

	_item_list = get_node_or_null(ITEM_LIST_PATH) as ItemList
	_empty_label = get_node_or_null(EMPTY_LABEL_PATH) as Label
	_icon = get_node_or_null(ICON_PATH) as TextureRect
	_item_name = get_node_or_null(NAME_PATH) as Label
	_description = get_node_or_null(DESC_PATH) as RichTextLabel
	_use_button = get_node_or_null(USE_BUTTON_PATH) as Button
	_cancel_button = get_node_or_null(CANCEL_BUTTON_PATH) as Button
	_warning_label = get_node_or_null(WARNING_PATH) as Label

	_refs = [_item_list, _empty_label, _icon, _item_name, _description, _use_button, _cancel_button, _warning_label]
	for i in _refs.size():
		assert(_refs[i] != null, "InventoryUI: node ref %d is null, check scene paths" % i)

	if _item_list != null:
		_item_list.item_selected.connect(_on_item_selected)
		_item_list.gui_input.connect(_on_item_list_gui_input)
		_item_list.mouse_exited.connect(_on_item_list_mouse_exited)
	if _use_button != null:
		_use_button.pressed.connect(_on_use_pressed)
	if _cancel_button != null:
		_cancel_button.pressed.connect(_reset_confirm)

	Inventory.changed.connect(_on_inventory_changed)
	_refresh_list()


## 打开背包：显示界面并暂停游戏
func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_clear_warning()
	_refresh_list()
	_reset_confirm()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	if _item_list != null and _item_list.item_count > 0:
		_item_list.grab_focus()


## 关闭背包：隐藏界面并恢复游戏
func close() -> void:
	if not _is_open:
		visible = false
		return
	_is_open = false
	_hovered_index = -1
	_reset_confirm()
	_clear_warning()
	_refresh_details()
	visible = false
	if _item_list != null:
		_item_list.release_focus()
	if _paused_by_me:
		_paused_by_me = false
		get_tree().paused = false


## 供 UIManager / 快捷键调用
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func is_open() -> bool:
	return _is_open


func _input(event: InputEvent) -> void:
	# 用 _input 而不是 _unhandled_input：ItemList 获得焦点时也可能吃掉按键
	if event.is_action_pressed("inventory"):
		# 别的原因（主菜单、剧情）已经暂停时不要抢 I 键
		if not _is_open and get_tree().paused:
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	# 确认状态下按 Esc 只取消确认，不关背包
	if _is_open and _confirming and event.is_action_pressed("ui_cancel"):
		_reset_confirm()
		get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	if _is_open:
		_refresh_list()


## 重建列表；尽量保留当前选中物品
func _refresh_list() -> void:
	if _item_list == null:
		return

	var keep_id: StringName = &""
	var current := _displayed_item()
	if current != null:
		keep_id = current.id

	_item_list.clear()
	_hovered_index = -1
	for item in Inventory.items:
		if item == null:
			continue
		var index := _item_list.add_item(item.display_name)
		_item_list.set_item_metadata(index, item)
		if item.icon != null:
			_item_list.set_item_icon(index, item.icon)

	var has_items := _item_list.item_count > 0
	_item_list.visible = has_items
	if _empty_label != null:
		_empty_label.visible = not has_items

	if not has_items:
		_reset_confirm()
		_refresh_details()
		return

	var target := 0
	if keep_id != &"":
		for i in range(_item_list.item_count):
			var data := _item_list.get_item_metadata(i) as ItemData
			if data != null and data.id == keep_id:
				target = i
				break
	_item_list.select(target)
	_reset_confirm()
	_refresh_details()


## 当前要展示的物品：优先鼠标悬停项，否则取选中项
func _displayed_item() -> ItemData:
	if _item_list == null:
		return null
	var index := _hovered_index
	if index < 0:
		var selected := _item_list.get_selected_items()
		if selected.is_empty():
			return null
		index = selected[0]
	if index < 0 or index >= _item_list.item_count:
		return null
	return _item_list.get_item_metadata(index) as ItemData


func _refresh_details() -> void:
	var item := _displayed_item()
	if _icon != null:
		_icon.texture = item.icon if item != null else null
	if _item_name != null:
		_item_name.text = item.display_name if item != null else ""
	if _description != null:
		_description.text = item.description if item != null else ""
	_update_use_controls()


func _update_use_controls() -> void:
	if _use_button == null:
		return
	_use_button.disabled = _displayed_item() == null
	_use_button.text = "确认使用？" if _confirming else "使用"
	if _cancel_button != null:
		_cancel_button.visible = _confirming


func _on_item_selected(_index: int) -> void:
	_hovered_index = -1
	_reset_confirm()
	_refresh_details()


func _on_item_list_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	var motion := event as InputEventMouseMotion
	_set_hovered(_item_list.get_item_at_position(motion.position, true))


func _on_item_list_mouse_exited() -> void:
	_set_hovered(-1)


func _set_hovered(index: int) -> void:
	if index == _hovered_index:
		return
	_hovered_index = index
	_reset_confirm()
	_refresh_details()


func _on_use_pressed() -> void:
	var item := _displayed_item()
	if item == null:
		return
	# 不能用：只提示，不进入确认（顺便清掉可能残留的确认状态）
	if not item.can_use:
		_reset_confirm()
		_show_warning("现在还不能使用")
		return
	# 第二次点击才真正发出使用信号
	if _confirming and _confirm_item == item:
		_reset_confirm()
		use_requested.emit(item)
		return
	_confirming = true
	_confirm_item = item
	_update_use_controls()


## 取消 / 切换物品 / 关闭时重置二次确认
func _reset_confirm() -> void:
	_confirming = false
	_confirm_item = null
	_update_use_controls()


func _show_warning(text: String) -> void:
	if _warning_label == null:
		return
	_warning_serial += 1
	var serial := _warning_serial
	_warning_label.text = text
	_warning_label.visible = true
	# process_always = true：背包暂停游戏时计时器照常走
	var timer := get_tree().create_timer(2.0, true)
	timer.timeout.connect(_on_warning_timeout.bind(serial))


func _on_warning_timeout(serial: int) -> void:
	if serial != _warning_serial:
		return
	if _warning_label != null:
		_warning_label.text = ""
		_warning_label.visible = false


func _clear_warning() -> void:
	_warning_serial += 1
	if _warning_label != null:
		_warning_label.text = ""
		_warning_label.visible = false
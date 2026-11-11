class_name ItemData
extends Resource
## 物品数据：背包、检视、拾取都用它

## 唯一标识（存档 / 条件判断用）
@export var id: StringName = &""
## 显示名字
@export var display_name: String = ""
## 详情 / 检视时底部显示的文字
@export_multiline var description: String = ""
## 背包图标
@export var icon: Texture2D
## 检视用的 3D 模型（可空 → 不显示检视按钮）
@export var model_scene: PackedScene
## 检视时的缩放
@export var inspect_scale: float = 1.0
## 是否可在背包里「使用」
@export var can_use: bool = true
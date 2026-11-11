class_name KeyData
extends ItemData
## 钥匙类：声明这把钥匙能开哪些锁（lock_id）。
## 门上的 lock_id 与这里的 unlock_ids 对应，匹配即可开锁。

@export var unlock_ids: Array[StringName] = []


func can_unlock(lock_id: StringName) -> bool:
	if lock_id == &"":
		return false
	return unlock_ids.has(lock_id) or id == lock_id
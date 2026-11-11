# GameJam 后续开发 TODO（待审核）

> 依据 2026-11-11 群聊整理：背包系统、对话系统、物品展示（360° 检视）、恐怖逃脱剧情 + 解谜、主菜单、新手教程（开场旁白）。
> **本文档只是方案，等你审核通过后再动代码。**

---

## 0. 一句话目标

玩家被困在三个房间 + 走廊组成的恐怖场景里，通过**拾取物品 → 背包查看 → 检视线索 → 对话/旁白推进 → 解谜**逃出去；主菜单进入，开场有画外音教学。

## 1. 当前工程基础（已具备，直接复用）

| 已有 | 说明 |
| --- | --- |
| `RoomManager`（autoload） | 同帧换场景、继承速度、出生点、门角度/位置复制 |
| 房间 1/2/3 + `corridor-1` | 走廊是 hub，每间一个门；门为靠近自动开、走远自动关 |
| `interactable.gd` | 通用互动区：显示提示、按 E 触发（可开关灯、把人移到坐下点） |
| `player.tscn` + `p_3d.gd` | 移动/跳跃/动画/传送后自动走一段 |
| `Project.md` | 目录与命名规范 |

新增系统都按现有规范放置：`scripts/autoload`、`scripts/ui`、`scripts/world`、`scenes/ui`、`data/`。

---

## 2. 系统设计总览

```
┌─────────────┐   add/remove    ┌──────────────┐
│ PickupItem  │ ──────────────> │  Inventory   │──> 背包 UI ──> 检视（360°）
└─────────────┘                 │  (autoload)  │
                                └──────────────┘
┌─────────────┐   set/check     ┌──────────────┐
│ Dialogue    │ ──────────────> │  GameState   │<── 谜题/门/对话条件
│ Trigger     │                 │  (flags)     │
└─────────────┘                 └──────────────┘
        │
        └──> 对话 UI（打字机 + 选项 + 旁白音频）
```

### 2.1 数据层

**`ItemData`（自定义 Resource，`scripts/data/item_data.gd`）**

| 字段 | 类型 | 用途 |
| --- | --- | --- |
| `id` | StringName | 唯一标识（存档、条件判断用） |
| `display_name` | String | 背包里显示的名字 |
| `description` | String | 详情 / 检视时的说明文字 |
| `icon` | Texture2D | 背包格子图标 |
| `model_scene` | PackedScene | 检视时用的 3D 模型（可空 → 不显示检视按钮） |
| `inspect_scale` | float | 模型在检视视图里的缩放 |
| `stackable` / `max_stack` | bool / int | 预留（本作大概率不需要） |

存放：`data/items/*.tres`（例如 `data/items/rusty_key.tres`）。

**对话数据**：`data/dialogue/*.json`（比 .tres 好手写、好 diff）

```json
{
  "id": "intro_narration",
  "lines": [
    { "speaker": "", "text": "你醒来时，门已经锁死了。", "voice": "", "wait": 0.6 },
    { "speaker": "玩家", "text": "这是哪……", "voice": "", "next": "hint_1" }
  ],
  "choices": {
    "hint_1": [
      { "text": "先看看四周", "next": "end", "set_flag": "tutorial_seen" },
      { "text": "撞门试试", "next": "try_door", "set_flag": "tutorial_seen" }
    ]
  }
}
```
> 具体格式按实现时的解析器定，原则：**文本、说话人、可选语音、可选分支、可设 flag**。

### 2.2 状态层（两个 autoload）

**`GameState`（`scripts/autoload/game_state.gd`）**
- `flags: Dictionary`；`set_flag(k, v)`、`get_flag(k, default)`、`has_flag(k)`
- 信号 `flag_changed(key, value)`（谜题/门/对话监听）
- 剧情进度 `chapter`、玩家是否已看过教程 `tutorial_seen`
- 预留 `save()/load()`（JSON → `user://save.json`）

**`Inventory`（`scripts/autoload/inventory.gd`）**
- `items: Array[ItemData]`
- `add(item)`、`remove(id)`、`has(id)`、`get_item(id)`
- 信号 `changed`、`item_added(item)`
- 与 UI 解耦：UI 只监听信号

---

## 3. 功能任务（按里程碑）

### M1 · 基础框架（0.5 天）

- [ ] **T1.1** 新建 `scripts/data/item_data.gd`（Resource）
  - 8 个导出字段见 §2.1，`class_name ItemData`
  - 验收：能在检查器里新建 `.tres` 并拖进 `@export var item: ItemData`
- [ ] **T1.2** 新建 `scripts/autoload/game_state.gd`、`scripts/autoload/inventory.gd`
  - 注册到 `project.godot` 的 `[autoload]`（`GameState`、`Inventory`）
  - 验收：任意脚本里 `GameState.set_flag("x", true)` / `Inventory.add(item)` 可用
- [ ] **T1.3** `interactable.gd` 扩展：新增 `item_to_give: ItemData`、`flag_to_set: StringName`、`consume_on_use: bool`
  - 按 E 时：给物品 + 设 flag + （可选）隐藏自身
  - 验收：房间放一个测试物品，按 E 后背包里有它、物体消失

### M2 · 背包 UI（1 天）

- [ ] **T2.1** `scenes/ui/inventory.tscn` + `scripts/ui/inventory_ui.gd`
  - 结构：`CanvasLayer > Panel > VBox(标题/GridContainer) + 右侧详情面板(Icon/Name/Desc/查看按钮)`
  - 开关：新增输入动作 `inventory`（Tab 或 I），打开时 `get_tree().paused = true`，UI `process_mode = ALWAYS`
  - 验收：按 I 打开/关闭；拾取后格子实时出现；点格子显示详情
- [ ] **T2.2** 拾取提示：屏幕下方 1.5s 淡出提示「获得：生锈的钥匙」
  - 监听 `Inventory.item_added`
- [ ] **T2.3** 空背包 / 选中态 / 键盘操作（方向键选择，Enter 查看）——基础可用即可

### M3 · 物品检视（360°）（1 天）

- [ ] **T3.1** `scenes/ui/inspect_view.tscn` + `scripts/ui/inspect_view.gd`
  - 结构：`CanvasLayer > ColorRect(半透明黑) > SubViewportContainer > SubViewport > (Camera3D + Node3D 模型根 + OmniLight3D)`，下方 `Label`（名称/描述），右上角「×」
  - 打开：从背包选中的 `ItemData.model_scene` 实例化进 SubViewport
- [ ] **T3.2** 360° 交互：鼠标拖拽 → 模型根 `rotation.y += dx * 0.01`；滚轮缩放（`scale` 夹 0.5~2.0）；松手后缓慢自转（可选）
  - 验收：任意角度可看，不穿模，Esc / × 关闭
- [ ] **T3.3** 检视时游戏暂停；关闭后回到背包

### M4 · 对话系统 + 旁白（1.5 天）

- [ ] **T4.1** `scripts/autoload/dialogue_manager.gd`
  - `start(id: StringName)` 读 `data/dialogue/<id>.json`，逐行推进；`advance()`；信号 `line_shown(speaker, text, voice)`、`choices_shown(options)`、`finished`
  - 打字机效果（`RichTextLabel` + `visible_ratio` tween，可按键跳过）
- [ ] **T4.2** `scenes/ui/dialogue_box.tscn` + `scripts/ui/dialogue_box.gd`
  - 底部对话框：说话人、正文、继续指示、选项按钮（可选）
- [ ] **T4.3** 触发方式：
  - `scripts/world/dialogue_trigger.gd`（Area3D，进入自动播放，可 `once`）
  - `interactable.gd` 再扩展：`dialogue_id` → 按 E 开始对话
  - 验收：走近触发区自动播开场旁白；E 与 NPC/物件对话
- [ ] **T4.4** 旁白音频：`voice` 字段指向 `res://` 音频（TTS 生成或录音），对话时播放，可静音

### M5 · 谜题框架 + 主线内容（1.5 天）

- [ ] **T5.1** `scripts/world/puzzle_lock.gd`（继承/扩展 interactable）
  - 字段：`required_item: ItemData`、`required_flags: Array[StringName]`、`on_solve_flags`、`on_solve_open_door: NodePath`、`fail_text`
  - 按 E：满足条件 → 解锁（开门/给物品/播对话）；不满足 → 显示提示
- [ ] **T5.2** 三个谜题示例（可替换）：
  1. **书桌抽屉**：需要「生锈的钥匙」→ 得到「纸条」→ 检视纸条得到密码线索
  2. **电视灯**：按 E 关掉电视灯 → 墙上荧光字显现（切材质/显示 Label3D）→ 得到开门密码
  3. **床垫**：翻找床垫 → 得到「地下室钥匙」→ 解锁走廊尽头的门
- [ ] **T5.3** 结局判定：`GameState` 的 `escaped` flag → 播结局对话 → 回主菜单

### M6 · 主菜单 + 新手教程（1 天）

- [ ] **T6.1** `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd`
  - 标题、开始游戏（切到 `scenes/rooms/room1.tscn`）、设置（音量）、退出
  - `project.godot` 的 `run/main_scene` 改为 `scenes/ui/main_menu.tscn`
  - 验收：启动进菜单，开始后进 room1
- [ ] **T6.2** 开场教程：
  - 首次进入（`GameState.tutorial_seen == false`）→ 黑屏 + 旁白对话（3~4 句）+ 操作提示（WASD/空格/E/I）
  - 结束后 `set_flag("tutorial_seen", true)`
- [ ] **T6.3** HUD：当前目标文字（如「找到逃出去的办法」）+ 拾取提示，`scenes/ui/hud.tscn`

### M7 · 打磨（1 天，可选）

- [ ] 存档/读档（`user://save.json`：flags + inventory）
- [ ] 音效：脚步/开门/拾取/心跳
- [ ] 门与走廊的视觉细节、灯光氛围统一
- [ ] 失败/死亡（被抓住 → 重开本房间）

---

## 4. 需要新增/修改的文件清单（预估）

**新增**
```
scripts/data/item_data.gd
scripts/autoload/game_state.gd
scripts/autoload/inventory.gd
scripts/autoload/dialogue_manager.gd
scripts/ui/inventory_ui.gd
scripts/ui/inspect_view.gd
scripts/ui/dialogue_box.gd
scripts/ui/main_menu.gd
scripts/ui/hud.gd
scripts/world/dialogue_trigger.gd
scripts/world/puzzle_lock.gd
scenes/ui/inventory.tscn
scenes/ui/inspect_view.tscn
scenes/ui/dialogue_box.tscn
scenes/ui/main_menu.tscn
scenes/ui/hud.tscn
data/items/*.tres
data/dialogue/*.json
```

**修改**
```
project.godot           # autoload 注册、inventory 输入动作、主场景
scripts/rooms/interactable.gd  # 扩展 item/dialogue/flag
scenes/rooms/room1|2|3.tscn    # 摆线索物、谜题、对话触发
corridor-1.tscn         # 尽头加锁门/结局判定
docs/Project.md         # 新增系统说明
```

---

## 5. 排期建议

| 天 | 内容 |
| --- | --- |
| Day 1 | M1 框架 + M2 背包 |
| Day 2 | M3 检视（360°）+ M4 对话骨架 |
| Day 3 | M4 收尾 + M5 谜题与内容 |
| Day 4 | M6 主菜单/教程 + M7 打磨 + 录旁白 |

> 依据聊天记录「明天先输提示词叫 AI 先写」：每个里程碑可以先让我产出**给 AI 的提示词**（包含数据结构、节点结构、验收标准），再落地代码。

---

## 6. 待你确认的设计问题（审核重点）

1. **背包形态**：格子 + 右侧详情（推荐）还是列表？
2. **检视**：要不要暂停游戏？模型是每个物品单独做 `.glb`，还是复用现有素材包里的物件？
3. **对话**：需要分支选项吗？还是纯线性旁白 + 单句确认？（分支会多约 0.5 天）
4. **旁白形式**：TTS 生成 / 真人录音 / 纯字幕？
5. **谜题数量**：先做 2 个（钥匙 + 电视）够不够？结局要几个？
6. **存档**：这一版需要吗？（默认先不做，除非你要求）
7. **恐怖强度**：要不要惊吓事件（突然关灯、脚步声、追逐）？这会影响 M7。
8. **主菜单**：需要设置项（音量/画质）吗？

---

## 7. 风险

- 现有素材包（URBAN/OFFICE/PSX）很大，检视用的单品模型要单独挑，避免把整个包带进 UI 场景；
- 背包/对话 UI 会与现有 `interactable` 的 Label3D 提示并存，需要统一「互动提示」与「对话/拾取提示」的显示层级；
- 对话系统若做分支 + 存档，flag 命名要提前定规范（建议 `chapter_x_xxx` 前缀）。
# GameJam 开发 TODO（v2 · 待审核）

> 依据 2026-11-11 追加的口头需求重写。**本文档只描述方案，不写代码**；确认后再按 §6 顺序实现。
> 上一版（背包/对话/检视/剧情/主菜单的通用规划）已并入本文，范围收敛为下面 7 个 P0 功能。

---

## 0. 本轮要做的 7 件事（P0）

1. **开始界面（覆盖在游戏场景上）**：和游戏同一个场景、同一个摄像机，只叠一层 UI；菜单期间玩家完全不能操作；点「开始游戏」立刻能玩；「退出游戏」退出。
2. **对话系统**：旁白 + 角色对话，逐字显示、可跳过、可推进。
3. **交互系统**：走到物件旁显示「按 E …」，支持 检视 / 对话 / 使用。
4. **背包（列表式）**：左右分栏，左边物品列表、右边信息 + 图片 + 使用 / 警示。
5. **检视系统**：按 E 检视 → 屏幕蒙版 → 3D 物品居中 → 鼠标 360° 旋转 → 底部文字说明。
6. **噪声旁白**：不用录音，用噪声图样 + 逐字哈希生成「嘟嘟囔囔」的合成语音。
7. **新手教程 + 第一个小谜题**：用对话把「我们搭了个恐怖场景来整蛊你」讲清楚，引导玩家走完 WASD / 空格 / E / 背包 / 检视，并解开第一个谜题。

其余（存档、结局分支、更多谜题、设置菜单、惊吓事件）**本轮不做**，见 §7。

---

## 1. 现状（可直接复用）

| 已有 | 用途 |
| --- | --- |
| `RoomManager`（autoload） | 换场景、出生点、门角度/位置复制 |
| `room1/2/3` + `corridor-1` | 三个房间 + 走廊 hub，每间一个门 |
| `player.tscn` + `p_3d.gd` | 移动/跳跃/动画/传送后自动走一段 |
| `interactable.gd` | Area3D 互动区：显示 Label3D 提示、按 E 开关灯或移到坐下点 |
| `Project.md` | 目录/命名规范 |

---

## 2. 主菜单（覆盖在游戏场景上）

### 2.1 需求还原
- 不要单独的主菜单场景跳转：**菜单就是 room1 场景上的一层 UI**，背后能看到房间和摄像机画面（同一个 `mainCamera3D`）。
- 菜单期间：玩家不能移动/跳跃/交互，门不响应。
- 点「开始游戏」→ 菜单消失，**立刻**可以操作。
- 点「退出游戏」→ 退出进程。

### 2.2 实现方式
- 新建 `scenes/ui/main_menu.tscn`（根节点 `CanvasLayer`），直接**拖进 `scenes/rooms/room1.tscn`**（名字 `MainMenu`）。
- 结构：
  ```
  MainMenu (CanvasLayer, layer=100, process_mode=ALWAYS, script=main_menu.gd)
  ├─ Dim (ColorRect, 0,0,0,0.55, 全屏)
  ├─ Title (Label: 「被困」/项目名)
  ├─ Buttons (VBoxContainer)
  │   ├─ StartButton (Button「开始游戏」)
  │   └─ QuitButton  (Button「退出游戏」)
  └─ Hint (Label: 「v0.1 · GameJam」)
  ```
- 脚本要点：
  - `_ready()`：`get_tree().paused = true`；自己 `process_mode = ALWAYS`（保证按钮可点）；
  - 「开始游戏」：`get_tree().paused = false`；`queue_free()` 自己；调 `Tutorial.start()` 播开场旁白；
  - 「退出游戏」：`get_tree().quit()`。
- 用 `paused` 的代价：雾/灯光动画也会停（菜单是静态画面，可接受）；如果你想背后场景继续动，改成「只禁用 player 的 `_physics_process` + 所有 Area3D 的 `monitoring=false`」，实现更麻烦，**默认用暂停**。

### 2.3 验收
- 启动游戏 → 直接看到 room1 的画面 + 菜单，玩家按键无效；
- 点开始 → 菜单消失、能立刻走动；
- 点退出 → 进程退出；
- 菜单期间摄像机就是游戏里的 `mainCamera3D`，没有额外相机。

---

## 3. 对话系统

### 3.1 数据格式（`data/dialogue/*.json`）
```json
{
  "id": "intro_prank",
  "lines": [
    { "speaker": "", "text": "欢迎来到我们搭的恐怖屋。", "pause": 0.4 },
    { "speaker": "制作组", "text": "放心，我们是来整蛊你的。", "pause": 0.2 },
    { "speaker": "", "text": "先试试解开第一个谜题吧。", "next": "hint" }
  ],
  "choices": {
    "hint": [
      { "text": "好", "next": "end", "set_flag": "tutorial_started" }
    ]
  }
}
```
- 字段：`speaker`（空 = 旁白）、`text`、`pause`（句后停顿）、`voice`（可选，覆盖合成音色）、`next`（跳转）、`set_flag`（推进时设 flag）。
- 解析器容错：缺字段用默认值；找不到 id 时打印警告并跳过。

### 3.2 运行时（`scripts/autoload/dialogue_manager.gd`）
- `start(id) -> void`、`advance() -> void`、`skip_typing() -> void`、`stop()`；
- 信号：`line_started(speaker, text)`、`line_finished`、`choices_shown(options)`、`dialogue_finished(id)`；
- 打字机：`RichTextLabel.visible_ratio` 用 `tween` 0→1，速度约 40 字/秒；按 E/空格跳过；
- 与旁白联动：每行开始调 `VoiceSynth.speak(text)`（见 §6）。

### 3.3 UI（`scenes/ui/dialogue_box.tscn`）
```
DialogueBox (CanvasLayer, layer=90, process_mode=ALWAYS)
└─ Panel (底部，高度约 30%)
   ├─ Speaker (Label)
   ├─ Text (RichTextLabel, bbcode)
   ├─ Continue (Label「▼ 按 E 继续」闪烁)
   └─ Choices (VBoxContainer, 默认隐藏)
```
- 打开对话时 `get_tree().paused = true`（UI ALWAYS），玩家不能动；关闭恢复。
- 触发方式：
  - `interactable.gd` 增加 `dialogue_id`：按 E 开始对话；
  - `dialogue_trigger.gd`（Area3D，进入自动播，`once` 可选）。

---

## 4. 交互系统（统一 E 键）

### 4.1 现有 `interactable.gd` 扩展
| 新字段 | 作用 |
| --- | --- |
| `dialogue_id: StringName` | 按 E 播对话 |
| `inspect_item: ItemData` | 按 E 打开检视（§5） |
| `item_to_give: ItemData` | 按 E 拾取进背包 |
| `flag_to_set: StringName` | 按 E 设 flag |
| `consume_on_use: bool` | 用过后隐藏自身 |

- 提示文字自动生成：检视 →「按 E 检视」；对话 →「按 E 交谈」；拾取 →「按 E 拾取」。
- 优先级：对话 > 检视 > 拾取 > 开关灯/坐下。
- 按 E 后统一走 `InteractionRouter`（小工具函数），避免每个脚本各写一遍。

### 4.2 验收
- 场景里放一个灯：走近出现「按 E 检视」，按 E 打开检视视图；
- 放一个箱子：按 E 后物品进背包、箱子消失、屏幕提示「获得：xxx」。

---

## 5. 背包（列表式，左右分栏）

### 5.1 布局
```
InventoryUI (CanvasLayer, layer=80, process_mode=ALWAYS)
└─ HBox (全屏，左右各 50%)
   ├─ Left  (VBox)
   │   ├─ Title (Label「背包」)
   │   └─ ItemList (列表：图标 + 名字，键盘/鼠标可选)
   └─ Right (VBox)
       ├─ Icon (TextureRect，128×128)
       ├─ Name (Label)
       ├─ Desc (RichTextLabel，自动换行)
       ├─ UseButton (Button「使用」)
       └─ Warning (Label，红色：现在不能使用/缺少条件)
```
- 开关：新增输入动作 `inventory`（`I` 键）；打开时暂停游戏（`paused = true`），关闭恢复。
- **鼠标悬停**或**点击/键盘选中**都更新右侧信息（`ItemList.item_selected` + 自己加 `mouse_entered` 检测）。
- 「使用」按钮：发 `Inventory.use_requested(item_id)`；如果当前没有可用目标 → `Warning` 显示「现在还不能使用」，2 秒后清除。

### 5.2 数据
- `ItemData`（Resource）：`id / display_name / description / icon / model_scene / inspect_scale / can_use`。
- `Inventory`（autoload）：`items: Array[ItemData]`、`add/remove/has/get`、信号 `changed`。
- `GameState`（autoload）：`flags: Dictionary`（谜题条件用），信号 `flag_changed`。

### 5.3 验收
- 拾取物品后按 I：左侧出现条目，点它右侧显示图标/名字/描述；
- 若该物品此刻不能用，点使用在右侧红色提示；
- 关闭背包后游戏继续，玩家位置不变。

---

## 6. 检视系统（蒙版 + 360° 旋转）

### 6.1 交互流程
1. 走近可检视物件 → 提示「按 E 检视」；
2. 按 E → 全屏半透明黑蒙版（0.75）+ 物品 3D 模型出现在屏幕中央；
3. 鼠标按住拖动 → 绕 Y 轴旋转（可 360°），上下拖动小幅俯仰；
4. 滚轮缩放；松开后缓慢自转（可关）；
5. 屏幕底部显示名称 + 描述文本（例如灯底图案的线索）；
6. 按 E / Esc / 右上角 × 关闭，回到游戏。

### 6.2 场景结构
```
InspectView (CanvasLayer, layer=85, process_mode=ALWAYS)
├─ Dim (ColorRect 全屏 0,0,0,0.75)
├─ ViewportBox (SubViewportContainer，居中，占屏 60%)
│   └─ SubViewport (transparent_bg = true)
│       ├─ Camera3D
│       ├─ ModelRoot (Node3D，脚本旋转它)
│       ├─ OmniLight3D ×2（主光 + 补光）
│       └─ WorldEnvironment（可选，环境光）
├─ CloseButton (Button「×」)
└─ Info (Panel 底部)
    ├─ Name (Label)
    └─ Desc (RichTextLabel)
```
- 打开时：清空 `ModelRoot` 子节点 → `model_scene.instantiate()` → 放进去，按 `inspect_scale` 缩放，自动居中（用合并 AABB 算偏移）。
- 玩家不能移动：`get_tree().paused = true`（UI ALWAYS），关闭恢复。
- 模型自转用 `_process(delta)`：`rotation.y += spin_speed * delta`；拖动时暂停自转。

### 6.3 验收
- 任意角度都能看，模型不穿蒙版、不抖；
- 关闭后游戏状态、玩家位置不变；
- 不同物品用不同 `model_scene`，支持 `.glb` 直接引用。

---

## 7. 噪声旁白（不用录音）

### 7.1 需求还原
> 用噪声图样生成噪声；文字里每个字有固定的取值，对应噪声图里固定的东西，用来播放「嘟嘟囔囔」的旁白。

### 7.2 实现方式（`scripts/audio/voice_synth.gd`，autoload 或静态单例）
1. **噪声源**：启动时生成一张长度为 `N=4096` 的 `Float32Array`（值域 0..1），可用 `FastNoiseLite`（Godot 内置）按 `x = i * 0.01` 采样，或者直接用 `RandomNumberGenerator` 固定种子生成——**必须固定种子**，保证每次启动一致。
2. **逐字映射（确定性）**：
   ```gdscript
   var cp := text.unicode_at(i)                 # 字符码位
   var h := (cp * 2654435761) & 0xFFFFFFFF      # 稳定哈希
   var idx := h % N
   var amp := noise[idx]                        # 0..1 → 音量/波形
   var semitone := h % 12                       # 音高抖动
   var dur := 0.04 + float(h % 4) * 0.01        # 40~70ms
   ```
3. **合成**：按字顺序拼 PCM 片段：
   - 波形 = `sin(2π·f·t)` 与噪声插值混合（噪声权重 ~0.3，听感更"沙哑"）；
   - `f = base_freq * pow(2, semitone/12.0)`，`base_freq` 男声 ~110Hz / 女声 ~180Hz（可导出参数）；
   - 每段包络：快起（5ms）+ 快落（15ms），避免爆音；
   - 标点/空格：插入 60~120ms 静音；
   - 最终生成 `AudioStreamWAV`（16-bit、22050Hz、单声道），交给 `AudioStreamPlayer` 播放。
4. **接口**：`VoiceSynth.speak(text: String)`、`set_muted(bool)`、`set_pitch_scale(float)`。
5. **缓存**：同一段文本的 WAV 缓存到字典（`text -> AudioStreamWAV`），避免重复合成。

### 7.3 验收
- 同一句话每次生成的音频**完全一致**（固定种子 + 确定性哈希）；
- 不同字音高/音色不同，听起来像"咕哝的说话声"而不是电子噪音；
- 文字长度 100 字以内合成耗时 < 50ms（一次性），不卡顿；
- 可静音，音量跟随主音量。

---

## 8. 新手教程 + 第一个谜题（流程脚本）

| 步骤 | 触发 | 表现 |
| --- | --- | --- |
| 1 | 启动 | 主菜单覆盖在 room1 画面上，玩家不能动 |
| 2 | 点「开始游戏」 | 菜单消失；黑屏 0.5s；旁白（合成音）：「我们搭了个恐怖屋，来整蛊你的」 |
| 3 | 旁白结束 | HUD 提示「WASD 移动」→ 玩家走到房间中央（`Area3D` 检测到）后进入下一步 |
| 4 | 到达中央 | 提示「空格跳跃」；跳一次后继续 |
| 5 | 提示「E 互动」 | 书桌上的台灯（`circular_desklamp.glb`）按 E 打开检视 |
| 6 | 检视台灯 | 蒙版 + 360° 旋转；底部文字点出灯座有刻痕（数字「3-1-4」） |
| 7 | 关闭检视 | 提示「I 打开背包」；桌上纸条（`paper_single_sheet.glb`）可拾取 |
| 8 | 背包使用 | 选中纸条点「使用」→ 二次确认 → 打开检视看到「文件柜密码 3-1-4」 |
| 9 | 文件柜 | 用纸条开文件柜（`file_cabinet_small.glb` → `file_cabinet_small_open.glb`），得到「锈钥匙」 |
| 10 | 结束 | 设置 `tutorial_seen = true`，HUD 目标变成「找到逃出去的办法」 |

- 引导用 `TutorialManager`（`scripts/autoload/tutorial_manager.gd`）按步骤推进，每步监听 flag/Area3D/信号，避免写死时间。
- HUD：右上角目标文字 + 底部临时提示（2s 淡出）。

---

## 9. 数据与文件清单

**新增**
```
scripts/data/item_data.gd
scripts/autoload/game_state.gd
scripts/autoload/inventory.gd
scripts/autoload/dialogue_manager.gd
scripts/autoload/tutorial_manager.gd
scripts/audio/voice_synth.gd
scripts/ui/main_menu.gd
scripts/ui/inventory_ui.gd
scripts/ui/inspect_view.gd
scripts/ui/dialogue_box.gd
scripts/ui/hud.gd
scripts/world/dialogue_trigger.gd
scenes/ui/main_menu.tscn
scenes/ui/inventory.tscn
scenes/ui/inspect_view.tscn
scenes/ui/dialogue_box.tscn
scenes/ui/hud.tscn
data/items/*.tres
data/dialogue/*.json
```

**修改**
```
project.godot                # autoload 注册 + inventory 输入动作
scripts/rooms/interactable.gd # 扩展对话/检视/拾取/flag
scenes/rooms/room1.tscn      # 挂 MainMenu、HUD、教程物件、第一个谜题
docs/Project.md              # 新系统说明
```

---

## 10. 实现顺序（每一档都可单独验收）

1. **A** 数据层：`ItemData` + `GameState` + `Inventory`（0.5 天）
2. **B** 对话系统（管理器 + UI + 合成旁白）（1 天）
3. **C** 主菜单覆盖层 + 暂停 + 开始/退出（0.5 天）
4. **D** 交互扩展（E：对话/检视/拾取）（0.5 天）
5. **E** 背包 UI（列表左右分栏 + 使用/警示）（1 天）
6. **F** 检视系统（蒙版 + 360°）（1 天）
7. **G** 教程流程 + 第一个谜题（1 天）

> 顺序理由：A 是所有系统的数据基础；B 先做，教程的旁白就能复用；C 很独立；D/E/F 依赖 A；G 最后把所有东西串起来。

---

## 11. 待你确认

1. 主菜单标题文字（暂定「被困」）和按钮文案；
2. 「开始游戏」后是否要黑屏过渡再进游戏，还是直接能走；
3. 背包里物品的「使用」是否会出现二次确认（还是直接生效）；
4. 检视时是否允许旋转到任意角度（包括看到背面/底面）——我默认允许；
5. 合成旁白的性别/音高偏好（默认偏中性、低频）；
6. 第一个谜题的具体设计（暂定：检视台灯 → 得到钥匙 → 开抽屉），你有别的想法可以直接改。

---

## 12. 可用素材清单（据项目实际资源盘点）

### 12.1 恐怖/氛围（`Assets/models/fbx/`，fbx 已导入）
| 素材 | 可用途 |
| --- | --- |
| `candle` / `candle_melted` / `candle_thin` / `candle_triple` / `skull_candle` | 房间恐怖氛围、祭坛（`shrine_candles`） |
| `lantern_hanging` / `lantern_standing` / `post_lantern` | 走廊/房间光源 |
| `skull` / `bone_A/B/C` / `ribcage` | 线索物、装饰、仪式感 |
| `coffin` / `coffin_decorated` / `crypt` | 房间里的「大物件」、可当谜题目标 |
| `grave_A/B` / `gravestone` / `gravemarker_A/B` | 室外/房间角落 |
| `pumpkin_*_jackolantern` | 已有点亮效果，适合当氛围灯 |
| `tree_dead_*` / `fence_*` / `arch` / `pillar` | 走廊尽头、院子场景 |

### 12.2 办公/家具（`OFFICE/OFFICE/`，glb）
| 分类 | 可用模型 | 用途 |
| --- | --- | --- |
| `extras` | **`circular_desklamp` / `square_desklamp`**（台灯）、`desk_phone`、`wall_clock`、`whiteboard`、`coffee_machine`、`water_cooler`、`mug`、`glass` | 台灯=检视谜题；电话/时钟=线索物 |
| `stationary` | **`paper_single_sheet` / `paper_stack`**（纸条）、`pen` | 纸条=可拾取/可检视的道具 |
| `file_cabinets` | `file_cabinet_small` / `_small_open` / `_larger` / `_larger_open` / `_smallest` …（都有开/关两种） | 文件柜=「上锁—开启」的视觉切换 |
| `desks` | `desk1` 系列（含 weathered 做旧版）、会议桌 | 书桌/工作台 |
| `chairs` / `couches` | `office_chair_*`、`couch_*`、`armchair_*`、`beanbag_*` | 沙发/座椅 |
| `computers` | `computer_monitor`、`TV`、`computer_tower`、`keyboard` | 电视谜题、监控感 |
| `book_things` | `books`、`books_alt`、`book_case` 系列 | 书架、埋在书里的线索 |
| `carpet_floor` | `floor_2x2` 等 | 局部地毯装饰 |

### 12.3 PSX 家具（`PSX-Derelict-Furniture-Standard/glb/`）
`chair` / `couch` / `fridge` / `mattress` / `shelf` / `vase` —— 冰箱已加碰撞；床垫、货架、花瓶可继续用作线索点。

### 12.4 城市户外（`URBAN/`，glb）——**留给结局/逃出后的场景**
建筑部件、预拼建筑、公交站、路障锥、垃圾桶、围栏、管道、道路、红绿灯、通风口。
> 适合做「逃出房间后走到街上」的收尾场景，本轮 P0 不用。

### 12.5 角色
`player/sophia_skin`：模型 + 动画状态机（Idle/Move/Jump/Fall/EdgeGrab/WallSlide）+ 脚步声。

---

## 13. 第一个谜题（按实际素材细化）

**场景**：room1 的书桌区（已有 `desk1_alt2_weathered`、`fridge`、`armchair_red`、`TV`）。

| 步骤 | 物件（实际模型） | 交互 | 产出 |
| --- | --- | --- | --- |
| 1 | 台灯 `circular_desklamp.glb`（放书桌上） | 按 E 检视 → 360° 转到灯底 | 底部文字：「灯座刻着 3-1-4」 |
| 2 | 纸条 `paper_single_sheet.glb`（桌上/地上） | 按 E 拾取 | 背包出现「皱巴巴的纸条」 |
| 3 | 背包 | 选纸条 → 「使用」→ 二次确认 | 打开检视：纸条内容「文件柜密码 3-1-4」 |
| 4 | 文件柜 `file_cabinet_small.glb` | 按 E → 需要「纸条」→ 使用后模型换成 `file_cabinet_small_open.glb` | 得到「锈钥匙」（占位模型：暂用 `pen.glb` 或 `paper_stack`，后续可换） |
| 5 | 走廊尽头的门 | 需要「锈钥匙」 | 解锁 → 进入下一阶段 |

- 椅子、冰箱、床垫、电视保留现有互动（电视灯光 E 开关）。
- 「锈钥匙」只是占位：如果你们后面找到/做一个钥匙模型，直接替换 `ItemData.model_scene` 即可，不影响逻辑。

---

## 14. 已确认的设计决定（对应 §11）

| # | 决定 |
| --- | --- |
| 1 | 主菜单标题、按钮文案**先用临时名字**，后续你自己改 |
| 2 | 点「开始游戏」**不做黑屏过渡**，点完立刻可操作 |
| 3 | 背包「使用」**需要二次确认**（弹确认按钮/再次点击确认） |
| 4 | 检视允许**任意角度**（含背面/底面） |
| 5 | 合成旁白默认**中性音色** |
| 6 | 第一个谜题按 §13 执行（台灯 → 纸条 → 文件柜 → 锈钥匙） |

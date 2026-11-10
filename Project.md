# 万圣节房间游戏 · 项目说明

> 一句话：三个连通的 3D 房间，玩家走门口即可无缝换房间，门扇会被玩家身体顶开（绕合页旋转），走远后自动关上。
> 本文档是给「下一个接手的人」看的，包含目录约定、命名规范、改代码前必须知道的硬性路径依赖，
> 以及新增房间 / 新增门的完整步骤。

---

## 1. 项目简介与运行

| 项目 | 值 |
| --- | --- |
| 引擎 | **Godot 4.7.2 stable**（steam 版，`4.7` 特性、Forward Plus 渲染） |
| 语言 | GDScript |
| 主场景 | `res://scenes/rooms/room1.tscn`（`project.godot` 里以 UID `uid://bjcvwlirbaycn` 引用） |
| 物理引擎 | Jolt Physics |
| 窗口 | 1920×1080，`canvas_items` 拉伸 + `expand` |
| 渲染 | Windows 走 D3D12；Mobile 回退 `gl_compatibility` |

### 怎么跑

```powershell
# 编辑器
& 'E:\games\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path 'D:\Gamemaker\GameJam' --editor

# 直接跑（headless 自检，CI 用）
& 'E:\games\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'D:\Gamemaker\GameJam' --quit-after 180

# 移动端 / 美术素材改动后，让 Godot 重新扫描并导入
& 'E:\games\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'D:\Gamemaker\GameJam' --import
```

**操作**：`WASD` 移动，`空格` 跳跃（`ui_accept`）。走到门前继续朝门的方向走，身体就会把门顶开（不需要按键）。

### 怎么导出

仓库里**还没有** `export_presets.cfg`，第一次导出要先在编辑器里建预设：

1. 编辑器 → `项目 / Project` → `导出 / Export` → `添加 / Add…` → `Windows Desktop`
2. 确认 `可执行文件 / Export Path`（建议 `build/GameJam.exe`），`资源 / Resources` 用默认「导出所有资源」
3. 需要先装好与 4.7.2 匹配的导出模板（`编辑器 → 管理导出模板`）
4. 之后命令行可用：

```powershell
& '<godot.exe>' --headless --path 'D:\Gamemaker\GameJam' --export-release 'Windows Desktop' 'build\GameJam.exe'
```

> `build/` 建议加进 `.gitignore`（目前没加）。

---

## 2. 目录结构

```
res://
├─ project.godot                  # 工程配置：主场景、autoload、输入映射、物理/渲染
├─ Project.md                     # 本文档
├─ icon.svg (+ .import)           # 工程图标，留在根目录（project.godot 引用 res://icon.svg）
│
├─ scenes/                        # 所有场景
│  ├─ rooms/
│  │   ├─ room1.tscn              # 房间1（= 原 level.tscn，主场景）
│  │   ├─ room2.tscn              # 房间2（两个门：回房间1、去房间3）
│  │   └─ room3.tscn              # 房间3
│  ├─ doors/
│  │   └─ door_leaf.tscn          # 可交互门扇预制体（被三个房间实例化）
│  ├─ player/
│  │   └─ player.tscn             # 玩家预制体（CharacterBody3D + SophiaSkin + 胶囊碰撞），三个房间共用
│  ├─ props/
│  │   └─ pumpkin.tscn            # 6 种南瓜模型摆在一起的展示/取模场景
│  └─ dev/                        # 开发辅助，不参与玩法
│      ├─ grid_map_preview.tscn   # 空 GridMap 测试场景
│      └─ floor_mesh_preview.tscn # 手工拼的地板网格 + 万圣节贴图预览
│
├─ scripts/                       # 所有 GDScript
│  ├─ autoload/
│  │   └─ room_manager.gd         # Autoload「RoomManager」：同帧换房间
│  ├─ rooms/
│  │   ├─ door.gd                 # 门洞触发器（Area3D，class_name Door）
│  │   └─ door_leaf.gd            # 门扇开关（Node3D，组 "door_leaf"）
│  └─ player/
│      └─ p_3d.gd                 # 玩家移动 / 重力 / 跳跃 / 动画状态
│
├─ player/                        # 角色资源包：模型 + 材质 + 骨架动画 + 音效（整体保留相对路径）
│  ├─ sophia_skin/
│  │   ├─ sophia_skin.tscn / .gd  # 皮肤场景 + 动画状态机控制（class_name SophiaSkin）
│  │   ├─ model/                  # sophia.glb、贴图 png、materials/*.tres、textures/
│  │   └─ ...
│  └─ sounds/                     # robot_jump / robot_land / robot_step_01..05.wav
│
├─ shaders/
│  └─ level_blur.gdshader         # 屏幕模糊（CanvasItem shader，用于雾/蒙层 ColorRect）
│
├─ Assets/                        # 万圣节素材包（大写 A：Unity/FBX 素材源目录习惯）
│  ├─ models/
│  │   ├─ fbx/                    # ★ 游戏实际引用的模型格式（scenes/props/pumpkin.tscn 用的是它）
│  │   ├─ fbx_unity/              # Unity 导出版 FBX（轴向/单位与 fbx/ 不同），仅备份
│  │   ├─ gltf/                   # .gltf + .bin 文本格式，可 diff，仅备份
│  │   └─ obj/                    # .obj + .mtl，仅备份
│  ├─ textures/
│  │   └─ halloweenbits_texture.png  # 万圣节共享贴图（副本）
│  └─ meshlibrary/
│      └─ floor.meshlib           # GridMap 用的 MeshLibrary（地板网格 + 碰撞）
│
└─ docs/
   └─ reference/
      └─ tutorial-3d-controller/  # 解压出来的第三方教程工程（自带 project.godot）
                                  # 内含 .gdignore，Godot 扫描时整目录跳过，见 §5
```

### 为什么 `player/` 在根目录而不是 `scenes/` 或 `assets/`

`sophia_skin.tscn` 内部写死了 `res://player/sophia_skin/...` 这一组相对路径（模型、脚本、材质）。
把它整体放成根目录 `player/`，这些路径天然成立，**零改动、零风险**。
移动它就必须同步改 `sophia_skin.tscn` 里三条 `ext_resource`，得不偿失。

---

## 3. 命名规范

### 文件 / 目录
- 目录与文件名一律 **小写 snake_case**：`door_leaf.tscn`、`room_manager.gd`。
- **场景与脚本同名成对**：`door_leaf.gd` ↔ `door_leaf.tscn`（`p_3d.gd` 这种只服务玩家的脚本除外）。
- 房间场景用 `roomN.tscn`（N = 房间号），不要再用 `level.tscn` 这种泛名。
- 开发/测试场景统一放 `scenes/dev/`，名字带含义（`grid_map_preview`），不要留 `scen.tscn`、`test2.tscn`。

### 场景根节点
用 **PascalCase 实体名**，与文件名呼应：`Room1` / `Room2` / `Room3` / `DoorLeaf` / `SophiaSkin`。

### 容器节点（每个房间固定五件套，顺序也一致）

| 容器 | 类型 | 放什么 |
| --- | --- | --- |
| `Environment` | `Node3D` | `WorldEnvironment`、`KeyLight`(OmniLight3D)、`FogVolume` |
| `Geometry` | `Node3D` | `FloorGrid`(GridMap)、`FloorPlane`、`Backdrop`、`DoorWall_Z/_X`、`Bounds` |
| `Doors` | `Node3D` | 所有 `DoorLeaf*` 与 `DoorToRoom*` |
| `Spawns` | `Node3D` | 所有 `SpawnFromRoom*` |
| `UI` | `CanvasLayer` | `MistRect`(ColorRect + 模糊 shader) |

容器一律 **identity transform**（不写 `transform =` 行），这样把节点挪进容器不会改变世界坐标。

### 几何/灯光命名

| 名字 | 类型 | 说明 |
| --- | --- | --- |
| `FloorGrid` | GridMap | 地板视觉（`floor.meshlib`） |
| `FloorPlane` | MeshInstance3D | 地板碰撞面（子 `StaticBody3D/CollisionShape3D`） |
| `Backdrop` | MeshInstance3D | 挡住视线的纯黑大平面 |
| `DoorWall_Z` / `DoorWall_X` | CSGBox3D | 带门洞的墙；**按墙的法线轴命名**，`use_collision = true` |
| `DoorHole` | CSGBox3D | `DoorWall_*` 的子节点，`operation = 2`（差集）挖出门洞 |
| `Bounds` | StaticBody3D | 房间四周的隐形围挡 |
| `Wall_Z` / `Wall_X` | CollisionShape3D | `Bounds` 的子节点，平面碰撞（厚度 0） |
| `KeyLight` | OmniLight3D | 主光 |
| `RoomLabel` | Label3D | 房间号文字（「房间1」） |

### ⚠️ 不许改名的「锚点节点」

这些名字被脚本或场景属性按字符串/NodePath 依赖，改名会静默失效：

| 节点名 | 谁依赖 | 依赖方式 |
| --- | --- | --- |
| `player` | `door.gd` / `room_manager.gd` / `door_leaf.gd` | 是 `scenes/player/player.tscn` 的实例，名字必须是 `player`（实例名覆盖为小写），且必须是**房间根的直接子节点**；`door.gd` 判 `body.name == "player"`，`room_manager` 用 `get_node_or_null("player")` |
| `CollisionShape3D`（在 player 内） | 碰撞体 | 胶囊 `radius=0.35`、`height=1.8`、中心 `y=0.9`，按模型 AABB（高 1.82m）拟合，脚底正好在 y=0 |
| `mainCamera3D` | `p_3d.gd` 的 `@export var camera` | 场景里存的是 `NodePath("../mainCamera3D")`，所以它必须和 `player` 同级（都在根下） |
| `SophiaSkin` | `p_3d.gd` | `get_node_or_null("SophiaSkin")`（player 的子节点） |
| `Hinge` | `door_leaf.gd` | 门轴节点，脚本只转它的 `rotation.y`（`Leaf` / `StaticBody3D` 是它的子节点，所以是绕门框边轴转） |
| `SpawnFromRoomN` | `room_manager.gd` | `scene.find_child(名字, true, false)` 递归查找（可以放在 `Spawns/` 里） |
| `DoorToRoomN` | 无（脚本挂在自身上） | 名字本身不参与逻辑，但**必须和对面房间的 `SpawnFromRoomN` 严格对应**，见 §4 |
| `DoorLeaf*` | `door_leaf.gd` | 靠 `add_to_group("door_leaf")`，节点名随意，但同房间内要唯一 |
| 组 `door_leaf` | `room_manager.gd` | 换房间后自动开门用（`get_nodes_in_group`） |

---

## 4. 房间 · 门 · 出生点 · 切换（核心玩法约定）

### 数据流

```
玩家走进 DoorToRoom2 (Area3D + door.gd)
  → 校验：body 是 player、速度方向 · exit_direction ≥ direction_tolerance、距上次换场 > 600ms
  → RoomManager.change_room(preload 好的 PackedScene, "SpawnFromRoom1")
      → 实例化目标房间并 add_child（旧房间还在，屏幕上不空帧）
      → current_scene = 新房间
      → find_child("SpawnFromRoom1") → 把 player 摆到它的 global_position / rotation.y
      → 打开离玩家 3.2m 内最近的门（open_instant），模拟「门还开着」
      → 继承旧 player 的速度，queue_free 旧房间
```

### 命名规则（最容易搞错的地方）

- **`SpawnFromRoomN` = 「从房间 N 走进来时站的位置」**，写在**目标房间**里。
  例：`room1` 的门 `DoorToRoom2` 的 `target_spawn = "SpawnFromRoom1"` —— 因为目标是 room2，
  而玩家是从 room1 来的，所以要落到 room2 里的 `SpawnFromRoom1`。
- 房间有几扇门，就有几个 `SpawnFromRoomX`；`room2` 有两扇门 → `SpawnFromRoom1` + `SpawnFromRoom3`。
- 出生点要放在门框**里侧**（离门 0.5~1m），`rotation.y` 朝向房间内部，否则一出生就贴着墙。

### 门洞触发器（`DoorToRoomX`）

| 导出属性 | 默认 | 说明 |
| --- | --- | --- |
| `target_scene` | `""` | 目标房间路径，**字符串**，如 `res://scenes/rooms/room2.tscn`；移动场景文件必须同步改 |
| `target_spawn` | `""` | 目标房间里的出生点名字 |
| `exit_direction` | `(0,0,-1)` | 「走出本房间」的世界方向；朝 -Z 的门用 `(0,0,-1)`，朝 -X 的用 `(-1,0,0)` |
| `direction_tolerance` | `0.2` | 速度方向与 `exit_direction` 的点积阈值；`0` 表示不判方向 |

触发器位置放在**门框外侧**（门洞穿过墙体之后的位置），碰撞盒尺寸贴着门洞：
Z 向门 `Vector3(1.4, 2.3, 0.6)`，X 向门 `Vector3(0.6, 2.3, 1.4)`。

### 门扇（`DoorLeaf`，来自 `scenes/doors/door_leaf.tscn`）

结构：`DoorLeaf`(Node3D 容器，放在合页位置) → `Hinge`(Node3D，只转它的 Y) → `Leaf` + `StaticBody3D/CollisionShape3D`（都在 `Hinge` 下，偏移 +0.8）。
**转的是 `Hinge` 节点，不是 `Leaf` 网格**，所以是绕门框边轴旋转，不会绕门板中心打转。

推动是**物理式**的，不是 tween 动画：脚本维护角速度 `_ang_vel`，玩家顶着门走就按 `push_accel` 加速，松手后按 `angular_drag` 衰减（有惯性、会多转一点），玩家走远后弹簧把门拉回；角度是对角速度积分出来的。

每个门有状态机：`CLOSED → AUTO_OPENING（传送到房间时自动开一次的动画）→ FREE（玩家推，物理）→ CLOSING（走远自动关）`。动画途中玩家撞上来会立刻切到 `FREE` 由物理接管。

| 导出属性 | 默认 | 说明 |
| --- | --- | --- |
| `max_swing_deg` | `100` | 最大开合角度（度） |
| `push_range` | `1.4` | 玩家离门板多近算"在推门" |
| `push_accel` | `14.0` | 推门角加速度（rad/s²），越大门越轻 |
| `angular_drag` | `6.0` | 松手后角速度衰减（rad/s²），越大越"涩" |
| `auto_close_distance` | `2.8` | 玩家离开到多远后自动关 |
| `auto_close_delay` | `1.2` | 走远后延迟几秒开始关 |
| `close_stiffness` / `close_damp` | `10` / `5` | 关门弹簧刚度 / 阻尼 |
| `max_angular_speed` | `5` | 角速度上限 |
| `auto_open_time` | `0.45` | 传送到达时那次自动开门的动画时长 |
| `open_on_start` | `false` | 是否开局就开着 |

跨房间的"门还开着"：`RoomManager` 换场前记录出发门的 `get_angle_deg()` **角度大小**，换场后调用目标门的 `open_with_animation(angle)`；方向不用复制——每扇门自己算"朝房间内"的符号（`_inward_sign`），所以从 1→2、2→3、3→2、2→1 任何方向进来，门都朝你进入的那个房间内侧开，不会再出现贴墙的怪角度。

摆放要点：
1. 节点放在**合页**（门框一侧边缘）位置，本地 **+X 就是门板伸出的方向**；
2. 门板在 `Hinge` 下偏移 `x = 0.8`（门宽 1.56 的一半 + 一点间隙）；
3. 用**容器节点**的 `rotation.y` 把本地 +X 转成门洞方向；
4. 推开方向自动计算（门板朝向 → 房间外），**不需要手填角度**；
5. 门板底边要高于门洞下沿（现在门洞有 3.6cm 门槛，门板底边在 0.05m）。

---

## 5. 素材规范

### 四种格式的关系

`Assets/models/` 下是**同一套万圣节模型**的四种导出格式：

| 目录 | 内容 | 状态 |
| --- | --- | --- |
| `fbx/` | 63 个 `.fbx` + `.import` | **游戏实际使用的格式**（`scenes/props/pumpkin.tscn` 引用） |
| `fbx_unity/` | 同名 `.fbx`，Unity 导出版（单位/轴向与 `fbx/` 不同） | 备份，无引用 |
| `gltf/` | `.gltf` + `.bin`（文本、可 diff） | 备份，无引用 |
| `obj/` | `.obj` + `.mtl` | 备份，无引用 |

- 模型源文件（`.fbx/.gltf/.obj/.png/.wav`）**不要改名、不要移动**。改名/移动会改变 UID 解析链，
  必须走「编辑器里拖动」或「连同 `.import` 一起移动 + 跑一次 `--import`」。
  （本轮整理已把 `Assets/fbx|fbx(unity)|gltf|obj|textures` 整体移到 `Assets/models/*` 与 `Assets/textures/`，
  并跑过一次 `--import`，`.import` 里的 `source_file` 已由 Godot 自动改成新路径、`uid` 未变。）
- 贴图：`Assets/textures/halloweenbits_texture.png` 与三份格式目录里的同名 png 完全重复。
  新材质请**指向 `Assets/textures/` 那一份**，避免再复制。
- **`.import` 是 Godot 生成的**，不要手改。移动素材的正确姿势：
  1. 把 `xxx.fbx` 和 `xxx.fbx.import` 一起移动；
  2. 跑 `godot --headless --path . --import`（或在编辑器里让它自己重扫），Godot 会重写 `source_file` 并保留 `uid`；
  3. 再改场景里 `ext_resource` 的 `path=`（其实 uid 不变，不改也能加载，但路径写错会留下脏数据）。
- `.godot/` 是纯缓存，不进版本库（已在 `.gitignore`），**不要手改里面任何文件**。

### `docs/reference/tutorial-3d-controller/`

这是从压缩包解压出来的第三方教程工程，**自带 `project.godot`**，并且它的
`player/sophia_skin/*` 与本工程 `player/sophia_skin/*` **共用同一批 UID**（24 个重复）。

因此该目录里放了 `.gdignore`（Godot 扫描时跳过整个目录）。
**不要**把它的 `.gdignore` 删掉，也不要把里面的资源复制回 `player/`——会产生 UID 冲突警告。

---

## 6. 代码约定

- **缩进用 Tab**（GDScript 官方规范），不要用空格。
- **注释写中文**；文件级说明用 `##`（会进编辑器文档），行内解释用 `#`。
- 属性和函数都标类型：`func open() -> void:`、`@export var speed: float = 5.0`（现有代码部分用了
  类型推断 `:=`，新代码保持一致即可）。
- 按名字查节点一律用 `get_node_or_null` + 空值降级，不要在 `_ready` 里裸 `$Node` 硬崩
  （`p_3d.gd` 允许没有 `SophiaSkin` 的场景复用就是这个原因）。
- `class_name`：`Door`（Area3D）、`SophiaSkin`（Node3D）。新增可复用组件时优先给 `class_name`。
- 跨房间通信**只走 `RoomManager`**（autoload），不要写 `get_tree().root.get_node("...")` 之类的硬路径。

### Autoload

| 名字 | 脚本 | 作用 |
| --- | --- | --- |
| `RoomManager` | `res://scripts/autoload/room_manager.gd` | 换房间的唯一入口：`change_room(packed, spawn_name)`；维护 `is_changing`、`last_change_msec`、`current_room` |

改 autoload 脚本位置时，必须同步改 `project.godot`：

```ini
[autoload]

RoomManager="*res://scripts/autoload/room_manager.gd"
```

### 输入动作（`project.godot`）

`move_left` / `move_right` / `move_forward` / `move_back`（WASD，deadzone 0.2）、`ui_accept`（空格，内置）。门是"撞上去就开"的，所以没有单独的交互按键。

---

## 7. 新增一个房间的完整步骤

以「加房间4，从房间3出去能到，也能走回房间3」为例：

### 7.1 建场景
1. 复制 `scenes/rooms/room3.tscn` → `scenes/rooms/room4.tscn`（建议在编辑器 `文件 → 另存为`）。
2. 根节点改名 `Room4`；`RoomLabel` 的 `text` 改成「房间4」。
3. 按需调整 `Geometry/`（地板 `FloorGrid` 的 cells、门墙 `DoorWall_*`、围挡 `Bounds`）。

### 7.2 加出生点（房间里每扇门一个）
在 `Spawns/` 下加 `Marker3D`：
- 命名 `SpawnFromRoom3`（因为是从房间3来的）；
- 位置：门框里侧 0.5~1m，`y ≈ 0`；
- `rotation.y` 朝向房间内部（`p_3d.gd` 会把这个 yaw 直接给玩家）。

### 7.3 加门洞触发器
在 `Doors/` 下加 `Area3D`：
- 命名 `DoorToRoom3`；
- 挂脚本 `res://scripts/rooms/door.gd`；
- 子节点加 `CollisionShape3D`，命名 **`Trigger`**，`shape` 用 `BoxShape3D` 贴门洞
  （Z 向门 `(1.4, 2.3, 0.6)`，X 向门 `(0.6, 2.3, 1.4)`）；
- `Area3D` 自身位置放在**门框外侧**（穿出去之后），避免刚出生就触发；
- 填参数：
  - `target_scene = "res://scenes/rooms/room3.tscn"`
  - `target_spawn = "SpawnFromRoom4"`（room3 里给「从房间4来」准备的新出生点）
  - `exit_direction` = 从本房间走出去的方向（朝 -Z 的门填 `(0, 0, -1)`，朝 -X 填 `(-1, 0, 0)`）
  - `direction_tolerance` 保持 `0.2`

### 7.4 加门扇
把 `scenes/doors/door_leaf.tscn` 拖进 `Doors/`：
- 命名 `DoorLeaf`（同房间多扇就 `DoorLeafLeft` / `DoorLeafBack` …，保证唯一）；
- 放在**合页**位置，用容器 `rotation.y` 让本地 +X 指向门板伸出方向；
- 推开方向、跨房间复制朝向都由脚本自动处理，**不需要手填角度**；
- 想要「一进门就是开着的」，把 `open_on_start` 打开。

### 7.5 反过来把房间3连到房间4
在 `room3.tscn` 里补一套：`Spawns/SpawnFromRoom4`(Marker3D) + `Doors/DoorToRoom4`(Area3D + `Trigger`) + 门扇。
- `DoorToRoom4.target_scene = "res://scenes/rooms/room4.tscn"`
- `DoorToRoom4.target_spawn = "SpawnFromRoom3"`（room4 里的那个出生点）

> 漏了这步不会崩，但会：走出门后角色留在原点，且控制台警告
> `RoomManager: 目标房间缺少出生点：SpawnFromRoomX`。

### 7.6 检查清单
- [ ] 每扇门都有对侧房间的 `SpawnFromRoomN`，且名字对得上
- [ ] `player`、`mainCamera3D` 还是房间根的直接子节点（没被塞进容器）
- [ ] `player` 的 `camera` 属性还指向 `../mainCamera3D`
- [ ] 门墙 `DoorWall_*` 的 `DoorHole` 尺寸（1.6×2.3×0.562）和门扇（1.6×2.3×0.08）对得上
- [ ] `godot --headless --path . --quit-after 180` 无 `SCRIPT ERROR` / `Parse Error`
- [ ] 三个（四个）门口都实际走一遍

### 7.7 新增一扇门（同房间加第二个出口）
只做 7.2 + 7.3 + 7.4，然后在**对面房间**补 `SpawnFromRoomN` + 返回门即可，不需要改 `project.godot`。

> 只有「把 room4 设成主场景」时才需要改 `project.godot` 的 `run/main_scene`；在编辑器里
> `项目 → 常规 → 应用 → 运行 → 主场景` 选一下即可（会写成 uid 引用）。

---

## 8. 已知问题 / 待决定（本次整理**没有**执行）

1. **三套重复格式可精简**：`Assets/models/` 下 `fbx_unity/`、`gltf/`、`obj/` 目前**无任何引用**，
   只留 `fbx/`（在用）+ 一套备份即可，约可省 3.8 MB。删除前请确认没人拿它当"源文件"。
2. **同名贴图 4 份**：`Assets/textures/` 与三份格式目录里的 `halloweenbits_texture.png` 完全重复，
   建议只留一份并统一材质引用。
3. **room2 缺 `FloorPlane`**：房间1、房间3 都有 `Geometry/FloorPlane`（地板碰撞面），room2 没有，
   目前靠 GridMap 自身。若发现 room2 掉出地图，补一个即可（对齐 room3 的写法）。
4. **`scenes/dev/` 两个场景**（`grid_map_preview`、`floor_mesh_preview`）是开发遗留，不影响运行；
   确认不需要可以删。
5. **`p_3d.gd` 每帧写 `get_viewport().scaling_3d_scale = 0.40`**：这是个降分辨率提帧的 hack，
   写在 `_physics_process` 里会让整个视口一直以 40% 渲染。要改画质请改这里（本次未动玩法逻辑）。
6. 仓库还没 `export_presets.cfg`，导出前需按 §1 建预设。
# Simple Warfare 核心玩法包 v0.1

这个包是 Simple Warfare 的第一版长期内容架构草案。它不是为了适配当前最小 loader 而设计，而是为了定义一套后续地图编辑器、玩法数据、前端表现和服务端模拟都能共同使用的包结构。

当前包仍然是 authoring target：目录和字段表达的是目标形态，不代表所有字段都已经被当前运行时代码完整消费。

## 先看哪里

如果只想理解这个包，建议按这个顺序看：

1. `manifest.toml`：包入口、默认地图、默认阵营、校验要求。
2. `registry/*.toml`：告诉 loader 哪些文件属于这个包。
3. `maps/duel_fields/`：一张完整地图如何组织。
4. `data/units/land/tank.toml`：一个单位如何引用模板、武器、资产和本地化。
5. `data/actions/production/produce_tank.toml`：一个生产指令如何表达成本、时间和结果。
6. `schema/package_schema.toml`：当前包结构的规则摘要。

如果只想新增内容，通常不需要先读完整个包。新增单位看 `data/units/`、`data/weapons/`、`data/projectiles/`、`data/assets.toml` 和 `registry/gameplay.toml`；新增地图看 `maps/<map_id>/` 和 `registry/maps.toml`。

## 总体原则

- `manifest.toml` 只描述包本身，不直接塞玩法数据。
- `registry/` 只列出文件入口，不定义具体玩法。
- `data/` 放可复用玩法定义，比如单位、武器、资源、地形类型、移动类型、效果。
- `maps/` 放具体地图实例，比如地形网格、出生点、资源点、地图对象、触发器。
- `assets/` 放真实图片、音频等文件。
- `schema/` 放包结构规则和迁移说明。
- `provenance/` 记录来源和转换依据，不参与运行时玩法。

换句话说，`data/` 是“这款游戏有哪些东西”，`maps/` 是“这一局地图上放了哪些东西”，`assets/` 是“这些东西长什么样、听起来是什么”。

## 目录职责

```text
simple_warfare_core_v0_1/
  manifest.toml
  README.md
  registry/
    assets.toml
    gameplay.toml
    maps.toml
  data/
    actions/
    abilities/
    ai/
    collision/
    effects/
    factions/
    localization/
    movement/
    projectiles/
    resources/
    terrain/
    units/
    upgrades/
    weapons/
    assets.toml
  maps/
    duel_fields/
      map.toml
      terrain.toml
      teams.toml
      spawns.toml
      objects.toml
      resources.toml
      triggers.toml
      source/
  assets/
    textures/
    audio/
  schema/
  migrations/
  provenance/
```

### `manifest.toml`

包入口。它回答几个问题：

- 包 id 是什么。
- 包版本是多少。
- 默认地图和默认阵营是什么。
- registry 文件在哪里。
- loader 应该做哪些校验。

它不应该列出每个单位、武器、地图对象。那些入口由 `registry/` 负责。

### `registry/`

registry 是显式索引，避免 loader 扫目录时把草稿、备份文件或未完成内容加载进去。

- `registry/assets.toml`：资产入口。
- `registry/gameplay.toml`：资源、阵营、单位、武器、action、效果等玩法入口。
- `registry/maps.toml`：地图入口。

新增一个正式内容文件时，一般也要把它加入对应 registry。这样包内可以保留实验文件，但不会误进运行时。

### `data/`

`data/` 是可复用定义区。地图可以引用这里的单位、资源、地形类型、移动类型、武器、效果等。

常见关系如下：

```text
unit
  -> templates
  -> faction
  -> movement profile
  -> collision footprint
  -> weapon
  -> action
  -> render asset
  -> localization key

weapon
  -> projectile
  -> audio/visual effects

action
  -> requirements
  -> cost
  -> timing
  -> effects

map
  -> terrain types
  -> teams
  -> spawns
  -> resources
  -> initial objects
```

这也是包看起来复杂的主要原因：我们把过去可能混在一个 INI 或一个场景里的东西拆成了明确领域。拆分的好处是引用关系可校验、可复用、可由编辑器独立编辑。

### `maps/`

每张地图一个目录。地图不是单个大文件，因为地图后续会有很多独立演进的部分：

- `map.toml`：地图元信息，比如尺寸、标题、默认规则。
- `terrain.toml`：逻辑地形和视觉地块。
- `teams.toml`：队伍、阵营、初始资源。
- `spawns.toml`：出生点和初始单位计划。
- `objects.toml`：装饰物、资源节点、地图静态对象。
- `resources.toml`：地图资源分布。
- `triggers.toml`：地图脚本、触发器、胜负条件扩展点。
- `source/`：地图编辑器源文件说明或原始工程文件，不作为运行时权威数据。

地图目录里的文件描述的是“这一张地图”。如果内容可以被多张地图复用，应放到 `data/`。

## 地形设计

地形保存在单个 `terrain.toml` 中，不拆成多个地形文件。原因是逻辑层和视觉层必须共享同一张地图尺寸和坐标系统，放在一起更容易校验，也更容易被地图编辑器导出。

`terrain.toml` 内部分成两类数据：

```text
[terrain.logic]
服务端、寻路、碰撞、放置、资源规则使用。

[terrain.visual]
前端渲染使用。
```

### 逻辑层

逻辑层回答“这个格子在玩法上是什么”。

例如：

```text
G = grass
R = road
W = water
O = ore
```

服务端和工具链可以用它判断：

- 单位能不能走。
- 建筑能不能放。
- 子弹或视野是否被阻挡。
- 资源点是否有效。
- 地图边界和出生点是否合法。

逻辑层不关心草地边缘贴图、水岸贴图、道路转角贴图。

### 视觉层

视觉层回答“这个格子最终应该显示哪一块 tile”。

例如：

```text
R = road center
r = road edge
W = water center
w = water edge
O = ore center
o = ore edge
```

视觉层不是运行时动态生成的。地图编辑器或导入器负责根据逻辑地形、邻接关系和美术规则提前算好边缘、过渡、变体，然后把结果写进 `terrain.visual`。

这样做的原因：

- 运行时不需要重复实现 autotile 规则。
- 服务端不会依赖视觉地块。
- 地图编辑器导出的结果是确定的，前端只负责显示。
- 以后支持 Tiled、Godot TileMap 或自研地图编辑器时，可以统一导出到这个格式。

### 为什么还用 `fixed_width_rows`

`fixed_width_rows` 只是一个紧凑编码方式，不代表只能表达简单地形。

在逻辑层里，一个字符代表一个玩法地形类型。

在视觉层里，一个字符代表一个已经选定的具体视觉 tile。复杂过渡不靠运行时推导，而是由编辑器把复杂结果编码进视觉层。

如果以后视觉 tile 种类超过单字符能舒服表达的范围，可以增加 `sparse_tiles` 或 `tiled_source` 编码；schema 已经为这个方向留了扩展点。

## 单位设计

单位定义放在 `data/units/` 下，并按领域分目录：

- `land/`：地面移动单位。
- `air/`：空中单位。
- `structures/`：建筑。
- `templates/`：模板。

一个单位通常由几部分组成：

```toml
id = "simple_warfare:unit.tank"
templates = [
  "simple_warfare:template.ground_vehicle",
  "simple_warfare:template.turreted_unit",
]

[identity]
display_name = "simple_warfare:loc.unit.tank"
faction = "simple_warfare:faction.human"

[body]
radius = 11.0

[health]
max = 210

[combat]
weapons = ["simple_warfare:weapon.tank_cannon"]

[render]
body = "simple_warfare:texture.unit.tank.body"
```

模板用于减少重复。例如大多数地面车辆都有类似的移动、碰撞、选择框和基础渲染规则，不应该每个单位复制一遍。loader 最终应该把模板展开为完整定义，再交给运行时。

## Action 设计

action 是玩家或 AI 可以触发的命令或能力定义，例如：

- 生产坦克。
- 建造工厂。
- 建造采集器。
- 升级工厂。
- 维修。
- 回收。

action 的基本合同是：

```text
requirements + cost + timing + effects
```

也就是：

- `requirements`：什么条件下可以执行。
- `cost`：消耗什么资源。
- `timing`：需要多久，是否占用队列。
- `effects`：完成后发生什么。

把 action 独立出来的原因是：同一个单位可以拥有多个 action，AI、UI、热键、网络命令和校验逻辑都可以围绕 action id 工作，而不是硬编码“工厂按钮 1 是造坦克”。

## 武器、弹丸和效果

武器、弹丸、效果分开定义：

```text
weapon -> projectile -> effects
```

例如坦克炮：

- weapon 决定射程、冷却、目标过滤、弹丸类型。
- projectile 决定速度、命中半径、伤害表达。
- effects 决定开火音效、爆炸视觉、命中反馈。

这种拆分让多种武器可以共享弹丸或效果，也让前端表现可以和服务端伤害规则分开演进。

## 资源和经济

资源定义放在 `data/resources/`，例如 credits 和 energy。

地图上的资源节点放在 `maps/<map_id>/resources.toml` 或 `objects.toml`。单位生产、建筑建造、升级等消耗通过 action 或 unit economy 字段引用资源 id。

原则是：

- 资源类型是全局玩法定义。
- 资源点是地图实例。
- 当前队伍拥有多少资源是运行时状态，不写进玩法包，除非是初始资源。

## 资产和本地化

资产分两层：

- `assets/`：真实文件。
- `data/assets.toml`：资产 id 到文件路径的映射。

玩法定义不直接写图片路径，而是引用资产 id：

```toml
[render]
body = "simple_warfare:texture.unit.tank.body"
```

本地化也类似。玩法定义引用本地化 key：

```toml
display_name = "simple_warfare:loc.unit.tank"
```

真实文本在 `data/localization/en_us.toml` 和 `data/localization/zh_cn.toml` 中。

## Loader 预期流程

目标 loader 可以按这个流程工作：

1. 读取 `manifest.toml`。
2. 读取 `schema/package_schema.toml`，确认 schema version。
3. 读取 `registry/*.toml`，得到正式入口文件列表。
4. 解析 `data/` 和 `maps/` 中被 registry 引用的文件。
5. 展开 templates。
6. 校验所有 id 唯一。
7. 校验所有引用存在。
8. 校验地图尺寸、地形层尺寸、出生点、资源点和对象边界。
9. 校验 action 的 requirements、cost、timing、effects 合法。
10. 校验生产图没有明显断链。
11. 校验资产文件存在。
12. 生成运行时可直接消费的归一化定义。

运行时最好不要直接依赖 authoring 文件的复杂结构，而是依赖 loader 输出的完整定义。

## 如何新增一个单位

最小步骤：

1. 在 `data/units/<domain>/` 新增单位文件。
2. 选择或新增 template。
3. 引用 movement、collision、weapon、render asset、localization key。
4. 如果需要新武器，在 `data/weapons/` 新增。
5. 如果需要新弹丸，在 `data/projectiles/` 新增。
6. 如果需要新图片或音效，在 `assets/` 放文件，并在 `data/assets.toml` 注册。
7. 在 `data/localization/*.toml` 添加显示名。
8. 在 `registry/gameplay.toml` 对应列表中加入新文件。
9. 跑校验。

不要把单位初始出生位置写进单位定义。出生位置属于地图，应写在 `maps/<map_id>/spawns.toml`。

## 如何新增一张地图

最小步骤：

1. 新建 `maps/<map_id>/`。
2. 添加 `map.toml`。
3. 添加 `terrain.toml`，包含逻辑层和视觉层。
4. 添加 `teams.toml`。
5. 添加 `spawns.toml`。
6. 按需添加 `objects.toml`、`resources.toml`、`triggers.toml`。
7. 如果来自地图编辑器，把源文件或说明放进 `source/`。
8. 在 `registry/maps.toml` 中注册地图。
9. 跑地图尺寸、出生点、资源点和地形引用校验。

地图编辑器应该输出 runtime 需要的结果文件。玩法包不应该在加载时临时生成地形视觉结果。

## 为什么现在看起来复杂

复杂度主要来自三个决定：

1. 我们把运行时数据、编辑器源数据、视觉资产、来源说明分开了。
2. 我们把单位、武器、弹丸、action、效果拆成可复用对象。
3. 我们希望 loader 能校验引用，而不是把错误留到运行时才暴露。

这会让第一眼目录变多，但长期收益是：

- 新增内容时更少改代码。
- 地图编辑器可以只改地图文件。
- 前端可以只关心资产和视觉层。
- 服务端可以只关心逻辑层和玩法定义。
- 未来多人同步、回放、AI、热更新和包迁移都有明确边界。

如果后续某个领域确认不会扩展，可以再合并。但在当前阶段，先保持领域清晰比过早压缩文件数量更稳。

## 当前包的非目标

- 不要求当前运行时代码已经支持全部字段。
- 不在运行时生成地形视觉 tile。
- 不把地图编辑器源文件当成运行时权威数据。
- 不把所有单位、武器、效果写进一个大文件。
- 不把版权或来源说明混进 gameplay 定义。

## 命名约定

id 使用：

```text
namespace:domain.name
```

例如：

```text
simple_warfare:unit.tank
simple_warfare:weapon.tank_cannon
simple_warfare:texture.unit.tank.body
simple_warfare:map.duel_fields
```

推荐规则：

- namespace 当前使用 `simple_warfare`。
- domain 表达对象类型。
- name 使用 snake_case。
- 本地化 key 使用 `simple_warfare:loc.*`。
- 资产 id 使用 `simple_warfare:texture.*`、`simple_warfare:audio.*` 等。

## 校验重点

一个成熟 loader 至少应校验：

- id 唯一。
- 引用存在。
- registry 指向的文件存在。
- 资产路径存在。
- 地图尺寸一致。
- terrain logic 和 terrain visual 尺寸一致。
- visual code 都能映射到 tileset tile。
- 出生点在地图内。
- 资源点在地图内。
- 单位 footprint 和 collision layer 合法。
- action 引用的资源、单位、升级、效果存在。
- production graph 没有明显断链。

这些校验是这个架构能够维护下去的关键。否则文件拆分只会增加负担。

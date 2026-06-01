# Simple Warfare Official Package

这是 Simple Warfare 的官方基础玩法包。它的定位是 authoring format：面向地图编辑器、内容工具和人工维护；运行时不应该直接依赖这些分散文件，而应该由 loader 校验、展开模板、解析引用后生成 normalized content database。

当前包只保留基础玩法需要的稳定结构，不把实验转换结果或来源研究资料放入官方运行时包的加载链路。

## 核心原则

- `manifest.toml` 只描述包身份、版本、入口和校验要求。
- `registry/` 是显式入口，loader 只加载 registry 指向的正式文件。
- `data/` 保存可复用玩法定义，例如单位、武器、弹丸、资源、地形、移动和碰撞。
- `maps/` 保存具体地图实例，例如地图元信息、地形层、队伍、出生单位和资源点。
- `assets/` 保存真实图片和音频，玩法定义通过 asset id 引用它们。
- `schema/package_schema.toml` 是当前 authoring contract 的机器可读摘要。
- 地图编辑器负责导出视觉地块结果；运行时不动态生成地块过渡。

## 目录结构

```text
official/
  manifest.toml
  README.md
  registry/
    assets.toml
    gameplay.toml
    maps.toml
  data/
    actions/
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
      resources.toml
      source/
  assets/
    audio/
    textures/
  schema/
    package_schema.toml
```

## 数据分层

`data/` 描述“游戏里有哪些可复用东西”：

- `units/`：单位和建筑定义。
- `units/templates/`：单位模板，由 loader 展开。
- `weapons/`：武器射程、冷却、目标过滤和弹丸引用。
- `projectiles/`：弹丸速度、命中和伤害表达。
- `actions/`：生产、建造、升级、维修、回收等命令。
- `resources/`：经济资源类型。
- `terrain/`：地形类型、pathing layer 和 tileset。
- `movement/`：移动类型。
- `collision/`：碰撞层和 footprint。
- `effects/`：当前只保留被引用的表现效果。
- `localization/`：显示文本。
- `assets.toml`：asset id 到真实文件路径的映射。

`maps/` 描述“这一张地图上有什么”：

- `map.toml`：地图 id、尺寸、tile size、推荐玩家数、默认相机。
- `terrain.toml`：逻辑地形层和视觉地块层。
- `teams.toml`：队伍、阵营和初始资源。
- `spawns.toml`：初始单位。
- `resources.toml`：地图资源点。
- `source/`：地图编辑器源文件说明，不作为运行时权威数据。

## 地形合同

`terrain.toml` 同时保存逻辑层和视觉层：

- 逻辑层回答玩法问题：能否移动、能否放置、是否资源地形、服务端模拟如何处理。
- 视觉层回答显示问题：这一格最终渲染哪一个 tile。

视觉层由地图编辑器或导入器导出，不在运行时根据邻接关系临时生成。这样可以保持服务端、前端和编辑器边界清晰，也避免多人运行时出现视觉推导差异。

`fixed_width_rows` 只是编码方式，不限制表达能力。逻辑层的字符表示地形类型；视觉层的字符表示已经选定的具体视觉 tile。以后如果单字符不够，可以扩展为 `sparse_tiles` 或 `tiled_source`，但当前基础包不提前引入复杂格式。

## Loader 预期流程

目标 loader 应按以下流程处理包：

1. 读取 `manifest.toml`。
2. 读取 `registry/*.toml`。
3. 解析 registry 指向的 `data/` 和 `maps/` 文件。
4. 展开 unit templates。
5. 校验 id 唯一。
6. 校验引用存在。
7. 校验资产文件存在。
8. 校验地图尺寸、地形层尺寸、出生点和资源点。
9. 校验 action 的 requirements、cost、timing、effects。
10. 输出运行时可直接消费的 normalized content database。

## 暂不放入官方包的内容

以下内容不是不需要，而是当前不放入官方包加载链路：

- AI 策略数据：等 AI 系统有明确消费方后再加入。
- 独立 abilities 目录：目前主动能力统一放进 `actions/`，避免和 command/action 概念重叠。
- migrations：等 schema 迁移工具存在后再定义。
- provenance：来源和转换说明不进入官方运行时包。
- schema changelog：目前使用 README 和 Git 历史记录。
- 未引用的表现/玩法效果：有实际引用后再进入 registry。

## 新增内容规则

新增正式内容时，应同时满足：

- 文件被 registry 显式引用。
- 所有 `simple_warfare:*` 引用都能解析。
- 资产通过 `data/assets.toml` 注册。
- 显示文本通过 localization key 引用。
- 地图坐标在地图边界内。
- 不把编辑器源文件当成运行时权威数据。

新增单位时，优先复用 `data/units/templates/`；新增地图时，优先让编辑器导出 `terrain.toml` 的逻辑层和视觉层。

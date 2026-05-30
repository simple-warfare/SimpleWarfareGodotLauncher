# Simple Warfare Example Content Pack v0.1 Overview

这是一份用于讨论“正式玩法包框架”的示例，不是最终 schema。

## 关键原则

1. `data/` 和 `assets/` 分离。
2. 所有贴图、音频通过 `data/assets.toml` 的 asset id 引用。
3. 单位引用 movement / weapon / action / asset，不直接内联全部系统。
4. weapon 引用 projectile / effect / audio。
5. action 使用 requirements / cost / timing / effects。
6. 脚本目录保留，但不是核心玩法的必需项。
7. 运行时应把源码 TOML 编译成 UnitRegistry / WeaponRegistry / ActionRegistry / AssetCatalog 等结构。

## 目录摘要

- `manifest.toml`：包身份、版本、入口地图。
- `data/assets.toml`：AssetCatalog。
- `data/resources.toml`：资源定义。
- `data/units/`：单位定义。
- `data/movement/`：移动 profile。
- `data/weapons/`：武器。
- `data/projectiles/`：弹体。
- `data/actions/`：生产、升级、命令。
- `data/effects/`：视觉/音频效果。
- `data/maps/`：地图。
- `data/localization/`：多语言文本。
- `assets/`：占位贴图和音频。
- `scripts/`：预留扩展层。
- `migrations/`：预留 schema 迁移层。

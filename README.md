# SimpleWarfareGodotLauncher

这是 `Simple Warfare` 的 Godot 前端工程。

当前工程已经从旧启动器原型中清理出来，只保留新的启动结构、Rust GDExtension 接入、基础前端资源和必要文档。

如果后续需要参考旧 UI、旧场景或旧脚本，应该通过 Git 历史或团队约定的历史备份读取，不应把旧 `GLOBALS / Backend / Adaptor` 体系重新搬回当前工程。

## 当前技术栈

- 引擎：`Godot 4.6`
- 脚本：`GDScript`
- Rust 接入：`GDExtension`
- Rust 核心工程：`simple-warfare/rusty_warfare` 仓库

明确不采用：

- C# 桥接
- 整体 C# 重构
- 外部进程后端作为正式路线

## 当前结构

```text
project.godot
  -> scenes/bootstrap.tscn
    -> scripts/bootstrap/bootstrap.gd
    -> scripts/bootstrap/resource_bootstrap.gd
    -> scripts/backend/rust_backend.gd
    -> scripts/app/app_state.gd
    -> scripts/app/scene_router.gd
    -> scenes/main_menu.tscn
    -> scenes/game.tscn
```

核心路径：

- `addons/rusty_core/`
  - Rust GDExtension 配置和本地动态库。
- `assets/`
  - Godot 直接导出的基础前端资源。
- `scenes/bootstrap.tscn`
  - 正式启动入口。
- `scenes/main_menu.tscn`
  - 当前安全主菜单入口。
- `scenes/game.tscn`
  - 当前最小游戏场景，用简单方块渲染 Rust snapshot 实体。
- `scripts/backend/rust_backend.gd`
  - Godot 到 Rust 的统一适配层。
- `scripts/bootstrap/resource_bootstrap.gd`
  - 初始化 `user://assets` 和 `user://mods` 运行时目录。
- `scripts/app/scene_router.gd`
  - 统一场景跳转。
- `scripts/app/app_state.gd`
  - 保存少量前端状态。

## 当前运行流程

```text
Godot 启动
  -> Bootstrap
    -> RustBackend 把 user://assets 真实路径传给 RustyCore 并初始化
    -> ResourceBootstrap 初始化 user://assets 和 user://mods
    -> AppState 记录启动状态
    -> SceneRouter 进入 main_menu.tscn
```

`ResourceBootstrap` 不再在启动阶段解压资源包。它只确保运行时可写目录存在：

```text
user://assets
user://mods
```

实际物理路径由 Godot 按平台映射，代码中不要硬编码本机路径。

```text
user://assets
user://mods
```

## 当前已完成

- Godot 能加载 Rust GDExtension。
- Godot 能通过 `RustBackend` 调用 Rust `RustyCore`。
- 启动流程能初始化 Rust 和运行时资源目录。
- 新主菜单的单人 / 主机 / 加入按钮已能调用 Rust runtime mode API。
- 单人模式已能通过 Godot `_process(delta)` 驱动 Rust update，并显示结构化 `Dictionary` frontend snapshot。
- frontend snapshot 已包含最小占位实体列表，主菜单可显示实体数量和第一个实体状态。
- 单人模式启动成功后会进入 `game.tscn`，并用简单方块渲染 snapshot 中的占位实体。
- `SceneRouter` 和 `AppState` 已经作为 autoload 注册。
- 当前工程已经移除旧外部后端、旧场景、旧 `class_name` 脚本和旧 C# 线索。

## 当前未完成

- 新主菜单还是安全占位入口，不是最终 UI。
- 单人模式当前只有占位 tick，还没有启动真实 server/client。
- 主机 / 加入当前只记录 Rust 运行模式，还没有启动真实联网。
- 设置页、模组页、房间页、地图页需要重新按新结构实现。
- 游戏场景目前只渲染占位实体，还没有正式地图、镜头、选择框或输入系统。
- Android / iOS 导出需要重新配置，不应沿用旧导出预设。

## Rust 核心

Rust 核心工程位于 `simple-warfare/rusty_warfare` 仓库。

## 建议阅读顺序

1. `project.godot`
2. `scripts/bootstrap/bootstrap.gd`
3. `scripts/bootstrap/resource_bootstrap.gd`
4. `scripts/backend/rust_backend.gd`
5. `scripts/app/scene_router.gd`
6. `scripts/app/app_state.gd`
7. `scenes/main_menu.tscn`

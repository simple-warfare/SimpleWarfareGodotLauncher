# 协作约定

本仓库是 `Simple Warfare` 的 Godot 前端工程。提交代码前请优先保证启动流程、资源路径和 Rust GDExtension 接入方式保持清晰。

## 分支规则

- 日常开发使用功能分支或约定的开发分支，不直接向默认主分支推送。
- 合并前应先确认改动范围，只提交和当前任务相关的文件。
- 不要提交本机专用路径、个人配置、临时调试文件或构建产物。

## 文件规则

- 可以提交：场景、脚本、项目配置、正式前端资源、正式内容包源文件。
- 不提交：`.godot/`、`.doc/`、`docs/`、`build/`、本地日志、导出的安装包、GDExtension 动态库。
- 正式内容包源文件放在 `assets/content_packages/`。
- 运行时可写目录使用 Godot 的 `user://`，代码和文档中不要硬编码本机绝对路径。
- 修改 Rust GDExtension 动态库产物时不要直接提交二进制；应由 Rust 仓库的 `builder` 重新生成本地运行产物。

## 代码规则

- Godot 前端负责 UI、输入采集、场景跳转和渲染表现。
- Rust 核心负责游戏规则、内容加载、模拟、网络和快照。
- Godot 与 Rust 通过 `RustBackend` 和 GDExtension 边界交互，不在 UI 脚本里直接分散调用底层接口。
- 前端场景只消费 `RustBackend.get_frontend_snapshot()` 和命令反馈，不自行推导权威规则。
- 注释优先使用中文，说明“为什么这样做”，不要重复描述代码本身。

## 提交前检查

- 确认 Godot 编辑器能打开项目。
- 如果修改了启动或 GDExtension 调用链，至少运行一次启动场景。
- 如果修改了资源包，确认 `assets/content_packages/` 中的路径和 ID 一致。
- 提交前运行 `git status --short`，确认没有误提交本地文件。

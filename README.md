# 笔削春秋

《笔削春秋》是一个使用 Godot 4.7 Mono 与 C# 开发的 2D 叙事游戏项目。当前工程以 Pentiment 式插画场景、Path Network 约束移动和 NarrRail 叙事驱动为核心。

Godot 工程根目录为 [`bxcq`](bxcq/)。仓库根目录的 `arts/` 保存原始美术资料，不属于 `res://` 运行时资源；正式 UI 与 Spine 美术尚未接入。

## 当前可玩能力

- WASD 沿 Walk Path 移动，在 Junction 选择分支
- 左键点击路径移动，点击交互物时自动沿路径接近
- 右键直接请求交互
- Person、Examine、Investigate、Hotspot 四类交互
- 分区固定 Camera2D 与淡入淡出
- NarrRail 世界锚定对白、选项、剧情变量和事件桥
- 村庄、书房、教堂三场景开发回归闭环

当前不包含主菜单、暂停菜单、存读档、Codex、音频和发布导出流程。

## NarrRail

`bxcq/addons/narrrail` 已包含可直接运行的 NarrRail 插件快照，不依赖本机绝对路径。
上游版本与更新方式记录在 `bxcq/addons/narrrail/UPSTREAM.md`。

正式 NarrRail 故事仓库尚未配置。`bxcq/Stories/DevPrototype/` 只用于玩法回归。

## 启动

用 Godot 4.7 .NET 打开 `bxcq/project.godot`。项目会直接进入开发用村庄场景。

## 验证

```bash
cd bxcq
dotnet build BXCQ.csproj
bash Tests/run_smoke.sh
```

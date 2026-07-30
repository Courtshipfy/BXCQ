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

## Windows 一键更新与打包

面向美术、策划等非开发成员，仓库根目录提供两个可直接双击的 Windows 脚本：

- `一键更新项目.bat`：更新到当前远程分支的最新版本。如果电脑没有 Git，会自动下载带凭据管理器的便携版 Git 到 `.tools/`。首次访问私有仓库时可能会弹出 GitHub 浏览器登录，使用者需要拥有本仓库的访问权限。已有 Git 项目会先暂存本地改动，更新后再恢复。如果当前文件夹不含 `.git`，脚本会先在同级目录创建完整备份，再将当前文件夹接入仓库并更新。
- `一键打包Windows版.bat`：生成 64 位 Windows 发布包。支持 Godot 4.7 及以上的 4.x Mono 稳定版，并会扫描 PATH、`GODOT_EXE`、常见安装目录、下载目录和桌面；不自动接受 Godot 5.x。如果电脑没有可用的 Godot、.NET 8 SDK 或对应 Godot 导出模板，会自动下载到 `.tools/`，不需要管理员权限。使用较新 Godot 打包时，脚本会临时匹配 C# SDK 版本，并在结束后恢复项目文件。每次打包会在 `build/windows/` 下产生一个带时间戳的目录和 zip 包，不覆盖之前的产物。

首次运行需要网络，下载后可复用本地工具。如果脚本报错，不要关闭窗口，将完整报错截图发给开发人员。更新脚本不会自动解决同一文件的合并冲突，遇到冲突时会保留 Git stash 和首次备份供恢复。

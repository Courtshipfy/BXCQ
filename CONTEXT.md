# 笔削春秋领域模型

## Movement

**Path Network**：由多条可编辑 Walk Path 和 Junction 组成的可行走拓扑，是角色位置与移动的唯一真相。

**Walk Path**：场景中的一条 `Path2D` / `Curve2D`。不使用自由平面移动或 NavMesh 与之并存。

**Junction**：两条或更多 Walk Path 在焊接阈值内形成的路口。

**Path Pose**：角色在 Path Network 上的位置，由 PathId 与路径偏移组成；世界坐标由它导出。

**Movement Intent**：键盘方向或点击目标形成的移动意图。输入层不直接写自由速度。

## Interaction

**Smart Interact**：目标在范围内时立即触发；否则先沿 Path Network 走到接近点，再自动触发。

**Person**：可对话角色，进入完整 NarrRail 会话并面向说话人。

**Examine**：一次性短查看文本，不启动 NarrRail Session，也不提供选项。

**Investigate**：通过 NarrRail 短剧情改变变量或剧情分支的调查物。

**Hotspot**：门、道路等场景切换点，不走对白呈现路径。

## Dialogue

**Dialogue Presenter**：负责 NarrRail 台词、选项和 Examine 的世界锚定呈现，不拥有剧情状态机。

**Dialogue Blocking**：对话或 Examine 期间禁止角色移动和新的世界交互，由 `GameState.IsDialogueBlocking` 表达。

**NarrRail Bridge**：将 `EmitEvent` 路由到世界行为，并跨场景缓存本次运行会话的剧情变量。

世界事件包括 `switch_camera_zone`、`change_scene`、`set_hotspot_enabled`；演出事件包括 `presentation.fade` 和 `delay`。

**Presentation Director**：负责淡入淡出和延迟等屏幕演出，不修改世界规则或剧情变量。

## World State

**GameState**：只保存当前进程中的场景、出生点、机位、热点覆盖和对话锁。它不写入磁盘，也不拥有 NarrRail 剧情变量。

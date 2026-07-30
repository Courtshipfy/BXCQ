# Smoke tests

这些测试从公开玩法边界验证迁移后的正式基线：

- Path Network 的 WASD、Junction 方向择路、点击移动和 Smart Interact
- Path Network 移动模块无需完整 Location 即可验证路线与 Junction 择路
- Person、Examine、Investigate、Hotspot
- NarrRail 对话、变量、世界事件和演出事件
- NarrRail Execution 的故事启动、推进、选择与结束，通过正式执行接口验证，不借用 Dialogue Presenter 的测试方法
- NarrRail Execution 无需 Location 或 Dialogue Presenter 即可运行纯剧情分支
- 九宫格气泡的短句收窄、长句换行增长、尺寸补间和尾巴锚定
- 气泡实验台的逐字显示、点击补全、点击换句、跨位置演示与安全区约束
- 村庄、书房、教堂的场景机制一致性和跨场景剧情链

从 Godot 工程根目录运行：

```bash
bash Tests/run_smoke.sh
```

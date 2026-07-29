# ADR-0002：Path Network 是唯一移动模型

## Status

Accepted — 2026-07-29

## Decision

- 角色位置以 Path Pose 为真相。
- 点击目标先投影到最近 Walk Path，再沿网络最短路线行走。
- WASD 沿当前路径切线移动，并在 Junction 根据输入方向选择出口。
- Smart Interact 的接近过程使用同一套 Path Network Motor。
- 不引入 `NavigationRegion2D` 或自由平面移动作为并行方案。

## Consequences

每个正式 Location 都必须配置 Walk Path、Junction、PathNetworkHost 和路径调试显示。新输入设备应调用 PlayerController 的移动/交互命令入口，不应绕过 Movement Intent 和 Path Network Motor。

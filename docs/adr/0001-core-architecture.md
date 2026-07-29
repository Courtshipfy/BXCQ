# ADR-0001：核心叙事玩法架构

## Status

Accepted — 2026-07-29

## Context

《笔削春秋》是 Godot 4.7 Mono + C# 的 2D 叙事游戏，体验方向大量参考 Pentiment。项目需要将插画式探索、固定机位和数据驱动叙事明确分层。

## Decisions

- 玩家使用 Path Network 移动，键盘、点击和 Smart Interact 共享同一执行路径。
- 场景采用多个固定 Camera2D Zone，而不是玩家跟随镜头。
- Person、Examine、Investigate、Hotspot 是四种独立交互语义。
- NarrRail Session 拥有剧情执行；C# Presenter 只负责呈现。
- NarrRail Bridge 处理世界事件，Presentation Director 处理屏幕演出。
- NarrRail 变量负责剧情状态，GameState 只负责当前运行时世界状态。
- 开发回归内容隔离在 `Scenes/DevPrototype` 与 `Stories/DevPrototype`。

## Excluded from the current baseline

主菜单、暂停菜单、存读档、Codex、音频、正式美术接入和桌面发布流程不属于当前基线。

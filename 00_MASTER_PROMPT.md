# 项目总控提示词 - War of Dots: Advanced

## 项目概述
一个基于 Godot 4.7 的极简风格即时战略游戏（RTS），支持 PvP 对战。核心玩法是“划线移动、阵型布阵、兵种克制”，核心机制是“数据驱动设计”。

## 技术栈
- 引擎: Godot 4.7 (GDScript)
- 架构: 数据驱动 + 事件总线 + 命令模式
- 网络: Lockstep 同步 (ENet)

## 核心规则
1.  **数据与逻辑分离**: 所有兵种属性必须定义在 `data/units/*.json` 中。战斗逻辑必须通过读取这些数据来执行，严禁将数值硬编码在脚本里。
2.  **继承与接口**: 所有单位脚本必须继承自 `scripts/units/unit_base.gd` (UnitBase)。所有玩家操作必须封装为 `Command` 对象。
3.  **架构约定**:
	- 核心系统 (战斗、经济等) 位于 `scripts/core/`，不依赖具体场景。
	- 使用 `autoload/event_bus.gd` 单例进行系统间通信，降低耦合。
4.  **代码规范**: 使用 Godot 4.x 的 GDScript 2.0 语法（如 `@export`， `signal`， `await`）。

## 当前任务
参考 `scripts/core/combat_system.gd` 的接口定义，实现一个基础的单机战斗场景，包含“长矛兵”和“轻骑兵”两个兵种，验证反骑与克制逻辑。
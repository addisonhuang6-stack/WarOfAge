extends Node
## 全局事件总线（autoload 单例）。
## 系统之间通过信号通信，降低耦合；具体逻辑系统不互相直接依赖。
## 注意：autoload 脚本本身不能声明同名 class_name，全局名 EventBus 由 autoload 注册提供。

## 玩家/系统发出指令（命令模式入口）。
signal command_issued(command: Command)

## 单位受到攻击（用于表现层：飘字、音效等）。
signal unit_attacked(attacker: UnitBase, target: UnitBase, damage: float, is_counter: bool)

## 单位死亡。
signal unit_died(unit: UnitBase)

## 战斗结束，参数为获胜方 player_id。
signal battle_ended(winner_player_id: int)

## 当前选中单位数量变化（供 HUD 更新）。
signal selection_changed(selected_count: int)

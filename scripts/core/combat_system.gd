class_name CombatSystem
extends Object
## 战斗数值计算（纯逻辑，不依赖任何场景）。
##
## 所有数值都来自 UnitData（data/units/*.json），本文件不硬编码任何兵种数值，
## 以保证“数据与逻辑分离”。全部为静态纯函数，便于测试与后续 Lockstep 确定性模拟。


## 计算攻击方对目标造成的最终伤害（克制加成后再减去护甲，且不低于最低伤害）。
static func compute_damage(attacker: UnitData, target: UnitData) -> float:
	var attack: float = float(attacker.get_stat(&"attack", 0.0))
	var armor: float = float(target.get_stat(&"armor", 0.0))
	var min_damage: float = float(attacker.get_stat(&"min_damage", 0.0))
	var damage := attack * counter_multiplier(attacker, target) - armor
	return maxf(damage, min_damage)


## 攻击方对目标的克制倍率：目标带有关键标签时生效（例如长矛兵反骑）。
static func counter_multiplier(attacker: UnitData, target: UnitData) -> float:
	var counter_tags: Array = attacker.get_stat(&"counter_tags", [])
	for tag in counter_tags:
		if target.has_tag(StringName(tag)):
			return float(attacker.get_stat(&"counter_multiplier", 1.0))
	return 1.0


## 目标是否处于攻击方的近战范围（水平距离）。
static func is_in_attack_range(attacker: UnitData, distance: float) -> bool:
	return distance <= float(attacker.get_stat(&"attack_range", 0.0))
